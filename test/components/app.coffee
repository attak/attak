uuid = require 'uuid'
tape = require 'tape'
tapes = require 'tapes'
async = require 'async'
attak = require '../../'
dotenv = require 'dotenv'
Differ = require 'deep-diff'
nodePath = require 'path'
ATTAK = require '../../lib/attak'
Processors = require '../../lib/components/processors'
TopologyUtils = require '../../lib/topology'
ServiceManager = require '../../lib/simulation/service_manager'

test = tapes tape
dotenv.load()

setupTest = (oldState, newState, component, callback) ->
  services = component.getSimulationServices()

  manager = new ServiceManager
  manager.setup oldState, {}, services, (err, services) ->
    opts =
      role: 'testrole'
      services: services
      dependencies: {}

    deps = component.constructor::dependencies
    if deps?.constructor is Array
      objDeps = {}
      for dep in deps
        objDeps[dep] = {}
      deps = objDeps

    for key, val of deps
      opts.dependencies[key] = newState[key]

    callback err, {opts, manager}

test 'app', (suite) ->
  topology = TopologyUtils.loadTopology
    topology:
      name: 'state-tests'
      processors:
        testProc: (event, context, callback) ->
          callback null, {ok: true}
      streams:
        ['testProc', 'testProc']

  suite.test 'state', (suite) ->

    suite.test 'should be able to clear and have a blank state', (suite) ->
      @component = new ATTAK
        topology: topology
        simulation: true
        environment: 'development'

      @component.clearState()
      @component.setup ->
        @component.getState (err, state) ->
          console.log "STATE IS", err, state
          suite.equal Object.keys(state).length, 0
          suite.end()

    suite.test 'should update dependencies appropriately', (suite) ->      
      startState =TopologyUtils.loadTopology
        topology:
          name: 'testTopo'
          processors:
            first: {id: '1234'}
            second: {id: 'abc'}
          streams: [
            ['first', 'second']
          ]

      endState = TopologyUtils.loadTopology
        topology:
          name: 'testTopo'
          processors:
            first: {id: '4321'}
            second: {id: 'abc'}
          streams: [
            ['first', 'second']
          ]

      setupTest startState, endState, @component, (err, {opts, manager}) =>
        @component = new ATTAK
          topology: topology
          simulation: true
          environment: 'development'

        @component.clearState()
        @component.setup =>
          @component.setState startState, endState, opts, (err, state) =>
            console.log "DONE SETTING STATE", err, state
            @component.getState (err, state) ->
              manager.stopAll ->
                console.log "STATE IS", err, state
                suite.notEqual Object.keys(state).length, 0
                suite.end()

    suite.end()
  suite.end()