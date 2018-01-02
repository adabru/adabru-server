require! [child_process]

# test execution:
#
# i 0 c1 ┬
#   1    ├m1
#   2    ┴
#   3 c2 ┬
#   4    │   ┬ s1
#   5    ├m2 │
#   6    │   ┴
#   7    │   ┬ s2
#   8    ├m3 │
#   9    ┴   │
#  10 c3 ┬   │
#  11    ├m4 │
#  12    │   ┴
#  13    ┴
#  14
#
# whilte box: log folder
# black box: http request
#

tcp_port = 1566
http_port = 1567
# must be adapted to logpipe.js
connect_timeout = 1000

fork = (module, args, name, close) ->
  cp = child_process.fork module, args, {stdio: 'pipe', env:{"DEBUG":"true"}}
  [cp.stdout, cp.stderr].map (s) -> s.setEncoding 'utf8'
  cp.stdout.on 'data', (d) -> console.log "\x1b[1m#name\x1b[22m #{d.trim!}"
  cp.stderr.on 'data', (d) -> console.log "\x1b[91m#name\x1b[39m #{d.trim!}"
  cp.on 'close', (code) -> console.log "\x1b[1m#name\x1b[22m closed with #code" ; close!
  cp

switch
  | process.argv.2 is "client"
    pipe = fork "./logpipe.js", [process.argv.2, tcp_port], process.argv.2, ->
    process.on "message", (m) -> switch m
      | "exit" then process.exit!
      else then pipe.stdin.write m
  else
    state = i:0
    trans = ->
      console.log "\x1b[32mstate #{state.i}\x1b[39m"
      switch state.i++
        | 0
          state.c1 = fork './test_log.js', ['client'], "c1", trans
          setTimeout trans, 200
        | 1
          state.c1.send "m1"
          setTimeout trans, 200
        | 2
          state.c1.send "exit"
        | 3
          state.c2 = fork './test_log.js', ['client'], "c2", trans
          setTimeout trans, 200
        | 4
          state.s1 = fork './logserver.js', [tcp_port, http_port], "s1", trans
          setTimeout trans, 200
        | 5
          state.c2.send "m2"
          setTimeout trans, connect_timeout+200
        | 6
          state.s1.kill "SIGTERM"
        | 7
          state.s2 = fork './logserver.js', [tcp_port, http_port], "s2", trans
          setTimeout trans, 200
        | 8
          state.c2.send "m3"
          setTimeout trans, connect_timeout+200
        | 9
          state.c2.send "exit"
        | 10
          state.c3 = fork './test_log.js', ['client'], "c3", trans
          setTimeout trans, 200
        | 11
          state.c3.send "m4"
          setTimeout trans, 200
        | 12
          state.s2.kill "SIGTERM"
        | 13
          state.c3.send "exit"
        | 14
          console.log "\x1b[32mfinish\x1b[39m"
    trans!
