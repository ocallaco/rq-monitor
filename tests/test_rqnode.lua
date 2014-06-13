local rc = require 'redis-async'
local rn = require 'redis-status.node'

local async = require 'async'
local fiber = require 'async.fiber'

redis_details = {host='localhost', port=6379}

local opt = lapp([[
   -n,--name (default do0)
   -p,--port (default 10001)
]])

local standardconfig = {
   groupname = "REDISQUEUE",
   nodename = opt.name,
   replport = opt.port, 
   replportnext = false,
}


fiber(function()

   local writecli = wait(rc.connect, {redis_details})
   local subcli = wait(rc.connect, {redis_details})

   local proccount = 1

   standardconfig.addcommands = function(commands)
      local lbcount = 1
      commands.spawn_lb = function(n)
         n = n or 4
         for i=1,n do
            commands.spawn("th", {"./test_worker.lua", '-j', "lb"}, {name = "LB_WORKER" .. lbcount})
            proccount = proccount + 1
            lbcount = lbcount + 1
         end
      end
      
      local mrcount = 1
      commands.spawn_mr = function(n)
         n = n or 8
         for i=1,n do
            commands.spawn("th", {"./test_worker.lua", '-j', "mr", '-m', (mrcount % 4) + 1}, {name = "MR_WORKER" .. mrcount})
            proccount = proccount + 1
            mrcount = mrcount + 1
         end
      end

      local delcount = 1
      commands.spawn_del = function(n)
         n = n or 4
         for i=1,n do
            commands.spawn("th", {"./test_worker.lua", '-j', "del"}, {name = "DEL_WORKER" .. delcount})
            proccount = proccount + 1
            delcount = delcount + 1
         end
      end

   end

   node = rn(writecli, subcli, standardconfig, function() print("READY") end)
end)

async.repl()

async.go()

--global_commands.spawn_test()
--global_commands.killall()
