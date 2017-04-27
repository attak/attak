async = require 'async'
attak = require '../../'
Differ = require 'deep-diff'
nodePath = require 'path'
Processors = require '../../lib/components/processors'

describe.only 'processors', ->
  describe 'state', ->

    setup = ->
      topology =
        name: 'state-tests'
        processors:
          hello: (event, context, callback) ->
            callback null, {ok: true}

    it 'should have a blank initial state', (done) ->
      
      done()
