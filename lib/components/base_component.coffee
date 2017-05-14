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

    @manager = require '../component_manager'

  setup: (callback) ->
    @manager.add @
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

  clean: (obj) ->
    for key, val of obj
      if val is undefined
        delete obj[key]
      else if typeof val is 'object'
        @clean val

  setState: (currentState, newState, opts, callback) ->
    @clean currentState
    @clean newState

    differences = Differ.diff currentState, newState
    @resolveState currentState, newState, differences, opts, (err, finalState) =>
      callback err

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
    cwd = @options.cwd || process.cwd()
    resolved = nodePath.resolve cwd, stateFilePath
    fs.writeFileSync stateFilePath, JSON.stringify(state, null, 2)

    for key, child of (@children || {})
      child.clearState()

    @manager.remove @guid

  saveState: (newState, path=[]) ->
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

    stateFilePath = if @options?.simulation then SIMULATION_STATE_FILE_PATH else STATE_FILE_PATH
    
    cwd = @options?.cwd || process.cwd()
    resolved = nodePath.resolve cwd, stateFilePath
    console.log "SAVING STATE TO", @namespace, path, resolved, path, state
    fs.writeFileSync resolved, JSON.stringify(state, null, 2)

  loadState: (path=[]) ->
    stateFilePath = if @options?.simulation then SIMULATION_STATE_FILE_PATH else STATE_FILE_PATH
    cwd = @options?.cwd || process.cwd()
    resolved = nodePath.resolve cwd, stateFilePath
    if fs.existsSync resolved
      contents = fs.readFileSync(resolved, 'utf8')
      if contents in ['undefined', undefined, null]
        contents = '{}'
      state = JSON.parse contents
    else
      state = {}

    for pathItem in path
      state = state?[pathItem]

    # console.log "LOAD STATE FROM", @namespace, resolved, state
    state

  handleDiff: (diff, opts) ->
    fromNamespace = opts.fromNamespace || @namespace
    fullPath = [fromNamespace, (diff.path || [])...]

    switch diff.kind
      when 'N'
        @create fullPath, diff.rhs, opts
      when 'E'
        @update fullPath, diff.lhs, diff.rhs, opts
      when 'D'
        @delete fullPath, diff.lhs, opts
      when 'A'
        @add fullPath, diff.index, diff.item, opts
      else
        throw new Error "Unknown diff type #{diff.kind || diff}"

  resolveState: (currentState, newState, diffs, opts, callback) ->
    opts.group = uuid.v1()

    @planResolution currentState, newState, diffs, opts, (err, plan) =>
      if err then console.log "GOT PLAN ERR", err
      @executePlan currentState, newState, diffs, plan, opts, (err, finalState, path) =>
        callback err, finalState

  executePlan: (currentState, newState, diffs, plan, opts, callback) ->    
    console.log "EXECUTE PLAN", @constructor.name
    async.eachSeries plan, (item, nextItem) =>
      try
        console.log "RUNNING ITEM", item.source?.constructor.name, item.msg
        item.run currentState, (err, changedState={}) =>
          console.log "EXECUTE RESULTS", err, item.source?.constructor.name, changedState
          changedState = extend true, currentState, changedState
          @saveState changedState
          nextItem err
      catch err
        console.log "CAUGHT EXCEPTION", err
        nextItem err
    , (err) =>
      if err
        console.log "CAUGHT ERR DURING ITEM", err
        return callback err

      callback err

  executePlanInGroups: (currentState, newState, diffs, plan, opts, callback) ->    
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

    async.forEachOfSeries groups, (group, groupId, nextGroup) =>
      async.eachSeries group.plan, (item, nextItem) =>
        item.run (err, changedState={}, changePath=[]) ->
          finalState = extend finalState, changedState
          nextItem err
      , (err) =>
        if err then return nextGroup err

        if group.deferred?.length > 0
          group.deferred[0].source.executeDeferred group.deferred, (err) ->
            nextGroup err
        else
          nextGroup err
    , (err) ->
      callback err, finalState

  planChildResolutions: (currentState, newState, childDiffs, opts, callback) ->
    console.log "PLAN CHILD RESOLUTION"
    plan = []
    asyncItems = {}
    async.eachOfSeries childDiffs, (config, childName, nextChild) =>
      child = config.child
      
      getPlan = (results..., done) ->
        child.planResolution currentState, newState[childName], config.diffs, opts, (err, childPlan) ->
          plan = plan.concat childPlan
          done null, plan

      if child.dependencies
        asyncItems[config.child.namespace] = [child.dependencies..., getPlan]
      else
        asyncItems[config.child.namespace] = getPlan
      
      nextChild()
    , (err) =>
      async.auto asyncItems, (err) ->
        console.log "DONE CHILD RESOLUTION", @constructor.name, err
        callback err, plan
  
  planComponentResolutions: (currentState, newState, diffs, opts, callback) ->
    console.log "PLAN COMPONENT RESOLUTION", @constructor.name, diffs
    plan = []
    async.eachSeries diffs, (diff, nextDiff) =>
      diffPlan = @handleDiff diff, opts
      for item in diffPlan
        item.source = @
        item.group = item.group || opts.group
      
      fromNamespace = opts.fromNamespace || @namespace
      fullPath = diff.path || []
      @manager.notifyChange @namespace, fullPath, diffPlan, currentState, newState, [diff], opts, (err, diffPlan) ->
        plan = [plan..., diffPlan...]
        nextDiff()
    , (err) =>
      console.log "DONE COMPONENT RESOLUTION", @constructor.name, err
      callback err, plan

  planResolution: (currentState, newState, diffs=[], opts, callback) ->
    console.log "PLAN RESOLUTION", @namespace, handleDiffs?
    plan = []
    opts.fullState = @loadState()
    
    if @handleDiffs
      plan = @handleDiffs currentState, newState, diffs, opts
      for planItem in plan
        planItem.source = @

      async.each diffs, (diff, next) =>
        fromNamespace = opts.fromNamespace || @namespace
        fullPath = [(diff.path || [])...]
        @manager.notifyChange @namespace, fullPath, plan, currentState, newState, diffs, opts, (err, newPlan) ->
          plan = newPlan
          next()
      , (err) =>
        callback err, plan
    else
      if diffs.length is 0
        return callback null, plan

      childDiffs = {}
      diffsForThis = []
      for diff in diffs
        childPath = diff.path?[0]
        if childPath and @children?[childPath]
          if childDiffs[childPath] is undefined
            childDiffs[childPath] =
              child: @children[childPath]
              diffs: [diff]
          else
            childDiffs[childPath].diffs.push diff
        else
          diffsForThis.push diff

      async.waterfall [
        (done) =>
          @planChildResolutions currentState, newState, childDiffs, opts, done
        (childPlans, done) =>
          @planComponentResolutions currentState, newState, diffsForThis, opts, (err, componentPlans) ->
            done err, childPlans, componentPlans
      ], (err, childPlans, componentPlans) =>
        plan = [plan..., childPlans..., componentPlans...]
        console.log "FINAL PLAN", plan
        callback err, plan

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
      services = extend true, services, child.getSimulationServices()

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