ATTAK = require '../lib/attak'
dotenv = require 'dotenv'
extend = require 'extend'
TopologyUtils = require '../lib/topology'
ServiceManager = require '../lib/simulation/service_manager'

dotenv.load()

TestUtils = 
  setupComponentTest: (oldState, newState, component, testOpts={}, callback) ->
    services = component.getSimulationServices()

    manager = new ServiceManager
      app: component
    manager.setup oldState, testOpts, services, (err, services) ->
      opts =
        role: 'testrole'
        target: extend true, testOpts?.target || {}, newState || {}
        services: services

      callback err, {opts, manager, oldState, newState}, (finish) ->
        manager.stopAll ->
          finish()

  setupTest: (state, topology, testOpts={}, callback) ->
    endState = TopologyUtils.loadTopology {topology}

    app = new ATTAK
      topology: topology
      simulation: true
      environment: testOpts.environment || 'development'

    TestUtils.setupComponentTest state, endState, app, testOpts, (err, resp, cleanup) ->
      app.setState state, endState, testOpts, (err, state) ->
        resp.state = app.loadState()
        resp.cleanup = cleanup
        callback err, resp

module.exports = TestUtils