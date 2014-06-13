local REPL = "REPL"
local ALL = "ALL"

local json = require 'cjson'

-- if response = REPL, that means enter a repl before issuing command to see response
-- if args = REPL, that means open repl to set your own args
-- repl command is a special case
return function(config)
   local base_config = {
      namespace = "RQ",
      commands = {   
         repl = {name = '', args = REPL},
         restart = {},
         killall = {},
         ps = {response = REPL},
         git = {name = 'git', args = {'pull'}},
         update = {},
         zombies = {},
      },

      groups = {
         all = ALL
      },

      display_worker = {
         default = function(nodename, workername, status)
            local out = {}
            local status_table
            if type(status.last_status) == "string" then
               ok, status_table = pcall(json.decode, status.last_status)
               if not ok then
                  status_table = {}
               end
            else
               status_table = status.last_status 
            end

            local age = os.time() - tonumber(status_table.time or 0)

            if age > 30 then 
               table.insert(out, "*** ")
            end
            table.insert(out, workername) 
            table.insert(out, ": ")
            table.insert(out, status_table.state or "")
            table.insert(out, "\n")
            return table.concat(out)
         end
      }
   }

   base_config.namespace = config.namespace or base_config.namespace

   base_config.redis_host = config.redis_host
   base_config.redis_port = config.redis_port

   if config.commands then
      for k,v in pairs(config.commands) do
         base_config.commands[k] = v
      end
   end

   local commands = {}
   for k,v in pairs(base_config.commands) do
      table.insert(commands, k)
   end

   for k,v in pairs(config.display_worker or {}) do
      base_config.display_worker[k] = v
   end

   table.sort(commands)
   base_config.command_list = commands

   if config.groups then
      for k,v in pairs(config.groups) do
         base_config.groups[k] = v
      end
   end

   local groups = {}
   for k,v in pairs(base_config.groups) do
      table.insert(groups, k)
   end

   table.sort(groups)
   base_config.group_list = groups

   base_config.node_repls = config.node_repls or {}

   base_config.node_groups = config.node_groups or {}

   
   return base_config
end
