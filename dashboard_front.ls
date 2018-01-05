React = require 'react'
ReactDOM = require 'react-dom'
e = React.createElement

class Dashboard extends React.Component
  ->
    @state = do
      token: 'null'
      procs: []
  # componentDidMount: ->
  #   fetch "/proc"
  #   .then (res) -> res.json!
  #   .then (json) -> @setState procs: json
  render: ->
    # buildProc = (p,i) ->
    #   li do
    #     key: "p#i"
    #     span p.name
    #     span p.status
    #     span p.pid
    #     span p.ports

    e 'div',
      className: 'token'
      e 'input',
        value: @state.token
        onChange: (e) ~> @setState token: e.target.value
      # e 'ul'
      #   class: 'proc'
      #   @state.proc.map buildProc

ReactDOM.render React.createElement(Dashboard), document.getElementById "app"
