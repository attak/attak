fs = require 'fs'
async = require 'async'
extend = require 'extend'
nodePath = require 'path'
Processors = require './components/processors'
TopologyUtils = require './topology'
BaseComponent = require './components/base_component'

class ATTAK extends BaseComponent
  namespace: 'ATTAK'

  defaultComponents:
    api: require './components/api'
    name: require './components/name'
    hooks: require './components/hooks'
    static: require './components/static'
    streams: require './components/streams'
    schedule: require './components/schedule'
    processors: require './components/processors'

  constructor: (@options={}) ->
    super @options
    @topology = @options.topology
    @dependencies = @options.dependencies || []
    components = extend @defaultComponents, @topology.components || {}
    allComponents = extend @options.children || {}, components

    @children = {}
    for key, Component of allComponents
      child = new Component extend @options,
        path: [key]
      @addChild key, child

  setState: (currentState, newState, opts, callback) ->
    keys = Object.keys(currentState)
    for key, val of newState
      if key not in keys
        keys.push key

    asyncItems = {}
    async.eachSeries keys, (key, next) =>
      component = @children[key]
      target = newState[key] || {}
      current = currentState[key] || {}

      runSetState = (args..., done) =>
        component.setState current, target, opts, (err, results) =>
          extend true, currentState, @loadState()
          done err

      if component is undefined
        console.log "UNKNOWN COMPONENT", key, newState, keys

      if component.dependencies
        asyncItems[key] = [component.dependencies..., runSetState]
      else
        asyncItems[key] = runSetState

      next()
    , (err) =>
      async.auto asyncItems, 1, (err) ->
        callback err, currentState

  handleDiff: (state, diff, opts) ->
    async.forEachOf diff.rhs, (val, key, next) =>
      component = @children[key]
      if component is undefined
        return next new Error "No component for namespace #{key}"

      component.setState val, ->
        next()
    , (err) ->
      callback err

module.exports = ATTAK