fs = require 'fs'
uuid = require 'uuid'
async = require 'async'
extend = require 'extend'
Differ = require 'deep-diff'
nodePath = require 'path'

STATE_FILE_PATH = '../../state.json'
SIMULATION_STATE_FILE_PATH = '../../simulation_state.json'

class BaseComponent
  lifecycle:
    events: ['init', 'resolve', 'diff']
    stages: ['before', 'after']

  constructor: (@options={}) ->
    @guid = uuid.v1()
    @path = @options.path || []
    @state = {}
    @children = @options.children || {}
    @namespace = 'base'
    @listeners = {}
    @dependencies = @options.dependencies || []

  setup: (callback) ->
    async.forEachOf @children || {}, (child, name, next) ->
      child.setup next
    , (err) =>
      @init callback

  init: (callback) ->
    callback()

  getState: (callback) ->
    callback null, @loadState(@path)

  create: (path, newDefs, opts) ->
    throw new Error "#{@namespace} create() #{path} Unimplemented"

  delete: (path, oldDefs, opts) ->
    throw new Error "#{@namespace} delete() #{path} Unimplemented"

  add: (path, index, item, opts) ->
    throw new Error "#{@namespace} add() #{path} Unimplemented"

  update: (path, oldDefs, newDefs, opts) ->
    deletePlan = @delete path, oldDefs, opts
    createPlan = @create path, newDefs, opts
    [deletePlan..., createPlan...]

  setState: (newState, callback) ->
    @getState (err, currentState) =>
      differences = Differ.diff currentState, newState
      @resolveState currentState, newState, differences, (err, results) =>
        @saveState newState, @path
        callback err, results

  saveState: (newState, path) ->
    state = @loadState()
    target = state
    for pathItem, index in path
      if index is path.length - 1
        target[pathItem] = newState
      else
        target = target[pathItem]

    stateFilePath = if @options.simulation then SIMULATION_STATE_FILE_PATH else STATE_FILE_PATH
    fs.writeFileSync stateFilePath, JSON.stringify(state, null, 2)

  loadState: (path=[]) ->
    stateFilePath = if @options.simulation then SIMULATION_STATE_FILE_PATH else STATE_FILE_PATH
    if fs.existsSync stateFilePath
      state = JSON.parse fs.readFileSync stateFilePath
    else
      state = {}

    for pathItem in path
      state = state?[pathItem]

    state

  handleDiff: (diff, opts) ->
    switch diff.kind
      when 'N'
        @create diff.path || [], diff.rhs, opts
      when 'E'
        @update diff.path || [], diff.lhs, diff.rhs, opts
      when 'D'
        @delete diff.path || [], diff.lhs, opts
      when 'A'
        @add diff.path || [], diff.index, diff.item, opts
      else
        throw new Error "Unknown diff type #{diff.kind || diff}"

  resolveState: (currentState, newState, diffs, callback) ->
    plan = @planResolution currentState, newState, diffs
    @executePlan currentState, newState, diffs, plan, (err, results) ->
      console.log "EXECUTE RESULTS", err, results
      callback err, results

  executePlan: (currentState, newState, diffs, plan, callback) ->
    console.log "EXECUTE PLAN", @namespace, plan
    async.eachSeries plan, (item, next) ->
      console.log "EXECUTE ITEM", item
      item.run (err) ->
        next err
    , (err) ->
      callback err

  planResolution: (currentState, newState, diffs) ->
    plan = []
    for diff in diffs
      if @children?[diff.path?[0]]
        childPath = diff.path.shift()
        diffPlan = @children[childPath].handleDiff diff
        plan = [plan..., diffPlan...]
      else
        diffPlan = @handleDiff diff, next
        plan = [plan..., diffPlan...]
    plan

  getSimulationServices: () ->
    services = {}

    if @simulation?.services?.constructor is Function
      serviceDefs = @simulation.services.bind(@)()
    else
      serviceDefs = @simulation?.services

    if serviceDefs?.constructor is Array
      for defs in serviceDefs
        if defs.constructor is String
          existing = services[defs] || {}
          services[defs] = extend existing, {}
        else
          namespace = Object.keys(defs)[0]
          config = defs[namespace]

          for namespace, config of defs
            existing = services[namespace] || {}
            services[namespace] = extend existing, config
    
    else if serviceDefs
      for namespace, config of serviceDefs
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