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
    db: require './components/db'
    api: require './components/api'
    name: require './components/name'
    auth: require './components/auth'
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

module.exports = ATTAK