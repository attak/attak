extend = require 'extend'
TopologyUtils = require '../lib/topology'
ServiceManager = require '../lib/simulation/service_manager'

TestUtils = 
  setupComponentTest: (oldState, newState, component, testOpts={}, callback) ->
    services = component.getSimulationServices()

    manager = new ServiceManager
    manager.setup oldState, testOpts, services, (err, services) ->
      opts =
        role: 'testrole'
        target: extend true, testOpts?.target || {}, newState || {}
        services: services

      callback err, {opts, manager, oldState, newState}, (finish) ->
        manager.stopAll ->
          finish()

  setupTest: (oldState, newState, app, testOpts={}, callback) ->
    startState = TopologyUtils.loadTopology oldState
    endState = TopologyUtils.loadTopology newState

    app = new ATTAK
      topology: topology
      simulation: true
      environment: testOpts.environment || 'development'

    app.clearState()
    app.setup ->
      services = app.getSimulationServices()

      manager = new ServiceManager
      manager.setup topology, {}, services, testOpts, (err, services) ->
        app.setState startState, endState, {services}, (err, results) ->

module.exports = TestUtils