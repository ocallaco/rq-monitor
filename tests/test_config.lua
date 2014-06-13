
return {
   namespace = "REDISQUEUE",
   commands = {
      spawn_lb = {name = 'spawn_lb', args = {4}, desc = "spawn_lb"},
      spawn_lb_repl = {name = 'spawn_lb', args = "REPL", desc = "spawn_lb(#)"},
      spawn_mr = {name = 'spawn_mr', args = {8}, desc = "spawn_mr"},
      spawn_mr_repl = {name = 'spawn_mr', args = "REPL", desc = "spawn_mr(#)"},
      spawn_del = {name = 'spawn_del', args = {4}, desc = "spawn_del"},
      spawn_del_repl = {name = 'spawn_del', args = "REPL", desc = "spawn_del(#)"},
   },

   node_repls = {
      do0 = {host="localhost",port="10001"},
      do1 = {host="localhost",port="10002"},
   },
}
