local rc = require 'redis-async'
local rs = require 'redis-status.server'
local rq = require 'redis-queue'
local io_manager = require 'rq-monitor.io'

local uv = require 'luv'
local async = require 'async'
local fiber = require 'async.fiber'
local handle = require 'async.handle'
local tcp = require 'async.tcp'

local curses = require 'ncurses'

local windowbox = require 'rq-monitor.windowbox'
local replmanager = require 'rq-monitor.replmanager'

local monitor_config = require 'rq-monitor.config'

redis_details = {host='localhost', port=6379}

local opt = lapp([[
thnode: a Torch compute node
   -p,--print dont use ncurses
   -c, --cfg (string) load a config file
]])

local config
if opt.cfg then
   print(opt.cfg)
   local config_table = require(opt.cfg)
   config = monitor_config(config_table)
else
   config = monitor_config({})
end

-- get a list of node groups
local node_groups = {"all"}

for name,list in pairs(config.node_groups) do
   table.insert(node_groups, name)
end


-- helper function
local function getTimeAgo(ts)
   local ago = os.time() - ts

   if ago < 60 then
      return ago .. " seconds"
   elseif ago < (60 * 60) then
      return math.floor(ago / 60) .. " minutes"
   elseif ago < (24 * 60 * 60) then
      return math.floor(ago / 60 / 60) .. " hours"
   else
      return "long ass time"
   end
end


-- IO Handler:
--start reading 

local timers = {}
local clients = {}

local repl

local iomanager = io_manager(timers, clients, repl)


-- Set up the display
local commandbar = {}
local debugbar = {}
local outputbar = {}

local HEIGHT = 10
local WIDTH = 40
local ROWS = 6

local display_startx = 0
local display_starty = 0
   
if not opt.print then
   curses.initscr()
   
--   if curses.has_colors() ~= 0 then
--      curses.start_color()
--      curses.init_pair(1, 1, 0)
--      curses.attron(curses.COLOR_PAIR(1))
--   end

   local width = curses.getmaxx(curses.stdscr)
   local height = curses.getmaxy(curses.stdscr)

   commandbar.width = math.floor(width / 4)
   commandbar.height = height  - 21
   commandbar.box = windowbox(commandbar.height, commandbar.width, 0, 0)

   debugbar.width = width
   debugbar.height = 5
   debugbar.box = windowbox(debugbar.height, debugbar.width, commandbar.height+1, 0)

   outputbar.width = width
   outputbar.height = 15
   outputbar.box = windowbox(outputbar.height, outputbar.width, debugbar.height + commandbar.height+1, 0)


   -- put text buffer on debug bar
   iomanager.onBuffer(function(data)
      if data == "" then
         data = "\n"
      end

      debugbar.box.settext(data)
      debugbar.box.redraw()
   end)

   -- pipe repl output to outputbar
   repl = replmanager(outputbar.box)

   display_startx = commandbar.width + 1
   display_starty = 0

   ROWS = math.floor((height - 21) / HEIGHT )
end

-- set up node and worker representation
local nodes = {}
local node_names = {}


local updateNode = function(nodename)
   local nodeEntry = nodes[nodename]

   if opt.print then
      print(nodeEntry)
      return
   end

   local box = nodeEntry.box

   local text_tbl = {}

   table.insert(text_tbl, nodename)
   table.insert(text_tbl, "\n")
   table.insert(text_tbl, "Number of workers: " .. #nodeEntry.worker_names)
   table.insert(text_tbl, "\n")
   table.insert(text_tbl, "Last Seen: " .. getTimeAgo(tonumber(nodeEntry.last_seen)) .. " ago")
   table.insert(text_tbl, "\n")

   for i,workername in ipairs(nodeEntry.worker_names) do
      if nodeEntry.workers[workername].status then
         local display_worker = (config.display_worker["node"] and config.display_worker["node"][nodename]) or config.display_worker.default
         table.insert(text_tbl, display_worker(nodename, workername, nodeEntry.workers[workername] and nodeEntry.workers[workername].status))   
      end
   end
   table.insert(text_tbl, "\n")
   
   box.settext(table.concat(text_tbl))
   box.redraw()
end

local update_last_seen = function()
   for i,nodename in ipairs(node_names) do
      updateNode(nodename)
   end
end

table.insert(timers, async.setInterval(1000, update_last_seen))

local newNode = function(nodename)
   local found = false
   for i,n in ipairs(node_names) do
      if n == nodename then 
         found = true
         break 
      end
   end

   local nodeEntry = {workers = {}, last_seen = os.time(), worker_names = {}}

   if not found then
      table.insert(node_names,nodename)
   
      local numnodes = #node_names - 1
      local startx = display_startx + math.floor(numnodes / ROWS) * WIDTH
      local starty = display_starty + math.floor(numnodes * HEIGHT) % (ROWS * HEIGHT)
      nodeEntry.box = windowbox(HEIGHT, WIDTH, starty, startx)
   else
      nodeEntry.box = nodes[nodename].box
   end
      
   nodes[nodename] = nodeEntry
   updateNode(nodename)
end

local newWorker = function(nodename, workername)
   nodes[nodename].workers[workername] = {last_seen = os.time()}
   table.insert(nodes[nodename].worker_names, workername)
   updateNode(nodename)
end

local deadWorker = function(nodename, workername)
   nodes[nodename].workers[workername] = nil
   local index
   for i,w in ipairs(nodes[nodename].worker_names) do
      if w == workername then 
         index = i
         break 
      end
   end
   table.remove(nodes[nodename].worker_names, index)
   updateNode(nodename)
end


local workerStatus = function(nodename, workername, status)
   --print(nodes)
   nodes[nodename].workers[workername].status = status
   nodes[nodename].workers[workername].last_seen = os.time()
   nodes[nodename].last_seen = os.time()
   updateNode(nodename)
end

--TODO: fix this. not really clean to do this with server available when possibly not initialized
local server

fiber(function()

   local writecli = wait(rc.connect, {redis_details})
   local subcli = wait(rc.connect, {redis_details})

   table.insert(clients, writecli)
   table.insert(clients, subcli)


   server = rs(writecli, subcli, config.namespace, {onStatus = workerStatus, onWorkerReady = newWorker, onNodeReady = newNode, onWorkerDead = deadWorker})
   outputbar.box.append("Connected on namespace " .. config.namespace .. "\n")
   outputbar.box.redraw()
   
end)

-- handle commands from the keyboard


local set_selected_box = function(box)
   if box then
      iomanager.onUpArrow(function()
         box.scroll(-1,0)
         box.redraw()
      end)

      iomanager.onDownArrow(function()
         box.scroll(1,0)
         box.redraw()
      end)
      iomanager.onRightArrow(function()
         box.scroll(0,1)
         box.redraw()
      end)
      iomanager.onLeftArrow(function()
         box.scroll(0,-1)
         box.redraw()
      end)
   else
      iomanager.onUpArrow(function()
         commandbar.box.scroll(-1,0)
         commandbar.box.redraw()
      end)
      iomanager.onDownArrow(function()
         commandbar.box.scroll(1,0)
         commandbar.box.redraw()
      end)
      iomanager.onRightArrow(function()
         commandbar.box.scroll(0,1)
         commandbar.box.redraw()
      end)
      iomanager.onLeftArrow(function()
         commandbar.box.scroll(0,-1)
         commandbar.box.redraw()
      end)
   end
end


local base_commands = [[
(n)   node select
(g)   group select
]]

local set_base_state = function()
   commandbar.state = "BASE"
   commandbar.box.settext(base_commands)
   commandbar.box.redraw() 
   set_selected_box(nil)
   commandbar.selected_node = nil
   commandbar.selected_group = nil
   
   iomanager.unbuffered_mode()
   repl.kill()
end

local set_node_state = function()
   -- outside of base state, want buffered input
   commandbar.state = "NODE"
   local node_text_list = {}
   for i,nodename in ipairs(node_names) do
      table.insert(node_text_list, "(" .. i .. ") ")
      table.insert(node_text_list, nodename)
      table.insert(node_text_list, "\n")
   end

   commandbar.box.settext(table.concat(node_text_list))
   commandbar.box.redraw() 
   
   iomanager.buffered_mode()
   repl.kill()
end

local set_group_state = function()
   commandbar.state = "GROUP" 
   local node_text_list = {}
   for i,groupname in ipairs(node_groups) do
      table.insert(node_text_list, "(" .. i .. ") ")
      table.insert(node_text_list, groupname)
      table.insert(node_text_list, "\n")
   end

   commandbar.box.settext(table.concat(node_text_list))
   commandbar.box.redraw() 

   iomanager.buffered_mode()
   repl.kill()
end

local set_repl_state = function(initial_data)
   commandbar.state = "REPL"
   -- print output to debug window
   iomanager.buffered_mode()
   iomanager.add_to_buffer(initial_data)
   set_selected_box(outputbar.box)
   commandbar.box.settext("In REPL.\nPress Esc to exit")
   commandbar.box.redraw()
end

local set_command_state = function()
   commandbar.state = "COMMAND"
   command_text_list = {}
   for i,command in ipairs(config.command_list) do
      table.insert(command_text_list, "(" .. i .. ") ")
      table.insert(command_text_list, command)
      table.insert(command_text_list, "\n")
   end
   commandbar.box.settext(table.concat(command_text_list))
   commandbar.box.redraw() 

   iomanager.buffered_mode()
end

local get_selected_node_list = function()
   local nodelist

   if commandbar.selected_group == "all" then
      nodelist = node_names
   else
      nodelist = config.node_groups[commandbar.selected_group] 
   end

   return nodelist
end

local get_current_domains = function()
   local domains
   if commandbar.selected_node then
      domains = {config.node_repls[commandbar.selected_node]}
   elseif commandbar.selected_group then
      local nodelist = get_selected_node_list()
      domains = {}
      for i,name in ipairs(nodelist) do
         if config.node_repls[name] then
            table.insert(domains, config.node_repls[name])
         end
      end
   else
      -- TODO: handle this ERROR -- 
      domains = {}
   end

   return domains
end

local execute_command = function(comnumber)
   local commandname = config.command_list[comnumber]

   if commandname == "repl" then
      local domains = get_current_domains()
      repl.set(domains)
      set_repl_state()
      return
   end

   local command = config.commands[commandname]

   if command.args == "REPL" then
      -- put the command name onto the buffer
      local domains = get_current_domains()
      repl.set(domains)
      set_repl_state((command.name or commandname) .. "(")
      return
   end

   if commandbar.selected_node then
      server.issueCommand({"CONTROLCHANNEL:" .. config.namespace .. ":" .. commandbar.selected_node}, commandname, command.args or {}, function(res) 
         outputbar.box.append("Issued command " .. commandname .. "\n")
         outputbar.box.redraw() 
      end)
   else
      local nodelist = get_selected_node_list()

      -- figure out selected node group
      for i,node in ipairs(nodelist) do
         server.issueCommand({"CONTROLCHANNEL:" .. config.namespace .. ":" .. node}, commandname, command.args or {}, function(res)  
            outputbar.box.append("Issued command " .. commandname .. "\n")
            outputbar.box.redraw()
         end)
      end
   end

   set_base_state()

end

iomanager.handleInput(function(data)
   debugbar.box.clear()
   if commandbar.state == "REPL" then
      repl.write(data)
      return
   end

   if commandbar.state == "BASE" then
      local input = data:sub(1,1)
      if input == "n" then
         set_node_state()
      elseif input == "g" then
         set_group_state()
      end
      --TODO: make this handle numbers higher than 9
   elseif commandbar.state == "NODE" then
      local comnumber = tonumber(data)
      if comnumber then
         local nodename = node_names[comnumber]
         commandbar.selected_node = nodename
--         outputbar.box.append("NODE " .. nodename)
--         outputbar.box.redraw()
         set_selected_box(nodes[nodename].box)
         set_command_state()
      end
   elseif commandbar.state == "COMMAND" then
      local comnumber = tonumber(data)
      if comnumber then
         execute_command(comnumber) 
      end
   elseif commandbar.state == "GROUP" then
      local comnumber = tonumber(data)
      if comnumber then
         local groupname = node_groups[comnumber]
         commandbar.selected_group = groupname
--         outputbar.box.append("GROUP " .. groupname)
--         outputbar.box.redraw()
         set_command_state()
      end
   end
end)

set_base_state()
iomanager.onEscape(set_base_state)

async.go()


