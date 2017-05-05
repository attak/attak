extend = require 'extend'
TopologyUtils = require '../lib/topology'
ServiceManager = require '../lib/simulation/service_manager'

TestUtils = 
  setupTest: (oldState, newState, component, testOpts={}, callback) ->
    services = component.getSimulationServices()

    manager = new ServiceManager
    manager.setup oldState, testOpts, services, (err, services) ->
      opts =
        role: 'testrole'
        target: extend true, testOpts?.target || {}, newState
        services: services

      callback err, {opts, manager, oldState, newState}, (finish) ->
        manager.stopAll ->
          finish()

module.exports = TestUtils