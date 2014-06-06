local curses = require 'ncurses'

local colors = {
   none = '%[0m',
   black = '%[0;30m',
   red = '%[0;31m',
   green = '%[0;32m',
   yellow = '%[0;33m',
   blue = '%[0;34m',
   magenta = '%[0;35m',
   cyan = '%[0;36m',
   white = '%[0;37m',
   Black = '%[1;30m',
   Red = '%[1;31m',
   Green = '%[1;32m',
   Yellow = '%[1;33m',
   Blue = '%[1;34m',
   Magenta = '%[1;35m',
   Cyan = '%[1;36m',
   White = '%[1;37m',
   _black = '%[40m',
   _red = '%[41m',
   _green = '%[42m',
   _yellow = '%[43m',
   _blue = '%[44m',
   _magenta = '%[45m',
   _cyan = '%[46m',
   _white = '%[47m',
}

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

   box.scroll_lock = false
   -- true means locked.  false means scrolls to bottom
   box.setscrolllock = function(scrolllock)
      box.scroll_lock = scroll 
   end

   box.redraw = function()
--      local lines = math.min(height, #box.text - box.curpos[1])
      for i=1,height do
         -- for now, not using the colors
         local line_table = {""}
         
         for i,entry in ipairs(box.text[i +  box.curpos[1]] or {}) do
            table.insert(line_table,entry[2])
         end

         local l1 = table.concat(line_table)

         local line = l1:sub(box.curpos[2], box.curpos[2] + width) or ""
         curses.mvwprintw(box.win, i, 1, line)
         curses.wclrtoeol(box.win)
      end
      curses.box(box.win, 0 , 0)		
      curses.wrefresh(box.win)
   end

   local widest_line = 0
   box.text = {}
   box.colored_text = {}

   
   local split_colors = function(line)
      local entries = {}

      local split_line = stringx.split(line, "\27")

      for i,section in ipairs(split_line) do
         local color = "none"
         for cname,val in pairs(colors) do
            local x = section:find(val)
            if x == 1 then
               local cleaned = section:gsub(val, "")
               table.insert(entries, {cname, cleaned})
               color = nil
               break
            end
         end

         if color then
            table.insert(entries, {color, section})
         end
      end

      return entries
   end



   -- split the text by \n determine width and height for scrolling
   box.settext = function(text)
      local split_text = stringx.split(text, "\n")

      box.text = {}

      for i,line in ipairs(split_text) do
         if #line > widest_line then
            widest_line = #line
         end
         table.insert(box.text, split_colors(line))
      end
      -- might need to slice the text if > maxlen or error
   end

   box.append = function(text)
      local lines =  stringx.split(text, "\n")

      for i,line in ipairs(lines) do
         if #line > widest_line then
            widest_line = #line
         end

         table.insert(box.text,split_colors(line))
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


