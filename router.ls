
require! [fs, https, http, net, url, zlib]

{http_redirect, port, routes, host} = JSON.parse process.argv.2


host ?= '::1'
$ = http_redirect ; http_redirect = {} ; [, http_redirect.from, http_redirect.to] = /(.*)->(.*)/.exec $

start_router = (host, port, cb) ->
  signing =
    key: fs.readFileSync './.config/key.pem'
    cert: fs.readFileSync './.config/cert.pem'
  https.createServer signing, (req, res) ->
    href = req.headers.host + req.url
    r = Object.keys(routes).find (r) -> (new RegExp r).test req.headers.host + req.url
    if not r?
      res.writeHead 200, 'Content-Type': 'text/plain'
      return res.end 'no route defined for this url'

    options = {host: '::1', port: routes[r], path: req.url, req.headers, req.method}
    p_req = http.request options, (p_res) ->
      # no deflate support to avoid problems see e.g. https://github.com/expressjs/compression/issues/25
      if not p_res.headers['content-encoding']?
        and not p_res.headers['transfer-encoding']?
        and /gzip/.test(req.headers['accept-encoding'])
        and /^(text|application)/.test(p_res.headers['content-type'])
          delete p_res.headers['content-length']
          p_res.headers['content-encoding'] = 'gzip'
          res_body = p_res.pipe(zlib.createGzip())
      else
        res_body = p_res
      res.writeHead p_res.statusCode, p_res.headers
      res_body.pipe res
    p_req.on 'error', (e) ->
      console.error "problem with service on port #{routes[r]}: #{e.message}"
      res.writeHead 500
      res.end!
    req.pipe p_req
  .listen port, host, cb

# old certificates remain valid:
# https://github.com/certbot/certbot/issues/3465
state = {}
heartbeat = ->
  setTimeout heartbeat, 60*60*1000
  mtime =
    key: fs.statSync('./.config/key.pem').mtime.getTime!
    cert: fs.statSync('./.config/cert.pem').mtime.getTime!
  if not state.router?
    state.mtime = mtime
    state.router = start_router host, port, -> console.log "router running at https://#{host}:#{port}/"
  else if (state.mtime.key isnt mtime.key) or (state.mtime.cert isnt mtime.cert)
    console.log 'reloading SSL certificate'
    state.mtime = mtime
    # see https://stackoverflow.com/a/36830072/6040478
    state.router.close!
    setImmediate ->
      state.router = start_router host, port, ->

# 80 → 443 redirect
http.createServer (req, res) ->
  res.writeHead 302, 'location': "https://#{/[^:]*/.exec(req.headers['host']).0}:#{http_redirect.to}#{req.url}"
  res.end!
.listen http_redirect.from, host, -> console.log "http redirecting from http://#{host}:#{http_redirect.from}"

heartbeat!
