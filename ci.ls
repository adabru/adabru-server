
require! [livescript,http,path,child_process,fs,stream,crypto]

config_path = process.argv.2

callme = (callback, promise) -> promise.then((d)->callback void, d).catch((e)->callback e, d)
to_string = (stream, cb) ->
  chunks = []
  stream.on "data", (c) -> chunks.push c
  stream.on "end", ->
    cb Buffer.concat(chunks).toString('utf-8')
escaped_regex = (s) -> new RegExp(s.replace /[-[\]{}()*+?.,\\^$|#\s]/g, '\\$&')
compile_scripts = (path, call) ->
  (e,files) <- fs.readdir path, _
  files = files.filter((f) -> f.endsWith '.ls').map (f) -> /^(.*).ls$/.exec(f).1
  if files.length is 0 then return call!
  Promise.all(
    files.map (f) -> new Promise (y, n) ->
      (e, sLS) <- fs.stat "#path/#f.ls", _
      if e? then return n e
      (e, sJS) <- fs.stat "#path/#f.js", _
      if sJS? and sJS.mtimeMs > sLS.mtimeMs then return y!
      compile = child_process.spawn 'lsc', ['-c', "#path/#f.ls"]
      compile.on 'close', y
  ).catch(call).then ->
    console.log "Livescript files compiled in #{path}"
    call!
update_processes = (thresholdtime) ->
  restarts = []
  for k in Object.keys(config.processes)
    if k is 'ci' then continue
    p = config.processes[k]
    if fs.statSync(p.entry).mtime.getTime! <= thresholdtime then continue
    let k=k, p=p
      restarts.push new Promise (y,n) ->
        pid = state.pid[k]
        if not pid? then return y!
        console.log "restarting #k"
        <- supervisor.terminate pid, _
        state.pid[k] = (supervisor.start {logname:k, command:p.entry, p.args, config.env, p.cwd, logport:config.env.logport}).pid
        saveState!
        y!
  (e) <- callme _, Promise.all restarts
  if e? then console.log e
  if fs.statSync('./ci.ls').mtime.getTime! > thresholdtime
    console.log "restarting"
    supervisor.start {logname:'ci', command:'sh', args:['-c', "while [ -e /proc/#{process.pid} ] ; do sleep .2; done ; ./ci.ls &"], logport:config.env.logport}
    process.exit!

saveState = ->
  fs.writeFileSync './.cache/ci_state.json', JSON.stringify state

try config = JSON.parse fs.readFileSync config_path
catch e
  console.error e
  process.exit -1
supervisor = require './supervisor.js'
try state = JSON.parse fs.readFileSync './.cache/ci_state.json'
state = {pid:{}} <<< state
state.pid['ci'] = process.pid
validate_webhook = (req, token, cb) ->
  switch
    case req.headers['x-gitlab-token']?
      # https://docs.gitlab.com/ce/user/project/integrations/webhooks.html
      cb req.headers['x-gitlab-token'] is token
    case req.headers['x-hub-signature']?
      # https://developer.github.com/webhooks/securing/
      (body) <- to_string req, _
      cb req.headers['x-hub-signature'] is "sha1="+crypto.createHmac('sha1', token).update(body).digest('hex')
    default
      cb false
http.createServer (req, res) ->
  answer = (code, message) -> res.writeHead code ; res.end message
  try
    switch
      # for debugging
      case req.url is '/update'
        update_processes 0
      case req.url is '/'
        # ping
        answer 200, "ci running"
      case req.url is /\/webhook\//
        name = /[^\/]+$/.exec(req.url).0
        wh = config.webhooks[name]
        if not wh? then return answer 404, 'hook does not exist'
        (isOk) <- validate_webhook req, wh.token
        if isOk then answer 200 else return answer 400, 'token is wrong'
        t0 = Date.now!
        {status} = child_process.spawnSync 'git', ['pull'], {cwd:wh.path}
        console.log "#name pulled (exit code #status)"
        <- compile_scripts wh.path, _
        update_processes t0
      case req.url is '/ls'
        (Promise.all Object.keys(config.processes).map (k) -> new Promise (fulfill, reject) ->
          p = config.processes[k]
          res = fulfilled: 0, name:k
          pid = state.pid[k]
          if not pid?
            fulfill name:k, status:'not running'
          else fs.stat "/proc/#pid", (e,r) ->
            if e? then fulfill name:k, status:'stopped'
            else supervisor.get_ports pid, (ports) -> fulfill {name:k, status:'running', pid, ports}
        ).catch((e) -> console.log e ; answer 500, e.stack).then (values) -> answer 200, JSON.stringify values ++ {name:'ci', status:'running', process.pid, ports:[config.env.ciport]}
      case req.url is /\/start\//
        name = /[^\/]+$/.exec(req.url).0
        if not (p = config.processes[name])?
          return answer 404, "process #name not found!"
        console.log "starting #name"
        pid = state.pid[name]
        if pid? then return answer 200, "#name already running"
        state.pid[name] = supervisor.start {logname:name, p.script, p.args, config.env, p.cwd, logport:config.env.logport}
          .on 'error', (e) -> console.error e.stack
          .pid
        saveState!
        answer 200, "#name started"
      case req.url is /\/stop\//
        name = /[^\/]+$/.exec(req.url).0
        if not (p = config.processes[name])?
          return answer 404, "process #name not found!"
        if not (pid = state.pid[name])?
          return answer 200, "#name is not running"
        state.pid[name] = void
        saveState!
        <- supervisor.terminate pid, _
        answer 200, "#name stopped"
      case req.url is /\/config\//
        name = /[^\/]+$/.exec(req.url).0
        if name isnt 'ci' and not config.processes[name]?
          return answer 404, "process #name not found!"
        if req.method is 'GET'
          answer 200, JSON.stringify do
            if name is 'ci' then _config = {} <<< config ; delete _config.processes ; _config
            else then config.processes[name]
        else /*PUT*/
          (body) <- to_string req, _
          if name is 'ci' then config <<< JSON.parse body
          else            then config.processes[name] = JSON.parse body
          e <- fs.writeFile config_path, (JSON.stringify config, ' ', 2), _
          if e? then answer 500, "could not write config: #{e.stack}"
          else  then answer 200, "config updated"
      default
        answer 404, "not found"
  catch e
    answer 500, e.stack
.listen config.env.ciport, '::1', -> console.log "continuous integration server running on http://[::1]:#{config.env.ciport}"
