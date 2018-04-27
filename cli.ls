#!/usr/bin/env lsc

require! [http,child_process,fs]

help = -> console.log '''

\033[1musage\033[0m: cli.js command

  \033[1mls\033[0m
    list all available processes

  \033[1mstart\033[0m [name|ci]

  \033[1mstop\033[0m [name|ci]

  \033[1mrestart\033[0m [name|ci]

  \033[1mlog\033[0m [name]

'''

config = JSON.parse fs.readFileSync "./config.json"
supervisor = require "./supervisor.js"

fetch = (service, port, path, callback) ->
  req = http.request {hostname: "::1", port, path: "#path"}, (res) ->
    chunks = []
    res.on "data", (c) -> chunks.push c
    res.on "end", -> callback Buffer.concat(chunks).toString('utf-8'), res.statusCode
  req.on 'error', (e) ->
    console.log "\033[31mcannot connect to service \033[1m#service\033[22m!\033[39m"
    callback!
  req.end!
print_log = (log) ->
  log.pop!
  pad = (s) -> "  #s".substr -2
  console.log log.map((line) ->
    d = new Date line.d
    m = ['Jan' 'Feb' 'Mar' 'Apr' 'Jun' 'Jul' 'Aug' 'Sep' 'Oct' 'Nov' 'Dec']
    dt = Date.now! - d.getTime!
    diff = switch
      case dt <                 99 * 1000 then "#{pad Math.round dt                      / 1000}s"
      case dt <            99 * 60 * 1000 then "#{pad Math.round dt                 / 60 / 1000}m"
      case dt <       20 * 60 * 60 * 1000 then "#{pad Math.round dt            / 60 / 60 / 1000}h"
      case dt <   5 * 24 * 60 * 60 * 1000 then "#{pad Math.round dt       / 24 / 60 / 60 / 1000}d"
      case dt <  35 * 24 * 60 * 60 * 1000 then "#{pad Math.round dt   / 7 / 24 / 60 / 60 / 1000}w"
      case dt < 300 * 24 * 60 * 60 * 1000 then "#{pad Math.round dt  / 30 / 24 / 60 / 60 / 1000}m"
      case dt <                  Infinity then "#{pad Math.round dt / 365 / 24 / 60 / 60 / 1000}y"
    "\033[34m#{d.getUTCFullYear!} #{m[d.getUTCMonth!]} #{pad d.getUTCDate!} \033[2m#{pad d.getUTCHours!}\033[22m#{pad d.getHours!}:#{pad d.getUTCMinutes!}:#{pad d.getUTCSeconds!}\033[39m \033[33m\033[2m#{diff}\033[22m\033[39m #{line.s.trimRight!}"
  ).join '\n'
print_process = (p) ->
  s = "\033[1m#{p.name}\033[22m"
  s += ' '.repeat 16 - p.name.length
  s += switch p.status
    case "running"     then "\033[32mrunning\033[39m       #{p.ports}"
    case "stopped"     then "\033[31mstopped\033[39m       #{"    "}"
    case "not running" then "\033[33mnot running\033[39m   #{"    "}"
  console.log s

(res, code) <- fetch "ci", config.env.ciport, "/ls", _
m = (regex) -> new RegExp("^#{regex.source}$").test process.argv.2 + if process.argv.3? then " #that" else ''
if res? then (switch
  |m /ls/
    (res) <- fetch "ci", config.env.ciport, "/ls", _
    ps = JSON.parse res
    for p in ps
      print_process p
  |m /start( ci)?/
    console.log "ci is already running"
  |m /start .+/
    fetch "ci", config.env.ciport, "/start/#{process.argv.3}", console.log
  |m /stop( ci)?/
    process.stdout.write "Stopping ci..."
    (pid) <- supervisor.pgrep /.\/ci.js/, _
    <- supervisor.terminate pid, _
    console.log " ✔"
  |m /stop .+/
    fetch "ci", config.env.ciport, "/stop/#{process.argv.3}", console.log
  |m /restart( ci)?/
    process.stdout.write "Stopping ci..."
    (pid) <- supervisor.pgrep /.\/ci.js/, _
    <- supervisor.terminate pid, _
    console.log " ✔"
    console.log "ci started with PID #{supervisor.start({logname:'ci', script:'./ci.js', args:'./config.json', logport:config.env.logport}).pid}"
  |m /restart .+/
    (res, status) <- fetch "ci", config.env.ciport, "/stop/#{process.argv.3}", _
    console.log res, status
    if status is 200
      fetch "ci", config.env.ciport, "/start/#{process.argv.3}", console.log
  |m /log .+/
    (res, status) <- fetch "log", config.env.logbackendport, "/#{process.argv.3}", _
    if status is 200
      print_log JSON.parse res
    else
      console.log res, status
  |m /.*/
    help!
) else (switch
  |m /start( ci)?/ then fallthrough
  |m /restart( ci)?/
    console.log "ci started with PID #{supervisor.start({logname:'ci', script:'./ci.js', args:'./config.json', logport:config.env.logport}).pid}"
  |m /ls/ then fallthrough
  |m /start .+/ then fallthrough
  |m /stop( ci)?/ then fallthrough
  |m /stop .+/ then fallthrough
  |m /restart .+/
    console.error '\033[31mci is not running. Start it with \033[1mcli start [ci]\033[22m.\033[39m'
  |m /log .+/
    (res, status) <- fetch "log", config.env.logbackendport, "/#{process.argv.3}", _
    if status is 200
      print_log JSON.parse res
    else
      console.log res, status
  |m /.*/
    help!
)
