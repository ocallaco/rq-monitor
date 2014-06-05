local curses = require 'ncurses'

--TODO: make resizable and movable 
return function(height, width, starty, startx, parentbox)
   local box = {}

   if parentbox ~= nil then
      starty = starty + parentbox.starty
      startx = startx + parentbox.startx
   end

   --could make this configurable
   box.maxlen = 1000

   box.win = curses.newwin(height, width, starty, startx)
	curses.box(box.win, 0 , 0)		
   curses.wrefresh(box.win)
   
   local bottom = function()
      return #box.text - height + 1
   end

   box.scroll_lock = true
   -- true means locked.  false means scrolls to bottom
   box.setscrolllock = function(scrolllock)
      box.scroll_lock = scroll 
   end

   box.redraw = function()
--      local lines = math.min(height, #box.text - box.curpos[1])
      for i=1,height do
         local l1 = box.text[i +  box.curpos[1]] or ""
         local line = l1:sub(box.curpos[2], box.curpos[2] + width) or ""
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
      -- might need to slice the text if > maxlen or error
   end

   box.append = function(text)
      local lines =  stringx.split(text, "\n")

      for i,line in ipairs(lines) do
         if #line > widest_line then
            widest_line = #line
         end

         table.insert(box.text,line)
         if #box.text > box.maxlen then
            table.remove(box.text, 1)
         end
      end

      -- if we're not locked from scrolling jump to bottom
      if not box.scroll_lock then
         box.curpos[1] =  bottom()
      end

   end

   box.clear = function()
      box.settext("\n")
      box.redraw()
   end

   box.curpos = {0,0}
   -- (up -1 down +1), (left -1 right +1)
   box.scroll = function(ud, lr)
      box.curpos[1] = math.max(0, math.min(box.curpos[1] + ud, bottom())) -- add 1 because of border
      box.curpos[2] = math.max(0, math.min(box.curpos[2] + lr, widest_line - width + 3)) -- adding 2 because of borders

      if box.curpos[1] == bottom() then
         box.setscrolllock(false)
      else
         box.setscrolllock(true)
      end
   end

   return box

end


