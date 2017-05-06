uuid = require 'uuid'
tape = require 'tape'
tapes = require 'tapes'
async = require 'async'
attak = require '../../'
ATTAK = require '../../lib/attak'
dotenv = require 'dotenv'
extend = require 'extend'
Differ = require 'deep-diff'
Streams = require '../../lib/components/streams'
nodePath = require 'path'
TestUtils = require '../utils'
TopologyUtils = require '../../lib/topology'
ServiceManager = require '../../lib/simulation/service_manager'

test = tapes tape
dotenv.load()

test 'streams', (suite) ->

  suite.test 'processor creation', (suite) ->
    opts =
      target: TopologyUtils.loadTopology
        topology:
          name: 'api-test'
          api: 'endpoint'
          processors:
            endpoint: (event, context, callback) -> callback null, {ok: true}

    component = new ATTAK
      topology: opts.target

    TestUtils.setupComponentTest {}, opts.target, component, opts, (err, {opts, manager, oldState, newState}, cleanup) =>
      component.setState {}, newState, opts, (err, state) =>
        state = component.loadState()
        cleanup () ->
          suite.notEqual state.api.gateway?.id, undefined, 'should have created a gateway'
          suite.notEqual state.api.resources?.root?.id, undefined, 'should have created a root resource'
          suite.notEqual state.api.resources?.proxy?.id, undefined, 'should have created a proxy resource'
          suite.end()

  suite.end()