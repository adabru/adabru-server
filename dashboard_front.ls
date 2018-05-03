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
  componentDidMount: ->
    if (localStorage.getItem 'token')? then @putToken that
    if (localStorage.getItem 'procs')? then @setState procs: JSON.parse that
    setInterval (~> if @state.approved is 'yes' then @refresh!), 1000
  putToken: (token) ->
    @setState {approved: 'pending', token}, @refresh
  changeLogstate: (name, logstate) ~>
    procs = @state.procs.map (x) ->
      if x.name is name then x.logstate <<< logstate
      x
    @setState {procs}
    localStorage.setItem 'procs', JSON.stringify procs
  refresh: (callback = ->) ~>
    token = @state.token
    res <~ fetch "proc?token=#token" .catch((e) -> Promise.resolve e) .then _
    if res.status is 403 then return @setState approved: 'no', callback
    if res.status isnt 200 then return callback!
    procs <~ res.json!.then _
    procs = procs.map (p) ~> {logstate: {lastdate:0, lastsize:0}} <<< (@state.procs.find (x) -> x.name is p.name) <<< p
    localStorage.setItem 'token', token
    @setState {approved: 'yes', token, procs}, callback
    # update log information
    res <~ fetch "log?token=#token" .then _
    if res.status isnt 200 then return
    loginfo <~ res.json!.then _
    procs := procs.map (p) ~> {} <<< p <<< logstate: ({} <<< p.logstate <<< (loginfo.find (x) -> x.name is p.name){size})
    @setState {procs}
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
      e 'ul',
        className: 'procs'
        @state.procs.map (proc, i) ~> e ProcessItem, {key:i} <<< @state{token} <<< @{refresh} <<< {changeLogstate:@changeLogstate.bind null, proc.name} <<< proc



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
    @props.refresh ~> @setState pending: false
  render: ->
    e 'li',
      className: "proc #{@props.status.replace ' ', ''}#{if @state.pending then ' pending' else ''}#{if @state.expand then ' expand' else ''}",
      e 'div',
        className: "header #{@state.flash ? ''}",
        onAnimationEnd: ~> @setState flash: null
        onClick: ~>
          @setState expand: not @state.expand
          @props.changeLogstate lastsize: @props.logstate.size ? 0
        e 'span', className: 'name', @props.name
        e 'button', className: 'restart', onClick: (e) ~> e.stopPropagation! ; @act 'restart'
        e 'button', className: 'stop', onClick: (e) ~> e.stopPropagation! ; @act 'stop'
        e 'button', className: 'start', onClick: (e) ~> e.stopPropagation! ; @act 'start'
        e 'span', className: 'pid', @props.pid
        e 'span',
          className: 'ports'
          @props.ports.map (port, i) -> e 'span', key:i, className:'port', port
        e 'span', className: 'loginfo', (@props.logstate.size ? 0) - @props.logstate.lastsize
      e ProcessLog,
        {url: "log/#{@props.name}?token=#{@props.token}"} <<< @state{expand} <<< @props{logstate, changeLogstate}
      e ProcessConfig,
        {url: "proc/#{@props.name}/config?token=#{@props.token}"} <<< @state{expand}
ProcessItem.defaultProps = pid: -1, ports: []



class ProcessLog extends React.Component
  ->
    @scrollpane = null
    @state = do
      log: null
  componentDidUpdate: (prevProps, prevState) ->
    if @props.expand and (not @state.log? or prevProps.logstate.size isnt @props.logstate.size)
      res <~ fetch @props.url .catch((e) -> Promise.resolve e) .then _
      if res.status isnt 200 then return
      log <~ res.json!.then _
      @setState {log: log.slice 0, -1}
    if @state.log? and ((@props.expand and not prevProps.expand) or not prevState.log?)
      @scrollpane.scrollTop = @scrollpane.children[@state.log.findIndex (x) ~> x.d >= @props.logstate.lastdate]?.offsetTop
      @updateSeen!
  updateSeen: ->
    if @scrollpane?
      line = -1 + (Array.from @scrollpane.children).findIndex (c) ~> c.offsetTop > @scrollpane.scrollTop + @scrollpane.clientHeight + 5
      if line < 0 then line = @scrollpane.children.length - 1
      if @state.log[line].d > @props.logstate.lastdate then @props.changeLogstate lastdate: @state.log[line].d
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
        className:"entry #{if d > @props.logstate.lastdate then 'unread'}"
        e 'span', className: "date #{diff.substr -1}", diff
        e 'pre', {}, s
    e 'div',
      className: "log",
      onScroll: ~>@updateSeen!,
      onTransitionEnd: ~>@updateSeen!,
      ref: (dom) ~> @scrollpane = dom
      if @state.log? then @state.log.map buildItem else e 'span', {}, 'no log yet'


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
