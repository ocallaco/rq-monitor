---
--- Load-balancing enqueueing test
--- Run alongside test_lbwork.lua
---

local q = require 'redis-queue'
local rc = require 'redis-async'

local async = require 'async'
local fiber = require 'async.fiber'

fiber(function()

   local redis_client


   rc.connect({host='localhost', port=6379}, function(client)
      redis_client = client

      q(redis_client, function(newqueue)
         local queue = newqueue

         print("test start")

         for i = 1,200 do
            queue:enqueueJob("LB_QUEUE", "testJob2", {a = 1, b = "test", testnumber = (i % 25) + 1, waittime = 1000 }, {jobHash = tostring(i)})
         end
      end)
      
      async.setTimeout(7000, function()
         
         --client.del("LBQUEUE:TEST")
         --client.del("LBWAITING:TEST")
         --client.del("LBBUSY:TEST")
         --client.del("LBJOBS:TEST")
         client.close()
      end)

   end)
end)

async.go()



