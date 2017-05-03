fs = require 'fs'
uuid = require 'uuid'
async = require 'async'
extend = require 'extend'
Differ = require 'deep-diff'
nodePath = require 'path'

STATE_FILE_PATH = './state.json'
SIMULATION_STATE_FILE_PATH = './simulation_state.json'

class BaseComponent
  lifecycle:
    events: ['init', 'resolve', 'diff']
    stages: ['before', 'after']

  constructor: (@options={}) ->
    @guid = uuid.v1()
    @path = @options.path || []
    @state = {}
    @children = @options.children || {}
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

  addChild: (namespace, child) ->
    child.parent = @
    if @children is undefined
      @children = {}
    @children[namespace] = child

  setState: (currentState, newState, opts, callback) ->
    differences = Differ.diff currentState, newState
    @resolveState currentState, newState, differences, opts, (err, results) =>
      @saveState newState, @path
      callback err, results

  clearState: (path=[]) ->
    state = @loadState()
    target = state
    if path.length > 0
      for pathItem, index in path
        if index is path.length - 1
          target[pathItem] = {}
        else
          target = target[pathItem]
    else
      state = {}

    stateFilePath = if @options.simulation then SIMULATION_STATE_FILE_PATH else STATE_FILE_PATH
    fs.writeFileSync stateFilePath, JSON.stringify(state, null, 2)

  saveState: (newState, path) ->
    state = @loadState()
    target = state
    if path.length > 0
      for pathItem, index in path
        if index is path.length - 1
          target[pathItem] = newState
        else
          target = target[pathItem]
    else
      state = newState

    stateFilePath = if @options.simulation then SIMULATION_STATE_FILE_PATH else STATE_FILE_PATH
    
    cwd = @options.cwd || process.cwd()

    resolved = nodePath.resolve cwd, stateFilePath
    console.log "SAVING STATE TO", resolved, state, @namespace
    fs.writeFileSync resolved, JSON.stringify(state, null, 2)

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

  resolveState: (currentState, newState, diffs, opts, callback) ->
    opts.group = uuid.v1()

    plan = @planResolution currentState, newState, diffs, opts
    @executePlan currentState, newState, diffs, plan, (err, results) ->
      callback err, results

  executePlan: (currentState, newState, diffs, plan, callback) ->    
    groups = {}

    for item in plan
      group = item.group || uuid.v1()
      if groups[group] is undefined
        groups[group] =
          plan: []
          deferred: []
      
      if item.defer or item.deferred
        groups[group].deferred.push item
      else
        groups[group].plan.push item

    async.forEachOf groups, (group, groupId, nextGroup) =>

      async.eachSeries group.plan, (item, nextItem) =>        
        item.run (err) ->
          nextItem err
      , (err) =>
        if err then return nextGroup err

        if group.deferred?.length > 0
          group.deferred[0].source.executeDeferred group.deferred, (err) ->
            nextGroup err
        else
          nextGroup err
    , (err) ->
      callback err

  planResolution: (currentState, newState, diffs=[], opts) ->
    plan = []
    for diff in diffs
      if @children?[diff.path?[0]]
        childPath = diff.path.shift()
        diffPlan = @children[childPath].handleDiff diff, opts
        for item in diffPlan
          item.source = @children[childPath]
      else
        diffPlan = @handleDiff diff, opts
        for item in diffPlan
          item.source = @
        
      for item in diffPlan
        item.group = item.group || opts.group
      
      plan = [plan..., diffPlan...]
    
    return plan

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

  getDependencies: () ->
    deps = @dependencies || {}
    if deps.constructor is Array
      depsObj = {}
      for item in deps
        if item.constructor is String
          depsObj[item] = {}
        else
          for key, val of item
            depsObj[key] = val
      deps = depsObj

    if @parent
      deps[@parent.namespace] = {}
      parentDeps = @parent.getDependencies() || {}
      deps = extend deps, parentDeps

    deps

module.exports = BaseComponent