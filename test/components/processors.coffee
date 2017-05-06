uuid = require 'uuid'
tape = require 'tape'
tapes = require 'tapes'
async = require 'async'
attak = require '../../'
dotenv = require 'dotenv'
Differ = require 'deep-diff'
nodePath = require 'path'
TestUtils = require '../utils'
Processors = require '../../lib/components/processors'
ServiceManager = require '../../lib/simulation/service_manager'

test = tapes tape
dotenv.load()

test 'processors', (suite) ->

  suite.test 'processor creation', (suite) ->      
    state =
      hello: () -> null

    component = new Processors

    TestUtils.setupComponentTest {}, state, component, {}, (err, {opts, manager}, cleanup) =>
      component.setState {}, state, opts, (err, state) =>
        component.getState (err, state) ->
          cleanup () ->
            suite.equal state?.processors?.hello?.id,
              'arn:aws:lambda:us-east-1:133713371337:function:undefined',
              'should have recorded the new processor\'s ARN as its ID'

            suite.end()

  suite.end()