local curses = require 'ncurses'

return function(height, width, starty, startx, parentbox)
   local box = {}

   if parentbox ~= nil then
      starty = starty + parentbox.starty
      startx = startx + parentbox.startx
   end

   box.win = curses.newwin(height, width, starty, startx)
	curses.box(box.win, 0 , 0)		
   curses.wrefresh(box.win)

   box.redraw = function()
      local lines = math.min(height, #box.text - box.curpos[1])
      for i=1,lines do
         local line = box.text[i +  box.curpos[1]]:sub(box.curpos[2], box.curpos[2] + width)
         curses.mvwprintw(box.win, i, 1, line)
         curses.wclrtoeol(box.win)
      end
      curses.box(box.win, 0 , 0)		
      curses.wrefresh(box.win)
   end

   local widest_line = 0
   box.text = {""}
   -- split the text by \n determine width and height for scrolling
   box.settext = function(text)
      box.text = stringx.split(text, "\n")

      for i,line in ipairs(box.text) do
         if #line > widest_line then
            widest_line = #line
         end
      end
   end

   box.curpos = {0,0}
   -- (up -1 down +1), (left -1 right +1)
   box.scroll = function(ud, lr)
      box.curpos[1] = math.min(math.max(0, box.curpos[1] + ud), #box.text - height + 1) -- add 1 because of border
      box.curpos[2] = math.min(math.max(0, box.curpos[2] + lr), widest_line - width + 3) -- adding 2 because of borders
   end

   return box

end


