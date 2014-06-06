local async = require 'async'
local handle = require 'async.handle'
local uv = require 'luv'

local curses = require 'ncurses'

return function(timers, clients, replmanager)
   -- TODO: keyhandler[keystroke] should point to the handler function for each key
   -- if it's a multiple key sequence (up arrow, etc) then have it point to a similar table
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
      onBuffer = function(data)
      end,
      handleInput = function(data)
      end,
   }

   local buffered = false
   local buffer = {}

   local handle_function

   local exit_cleanly = function()

      handle_function = function() end

      for timer in ipairs(timers) do
         timer.clear()
      end

      local counter = 0
      for client in ipairs(clients) do
         client.close()
         counter = counter + 1
      end

      if replmanager then
         replmanager.kill()
      end

      -- giving 2 seconds to kill all connections.  i hope that's enough
      async.setTimeout(2000, function()
         uv.tty_set_mode(io.stdin, 0)
         curses.endwin()
         os.exit()
      end)

   end

   handle_function = function(data)

      local v = data:byte()
         
      -- exit on ^C and ^D
      if v == 3 or v == 4 then
         exit_cleanly()
      end

      -- handle escape before buffer
      if v == 27 then 
         local nextbyte = data:byte(2)
         if not nextbyte then
            keyhandler.onEscape()
            return
         elseif nextbyte == 91 then
            local dirbyte = data:byte(3)
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


      if buffered then
         -- split on \n
         if v == 13 then 
            data = table.concat(buffer)
            buffer = {}
         else
            if v == 127 then --backspace
               table.remove(buffer)
            else
               table.insert(buffer, data)
            end
            keyhandler.onBuffer(table.concat(buffer))
            return
         end
      end

      keyhandler.handleInput(data)
   end


   local io_manager = {}

   io.stdin = uv.new_tty(0,1)
   uv.tty_set_mode(io.stdin, 1)
   io_manager.stdin = handle(io.stdin)
   io_manager.stdin.ondata(handle_function)

   io_manager.buffered_mode = function()
      buffered = true 
      buffer = {}
   end

   io_manager.unbuffered_mode = function()
      buffered = false 
      buffer = {}
   end

   io_manager.onUpArrow = function(cb)
      keyhandler.onUpArrow = cb
   end

   io_manager.onDownArrow = function(cb)
      keyhandler.onDownArrow = cb
   end

   io_manager.onRightArrow = function(cb)
      keyhandler.onRightArrow = cb
   end

   io_manager.onLeftArrow = function(cb)
      keyhandler.onLeftArrow = cb
   end

   io_manager.onEscape = function(cb)
      keyhandler.onEscape = cb
   end

   io_manager.onBuffer = function(cb)
      keyhandler.onBuffer = cb
   end
   
   io_manager.handleInput = function(cb)
      keyhandler.handleInput = cb
   end

   io_manager.add_to_buffer = function(text)
      table.insert(buffer, text)
      keyhandler.onBuffer(table.concat(buffer))
   end

   return io_manager
end


