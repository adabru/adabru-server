React = require 'react'
ReactDOM = require 'react-dom'
e = React.createElement


class JsonEnum extends React.Component
  ->
  render: ->
    e 'select',
      className: 'json-enum'
      onChange: ({target}) ~> @props.setValue target.value
      value: @props.json
      @props.schema.values.map (value) -> e 'option', {value}, value
JsonEnum.defaultProps = schema: {values:['yes','no']}, json:'yes', setValue:->


class JsonString extends React.Component
  ->
  render: ->
    e 'textarea',
      className: 'json-string'
      placeholder: @props.schema.placeholder or ''
      value: @props.json
      onChange: (e) ~> @update e
      ref: (ta) ~> @ta = ta
  componentDidMount: ~> @resize!
  update: ({target}) ->
    @props.setValue target.value
    @resize!
  resize: ->
    # workaround issue when not visible
    dummy = @ta.cloneNode!
    dummy.style = "width:0; height:0; resize:none; overflow:hidden; white-space:pre; padding:4px 8px; min-width:0"
    document.body.append dummy
    @ta.style <<< { height:dummy.scrollHeight, width:dummy.scrollWidth }
    document.body.removeChild(dummy)
JsonString.defaultProps = schema: {placeholder:'json string'}, json:{i:2}, setValue:->


class JsonArray extends React.Component
  (props) ->
    if not Array.isArray props.json
      props.setValue [props.json]
  render: ->
    if not Array.isArray @props.json then return null
    e 'ul',
      className: 'json-array'
      @props.json.map (item, i) ~>
        e 'li', key:i,
          e 'button', onClick: (~> @props.setValue @props.json.filter (,_i) -> _i isnt i), '–'
          e {'string':JsonString, 'object':JsonObject, 'array':JsonArray}[@props.schema.child.type],
            schema: @props.schema.child
            json: item
            setValue: (val) ~> @props.setValue @props.json.map (_item, _i) -> if _i isnt i then _item else val
      e 'li', {},
        e 'button', onClick: (~> @props.setValue @props.json ++ {'string':'', 'object':{}, 'array':[]}[@props.schema.child.type]), '+'


class JsonObject extends React.Component
  (props) ->
    super props
    @domKeys = Object.keys({} <<< @props.schema.props <<< @props.json).reduce (a,key) -> (a <<< "#{key}":Math.random!), {}
    @newDomKey = Math.random!
    if typeof @props.json isnt 'object'
      props.setValue key:@props.json
  render: ->
    tuples = Object.entries({} <<< @props.schema.props <<< @props.json).sort!.map ([key, value]) ~>
      _schema = @props.schema.props?[key] or @props.schema.addProp or type: switch
        case typeof value isnt 'object' then 'string'
        case Array.isArray value then 'array'
        default then 'object'
      e 'li', key:@domKeys[key],
        e 'input',
          disabled: @props.schema.props?[key]?
          className: switch
            case @props.schema.required?.includes key then 'required'
            case not @props.schema.props?[key]?       then 'added'
            case @props.json[key]?                    then 'set'
            default                                   then 'unset'
            # TODO: 'invalid'
          value: key
          onChange: ({target}) ~>
            # only possible if not disabled = added property
            while @props.schema.props?[target.value]? or @props.json[target.value]?
              if target.value is key then return
              target.value += '_'
            if target.value isnt ''
              @props.json[target.value] = @props.json[key]
              @domKeys[target.value] = @domKeys[key]
            delete @props.json[key]
            delete @domKeys[key]
            @props.setValue @props.json
          size: 1
        e ( {'enum':JsonEnum, 'string':JsonString, 'object':JsonObject, 'array':JsonArray}[_schema.type] ),
          schema: _schema
          json: @props.json[key] or {'enum':'', 'string':'', 'array':[], 'object':{}}[_schema.type]
          setValue: (val) ~> @props.setValue @props.json <<< "#{key}":val

    if @props.schema.addProp?
      tuples ++= e 'li', {key:@newDomKey}, e 'input',
        placeholder: @props.schema.addProp.name
        value: '' # make input controlled to suppress console warning
        onChange: ({target}) ~>
          newKey = target.value
          while @props.json[newKey]? then newKey += '_'
          @props.setValue {} <<< @props.json <<< "#{newKey}": {'string':'', 'object':{}, 'array':[]}[@props.schema.addProp.type]
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
JsonObject.defaultProps = schema: {addProp:{name:'key',type:'string'}}, json:{i:2}, setValue:->

# class JsonInvalid extends React.Component
#   (props) ->
#     @state = raw: JSON.stringify props.json, ' ', 2
#   render: ->
#     e 'div', className: 'json-invalid',
#       e 'pre', {}, JSON.stringify @props.schema, ' ', 2
#       e JsonString,
#         json: @state.raw
#         schema: placeholder: 'raw json'
#         setValue: (val) ~>
#           try
#             @setState raw:val
#             json = JSON.parse val
#             @props.setValue json
#           catch e then # invalid JSON

validateSchema = (schema) ->
  without = (a, b) ->
    if not Array.isArray a then a = Object.keys a
    if not Array.isArray b then b = Object.keys b
    a.filter (x) -> not x in b
  schema-valid = (schema) ->
    if not schema.type? then "property 'type' is missing"
    else {'enum':enum-valid, 'string':string-valid, 'array':array-valid, 'object':object-valid}[schema.type] schema
  enum-valid = (schema) -> switch
    case not schema.values? then "property 'values' is missing"
    case not Array.isArray schema.values then "property 'values' must be array of string"
    case ($=schema `without` ['values']).0? then "properties '#$' are not allowed"
    default then 'ok'
  string-valid = (schema) -> switch
    case ($=schema `without` ['placeholder']).0? then "properties '#$' are not allowed"
    default then 'ok'
  array-valid = (schema) -> switch
    case not schema.child? then "property 'child' is missing"
    case ($=schema-valid schema.child) isnt 'ok' then "child's schema is invalid: #$"
    case ($=schema `without` ['child']).0? then "properties '#$' are not allowed"
    default then 'ok'
  object-valid = (schema) -> switch
    case not schema.props? and not schema.addProp? then "at least one of properties 'props' and 'addProp' is required"
    case schema.addProp? and ($=schema-valid schema.addProp) isnt 'ok' then "addProps's schema is invalid: #$"
    case schema.props? and ($=Object.entries(schema.props).map(([k,v]) -> [k,schema-valid v]).find(([k,v]) -> v isnt 'ok'))?
      "props.#{$.0}'s schema is invalid: #{$.1}"
    case ($=schema `without` ['props', 'addProp', 'required']).0? then "properties '#$' are not allowed"
    default then 'ok'
  schema-valid schema

# validateJson = (json, schema) ->
#   switch
#     case schema.type in ['enum', 'string']
#       if typeof json isnt 'string' then 'json must be a string'
#       else then 'ok'
#     case schema.type is 'array'
#       if not Array.isArray json then 'json must be an array'
#       else if ($=json.map((x,i)->[i,validateJson x, schema.child]).find(([,e])->e isnt 'ok'))?
#         "element #{$.0} is invalid: #{$.1}"
#       else then 'ok'
#     case schema.type is 'object'
#       if typeof json isnt 'object' then 'json must be an object'
#       else if ($=Object.entries(json).map(([k,v])->[k,validateJson v, schema.props?[k]? or schema.addProp]).find(([,e])->e isnt 'ok'))?
#         "property #{$.0} is invalid: #{$.1}"
#       else then 'ok'


exports <<< { JsonObject, JsonArray, validateSchema }

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
