#!/usr/bin/env lsc

require! [http,child_process,fs,util]

help = -> console.log '''

\033[1musage\033[0m: cli.js command

  \033[1mls\033[0m
    list all available processes

  \033[1mstart\033[0m [name|ci]

  \033[1mstop\033[0m [name|ci]

  \033[1mrestart\033[0m [name|ci]

  \033[1mlog\033[0m [name]

  \033[1mconfig\033[0m [p|processes|v|vars|w|webhooks] [get key|set key value]

'''

config = JSON.parse fs.readFileSync "./.config/config.json"
supervisor = require "./supervisor.js"

fetch = (service, port, path, data, callback) ->
  req = http.request {hostname: "::1", port, path: "#path", method: if data? then 'PUT' else 'GET' }, (res) ->
    chunks = []
    res.on "data", (c) -> chunks.push c
    res.on "end", -> callback Buffer.concat(chunks).toString('utf-8'), res.statusCode
  req.on 'error', (e) ->
    console.log "\033[31mcannot connect to service \033[1m#service\033[22m!\033[39m"
    callback!
  req.end(data)
print_log = (log) ->
  log.pop!
  pad = (s) -> "  #s".substr -2
  console.log log.map((line) ->
    d = new Date line.d
    m = ['Jan' 'Feb' 'Mar' 'Apr' 'May' 'Jun' 'Jul' 'Aug' 'Sep' 'Oct' 'Nov' 'Dec']
    dt = Date.now! - d.getTime!
    diff = switch
      case dt <           99*1000 then "#{pad Math.round dt                      / 1000}s"
      case dt <        99*60*1000 then "#{pad Math.round dt                 / 60 / 1000}m"
      case dt <     20*60*60*1000 then "#{pad Math.round dt            / 60 / 60 / 1000}h"
      case dt <   5*24*60*60*1000 then "#{pad Math.round dt       / 24 / 60 / 60 / 1000}d"
      case dt <  35*24*60*60*1000 then "#{pad Math.round dt   / 7 / 24 / 60 / 60 / 1000}w"
      case dt < 300*24*60*60*1000 then "#{pad Math.round dt  / 30 / 24 / 60 / 60 / 1000}m"
      case dt <          Infinity then "#{pad Math.round dt / 365 / 24 / 60 / 60 / 1000}y"
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

(res, code) <- fetch "ci", config.vars.ciport, "/ls", null, _
m = (regex) -> new RegExp("^#{regex.source}$").test process.argv.2 + if process.argv.3? then " #that" else ''
printJson = (s) ->
  if process.stdout.isTTY
    console.log util.inspect s, depth: Infinity, colors: true
  else
    console.log JSON.stringify(s, null, '  ')
if res? then (switch
  # valid response
  |m /ls/
    (res) <- fetch "ci", config.vars.ciport, "/ls", null, _
    {ps} = JSON.parse res
    for p in ps
      print_process p
  |m /start( ci)?/
    console.log "ci is already running"
  |m /start .+/
    fetch "ci", config.vars.ciport, "/start/#{process.argv.3}", null, console.log
  |m /stop( ci)?/
    process.stdout.write "Stopping ci..."
    (pid) <- supervisor.pgrep /.\/ci.js/, _
    <- supervisor.terminate pid, _
    console.log " ✔"
  |m /stop .+/
    fetch "ci", config.vars.ciport, "/stop/#{process.argv.3}", null, console.log
  |m /restart( ci)?/
    process.stdout.write "Stopping ci..."
    (pid) <- supervisor.pgrep /.\/ci.js/, _
    <- supervisor.terminate pid, _
    console.log " ✔\nci started with PID #{supervisor.start({logname:'ci', script:'./.build/ci.js', args:'./.config/config.json', logport:config.vars.logport}).pid}"
  |m /restart .+/
    (res, status) <- fetch "ci", config.vars.ciport, "/stop/#{process.argv.3}", null, _
    console.log res, status
    if status is 200
      fetch "ci", config.vars.ciport, "/start/#{process.argv.3}", null, console.log
  |m /log .+/
    (res, status) <- fetch "log", config.vars.logbackendport, "/#{process.argv.3}", null, _
    if status is 200
      print_log JSON.parse res
    else
      console.log res, status
  |m /config/
    printJson config
  |m /config .+/
    [_, field, method, key] = process.argv.slice(2)
    if field is 'p' then field = 'processes'
    if field is 'v' then field = 'vars'
    if field is 'w' then field = 'webhooks'
    data = process.argv.slice(6).join ''
    if field is 'update'
      data = method
      (res, status) <- fetch "ci", config.vars.ciport, '/config', data, _
      console.log status, res
    else if not method?
      printJson config[field]
    else if method is 'get' and config[field]?[key]?
      printJson config[field][key]
    else if method is 'delete' and config[field]?[key]?
      delete config[field][key]
      (res, status) <- fetch "ci", config.vars.ciport, '/config', JSON.stringify(config), _
      console.log status, res
    else if method is 'update' and config[field]?
      config[field][key] = JSON.parse data
      (res, status) <- fetch "ci", config.vars.ciport, '/config', JSON.stringify(config), _
      console.log status, res
    else
      console.log "#{key} not found in #{field}"
  |m /.*/
    help!
) else (switch
  # ci not started yet
  |m /start( ci)?/ then fallthrough
  |m /restart( ci)?/
    console.log "ci started with PID #{supervisor.start({logname:'ci', script:'./.build/ci.js', args:'./.config/config.json', logport:config.vars.logport}).pid}"
  |m /ls/ then fallthrough
  |m /start .+/ then fallthrough
  |m /stop( ci)?/ then fallthrough
  |m /stop .+/ then fallthrough
  |m /restart .+/ then fallthrough
  |m /config .+/
    console.error '\033[31mci is not running. Start it with \033[1mcli start [ci]\033[22m.\033[39m'
  |m /log .+/
    (res, status) <- fetch "log", config.vars.logbackendport, "/#{process.argv.3}", null, _
    if status is 200
      print_log JSON.parse res
    else
      console.log res, status
  |m /config/
    console.log util.inspect config, depth: Infinity, colors: process.stdout.isTTY
  |m /.*/
    help!
)
