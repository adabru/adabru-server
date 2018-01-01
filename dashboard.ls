#!/usr/bin/env lsc

require! [fs,http,url]

{dashboardport, ciport, logbackendport, token} = JSON.parse process.argv.2

http.createServer (req, res) ->
  answer = (code, message) -> res.writeHead code ; res.end message
  proxy = (port, path, errMsg) ->
    req = http.request {hostname: "::1", port, path}, (_res) ->
      res.writeHead _res.statusCode
      _res.pipe res
    req.on 'error', (e) -> answer 500, errMsg
    req.end!
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
      answer 200, "<h1>Dashboard</h1><script src=\"app.js\"></script>"
    case _url.pathname is /\/app.js$/
      res.writeHead 200, 'content-type': 'application/javascript'
      fs.createReadStream('./dashboard_front.js').pipe res
    case _url.query.token isnt token
      answer 403, "falsches token"
    case _url.pathname is /\/proc$/
      proxy ciport, "/ls", "ci service request failed"
    case _url.pathname is /\/proc\/(.*)\/start$/
      name = /\/proc\/(.*)\/start$/.exec(_url.pathname).1
      proxy ciport, "/start/#name", "ci service request failed"
    case _url.pathname is /\/proc\/(.*)\/stop$/
      name = /\/proc\/(.*)\/stop$/.exec(_url.pathname).1
      proxy ciport, "/stop/#name", "ci service request failed"
    case _url.pathname is /\/proc\/(.*)\/restart$/
      name = /\/proc\/(.*)\/restart$/.exec(_url.pathname).1
      (e, res, code) <- fetch ciport, "/stop/#name", _
      if e? then return answer 500, e
      if code isnt 200 then return answer code, res
      (e, res, code) <- fetch ciport, "/start/#name", _
      if e? then return answer 500, e
      if code isnt 200 then return answer code, res
      answer 200, "#name was restarted"
    case _url.pathname is /\/log$/
      proxy logbackendport, "/", "log service request failed"
    case _url.pathname is /\/log\/[^\/]+$/
      proxy logbackendport, /\/log(\/[^\/]+)$/.exec(_url.pathname).1, "log service request failed"
.listen dashboardport, '::1', -> console.log "dasboard service running on http://[::1]:#{dashboardport}"
