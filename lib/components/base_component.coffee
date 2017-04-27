Differ = require 'deep-diff'

class BaseComponent

  constructor: (@options) ->

  # Required interface for subclasses
  getState: (callback) -> callback new Error "Unimplemented"
  resolveState: (diff, currentState, newState, callback) -> callback new Error "Unimplemented"

  # Universal mechanics
  setState: (newState, callback) ->
    @getState (err, currentState) =>
      differences = Differ.diff currentState, newState
      @resolveState currentState, newState, differences, (err, results) ->
        callback err, results

module.exports = BaseComponent