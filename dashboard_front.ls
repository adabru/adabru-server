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
  putToken: (token) ->
    @setState {approved: 'pending', token}
    res <~ fetch "proc?token=#token" .then _
    if res.status is 403 then return @setState approved: 'no'
    procs <~ res.json!.then _
    localStorage.setItem 'token', token
    @setState {approved: 'yes', token, procs}
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
      buildProc = (p,i) ->
        if(p.status is 'running')
          e 'li',
            key: "p#i"
            e 'span', className: p.status, p.name
            e 'span', className: 'pid', p.pid
            e 'span',
              className: 'ports'
              p.ports.map (port, i) -> e 'span', key:i, className:'port', port
        else
          e 'li',
            key: "p#i"
            e 'span', className: p.status, p.name
      e 'ul',
        className: 'procs'
        @state.procs.map buildProc

ReactDOM.render React.createElement(Dashboard), document.getElementById "app"
