
require! [fs,child_process]

supervisor = new

  @pgrep = (regex, cb) ->
    ps = fs.readdirSync("/proc").filter (p) -> /^[0-9]+$/.test p
    count = ps.length
    f_limit = 50
    pid = void
    do get_pid = ->
      if pid? then return
      if not (p = ps.pop!)? then return
      fs.readFile "/proc/#p/cmdline", (e, d) ->
        if pid? then return
        if not e? and regex.test(d) then return cb (pid := p)
        if --count is 0 then return cb void
        setTimeout -> get_pid!
      if f_limit-- > 0
        setTimeout -> get_pid!

  # ip6
  @get_ports = (pid, cb) ->
    (e,files) <- fs.readdir "/proc/#pid/fd", _
    if e? then return cb []
    socket_inodes = []
    semaphore = new
      @c = files.length
      @tick = -> if --@c is 0 then @_next!
      @next = (cb) -> @_next=cb
    files.forEach (f) -> fs.stat "/proc/#pid/fd/#f", (e,stats) ->
      if not e? and stats?.isSocket! then socket_inodes.push stats.ino
      semaphore.tick!
    <- semaphore.next _
    (e,f) <- fs.readFile '/proc/net/tcp6', 'utf8', _
    cb (f.split '\n'
      .map (s) -> s.trim!.split /[ \t]+/
      .filter (f) -> parseInt(f.9) in socket_inodes
      .map (f) -> f.1
      .filter (e,i,a) -> i is a.indexOf e
      .map (tcp_addr) -> parseInt tcp_addr.split(':').1, 16
    )

  @start = ({logname, args, env, script, cwd, logport}) ->
    cwd ?= '.'
    args ?= ''
    env ?= {}
    child_log = child_process.spawn 'node', ['./logpipe.js', logname, logport], stdio: ['pipe', 'ignore', 'ignore']
      ..unref!
    _args = switch
      case typeof args is 'string' then args.split ' '
      case Array.isArray args then args
      default [JSON.stringify args]
    # env variables
    _args = _args.map (a) -> a.replace /\$\{(.+?)\}/g, (, $1) ->
      if not env[$1]?
        console.warn "argument parameter #{$1} is not defined in environment: #{JSON.stringify env}"
      env[$1] or ''
    _args.unshift script
    child = child_process.spawn "node", _args, {cwd, stdio: ['ignore', child_log.stdin, child_log.stdin]}
      ..unref!
    # deattach from pipe
    child_log.stdin.destroy!
    child

  @terminate = (pid, cb) ->
    try
      process.kill pid
    catch e
      if e.code is "ESRCH" then return cb! else throw e
    wait_p = ->
      try
        fs.statSync "/proc/#pid"
        # still alive
        setTimeout wait_p, 200
      catch
        cb!
    setTimeout wait_p

exports <<< supervisor
