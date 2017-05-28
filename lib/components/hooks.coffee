AWS = require 'aws-sdk'
async = require 'async'
extend = require 'extend'
BaseComponent = require './base_component'

class Hooks extends BaseComponent
  namespace: 'hooks'

  structure:
    ':hookName':
      handler: '*'

  planResolution: (currentState, newState, diffs=[], opts, [plan]..., callback) ->
    plan = plan || []

    if opts.fromNamespace in [null, undefined]
      newPlan = [{
        msg: 'setup state hooks'
        run: (state, done) ->
          if diffs[0]?.rhs
            [hookName, hookArgs...] = diffs[0].path

            if hookArgs.length > 0
              state = extend true, state,
                hooks:
                  "#{hookName}": {}

              assignTo = state.hooks[hookName]
              for arg, index in hookArgs
                if index is hookArgs.length - 1
                  assignTo[arg] = diffs[0].rhs
                else if assignTo[arg] is undefined
                  assignTo[arg] = {}
                  assignTo = assignTo[arg]
                else
                  assignTo = assignTo[arg]
            else
              state = extend true, state,
                hooks:
                  "#{hookName}": diffs[0].rhs

            assignTo = state.hooks[hookName]
            for arg in hookArgs
              assignTo = assignTo[arg]

            assignTo = diffs[0].rhs

          done null, state
      }, plan...]

      callback null, newPlan

    else
      for diff in diffs
        fullpath = [diff.path...]

      callback null, plan || []

module.exports = Hooks