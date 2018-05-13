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
    res <~ fetch "proc?token=#token" .catch((e) -> Promise.resolve e) .then _
    if res.status? then @setState beatPhase: (@state.beatPhase + 1) % 2
    if res.status is 403 then return @setState approved: 'no', proceed
    if res.status isnt 200 then return proceed!
    procs <~ res.json!.then _
    procs = procs.map (p) ~> {logsize:0} <<< (@state.procs.find (x) -> x.name is p.name) <<< {name:'n/a', pid:'', ports:[]} <<< p
    localStorage.setItem 'token', token
    @setState {approved: 'yes', token, procs}, callback
    callback := ->
    # central notification for log refreshing
    res <~ fetch "log?token=#token" .then _
    if res.status isnt 200 then return proceed!
    loginfo <~ res.json!.then _
    procs := procs.map (p) ~>
      p <<< if loginfo.find((x) -> x.name is p.name) then logsize: that.size else null
    @setState {procs}, proceed
  render: ->
    if @state.approved isnt 'yes'
      e 'div', className:'dashboard',
        e 'header', {},
          e 'span', className:"heartbeat phase#{@state.beatPhase}", '💙'
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
        e 'header', {}, e 'span', className:"heartbeat phase#{@state.beatPhase}", '💙'
        e 'div', className: 'procs',
          @state.procs.map (proc, i) ~>
            e ProcessItem, {key:proc.name} <<< @state{token} <<< @{heartbeat} <<< proc



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
        {url: "proc/#{@props.name}/config?token=#{@props.token}"} <<< @state{expand} <<< toggleExpand: ~> @setState expand: not @state.expand
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
        case dt <                 99 * 1000 then "#{Math.round dt                      / 1000}s"
        case dt <            99 * 60 * 1000 then "#{Math.round dt                 / 60 / 1000}m"
        case dt <       20 * 60 * 60 * 1000 then "#{Math.round dt            / 60 / 60 / 1000}h"
        case dt <   5 * 24 * 60 * 60 * 1000 then "#{Math.round dt       / 24 / 60 / 60 / 1000}d"
        case dt <  35 * 24 * 60 * 60 * 1000 then "#{Math.round dt   / 7 / 24 / 60 / 60 / 1000}w"
        case dt < 300 * 24 * 60 * 60 * 1000 then "#{Math.round dt  / 30 / 24 / 60 / 60 / 1000}o"
        case dt <                  Infinity then "#{Math.round dt / 365 / 24 / 60 / 60 / 1000}y"
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
      dirtyCompare: 'null'
      pending: false
      flash: null
  componentDidUpdate: (prevProps) ->
    if @props.expand and not prevProps.expand then @refreshConfig!
  refreshConfig: (callback) ->
    res <~ fetch @props.url .catch((e) -> Promise.resolve e) .then _
    if res.status isnt 200 then return callback!
    json <~ res.json!.then _
    @setState {json, dirtyCompare: JSON.stringify json}, callback
  render: ->
    if not @props.expand
      e 'div', className:'config',
        e 'button', onClick: @props.toggleExpand, '🛠'
    else
      dirty = JSON.stringify(@state.json) isnt @state.dirtyCompare
      e 'div',
        className:"config #{@state.pending and 'pending' or ''} #{@state.flash or ''}",
        onAnimationEnd: ~> @setState flash: null
        e 'button',
          className: dirty and 'unlocked' or 'locked'
          onClick: ~> if dirty
            @setState pending: true
            res <~ fetch(@props.url, method:'PUT', body:JSON.stringify @state.json) .catch((e) -> Promise.resolve e) .then _
            if res.status is 200 then @setState flash: 'success' else @setState flash: 'failure'
            @refreshConfig ~> @setState pending: false
          ''
        e 'button', onClick: @props.toggleExpand, '🗙'
        e json_component(@state.json),
          json: @state.json
          setValue: (val) ~> @setState json:val

ReactDOM.render React.createElement(Dashboard), document.getElementById "app"
