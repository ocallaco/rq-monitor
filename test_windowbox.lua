local curses = require 'ncurses'
local async = require 'async'
local handle = require 'async.handle'
local uv = require 'luv'

local windowbox = require './windowbox.lua'


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
      curses.endwin()

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

curses.initscr()

local text = [[
Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do 
eiusmod tempor incididunt 
ut labore et dolore 
magna aliqua. Ut enim ad minim veniam, quis nostrud 
exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in
reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. 

Excepteur sint occaecat cupidatat non proident, 
sunt 
in 
 culpa 
   qui 
    officia 
      deserunt 
       mollit 

       
anim id est laborum
]]


local window = windowbox(10, 30, 0, 0)

window.settext(text)

keyhandler.onUpArrow = function()
   window.scroll(-1,0)
   window.redraw()
end
keyhandler.onDownArrow = function()
   window.scroll(1,0)
   window.redraw()
end
keyhandler.onRightArrow = function()
   window.scroll(0,1)
   window.redraw()
end
keyhandler.onLeftArrow = function()
   window.scroll(0,-1)
   window.redraw()
end

window.redraw()

async.go()
