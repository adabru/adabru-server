React = require 'react'
ReactDOM = require 'react-dom'
e = React.createElement

json_component = (json) -> switch
  case json is null then JsonStem
  case typeof json isnt 'object' then JsonString
  case Array.isArray json then JsonArray
  default then JsonObject


# value null used for JsonStem
class JsonStem extends React.Component
  render: ->
    e 'div', className: 'json-stem',
      e 'button', {onClick: ~> @props.setValue ''}, '" "'
      e 'button', {onClick: ~> @props.setValue []}, '[ ]'
      e 'button', {onClick: ~> @props.setValue {}}, '{ }'


class JsonString extends React.Component
  render: ->
    e 'textarea',
      className: 'json-string'
      placeholder: 'text'
      value: @props.json
      onChange: (e) ~> @update e
      onFocus: (e) ~> @update e
      onBlur: (e) ~> @update e
      ref: (ta) ~> @ta = ta
  componentDidMount: ~> @resize!
  componentDidUpdate: ~> @resize!
  update: ({target}) ->
    @props.setValue target.value
    @resize!
  resize: ->
    # workaround issue when not visible
    dummy = @ta.cloneNode!
    dummy.style = "width:0; height:0; resize:none; overflow:hidden; white-space:pre; padding:4px 4px; min-width:0"
    document.body.append dummy
    @ta.style <<< { height:dummy.scrollHeight, width:dummy.scrollWidth }
    if @ta is document.activeElement and @ta.scrollWidth > @ta.clientWidth + 16
      @ta.style.height = parseInt(/[\d]+/.exec(@ta.style.height).0) + 12 + 'px'
    document.body.removeChild(dummy)


class JsonArray extends React.Component
  render: ->
    e 'ul',
      className: 'json-array'
      @props.json.map (item, i) ~>
        e 'li', key:i,
          e 'button', onClick: (~> @props.setValue @props.json.filter (,_i) -> _i isnt i)
          e json_component(item),
            json: item
            setValue: (val) ~> @props.setValue @props.json.map (_item, _i) -> if _i isnt i then _item else val
      e 'li', {},
        e 'button', onClick: (~> @props.setValue @props.json ++ null)


class JsonObject extends React.Component
  (props) ->
    super props
    @domKeys = Object.keys({} <<< @props.json).reduce (a,key) -> (a <<< "#{key}":Math.random!), {}
    @newDomKey = Math.random!
    if typeof @props.json isnt 'object'
      props.setValue key:@props.json
  render: ->
    tuples = Object.entries(@props.json).sort!.map ([key, value]) ~>
      e 'li', key:@domKeys[key],
        e 'input',
          value: key
          onChange: ({target}) ~>
            while @props.json[target.value]?
              if target.value is key then return
              target.value += '_'
            if target.value isnt ''
              @props.json[target.value] = @props.json[key]
              @domKeys[target.value] = @domKeys[key]
            delete @props.json[key]
            delete @domKeys[key]
            @props.setValue @props.json
          size: 1
        e json_component(value),
          json: @props.json[key]
          setValue: (val) ~> @props.setValue @props.json <<< "#{key}":val

    tuples ++= e 'li', {key:@newDomKey}, e 'input',
      value: '' # make input controlled to suppress console warning
      onChange: ({target}) ~>
        newKey = target.value
        while @props.json[newKey]? then newKey += '_'
        @props.setValue {} <<< @props.json <<< "#{newKey}": null
        @domKeys[newKey] = @newDomKey
        @newDomKey = Math.random!
      size: 1

    e 'ul',
      ref: (ul) ~> @ul = ul
      className: 'json-object'
      tuples
  componentDidUpdate: (prevProps) ~> @resize!
  componentDidMount: ~> @resize!
  resize: ->
    for li in @ul.children
      inp = li.children[0]
      # workaround issue when not visible
      dummy = inp.cloneNode!
      if inp.value is '' /*add prop*/ then dummy.value = inp.placeholder
      document.body.append dummy
      dummy.style = 'font-size: 0.9em; width:0; height:0; resize:none; overflow:hidden; white-space:pre; padding:8px; min-width:0'
      inp.style.width = dummy.scrollWidth + 'px'
      document.body.removeChild dummy


exports <<< { json_component, JsonStem, JsonString, JsonObject, JsonArray }

####  Example Usage
#
# class JsonEditor extends React.Component
#   ->
#     @state = do
#       json: {i:"2"}
#   render: ->
#     e JsonObject,
#       json: @state.json
#       setValue: (val) ~> @setState json:val
