uuid = require 'uuid'
tape = require 'tape'
tapes = require 'tapes'
async = require 'async'
attak = require '../../'
ATTAK = require '../../lib/attak'
dotenv = require 'dotenv'
Differ = require 'deep-diff'
nodePath = require 'path'
TestUtils = require '../utils'
Processors = require '../../lib/components/processors'
TopologyUtils = require '../../lib/topology'
ServiceManager = require '../../lib/simulation/service_manager'

test = tapes tape
dotenv.load()

test 'app', (suite) ->
  topology = TopologyUtils.loadTopology
    topology:
      name: 'state-tests'
      processors:
        testProc: (event, context, callback) ->
          callback null, {ok: true}
      streams:
        ['testProc', 'testProc']

  suite.test 'state', (suite) ->

    suite.test 'should be able to clear and have a blank state', (suite) ->
      @component = new ATTAK
        topology: topology
        simulation: true
        environment: 'development'

      @component.clearState()
      @component.setup ->
        @component.getState (err, state) ->
          suite.equal Object.keys(state).length, 0
          suite.end()

    suite.test 'should update dependencies appropriately', (suite) ->      
      startState = TopologyUtils.loadTopology
        topology:
          name: 'testTopo'
          processors:
            first: {id: '1234'}
            second: {id: 'abc'}
          streams: [
            ['first', 'second']
          ]

      endState = TopologyUtils.loadTopology
        topology:
          name: 'testTopo'
          processors:
            first: {id: '4321'}
            second: {id: 'abc'}
          streams: [
            ['first', 'second']
          ]

      TestUtils.setupTest startState, endState, @component, (err, {opts, manager}) =>
        @component = new ATTAK
          topology: topology
          simulation: true
          environment: 'development'

        @component.clearState()
        @component.setup =>
          @component.setState startState, endState, opts, (err, state) =>
            @component.getState (err, state) ->
              manager.stopAll ->
                suite.notEqual Object.keys(state).length, 0
                suite.end()

    suite.end()
  suite.end()