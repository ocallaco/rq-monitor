return {
   commands = {
      spawn_test = {name = 'spawn_test', args = {}, desc = "spawn_test"},
      spawn_test_repl = {name = 'spawn_test', args = "REPL", desc = "spawn_test(#)"},
   },

   node_repls = {
      t1 = {host="localhost",port="10001"},
      t2 = {host="localhost",port="10002"},
      t3 = {host="localhost",port="10003"},
      t4 = {host="localhost",port="10004"},
      t5 = {host="localhost",port="10005"},
      t6 = {host="localhost",port="10006"},
      t7 = {host="localhost",port="10007"},
   }
}
