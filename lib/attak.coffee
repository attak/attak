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

      runSetState = (done) =>
        console.log "SET COMPONENT STATE", component.constructor.name
        component.setState currentState, target, opts, (err, results) =>
          console.log "FINISHED SETTING COMPONENT STATE", component.constructor.name, err
          extend true, currentState, @loadState()
          console.log "UPDATED CURRENT STATE", currentState
          done err

      if component.dependencies
        asyncItems[key] = [component.dependencies..., runSetState]
      else
        asyncItems[key] = runSetState

      next()
    , (err) =>
      async.auto asyncItems, 1, (err) ->
        console.log "ALL DONE SETTING STATE", err
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