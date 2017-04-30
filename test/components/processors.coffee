uuid = require 'uuid'
async = require 'async'
attak = require '../../'
Differ = require 'deep-diff'
nodePath = require 'path'
Processors = require '../../lib/components/processors'

describe 'processors', ->
  describe 'state', ->

    topology =
      name: 'state-tests'
      processors:
        hello: (event, context, callback) ->
          callback null, {ok: true}

    before (done) ->
      @component = new Processors
        topology: topology
      
      done()

    it 'should have a blank initial state', (done) ->
      @component.getState (err, state) ->
        if Object.keys(state).length is 0
          done()
        else
          done "non-blank state"

    it 'should create a processor', (done) ->
      state =
        hello: uuid.v1()

      @component.setState state, (err, state) =>
        @component.getState (err, state) ->
          console.log "STATE iS", err, state

          if Object.keys(state).length is 0
            done "failed to create processor"
          else
            done()
