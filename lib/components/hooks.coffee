AWS = require 'aws-sdk'
async = require 'async'
extend = require 'extend'
nodePath = require 'path'
BaseComponent = require './base_component'

class Hooks extends BaseComponent
  namespace: 'hooks'

  structure:
    ':hookName':
      handler: '*'

  diffEvents:
    A: 'add'
    N: 'create'
    E: 'update'
    D: 'delete'

  handleHook: (hook, item, state, opts, callback) ->
    workingDir = opts.cwd || process.cwd()
    fullPath = nodePath.resolve workingDir, hook.src
    impl = require fullPath

    impl hook, item, state, opts, (err) ->
      callback err

  findFirstAndLast: (plan, path) ->
    matches = []
    for item in plan
      doesMatch = false
      
      for diff in item.diffs
        doesDiffMatch = true
        for pathItem, index in path
          if diff.path[index] and diff.path[index] isnt path[index] and path[index] isnt '*'
            doesDiffMatch = false

        if doesDiffMatch
          doesMatch = true

      if doesMatch
        matches.push item

    if matches.length is 0
      return []
    else
      return [matches[0], matches[matches.length - 1]]

  addHooksToPlan: (plan, state, opts) ->
    for item in plan
      item.before = []
      item.after = []

    for hookName, hook of (state.hooks || {})
      [first, last] = @findFirstAndLast plan, hook.path

      stages = hook.stages || [hook.stage]

      if 'before' in stages
        first?.before.push (state, done) => @handleHook hook, first, state, opts, done
      if 'after' in stages
        last?.after.push (state, done) => @handleHook hook, last, state, opts, done

  planResolution: (currentState, newState, diffs=[], opts, [plan]..., callback) ->
    plan = plan || []

    if opts.fromNamespace in [null, undefined]
      currentState = extend true, currentState,
        hooks: newState

      callback null, plan
    else
      @addHooksToPlan plan, currentState, opts
      callback null, plan || []

module.exports = Hooks