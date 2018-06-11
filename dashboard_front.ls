React = require 'react'
ReactDOM = require 'react-dom'
e = React.createElement

{ json_component } = require './jsoneditor'

class Dashboard extends React.Component
  ->
    @state = do
      token: ''
      approved: 'no'
      procs: []
      hooks: []
      showhook: null
      config: null
      beatPhase: 0
    @nextBeat = null
  componentDidMount: ->
    if (localStorage.getItem 'token')? then @putToken that
  putToken: (token) ->
    @setState {approved: 'pending', token}, @heartbeat
  heartbeat: (callback) ~>
    # callbacks is called as soon as all process status are available or call failed
    if @nextBeat? then clearTimeout @nextBeat
    proceed = ~>
      callback?!
      @nextBeat = setTimeout (~>@heartbeat!), 1000

    token = @state.token
    res <~ fetch "ls?token=#token" .catch((e) -> Promise.resolve e) .then _
    if res.status? then @setState beatPhase: (@state.beatPhase + 1) % 2
    if res.status is 403 then return @setState approved: 'no', proceed
    if res.status isnt 200 then return proceed!
    {ps, hooks} <~ res.json!.then _
    procs = ps.map (p) ~> {logsize:0} <<< (@state.procs.find (x) -> x.name is p.name) <<< {name:'n/a', pid:'', ports:[]} <<< p
    localStorage.setItem 'token', token
    @setState {approved: 'yes', token, procs, hooks}, callback
    callback := ->
    # central notification for log and config refreshing
    res <~ fetch "log?token=#token" .then _
    if res.status isnt 200 then return proceed!
    loginfo <~ res.json!.then _
    procs := procs.map (p) ~>
      p <<< if loginfo.find((x) -> x.name is p.name) then logsize: that.size else null
    res <~ fetch "config?token=#token" .then _
    if res.status isnt 200 then return proceed!
    config <~ res.json!.then _
    @setState {procs, config}, proceed
  render: ->
    if @state.approved isnt 'yes'
      e 'div', className:'dashboard',
        e 'header', {},
          e 'span', className:"heartbeat phase#{@state.beatPhase}", '♡'
          e 'input',
            className: 'token'
            value: @state.token
            placeholder: 'enter token'
            autoFocus: true
            onChange: (e) ~> @putToken e.target.value
            style:
              color: {'no':'#aa0000', 'pending':'#aaaa00'}[@state.approved]
    else
      e 'div', className:'dashboard',
        e 'header', {},
          e 'span', className:"heartbeat phase#{@state.beatPhase}", '♡'
          ...@state.hooks.map (h) ~>
            status = h.lines.some((l) -> l.tstart? and not l.tend?) and 'running'
              or h.lines.every((l) -> l.code is 0) and 'success' or 'failure'
            e 'button',
              className:"hook #status",
              onClick: ~> @setState showhook: if @state.showhook is h.name then null else h.name,
              h.name
          e 'button',
            onClick: ~>
              link = document.createElement 'a'
              link <<< {download:'config.json', href:"data:application/json,#{encodeURI JSON.stringify @state.config, null, 2}"}
              link.click!
            '💊'
          e 'textarea', onChange: ({target}) ~> @configimport = target.value
          e 'button',
            onClick: ~>
              res <~ fetch("config?token=#{@state.token}", method:'PUT', body:@configimport) .catch((e) -> Promise.resolve e) .then _
              if res.status isnt 200 then console.log res
              @heartbeat!
            '🍴'
        e HookView, @state{token} <<< @{heartbeat} <<< hook:@state.hooks.find((h) ~> h.name is @state.showhook)
        e 'div', className: 'procs',
          @state.procs.map (proc, i) ~>
            e ProcessItem, {key:proc.name} <<< @state{token, config} <<< @{heartbeat} <<< proc
          e 'button',
            className:'addproc',
            onClick: ~>
              @state.config.processes[parseInt(Math.random!*0xffff).toString 16] = {}
              res <~ fetch("config?token=#{@state.token}", method:'PUT', body:JSON.stringify @state.config) .catch((e) -> Promise.resolve e) .then _
              if res.status isnt 200 then console.log res
              @heartbeat!
            '+'



class HookView extends React.Component
  -> @state = pending: false
  render: ->
    duration = (ms) ->
      h = Math.floor   ms/60/60/1000
      m = Math.floor ((ms/60/60/1000)%1)*60
      s = Math.floor ((ms/60/1000)%1)*60
      "#h:#{"#m".padStart 2,0}:#{"#s".padStart 2,0}"
    e 'div', className:"hookview #{@state.pending and 'pending' or ''}",
      @props.hook? and e 'button',
        onClick: ~>
          @setState pending:true
          res <~ fetch "webhook/#{@props.hook.name}/restart?token=#{@props.token}" .catch((e) -> Promise.resolve e) .then _
          if res.status is 200 then @setState flash: 'success' else @setState flash: 'failure'
          @props.heartbeat ~> @setState pending: false
        '💣🏃'
      @props.hook? and e 'div', {},
        ...@props.hook.lines.map ({command,output,tstart,tend,code}) ->
          e 'div', {},
            e 'pre', {className: not tstart? and 'due' or not code? and 'running' or code is 0 and 'success' or 'failure'}, command
            e 'time', {}, (not tstart? and '-' or duration (tend or Date.now!) - tstart)
            e 'div', {}, ...(output ? []).map ({fid,data}) ->
              e 'pre', className:"fid#fid", data



class ProcessItem extends React.Component
  ->
    @flash = ->
    @state = do
      pending: false
      flash: null
      expand: false
  act: (action) ->
    @setState pending: true
    res <~ fetch "proc/#{@props.name}/#action?token=#{@props.token}" .catch((e) -> Promise.resolve e) .then _
    if res.status is 200 then @setState flash: 'success' else @setState flash: 'failure'
    @props.heartbeat ~> @setState pending: false
  shouldComponentUpdate: (nextProps, nextState) ->
    (Object.keys(@props).some (k) ~> k isnt 'ports' and @props[k] isnt nextProps[k])
      or (@props['ports'].length isnt nextProps['ports'].length)
      or (@props['ports'].some (p) ~> not (p in nextProps['ports']))
      or (Object.keys(@state).some (k) ~> @state[k] isnt nextState[k])
  render: ->
    e 'div',
      className: "proc #{@props.status.replace ' ', ''} #{@state.pending and 'pending' or ''} #{@state.expand and 'expand' or ''} #{@state.flash ? ''}",
      onAnimationEnd: ~> @setState flash: null
      e 'span', className: 'status', {'running':'', 'not running':'⚠', 'stopped':'☠'}[@props.status]
      e 'span',
        className: 'name',
        @props.name
      e 'button', className: 'restart', onClick:(~> @act 'restart'), '💣🏃'
      e 'button', className: 'stop',    onClick:(~> @act 'stop'   ), '💣'
      e 'button', className: 'start',   onClick:(~> @act 'start'  ), '🏃'
      e 'div', className: 'pid',
        e 'span', {}, @props.pid
        e 'div', className: 'ports', @props.ports.map (port, i) -> e 'span', key:i, className:'port', port
      e 'div', className: 'logwrapOuter', e 'div', className: 'logwrapInner', e ProcessLog,
        {url: "log/#{@props.name}?token=#{@props.token}"} <<< @state{expand} <<< @props{logsize, name} <<< toggleExpand: ~> @setState expand: not @state.expand
      e ProcessConfig,
        {url: "config?token=#{@props.token}"} <<< @state{expand} <<< @props{name, heartbeat, config} <<< toggleExpand: ~> @setState expand: not @state.expand
ProcessItem.defaultProps = pid: -1, ports: []



class ProcessLog extends React.PureComponent
  ->
    @state = do
      log: []
      logsize: 0
  componentDidMount: ->
    @refreshLog!
    # refresh elapsed time display
    @updateInterval = setInterval (~>@forceUpdate!), 1000
  componentDidUpdate: (prevProps, prevState) -> @refreshLog!
  componentWillUnmount: ->
    clearInterval @updateInterval
  refreshLog: ->
    if @state.logsize is @props.logsize then return
    # prevent further updates
    @setState logsize: @props.logsize
    res <~ fetch @props.url .catch((e) -> Promise.resolve e) .then _
    if res.status isnt 200 then return
    log <~ res.json!.then _
    @setState log:log.slice 0, -1
  render: ->
    buildItem = ({d,s}, i) ~>
      dt = Date.now! - d
      diff = switch
        case dt <           99*1000 then "#{Math.round dt                      / 1000}s"
        case dt <        99*60*1000 then "#{Math.round dt                 / 60 / 1000}m"
        case dt <     20*60*60*1000 then "#{Math.round dt            / 60 / 60 / 1000}h"
        case dt <   5*24*60*60*1000 then "#{Math.round dt       / 24 / 60 / 60 / 1000}d"
        case dt <  35*24*60*60*1000 then "#{Math.round dt   / 7 / 24 / 60 / 60 / 1000}w"
        case dt < 300*24*60*60*1000 then "#{Math.round dt  / 30 / 24 / 60 / 60 / 1000}o"
        case dt <          Infinity then "#{Math.round dt / 365 / 24 / 60 / 60 / 1000}y"
      e 'div',
        key:i,
        className:"entry"
        e 'span', className: "date #{diff.substr -1}", diff
        e 'pre', {}, s
    if @state.log.length > 0 then e 'div',
      className: "log",
      onClick: @props.toggleExpand
      @state.log.slice(-30).map buildItem
    else e 'span', {}, 'no log yet'



class ProcessConfig extends React.Component
  ->
    @state = do
      json: null
      name:null
      dirtyCompare: 'null'
      pending: false
      flash: null
  componentDidUpdate: (prevProps) ->
    dirtyCompare = @state.dirtyCompare
    if prevProps.config isnt @props.config
      dirtyCompare = JSON.stringify if @props.name isnt 'ci' then @props.config.processes[@props.name]
        else {} <<< @props.config <<< processes:''
      @setState {dirtyCompare}
    if not prevProps.config? and @props.config? or not prevProps.expand and @props.expand
      @setState {name:@props.name, json:JSON.parse dirtyCompare}
  render: ->
    if not @props.expand
      e 'div', className:'config',
        e 'div', className:'buttons',
          e 'button', onClick: @props.toggleExpand, '🛠'
    else
      dirty = @props.config and (JSON.stringify(@state.json) isnt @state.dirtyCompare or @props.name isnt @state.name)
      e 'div',
        className:"config #{@state.pending and 'pending' or ''} #{@state.flash or ''}",
        onAnimationEnd: ~> @setState flash: null
        e 'div', className:'buttons',
          e 'button',
            className: dirty and 'unlocked' or 'locked'
            onClick: ~> if dirty
              @setState pending: true
              if @props.name isnt 'ci'
                _config = JSON.parse JSON.stringify @props.config
                delete _config.processes[@props.name]
                newname = @state.name
                while newname is '' or _config.processes[newname]? then newname += '_'
                _config.processes[newname] = @state.json
              else
                _config = {} <<< @state.json <<< {processes:@props.config.processes}
              res <~ fetch(@props.url, method:'PUT', body:JSON.stringify _config) .catch((e) -> Promise.resolve e) .then _
              @update = true
              # component still alive
              if @state.name is @props.name
                if res.status is 200 then @setState flash: 'success' else @setState flash: 'failure'
                @props.heartbeat ~> @setState pending: false
              else
                @props.heartbeat!
            ''
          e 'button',
            className:'delete',
            onClick: ~>
              _config = JSON.parse JSON.stringify @props.config
              delete _config.processes[@props.name]
              fetch(@props.url, method:'PUT', body:JSON.stringify _config) .then ~> @props.heartbeat!
            '🗑'
          e 'button', onClick: @props.toggleExpand, '🗙'
        e 'input',
          value:@state.name or '',
          onChange: ({target}) ~> @setState name:target.value
        e json_component(@state.json),
          key: 'json'
          json: @state.json
          setValue: (val) ~> @setState json:val

ReactDOM.render React.createElement(Dashboard), document.getElementById "app"
