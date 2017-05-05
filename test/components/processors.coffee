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

    callback err, {opts, manager}, (finish) ->
      manager.stopAll ->
        finish()

test 'processors', (suite) ->
  topology =
    name: 'state-tests'
    processors:
      hello: (event, context, callback) ->
        callback null, {ok: true}

  suite.beforeEach (suite) ->
    @component = new Processors
    suite.end()


  suite.test 'processor creation', (suite) ->      
    state =
      hello: () -> null

    setupTest {}, state, @component, (err, {opts, manager}, cleanup) =>
      @component.setState {}, state, opts, (err, state) =>
        @component.getState (err, state) ->
          cleanup () ->
            suite.equal state?.processors?.hello?.id,
              'arn:aws:lambda:us-east-1:133713371337:function:undefined',
              'should have recorded the new processor\'s ARN as its ID'

            suite.end()

  suite.end()