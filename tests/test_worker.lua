local async = require 'async'
local fiber = require 'async.fiber'

local redis_async = require 'redis-async'
local redis_queue = require 'redis-queue'


local opt = lapp([[
test_rqnode: Test the monitor in managing a redis-queue environment   
   -j, --job (default lb) what job to run
   -m, --mrnode    (default 1) map reduce node number (for mrqueues)
]])


local lbjobs = {
   LB_QUEUE = {
      testJob1 = function(args)
         print("LB test job 1: ", args)
      end,
      testJob2 = function(args)
         local waittime = args.waittime or 2000
         local wfunc = function(cb)
            async.setTimeout(waittime, function()
               cb(true)
            end)
         end

         async.fiber.wait(wfunc, {})
         print("LB test job 2: ", args)
      end
   }
}

local mrjobs = {
   MR_QUEUE = {
      testJob1 = {
         map = function(args)
            print("MR test job 1 Map: ", args)
         end,
         reduce = function(args)
            print("MR test job 1 Reduce: ", args)
         end
      },
      testJob2 = {
         map = function(args)
            local waittime = args.waittime or 2000
            local wfunc = function(cb)
               async.setTimeout(waittime, function()
                  cb(true)
               end)
            end

            async.fiber.wait(wfunc, {})
            print("MR test job 2 Map: ", args)

         end,
         reduce = function(args)
            local waittime = args.waittime or 2000
            local wfunc = function(cb)
               async.setTimeout(waittime, function()
                  cb(true)
               end)
            end

            async.fiber.wait(wfunc, {})
            print("MR test job 2 Reduce: ", args)

         end
      },
      config = {skip = true, nodenum = opt.mrnode}
   }
}

local deljobs = {
   DEL_QUEUE = {
      testJob1 = function(args)
         print("DEL test job 1: ", args)
      end,
      testJob2 = function(args)
         local waittime = args.waittime or 2000
         local wfunc = function(cb)
            async.setTimeout(waittime, function()
               cb(true)
            end)
         end

         async.fiber.wait(wfunc, {})
         print("DEL test job 2: ", args)
      end
   }
}

local redis_addr = {host = "localhost", port = 6379}

fiber(function()
   local redis = fiber.wait(redis_async.connect, {redis_addr})
   
   local function conn_rq(cb)
      redis_queue(redis, function(rq)
         cb(rq)
      end)
   end

   local rq = fiber.wait(conn_rq, {})


   local cb = function()
      print("READY")
   end


   if opt.job == "lb" then
      rq:registerWorker(redis_addr, lbjobs, cb)
   elseif opt.job == "mr" then
      rq:registerWorker(redis_addr, mrjobs, cb)
   elseif opt.job == "del" then
      rq:registerWorker(redis_addr, deljobs, cb)
   end
end)

async.go()
