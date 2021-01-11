
require! [livescript,http,path,child_process,fs,stream,crypto]

configPath = process.argv.2

callme = (callback, promise) -> promise.then((d)->callback void, d).catch((e)->callback e, d)
to_string = (stream, cb) ->
  chunks = []
  stream.on "data", (c) -> chunks.push c
  stream.on "end", -> cb Buffer.concat(chunks).toString('utf-8')
escaped_regex = (s) -> new RegExp(s.replace /[-[\]{}()*+?.,\\^$|#\s]/g, '\\$&')
run_hook = ({name, path, env, commands}, callback) ->
  d = new Date()
  pad = (s) -> "0#s".substr -2
  m = ['Jan' 'Feb' 'Mar' 'Apr' 'May' 'Jun' 'Jul' 'Aug' 'Sep' 'Oct' 'Nov' 'Dec']
  state.hook[name] = lines:
    * date: "#{d.getUTCFullYear!} #{m[d.getUTCMonth!]} #{pad d.getUTCDate!} #{pad d.getUTCHours!}:#{pad d.getUTCMinutes!}:#{pad d.getUTCSeconds!}"
    ...(commands?.split '\n' or []).filter((line) -> line.trim! isnt '').map (command) -> ({command})
  run = ->
    line = state.hook[name].lines.find ({command, code}) -> command? and not code?
    if not line? then return callback!
    line <<< {output:[], tstart:Date.now!}
    cp = child_process.spawn 'sh', ['-c', line.command], cwd:path, env:({} <<< process.env <<< env)
    cp.stdout.setEncoding('utf8').on 'data', (data) -> line.output.push {fid:1, data}
    cp.stderr.setEncoding('utf8').on 'data', (data) -> line.output.push {fid:2, data}
    cp.on 'close', (code) ->
      line <<< {tend: Date.now!, code}
      if code is 0 then run! else callback!
  run!
get_argarray = (name) ->
  args = config[name].args ? ''
  _args = switch
    case typeof args is 'string' then args.split ' '
    case Array.isArray args then args
    default [JSON.stringify args]
  # variable substitution
  _args = _args.map (a) -> a.replace /\$\{(.+?)\}/g, (, $1) ->
    if $1.starts-with '.'
      $1 = name + $1
    substitution = ($1.split '.').reduce ((node, key) -> node?[key]), config
    if not substitution?
      console.warn "Variable \033[93m#{$1}\033[0m is not defined for process \033[37m#{name}\033[0m! (cli config get [process])"
    substitution or ''
update_processes = (thresholdtime, callback) ->
  restarts = []
  for k in Object.keys(config)
    if k is 'ci' then continue
    p = config[k]
    if not p.script? then continue
    if fs.statSync(p.script).mtime.getTime! <= thresholdtime then continue
    let k=k, p=p
      restarts.push new Promise (y,n) ->
        pid = state.pid[k]
        if not pid? then return y!
        console.log "restarting #k"
        <- supervisor.terminate pid, _
        state.pid[k] = (supervisor.start {logname:k, p.script, args:get_argarray(name), p.cwd, p.env, logport:config.log.ports.0}).pid
        saveState!
        y!
  (e) <- callme _, Promise.all restarts
  if e? then console.log e
  # restart ci (current process)
  if fs.statSync('./.build/ci.js').mtime.getTime! > thresholdtime
    console.log "restarting"
    supervisor.start {logname:'ci', command:'sh', args:['-c', "while [ -e /proc/#{process.pid} ] ; do sleep .2; done ; #{process.argv.join ' '} &"], logport:config.log.ports.0}
    process.exit!
  else callback!

saveState = ->
  fs.writeFileSync './.cache/ci_state.json', JSON.stringify state

try config = JSON.parse fs.readFileSync configPath
catch e
  console.error e
  process.exit -1
supervisor = require './supervisor.js'
try fs.mkdirSync './.cache'
try state = JSON.parse fs.readFileSync './.cache/ci_state.json'
state = {pid:{},hook:{}} <<< state
state.pid['ci'] = process.pid
validate_webhook = (req, token, restart, cb) ->
  switch
    case restart?
      # for local use (ie dashboard), pay attention to block this from extern
      cb true
    case req.headers['x-gitlab-token']?
      # https://docs.gitlab.com/ce/user/project/integrations/webhooks.html
      cb req.headers['x-gitlab-token'] is token
    case req.headers['x-hub-signature']?
      # https://developer.github.com/webhooks/securing/
      (body) <- to_string req, _
      cb req.headers['x-hub-signature'] is "sha1="+crypto.createHmac('sha1', token).update(body).digest('hex')
    default
      cb false
busy = false
http.createServer (req, res) ->
  answer = (code, message, headers=null) -> res.writeHead code, headers ; res.end message
  m = (regex) -> new RegExp("^#{regex.source}$").test req.url
  try
    switch
      # for debugging
      |m /\/update/
        update_processes 0
      |m /\//
        # ping
        answer 200, "ci running"
      |m /\/webhook\/([^\/]+)(\/restart)?/
        [,name,restart] = /\/webhook\/([^\/]+)(\/restart)?$/.exec req.url
        wh = config[name]?.webhook
        if not wh? then return answer 404, 'hook does not exist'
        (isOk) <- validate_webhook req, wh.token, restart, _
        switch
          case not isOk then return answer 400, 'token is wrong'
          case busy     then return answer 503, 'another hook is running', 'Retry-After':60
          else answer 200
        t0 = Date.now!
        busy := true
        <- run_hook {name, wh.path, wh.env, commands:"git pull\n#{wh.commands ? ''}"}, _
        update_processes t0, -> busy := false
      |m /\/ls/
        queries =  Object.entries(config).map ([k, p]) -> new Promise (y, n) ->
          res = name:k
          pid = state.pid[k]
          if not pid?
            y name:k, status:'not running'
          else fs.stat "/proc/#pid", (e,r) ->
            if e? then y name:k, status:'stopped'
            else supervisor.get_ports pid, (ports) -> y {name:k, status:'running', pid, ports}
        (e, values) <- callme _, Promise.all queries
        if e?
          console.log e
          answer 500, e.stack
        else
          answer 200, JSON.stringify do
            ps: values
            hooks: Object.entries(state.hook).map ([k, h]) -> h <<< name:k
      |m /\/start\/.+/
        name = /[^\/]+$/.exec(req.url).0
        if not (p = config[name])?
          return answer 404, "process #name not found!"
        console.log "starting #name"
        pid = state.pid[name]
        if pid? then return answer 200, "#name already running"
        state.pid[name] = supervisor.start {logname:name, p.script, p.command, args:get_argarray(name), p.cwd, p.env, logport:config.log.ports.0}
          .on 'error', (e) -> console.error e.stack
          .pid
        saveState!
        answer 200, "#name started"
      |m /\/stop\/.+/
        name = /[^\/]+$/.exec(req.url).0
        if not (p = config[name])?
          return answer 404, "process #name not found!"
        if not (pid = state.pid[name])?
          return answer 200, "#name is not running"
        state.pid[name] = void
        saveState!
        <- supervisor.terminate pid, _
        answer 200, "#name stopped"
      |m /\/config/
        if req.method is 'GET'
          answer 200, JSON.stringify config
        else /*PUT*/
          (body) <- to_string req, _
          config := JSON.parse body
          e <- fs.writeFile configPath, (JSON.stringify config, ' ', 2), _
          if e? then answer 500, "could not write config: #{e.stack}"
          else  then answer 200, "config updated"
      default
        answer 404, "not found"
  catch e
    answer 500, e.stack
.listen config.ci.ports.0, '::1', -> console.log "continuous integration server running on http://[::1]:#{config.ci.ports.0}"
