local rc = require 'redis-async'
local rs = require 'redis-status.server'
local rq = require 'redis-queue'
local io_manager = require './io.lua'

local uv = require 'luv'
local async = require 'async'
local fiber = require 'async.fiber'
local handle = require 'async.handle'
local tcp = require 'async.tcp'

local curses = require 'ncurses'

local windowbox = require './windowbox.lua'

local monitor_config = require './config'

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

local iomanager = io_manager(timers, clients)


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
   outputbar.box.setscrolllock(false)


   -- put text buffer on debug bar
   iomanager.onBuffer(function(data)
      if data == "" then
         data = "\n"
      end

      debugbar.box.settext(data)
      debugbar.box.redraw()
   end)


   display_startx = commandbar.width + 1
   display_starty = 0

   ROWS = math.floor((height - 21) / HEIGHT )
end

local replclient
local replbuffer = {}


local endrepl = function()
   if replclient then replclient.close() end
   replclient = nil
end


local writetorepl = function()
end


local setrepl = function(domain)

   -- i hope we can just drop the old client and replace it with a new one without waiting for a callback
   if replclient then
      endrepl()
   end

   tcp.connect(domain, function(client)
      -- receive results from server
      client.ondata(function(data)
         outputbar.box.append(data)
         outputbar.box.redraw()
      end)

      replclient = client

      writetorepl = function(data)
         client.write(' '..data .. "\n") 
      end

      -- now that we're connected, drain the buffer
      for i,line in ipairs(replbuffer) do
         writetorepl(' ' .. line)
      end

      replbuffer = {}
   end)

   -- until we're connected, we need to buffer all input
   writetorepl = function(data)
      table.insert(replbuffer, data)
   end
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
      table.insert(text_tbl, "Worker: " .. workername)   
      table.insert(text_tbl, "\n")
   end
   
   box.settext(table.concat(text_tbl))
   box.redraw()
end

local update_last_seen = function()
   for i,nodename in ipairs(node_names) do
      updateNode(nodename)
   end
end

table.insert(timers, async.setInterval(1000, update_last_seen))

local onNewNode = function(nodename)
   table.insert(node_names,nodename)
   local nodeEntry = {workers = {}, last_seen = os.time(), worker_names = {}}
   
   local numnodes = #node_names - 1
   local startx = display_startx + math.floor(numnodes / ROWS) * WIDTH
   local starty = display_starty + math.floor(numnodes * HEIGHT) % (ROWS * HEIGHT)

   nodeEntry.box = windowbox(HEIGHT, WIDTH, starty, startx)
   nodes[nodename] = nodeEntry
   updateNode(nodename)
end

local onNewWorker = function(nodename, workername)
   nodes[nodename].workers[workername] = {last_seen = os.time()}
   table.insert(nodes[nodename].worker_names, workername)
   updateNode(nodename)
end

local onDeadWorker = function(nodename, workername)
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


local onStatus = function(nodename, workername, status)
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


   server = rs(writecli, subcli, "RQ", {onStatus = onStatus, onWorkerReady = onNewWorker, onNodeReady = onNewNode, onDeadWorker = onDeadWorker})
   
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
   
   iomanager.unbuffered_mode()
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
   endrepl()
end

local set_group_state = function()
   commandbar.state = "GROUP" 
   iomanager.buffered_mode()
end

local set_repl_state = function()
   commandbar.state = "REPL"
   -- print output to debug window
   iomanager.buffered_mode()
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

local execute_command = function(comnumber)
   local commandname = config.command_list[comnumber]

   if commandname == "repl" then
      local domain = config.node_repls[commandbar.selected_node]
      setrepl(domain)
      set_repl_state()
      return
   end

   local command = config.commands[commandname]

   if command.args == "REPL" then
      -- put the command name onto the buffer
      iomanager.add_to_buffer(command.name or commandname .. "(")
      set_repl_state()
      return
   end

   if commandbar.selected_node then
      server.issueCommand({"CONTROLCHANNEL:RQ:" .. commandbar.selected_node}, commandname, command.args or {}, function(res)  end)
   else
      -- figure out selected node group
      for i,node in ipairs(node_names) do
         server.issueCommand({"CONTROLCHANNEL:RQ:" .. node}, commandname, command.args or {}, function(res)  end)
      end
   end

   set_base_state()

end

iomanager.handleInput(function(data)
   debugbar.box.clear()
   if commandbar.state == "REPL" then
      writetorepl(data)
      return
   end

   if commandbar.state == "BASE" then
      local input = data:sub(1,1)
      if input == "n" then
         set_node_state()
      end
      --TODO: make this handle numbers higher than 9
   elseif commandbar.state == "NODE" then
      local comnumber = tonumber(data)
      if comnumber then
         local nodename = node_names[comnumber]
         commandbar.selected_node = nodename
         curses.printw(nodename)
         set_selected_box(nodes[nodename].box)
         set_command_state()
      end
   elseif commandbar.state == "COMMAND" then
      local comnumber = tonumber(data)
      if comnumber then
         execute_command(comnumber) 
      end
   end
end)

set_base_state()
iomanager.onEscape(set_base_state)

async.go()


