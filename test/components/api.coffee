uuid = require 'uuid'
tape = require 'tape'
tapes = require 'tapes'
async = require 'async'
attak = require '../../'
Differ = require 'deep-diff'
nodePath = require 'path'
API = require '../../lib/components/api'

test = tapes tape

test 'api', (suite) ->
  suite.test 'state', (suite) ->

    topology =
      name: 'state-tests'
      api: 'endpoint'
      processors:
        endpoint: (event, context, callback) ->
          callback null, {ok: true}

    suite.beforeEach (suite) ->
      @component = new API
        topology: topology
      
      suite.end()

    suite.test 'should have a blank initial state', (suite) ->
      @component.getState (err, state) ->
        suite.equal err, null, err?.stack
        suite.notEqual state, undefined, 'no state returned'
        suite.equal Object.keys(state || {}).length, 0, 'non-blank state'
        suite.end()

    suite.test 'should create a gateway and associate it with a processor', (suite) ->
      state = 'endpoint'

      @component.setState state, (err, state) =>
        @component.getState (err, state) ->
          suite.equal err, null, err?.stack
          suite.notEqual state, undefined, 'no state returned'
          suite.notEqual Object.keys(state || {}).length, 0, 'failed to create processor' 

          suite.end()
    suite.end()
  suite.end()