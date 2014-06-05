local REPL = "REPL"
local ALL = "ALL"

-- if response = REPL, that means enter a repl before issuing command to see response
-- if args = REPL, that means open repl to set your own args
-- repl command is a special case
return function(config)
   local base_config = {
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
      }
   }

   if config.commands then
      for k,v in pairs(config.commands) do
         base_config.commands[k] = v
      end
   end

   local commands = {}
   for k,v in pairs(base_config.commands) do
      table.insert(commands, k)
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
