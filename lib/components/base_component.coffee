async = require 'async'
extend = require 'extend'
Differ = require 'deep-diff'

class BaseComponent

  lifecycle:
    events: ['init', 'resolve', 'diff']
    stages: ['before' 'after']

  constructor: (@options={}) ->
    @children = @options.children || {}
    @dependencies = @options.dependencies || []
    @listeners = {}

  getState: (callback) ->
    callback new Error "Unimplemented"

  create: (path, newDefs, callback) ->
    callback new Error "Unimplemented"

  delete: (path, oldDefs, callback) ->
    callback new Error "Unimplemented"

  add: (path, index, item, callback) ->
    callback new Error "Unimplemented"

  update: (path, oldDefs, newDefs, callback) ->
    @delete path, oldDefs, (err, results) =>
      if err then return callback err
      @create newDefs, callback

  setState: (newState, callback) ->
    @getState (err, currentState) =>
      differences = Differ.diff currentState, newState
      @resolveState currentState, newState, differences, (err, results) ->
        callback err, results

  handleDiff: (diff, callback) ->
    console.log "DIFF", diff
    switch diff.kind
      when 'N'
        @create diff.path || [], diff.rhs, callback
      when 'E'
        @update diff.path || [], diff.lhs, diff.rhs, callback
      when 'D'
        @delete diff.path || [], diff.lhs, callback
      when 'A'
        @add diff.path || [], diff.index, diff.item, callback
      else
        callback "Unknown diff type #{diff.kind || diff}"

  resolveState: (currentState, newState, diffs, callback) ->
    async.eachSeries diffs, (diff, next) ->
      if @children?[diff.path?[0]]
        diff.path.shift()
        @children[diff.path?[0]].handleDiff diff, next
      else
        @handleDiff diff, next
    , (err) ->
      callback err

  getSimulationServices: () ->
    services = {}

    if @simulation?.services?.constructor is Array
      for defs in @simulation.services
        if defs.constructor is String
          existing = services[defs] || {}
          services[defs] = extend existing, {}
        else
          namespace = Object.keys(defs)[0]
          config = defs[namespace]

          for namespace, config of defs
            existing = services[namespace] || {}
            services[namespace] = extend existing, config
    
    else if @simulation?.services
      for namespace, config of @simulation.services
        existing = services[namespace] || {}
        services[namespace] = extend existing, config

    for childName, child of (@children || {})
      services = extend services, child.getSimulationServices()

    return services

  getDependencies: (path) ->
    deps = @dependencies
    
    if @children?[path[0]]
      child = path.shift()
      deps = deps.concat @children[child].getDependencies(path)
    
    return deps

module.exports = BaseComponent