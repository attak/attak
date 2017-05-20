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

      resp = {opts, manager, oldState, newState}
      cleanup = (finish) ->
        manager.stopAll ->
          finish()

      callback err, resp, cleanup

  setupTest: (state, topology, testOpts={}, callback) ->
    endState = TopologyUtils.loadTopology {topology}
    testOpts.topology = topology
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