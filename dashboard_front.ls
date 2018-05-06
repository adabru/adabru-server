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
    @nextBeat = null
  componentDidMount: ->
    if (localStorage.getItem 'token')? then @putToken that
    if (localStorage.getItem 'procs')? then @setState procs: JSON.parse that
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
    if res.status is 403 then return @setState approved: 'no', proceed
    if res.status isnt 200 then return proceed!
    procs <~ res.json!.then _
    procs = procs.map (p) ~> {logsize:0} <<< (@state.procs.find (x) -> x.name is p.name) <<< {name:'n/a', pid:'', ports:[]} <<< p
    localStorage.setItem 'token', token
    @setState {approved: 'yes', token, procs}, callback
    callback := ->
    # central notification fo log refreshing
    res <~ fetch "log?token=#token" .then _
    if res.status isnt 200 then return proceed!
    loginfo <~ res.json!.then _
    procs := procs.map (p) ~>
      p <<< logsize: loginfo.find((x) -> x.name is p.name).size
    localStorage.setItem 'procs', JSON.stringify procs
    @setState {procs}, proceed
  render: ->
    if @state.approved isnt 'yes'
      e 'div',
        className: 'token'
        e 'input',
          value: @state.token
          placeholder: 'enter token'
          autoFocus: true
          onChange: (e) ~> @putToken e.target.value
          style:
            color: {'no':'#aa0000', 'pending':'#aaaa00'}[@state.approved]
    else
      e 'table',
        className: 'procs'
        e 'tbody', {}, @state.procs.map (proc, i) ~>
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
    console.log 'check procitem'
    Object.keys(@props).some (k) ~> k isnt 'ports' and @props[k] isnt nextProps[k]
    or @props['ports'].length isnt nextProps['ports'].length
    or @props['ports'].some (p) ~> not p in nextProps['ports']
    or Object.keys(@state).some (k) ~> @state[k] isnt nextState[k]
  render: ->
    console.log 'proc render'
    e 'tr',
      className: "proc #{@props.status.replace ' ', ''} #{@state.pending and 'pending' or ''} #{@state.expand and 'expand' or ''} #{@state.flash ? ''}",
      onAnimationEnd: ~> @setState flash: null
      onClick: ~>
        @setState expand: not @state.expand
      e 'td', className: 'status', {'running':'', 'not running':'⚠', 'stopped':'☠'}[@props.status]
      e 'td', className: 'name', @props.name
      e 'td', className: 'restart', e 'button', onClick:((e) ~> e.stopPropagation! ; @act 'restart'), '💣🏃'
      e 'td', className: 'stop',    e 'button', onClick:((e) ~> e.stopPropagation! ; @act 'stop'   ), '💣'
      e 'td', className: 'start',   e 'button', onClick:((e) ~> e.stopPropagation! ; @act 'start'  ), '🏃'
      e 'td', className: 'pid',
        e 'span', {}, @props.pid
        e 'div', className: 'ports', @props.ports.map (port, i) -> e 'span', key:i, className:'port', port
      e 'td', {}, e ProcessLog,
        {url: "log/#{@props.name}?token=#{@props.token}"} <<< @state{expand} <<< @props{logsize, name}
      e 'td', {}, e ProcessConfig,
        {url: "proc/#{@props.name}/config?token=#{@props.token}"} <<< @state{expand}
ProcessItem.defaultProps = pid: -1, ports: []



class ProcessLog extends React.PureComponent
  ->
    @state = do
      scrollend: true
      log: []
      logsize: 0
    @scrollpane = null
  componentDidMount: ->
    @scrollpane.scrollTop = @scrollpane.scrollHeight
    if (localStorage.getItem "log_#{@props.name}")?
      @setState JSON.parse(that), @refreshLog
    else
      @refreshLog!
  componentDidUpdate: (prevProps, prevState) ->
    @refreshLog!
    if @state.logsize isnt prevState.logsize
      if @state.scrollend then @scrollpane.scrollTop = @scrollpane.scrollHeight
      localStorage.setItem "log_#{@props.name}", JSON.stringify @state{log,logsize}
  refreshLog: ->
    console.log 'log render'
    if @state.logsize is @props.logsize then return
    # prevent further updates
    @setState logsize: @props.logsize
    res <~ fetch @props.url .catch((e) -> Promise.resolve e) .then _
    if res.status isnt 200 then return
    log <~ res.json!.then _
    @setState log:log.slice 0, -1
  render: ->
    buildItem = ({d,s}, i) ~>
      e 'div',
        key:i,
        className:"entry"
        e ElapsedTime, {d}
        e 'pre', {}, s
    e 'div',
      className: "log",
      onScroll: ~> @setState scrollend: @scrollpane.scrollTop is @scrollpane.scrollHeight,
      ref: (dom) ~> @scrollpane = dom
      if @state.log.length > 0 then @state.log.map buildItem else buildItem {d:Date.now!, s:'no log yet'}
# class used for optimized performance in react dev mode
class ElapsedTime extends React.PureComponent
  (props) ->
    super props
    @state = diffTime: @diffTime!
  # componentDidMount: ->
  #   console.log 'zahl'
    # @timer = setTimeout ~> @forceUpdate!
  # componentDidMount: -> @timer = setInterval (~>@setState systemtime:Date.now!), 2000
  # componentDidMount: -> @timer = setInterval (~>@forceUpdate!), 5000
  componentDidMount: -> @timer = setInterval (~>@setState diffTime:@diffTime!), 5000
  componentWillUnmount: ->
    # clearTimeout @timer
    clearInterval @timer
  render: ->
    console.log 'date'
    # dt = @state.systemtime - @props.d
    e 'span', className: "date #{@state.diffTime.substr -1}", @state.diffTime
  diffTime: ->
    dt = Date.now! - @props.d
    diff = switch
      case dt <                 99 * 1000 then "#{Math.round dt                      / 1000}s"
      case dt <            99 * 60 * 1000 then "#{Math.round dt                 / 60 / 1000}m"
      case dt <       20 * 60 * 60 * 1000 then "#{Math.round dt            / 60 / 60 / 1000}h"
      case dt <   5 * 24 * 60 * 60 * 1000 then "#{Math.round dt       / 24 / 60 / 60 / 1000}d"
      case dt <  35 * 24 * 60 * 60 * 1000 then "#{Math.round dt   / 7 / 24 / 60 / 60 / 1000}w"
      case dt < 300 * 24 * 60 * 60 * 1000 then "#{Math.round dt  / 30 / 24 / 60 / 60 / 1000}o"
      case dt <                  Infinity then "#{Math.round dt / 365 / 24 / 60 / 60 / 1000}y"


class ProcessConfig extends React.Component
  ->
    @state = do
      json: null
  componentDidUpdate: (prevProps) ->
    if @props.expand and not prevProps.expand
      res <~ fetch @props.url .catch((e) -> Promise.resolve e) .then _
      if res.status isnt 200 then return
      json <~ res.json!.then _
      @setState {json}
  render: ->
    e 'div', className:'config',
      e json_component(@state.json),
        json: @state.json
        setValue: (val) ~> @setState json:val

ReactDOM.render React.createElement(Dashboard), document.getElementById "app"
