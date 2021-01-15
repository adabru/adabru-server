
require! [fs,child_process]
fs = fs.promises

supervisor = new

  @pgrep = (regex) ->>
    ps = (await fs.readdir "/proc").filter (p) -> /^[0-9]+$/.test p
    pid = void
    await Promise.any ps.map (p) ->>
      if not pid?
        d = await fs.readFile "/proc/#p/cmdline"
        if not pid? and regex.test(d)
          return pid := p
      throw 'not this one'

  # ip6
  @get_ports = (pid) ->>
    files = await fs.readdir "/proc/#pid/fd"
    socket_inodes = await Promise.all files.map (f) ->>
      try
        stats = await fs.stat "/proc/#pid/fd/#f"
        if stats?.isSocket! then return stats.ino
      catch e
        void # stat failed
    socket_inodes = socket_inodes.filter (x) -> x?
    f = await fs.readFile '/proc/net/tcp6', 'utf8'
    return (f.split '\n'
      .map (s) -> s.trim!.split /[ \t]+/
      .filter (f) -> parseInt(f.9) in socket_inodes
      .map (f) -> f.1
      .filter (e,i,a) -> i is a.indexOf e
      .map (tcp_addr) -> parseInt tcp_addr.split(':').1, 16
    )

  @start = ({logname, args, command, script, cwd, env, logport}) ->
    cwd ?= '.'
    _args = args?.slice! ? []
    child_log = child_process.spawn 'node', ['./.build/logpipe.js', logname, logport], stdio: ['pipe', 'ignore', 'ignore']
      ..unref!
    if script? then _args.unshift script
    _env = {} <<< process.env <<< env
    child = child_process.spawn (command or "node"), _args, {cwd, stdio: ['ignore', child_log.stdin, child_log.stdin], env:_env}
      ..unref!
    # deattach from pipe
    child_log.stdin.destroy!
    child

  @terminate = (pid, cb) ->>
    try
      process.kill pid
    catch e
      if e.code is "ESRCH" then return else throw e
    try
      for i in [1 to 50]
        await fs.stat "/proc/#pid"
        # still alive
        await new Promise (y) -> setTimeout y, 200
    catch
      return
    throw 'process does not die'

exports <<< supervisor
