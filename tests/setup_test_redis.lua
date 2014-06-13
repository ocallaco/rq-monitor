local async = require 'async'
local fiber = require 'async.fiber'

local redis_async = require 'redis-async'

local opt = lapp([[
test_rqnode: Test the monitor in managing a redis-queue environment   
   -n, --num (default 4) number of workers
]])

local rq_config = {
   LB_QUEUE = "LBQUEUE",
   MR_QUEUE = "MRQUEUE",
   DEL_QUEUE = "DELQUEUE",
}

local mrq_config = {
   nqueues = 4,
}

local redis_addr = {host = "localhost", port = 6379}

fiber(function()
   local redis = fiber.wait(redis_async.connect, {redis_addr})

   for k,v in pairs(rq_config) do
      redis.hset("RESERVED:QCONFIG", k, v, function(res) print(res) end)
   end

   for k,v in pairs(mrq_config) do
      redis.hset("MRCONFIG:MR_QUEUE", k, v, function(res) print(res) end)
   end
end)

async.go()
