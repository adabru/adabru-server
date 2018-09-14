require! [http, https, child_process]

srv_port = 1570
router_port = 1571
redirect_port = 1572

state = i:0
trans = ->
  console.log "\x1b[32mstate #{state.i}\x1b[39m"
  switch state.i++
    | 0 # starting echo server and router
      state.echo = http.createServer {}, (req, res) ->
        req.on 'data', (d) -> console.log "\x1b[1mecho server echoing\x1b[22m #d"
        res.writeHead 200, 'Content-Type': 'text/plain'
        req.pipe(res)
      .on 'upgrade', (req, sock, head) ->
        sock.write 'HTTP/1.1 101 Web Socket Protocol Handshake\r\n'+
                  'Upgrade: WebSocket\r\n'+
                  'Connection: Upgrade\r\n'+
                  '\r\n'
        sock.on 'data', (d) -> console.log "\x1b[1mecho ws-server echoing\x1b[22m #d"
        sock.pipe sock
      .listen srv_port, '::1'

      args = {
        port: router_port,
        http_redirect: "#redirect_port->#router_port",
        routes: '[^/]*/test': srv_port,
        host: '::1'
      }
      state.router = child_process.fork './.build/router.js', [JSON.stringify args], {stdio: 'pipe', env:{'DEBUG':'true'}}
      [state.router.stdout, state.router.stderr].map (s) -> s.setEncoding 'utf8'
      state.router.stdout.on 'data', (d) -> console.log "\x1b[1mrouter\x1b[22m #{d.trim!}"
      state.router.stderr.on 'data', (d) -> console.log "\x1b[91mrouter\x1b[39m #{d.trim!}"
      state.router.on 'close', (code) -> console.log "\x1b[1mexit code\x1b[22m #code"

      setTimeout trans, 200
    | 1 # no routing echo test
      msg = 'hello world!'
      console.log "\x1b[1mclient sending\x1b[22m #msg"
      req = http.request {host:'::1', port:srv_port, method:'post'}, (res) ->
        res.on 'data', (d) -> console.log "\x1b[1mclient received\x1b[22m #d"
        res.on 'end', trans
      req.end msg
    | 2 # no routing ws echo test
      msg = 'hello websocket!'
      http.request do
        host:'::1', port:srv_port, headers:{'Connection':'Upgrade', 'Upgrade':'websocket'}
      .on 'upgrade', (res, socket, head) ->
        console.log "\x1b[1mws-client sending\x1b[22m #msg"
        socket.end msg
        socket.on 'data', (d) -> console.log "\x1b[1mws-client received\x1b[22m #{d.toString!.trim!}"
        socket.on 'end', trans
      .end!
    | 3 # http(s) routing
      msg = 'hello router!'
      console.log "\x1b[1mclient sending\x1b[22m #msg"
      state.agent = new https.Agent rejectUnauthorized: false, host: '::1'
      req = https.request {host:'::1', port:router_port, method:'post', state.agent, path:'/test'}, (res) ->
        res.on 'data', (d) -> console.log "\x1b[1mclient received\x1b[22m #d"
        res.on 'end', trans
      req.end msg
    | 4 # ws routing
      msg = 'hello ws-router!'
      https.get do
        {host:'::1', port:router_port, headers:{'Connection':'Upgrade', 'Upgrade':'websocket'}, state.agent, path:'/test'},
        ->
      .on 'upgrade', (res, socket, head) ->
        console.log "\x1b[1mws-client sending\x1b[22m #msg"
        socket.write msg
        socket.on 'data', (d) -> console.log "\x1b[1mws-client received\x1b[22m #{d.toString!.trim!}"
        socket.on 'end', trans
        # needs some time to receive data
        setTimeout (-> socket.end!), 100
      .end!
    | 5
      console.log('test finished.')
      process.exit!
trans!

process.on 'exit', -> state.router.kill 'SIGTERM'