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
    processors: require './components/processors'

  constructor: (@options={}) ->
    super @options
    @topology = @options.topology
    @dependencies = @options.dependencies || []
    components = extend @defaultComponents, @topology.components || {}
    allComponents = extend @options.children || {}, components

    @children = {}
    for key, Component of allComponents
      @children[key] = new Component
        path: [key]

  handleDiff: (diff, callback) ->
    console.log "HANDLE DIFF", @namespace, diff
    async.forEachOf diff.rhs, (val, key, next) =>
      component = @children[key]
      if component is undefined
        console.log "WE HAVE", @children
        return next new Error "No component for namespace #{key}"

      component.setState val, ->
        next()
    , (err) ->
      callback err

module.exports = ATTAK