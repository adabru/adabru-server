# pipes stdin to tcp port using name and correct format
#
# node logpipe.js <log_name> <log_server_port>

require! [net]

[, , pipe_name, server_port] = process.argv

# debug output
console.debug = if process.env.DEBUG then (m)->console.log "\x1b[33m#m\x1b[39m" else ->

pipe = (name, port) ->
  sock = writable: false

  connecting = false
  connect = ->
    if connecting then return
    connecting := true
    sock := net.createConnection(port, "::1") <<< writable:false
    sock.on 'error', (e) ->
      sock.end!
      sock.writable = false
    sock.on 'close', ->
      connecting := false
    sock.on 'connect', ->
      console.debug 'connected to logserver'
      sock.writable = true
      sock.write "#name\n"
      if (chunk = process.stdin.read!)?
        sock.write chunk
        console.debug "written [#chunk]"

  nextbeat = false
  heartbeat = ->
    if nextbeat then clearTimeout nextbeat
    nextbeat := setTimeout heartbeat, 1000
    switch
      # process finished; no connection to logserver
      case process.stdin._readableState.ended and !sock.writable
        process.exit!
      # process finished; internal buffers flushed; established connection
      case not process.stdin.readable and sock.writable
        sock.end!
        clearTimeout nextbeat
        sock.on 'close', heartbeat
        # die from cardiac arrest
        setTimeout process.exit, 10000
      # process runnig; no connection to logserver
      case not process.stdin._readableState.ended and !sock.writable
        connect!
  heartbeat!

  # https://github.com/nodejs/node/blob/master/lib/_stream_readable.js
  process.stdin.setEncoding 'utf8'
  process.stdin.on 'readable', ->
    if sock.writable and (chunk = process.stdin.read!)?
      sock.write chunk
      console.debug "written [#chunk]"
  process.stdin.on 'end', heartbeat

pipe pipe_name, server_port
