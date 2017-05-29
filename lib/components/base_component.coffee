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
    for diff in differences
      diff.namespace = @namespace

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
    # console.log "SAVING STATE TO", @namespace, path, resolved, path, state
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
    fullPath = [(diff.path || [])...]

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

  executeItem: (item, currentState, newState, diffs, plan, opts, callback) ->
    async.waterfall [
      (done) =>
        if item.before
          async.eachSeries item.before || [], (beforeFn, nextBefore) =>
            beforeFn currentState, (err, changedState={}) =>
              currentState = extend true, currentState, changedState
              nextBefore err
          , (err) ->
            done err
        else
          done()
      (done) =>
        item.run currentState, (err, changedState={}) =>
          currentState = extend true, currentState, changedState
          @saveState changedState
          done err
      (done) =>
        if item.after
          async.eachSeries item.after || [], (afterFn, nextAfter) =>
            afterFn currentState, (err, changedState={}) =>
              currentState = extend true, currentState, changedState
              nextAfter err
          , (err) ->
            done err
        else
          done()
    ], (err) =>
      callback err

  executePlan: (currentState, newState, diffs, plan, opts, callback) ->
    async.eachSeries plan, (item, nextItem) =>
      promise = new Promise (resolve, reject) =>
        @executeItem item, currentState, newState, diffs, plan, opts, (err) =>
          if err then return reject err
          resolve()

      promise.then (results) -> nextItem()
      promise.catch nextItem
    , (err) =>
      if err
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
    plan = []
    asyncItems = {}
    async.eachOfSeries @children, (child, childName, nextChild) =>
      config = childDiffs[childName]
      
      getPlan = (results..., done) =>
        child.planResolution currentState, newState[childName], config.diffs, opts, plan, (err, newPlan) ->
          plan = newPlan
          done err, plan

      if config is undefined
        asyncItems[child.namespace] = (results..., done) -> done()
      else if child.dependencies
        asyncItems[child.namespace] = [child.dependencies..., getPlan]
      else
        asyncItems[child.namespace] = getPlan
      
      nextChild()
    , (err) =>
      async.auto asyncItems, 1, (err) ->
        callback err, plan
  
  planComponentResolutions: (currentState, newState, diffs, opts, callback) ->
    plan = []
    async.eachSeries diffs, (diff, nextDiff) =>
      diffPlan = @handleDiff diff, opts
      for item in diffPlan
        item.diffs = [diff]
        item.source = @
        item.group = item.group || opts.group
      
      fromNamespace = opts.fromNamespace || @namespace
      fullPath = diff.path || []
      @manager.notifyChange fromNamespace, fullPath, diffPlan, currentState, newState, [diff], opts, (err, newPlan) =>
        plan = newPlan
        nextDiff err
    , (err) =>
      callback err, plan

  planResolution: (currentState, newState, diffs=[], opts, [startPlan]..., callback) ->
    promise = new Promise (resolve, reject) =>

      plan = startPlan || []
      opts.fullState = @loadState()
      
      if @handleDiffs
        diffPlan = @handleDiffs currentState, newState, diffs, opts
        for planItem in diffPlan
          planItem.source = @
          planItem.diffs = diffs

        plan = [plan..., diffPlan...]

        async.each diffs, (diff, next) =>
          fromNamespace = opts.fromNamespace || @namespace
          fullPath = diff.path || []
          @manager.notifyChange fromNamespace, fullPath, plan, currentState, newState, diffs, opts, (err, newPlan) =>
            plan = newPlan
            next err
        , (err) =>
          if err then return reject err

          resolve plan
      else
        if diffs.length is 0
          return resolve plan

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
            if Object.keys(childDiffs).length > 0
              @planChildResolutions currentState, newState, childDiffs, opts, done
            else
              done null, []
          (childPlans, done) =>
            if diffsForThis.length > 0
              @planComponentResolutions currentState, newState, diffsForThis, opts, (err, componentPlans) ->
                done err, childPlans, componentPlans
            else
              done null, childPlans, []
        ], (err, childPlans, componentPlans) =>
          if err then return reject err

          plan = [plan..., childPlans..., componentPlans...]
          resolve plan

    promise.catch (err) ->
      callback err

    promise.then (results) ->
      callback null, results

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