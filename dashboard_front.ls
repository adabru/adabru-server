React = require 'react'
ReactDOM = require 'react-dom'
e = React.createElement

class Dashboard extends React.Component
  ->
    @state = do
      token: ''
      approved: 'no'
      procs: []
  componentDidMount: ->
    if (localStorage.getItem 'token')? then @putToken that
    setInterval (~> if @state.approved is 'yes' then @refresh!), 1000
  putToken: (token) ->
    @setState {approved: 'pending', token}, @refresh
  refresh: (callback) ~>
    token = @state.token
    res <~ fetch "proc?token=#token" .then _
    if res.status is 403 then return @setState approved: 'no'
    procs <~ res.json!.then _
    localStorage.setItem 'token', token
    @setState {approved: 'yes', token, procs}, callback
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
        @state.procs.map (proc, i) ~> React.createElement ProcessItem, {key:i, token:@state.token, refresh:@refresh} <<< proc



class ProcessItem extends React.Component
  ->
    @flash = ->
    @state = do
      pending: false
      flash: null
  act: (action) ->
    @setState pending: true
    res <~ fetch "proc/#{@props.name}/#action?token=#{@props.token}" .then _
    if res.status is 200 then @setState flash: 'success' else @setState flash: 'failure'
    @props.refresh ~> @setState pending: false
    setTimeout (~> @setState flash: null), 100
  render: ->
    e 'li',
      className: "#{@props.status.replace ' ', ''}#{if @state.pending then ' pending' else ''} #{@state.flash ? ''}",
      e 'span', className: 'name', @props.name
      e 'button', className: "restart", onClick: ~> @act 'restart'
      e 'button', className: "stop", onClick: ~> @act 'stop'
      e 'button', className: "start", onClick: ~> @act 'start'
      e 'span', className: 'pid', @props.pid
      e 'span',
        className: 'ports'
        @props.ports.map (port, i) -> e 'span', key:i, className:'port', port
ProcessItem.defaultProps = pid: -1, ports: []


ReactDOM.render React.createElement(Dashboard), document.getElementById "app"
