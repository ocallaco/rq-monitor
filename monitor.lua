local rc = require 'redis-async'
local rs = require 'redis-status.server'
local rq = require 'redis-queue'

local uv = require 'luv'
local async = require 'async'
local fiber = require 'async.fiber'
local handle = require 'async.handle'

local curses = require 'ncurses'

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

local stdin = handle(io.stdin)

stdin.ondata(function(data)
   local v = data:byte()
   -- exit on ^C and ^D
   if v == 3 or v == 4 then
      uv.tty_set_mode(io.stdin, 0)
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
local display = {
   commandbar = {},
   display_area = {}
}

--  window helper functions
local function create_newwin(height, width, starty, startx)
   local local_win;
	local_win = curses.newwin(height, width, starty, startx)
	curses.box(local_win, 0 , 0)		
   curses.wrefresh(local_win)
	return local_win;
end

local function refresh()
   curses.box(display.commandbar.win, 0 , 0)	
   curses.wrefresh(display.commandbar.win)

   for i,win in pairs(display.display_area.node_wins) do
      curses.box(win, 0 , 0)	
      curses.wrefresh(win)
   end

   curses.refresh()

end


local HEIGHT = 10
local WIDTH = 40
local ROWS = 6


if not opt.print then
   curses.initscr()
   display.width = curses.getmaxx(curses.stdscr)
   display.height = curses.getmaxy(curses.stdscr)
   ROWS = math.floor(display.height / HEIGHT )
   display.commandbar.width = math.floor(display.width / 4)
   display.commandbar.height = display.height 
   display.commandbar.win = create_newwin(display.commandbar.height, display.commandbar.width, 0, 0)

   display.display_area.startx = display.commandbar.width + 1
   display.display_area.starty = 0
end


-- set up node and worker representation
local nodes = {}
local node_names = {}
display.display_area.node_wins = {}

local update_last_seen = function()
   for i,nodename in ipairs(node_names) do
      local nodeEntry = nodes[nodename]
      local win = display.display_area.node_wins[nodename]
      curses.mvwprintw(win, 3, 1, "Last Seen: " .. getTimeAgo(tonumber(nodeEntry.last_seen)) .. " ago")
   end

   refresh()
end

async.setInterval(1000, update_last_seen)

local updateNode = function(nodename, workername)
   local nodeEntry = nodes[nodename]

   if opt.print then
      print(nodeEntry)
      return
   end

   local win = display.display_area.node_wins[nodename]

   curses.mvwprintw(win, 1, 1, nodename)
   curses.mvwprintw(win, 2, 1, "Number of workers: " .. #nodeEntry.worker_names)
   curses.mvwprintw(win, 3, 1, "Last Seen: " .. getTimeAgo(tonumber(nodeEntry.last_seen)) .. " ago")

   for i,workername in ipairs(nodeEntry.worker_names) do
      curses.mvwprintw(win, 3 + i, 1, "Worker: " .. workername)   
   end

   curses.box(win, 0 , 0)	
   curses.wrefresh(win)
   curses.refresh()
end

local onNewNode = function(name)
   table.insert(node_names,name)
   nodes[name] = {workers = {}, last_seen = os.time(), worker_names = {}}
   
   local numnodes = #node_names - 1
   local startx = math.floor(numnodes / ROWS) * WIDTH
   local starty = math.floor(numnodes * HEIGHT) % (ROWS * HEIGHT)
   if opt.print then
      print(display)
   end
   display.display_area.node_wins[name] = create_newwin(HEIGHT, WIDTH, display.display_area.starty, display.display_area.startx)
end

local onNewWorker = function(nodename, workername)
   nodes[nodename].workers[workername] = {last_seen = os.time()}
   table.insert(nodes[nodename].worker_names, workername)
end

local onStatus = function(nodename, workername, status)
   --print(nodes)
   nodes[nodename].workers[workername].status = status
   nodes[nodename].workers[workername].last_seen = os.time()
   nodes[nodename].last_seen = os.time()
   updateNode(nodename, workername)
end

fiber(function()

   local writecli = wait(rc.connect, {redis_details})
   local subcli = wait(rc.connect, {redis_details})


   local server = rs(writecli, subcli, "RQ", {onStatus = onStatus, onWorkerReady = onNewWorker, onNodeReady = onNewNode})

   for i,node in ipairs(node_names) do
      server.issueCommand({"CONTROLCHANNEL:RQ:" .. node}, "restart", function(res)  end)
   end

end)


async.go()


