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

module.exports = BaseComponent