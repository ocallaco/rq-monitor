local rc = require 'redis-async'
local rs = require 'redis-status.server'
local rsp = require 'redis-status.protocol'
local rq = require 'redis-queue'


local uv = require 'luv'
local async = require 'async'
local fiber = require 'async.fiber'
local handle = require 'async.handle'

local curses = require 'ncurses'

local windowbox = require './windowbox.lua'

redis_details = {host='localhost', port=6379}

local opt = lapp([[
thnode: a Torch compute node
   -p,--print dont use ncurses
   -c, --cfg load a config file
]])


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
io.stdin = uv.new_tty(0,1)
uv.tty_set_mode(io.stdin, 1)

local keyhandler = {
   onUpArrow = function()
   end,
   onDownArrow = function()
   end,
   onRightArrow = function()
   end,
   onLeftArrow = function()
   end,
   onEscape = function()
   end,
   handleInput = function(data)
   end
}

local timers = {}
local clients = {}

local stdin = handle(io.stdin)

stdin.ondata(function(data)
   local v = data:byte()
   -- exit on ^C and ^D
   if v == 3 or v == 4 then
      uv.tty_set_mode(io.stdin, 0)
      curses.endwin()
      for timer in ipairs(timers) do
         timer.clear()
      end

      for client in ipairs(clients) do
         client.close()
      end

      os.exit()
   end
   
   if v == 27 then
      local nextbyte = data:byte(2)
      if not nextbyte then
         keyhandler.onEscape()
         return
      end

      if nextbyte == 91 then
         dirbyte = data:byte(3)
         if dirbyte == 65 then
            keyhandler.onUpArrow()
            return
         elseif dirbyte == 66 then
            keyhandler.onDownArrow()
            return
         elseif dirbyte == 67 then
            keyhandler.onRightArrow()
            return
         elseif dirbyte == 68 then
            keyhandler.onLeftArrow()
            return
         end
      end
   end

   keyhandler.handleInput(data)

end)


-- Set up the display
local commandbar = {}


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
   commandbar.height = height 
   commandbar.box = windowbox(commandbar.height, commandbar.width, 0, 0)

   display_startx = commandbar.width + 1
   display_starty = 0

   ROWS = math.floor(height / HEIGHT )
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
      keyhandler.onUpArrow = function()
         box.scroll(-1,0)
         box.redraw()
      end
      keyhandler.onDownArrow = function()
         box.scroll(1,0)
         box.redraw()
      end
      keyhandler.onRightArrow = function()
         box.scroll(0,1)
         box.redraw()
      end
      keyhandler.onLeftArrow = function()
         box.scroll(0,-1)
         box.redraw()
      end
   else
      keyhandler.onUpArrow = function()
         commandbar.box.scroll(-1,0)
         commandbar.box.redraw()
      end
      keyhandler.onDownArrow = function()
         commandbar.box.scroll(1,0)
         commandbar.box.redraw()
      end
      keyhandler.onRightArrow = function()
         commandbar.box.scroll(0,1)
         commandbar.box.redraw()
      end
      keyhandler.onLeftArrow = function()
         commandbar.box.scroll(0,-1)
         commandbar.box.redraw()
      end
   end
end


commandbar.state = "BASE"

local base_commands = [[
(n)   node select
]]

local set_base_state = function()
   commandbar.state = "BASE"
   commandbar.box.settext(base_commands)
   commandbar.box.redraw() 
   set_selected_box(nil)
   commandbar.selected_node = nil
end

local set_node_state = function()
   commandbar.state = "NODE"
   local node_text_list = {}
   for i,nodename in ipairs(node_names) do
      table.insert(node_text_list, "(" .. i .. ") ")
      table.insert(node_text_list, nodename)
      table.insert(node_text_list, "\n")
   end

   commandbar.box.settext(table.concat(node_text_list))
   commandbar.box.redraw() 
end

local set_command_state = function()
   commandbar.state = "COMMAND"
   command_text_list = {}
   for i,command in ipairs(rsp.standard_commands) do
      table.insert(command_text_list, "(" .. i .. ") ")
      table.insert(command_text_list, command)
      table.insert(command_text_list, "\n")
   end
   commandbar.box.settext(table.concat(command_text_list))
   commandbar.box.redraw() 
end

keyhandler.handleInput = function(data)
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
         local commandname = rsp.standard_commands[comnumber]

         if commandbar.selected_node then
            server.issueCommand({"CONTROLCHANNEL:RQ:" .. commandbar.selected_node}, commandname, function(res)  end)
         else
            for i,node in ipairs(node_names) do
               server.issueCommand({"CONTROLCHANNEL:RQ:" .. node}, commandname, function(res)  end)
            end
         end
         set_base_state()
      end
   end
end

keyhandler.onEscape = set_base_state

async.go()


