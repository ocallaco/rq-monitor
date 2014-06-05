local async = require 'async'
local tcp = require 'async.tcp'
local uv = require 'luv'

return function(outputbox)
   
   local replclients = {}
   local pending_connections = {}

   local killrepls = function()
      for i,client in ipairs(replclients) do
         client.close()
      end

      --remove any pending connections as well

      replclients = {}
      pending_connections = {}
   end

   -- until we're connected this will drop all requests
   -- could buffer for pending connections.
   local writetorepls = function(data)
      for i,client in ipairs(replclients) do
         client.write(' '..data .. "\n") 
      end
   end

   local setrepls = function(domains)

      -- i hope we can just drop the old client and replace it with a new one without waiting for a callback
      if #replclients > 0 then
         killrepls()
      end

      for i,domain in ipairs(domains) do
         local conn_name = domain.host .. ":" .. domain.port
         
         pending_connections[conn_name] = true

         tcp.connect(domain, function(client)

            -- if we canceled before connection completed just drop it
            if pending_connections[conn_name] then
               table.insert(replclients, client)
               pending_connections[conn_name] = nil

               -- receive results from server
               client.ondata(function(data)
                  outputbox.append(data)
                  outputbox.redraw()
               end)

               client.onclose(function()
                  outputbox.append("Closed Connection " .. conn_name)

                  local index
                  for i,replclient in ipairs(replclients) do
                     if replclient == client then
                        index = i
                        break
                     end
                  end

                  -- clean it i
                  if index then 
                     table.remove(replclients, index)
                  end

                  outputbox.redraw()

               end)

            else
               uv.close(client)
            end
         end)
      end
   end

   return {
      kill = killrepls,
      set = setrepls,
      write = writetorepls,
   }
end


