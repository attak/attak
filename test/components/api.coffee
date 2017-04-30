uuid = require 'uuid'
async = require 'async'
attak = require '../../'
Differ = require 'deep-diff'
nodePath = require 'path'
API = require '../../lib/components/api'

describe 'api', ->
  describe 'state', ->

    topology =
      name: 'state-tests'
      api: 'endpoint'
      processors:
        endpoint: (event, context, callback) ->
          callback null, {ok: true}

    before (done) ->
      @component = new API
        topology: topology
      
      done()

    it 'should have a blank initial state', (done) ->
      @component.getState (err, state) ->
        if Object.keys(state).length is 0
          done()
        else
          done "non-blank state"

    it.only 'should create a gateway and associate it with a processor', (done) ->
      state = 'endpoint'

      @component.setState state, (err, state) =>
        @component.getState (err, state) ->
          console.log "API STATE IS", err, state

          if Object.keys(state).length is 0
            done "failed to create processor"
          else
            done()
