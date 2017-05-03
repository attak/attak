uuid = require 'uuid'
tape = require 'tape'
tapes = require 'tapes'
async = require 'async'
attak = require '../../'
dotenv = require 'dotenv'
Differ = require 'deep-diff'
nodePath = require 'path'
Processors = require '../../lib/components/processors'
ServiceManager = require '../../lib/simulation/service_manager'

test = tapes tape
dotenv.load()

setupTest = (oldState, newState, component, callback) ->
  console.log "ASFASDFASDFASDF"
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

test 'processors', (suite) ->
  topology =
    name: 'state-tests'
    processors:
      hello: (event, context, callback) ->
        callback null, {ok: true}

  suite.beforeEach (suite) ->
    @component = new Processors
      topology: topology
    suite.end()

  suite.test 'state', (suite) ->

    suite.test 'should be able to clear and have a blank state', (suite) ->
      @component.clearState()
      @component.getState (err, state) ->
        console.log "STATE IS", err, state
        suite.equal Object.keys(state).length, 0
        suite.end()

    suite.test 'should create a processor', (suite) ->      
      state =
        hello: uuid.v1()

      setupTest {}, state, @component, (err, {opts, manager}) =>
        @component.setState {}, state, opts, (err, state) =>
          @component.getState (err, state) ->
            manager.stopAll ->
              console.log "STATE IS", err, state
              suite.notEqual Object.keys(state).length, 0
              suite.end()

    suite.end()
  suite.end()