fs = require 'fs'
lave = require 'lave'
babel = require 'babel-core'
ATTAK = require '../lib/attak'
dotenv = require 'dotenv'
extend = require 'extend'
{generate} = require 'escodegen'
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
    
    js = lave topology, {generate, format: 'module'}
    indexPath = "#{__dirname}/index.js"
    
    if testOpts.simulation is false
      transformed = babel.transform js,
        presets: ['es2015']
      fs.writeFileSync indexPath, transformed.code

    testOpts.cwd = __dirname
    testOpts.topology = topology
    testOpts.simulation = if testOpts.simulation is undefined then true else testOpts.simulation
    testOpts.role = testOpts.role || process.env.AWS_ROLE_ARN || process.env.AWS_ROLE

    app = new ATTAK
      topology: topology
      simulation: testOpts.simulation
      environment: testOpts.environment || 'development'

    TestUtils.setupComponentTest state, endState, app, testOpts, (err, resp, cleanup) ->
      app.setState state, endState, testOpts, (err, state) ->
        resp.state = app.loadState()
        resp.cleanup = (finish) ->
          fs.unlink indexPath
          cleanup finish
        callback err, resp

module.exports = TestUtils