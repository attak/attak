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
    state =
      name: 'streams-test'
      processors:
        first: () -> null
        second: () -> null
      streams:
        'streams-test-first-second':
          from: 'first'
          to: 'second'

    component = new ATTAK
      topology: state

    TestUtils.setupComponentTest {}, state, component, {}, (err, {opts, manager, oldState, newState}, cleanup) =>
      component.setState {}, newState, opts, (err, state) =>
        cleanup () ->
          console.log "FINAL STATE IS", err, state
          suite.equal state?['streams-test-first-second']?.id,
            'arn:aws:kinesis:us-east-1:133713371337:stream/streams-test-first-second',
            'should have recorded the new stream\'s ARN as its ID'

          suite.end()

  suite.end()