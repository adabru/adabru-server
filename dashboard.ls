
require! [fs,http,url]

{dashboardport, ciport, logbackendport, token} = JSON.parse process.argv.2

# token security
#   alphabet: a-zA-Z0-9=25+25+10=60, code: 60^token_length
#   1y brute force attack, successrate: 365*24*60*60*1000 / t_min / 60^tokenlength
#   t_min = 1ms (server response time overestimate) → [tokenlength, successrate]: [5, 100%], [6, 68%], [7, 1.2%], [8, 0.02%]

http.createServer (req, res) ->
  answer = (code, message) -> res.writeHead code ; res.end message
  proxy = (port, path, errMsg) ->
    _req = http.request {hostname: "::1", port, path, req.method}, (_res) ->
      res.writeHead _res.statusCode
      _res.pipe res
    _req.on 'error', (e) -> answer 500, errMsg
    req.pipe _req
  fetch = (port, path, callback) ->
    req = http.request {hostname: "::1", port, path}, (res) ->
      chunks = []
      res.on "data", (c) -> chunks.push c
      res.on "end", -> callback null, Buffer.concat(chunks).toString('utf-8'), res.statusCode
    req.on 'error', callback
    req.end!
  _url = url.parse req.url, true
  switch
    case _url.pathname is /\/$/
      answer 200, '
        <head>
          <meta charset="utf-8">
          <link href="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABEAAAARCAMAAAAMs7fIAAAABGdBTUEAALGPC/xhBQAAAAFzUkdCAK7OHOkAAABIUExURUxpcf8AAP8AAP8HCP8AAP8AAP8AAP8AAP98lP8AAP8CA/8EBf8yPP8AAP8AAP8LDv8AAP9IVv9mfP8oMf9/mf+Ho/8AAP+bu2XmXx8AAAAYdFJOUwBTPHFIFA8J1SGMY4kwF50pscG34t1/+E9Tr2UAAACtSURBVBjTVY/ZEsMgCEVRAUGjRk3S///TErtMy8N9ODN3AQAgMnGMS2EdFXRYdCndjPwmIlte6sksZZOW2jEPU9lKBEZpwYX5mKZNkIGcJFSfjuQVkzh6kao5Za0vEv3oebe+QnvuwzNEzWdySpXUpTOr1bO1X1hjxcva+V5YsY/Lqw+jY12bo7rRrboPp+83LEpmm5I/4N4dbHMoX7DSz1AYfo53v/8BM8aP5QkltgfMYKXkdgAAAABJRU5ErkJggg==" rel="icon"/>
        </head>
        <div id="app"><h1 style="margin:0;top:0;left:0;width:100vw;position:fixed;text-align:center;line-height:100vh;">⌛</h1></div>
        <script src="dashboard_app.js"></script>
        <link href="dashboard_app.css" rel="stylesheet">
      '
    case _url.pathname is /\/dashboard_app.js$/
      res.writeHead 200, 'content-type': 'application/javascript'
      fs.createReadStream('./.build/dashboard_app.js').pipe res
    case _url.pathname is /\/dashboard_app.css$/
      res.writeHead 200, 'content-type': 'text/css'
      fs.createReadStream('./.build/dashboard_app.css').pipe res
    case _url.query.token isnt token
      answer 403, "falsches token"
    case _url.pathname is /\/ls$/
      proxy ciport, "/ls", "ci service request failed"
    case _url.pathname is /\/proc\/(.*)\/start$/
      name = /\/proc\/(.*)\/start$/.exec(_url.pathname).1
      proxy ciport, "/start/#name", "ci service request failed"
    case _url.pathname is /\/proc\/(.*)\/stop$/
      name = /\/proc\/(.*)\/stop$/.exec(_url.pathname).1
      proxy ciport, "/stop/#name", "ci service request failed"
    case _url.pathname is /\/config$/
      proxy ciport, "/config", "ci service request failed"
    case _url.pathname is /\/webhook\/(.*)\/restart$/
      name = /\/webhook\/(.*)\/restart$/.exec(_url.pathname).1
      proxy ciport, "/webhook/#name/restart"
    case _url.pathname is /\/proc\/(.*)\/restart$/
      name = /\/proc\/(.*)\/restart$/.exec(_url.pathname).1
      (e, res, code) <- fetch ciport, "/stop/#name", _
      if e? then return answer 500, e
      if code isnt 200 then return answer code, res
      (e, res, code) <- fetch ciport, "/start/#name", _
      if e? then return answer 500, e
      if code isnt 200 then return answer code, res
      answer 200, "#name was restarted"
    case _url.pathname is /\/log\/[^\/]+$/
      proxy logbackendport, /\/log(\/[^\/]+)$/.exec(_url.pathname).1, "log service request failed"
    # pay attention to /log/log
    case _url.pathname is /\/log$/
      proxy logbackendport, "/", "log service request failed"
.listen dashboardport, '::1', -> console.log "dasboard service running on http://[::1]:#{dashboardport}"
