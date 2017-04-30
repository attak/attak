uuid = require 'uuid'
tape = require 'tape'
tapes = require 'tapes'
async = require 'async'
attak = require '../../'
Differ = require 'deep-diff'
nodePath = require 'path'
Processors = require '../../lib/components/processors'

test = tapes tape

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

    suite.test 'should have a blank initial state', (suite) ->
      @component.getState (err, state) ->
        suite.equal Object.keys(state).length, 0
        suite.end()

    suite.test 'should create a processor', (suite) ->      
      state =
        hello: uuid.v1()

      @component.setState state, (err, state) =>
        @component.getState (err, state) ->
          console.log "STATE IS", err, state
          suite.notEqual Object.keys(state).length, 0
          suite.end()

    suite.end()
  suite.end()