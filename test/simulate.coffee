attak = require '../'
nodePath = require 'path'
AWSUtils = require '../lib/aws'
kinesalite = require 'kinesalite'
TopologyUtils = require '../lib/topology'

kinesisPort = 6668
kinesisEndpoint = "http://localhost:#{kinesisPort}"

describe 'simulate', ->

  before (done) ->
    kinesaliteServer = kinesalite
      path: nodePath.resolve __dirname, '../testdb'
      createStreamMs: 0

    kinesaliteServer.listen kinesisPort, (err) ->
      done()

  simulateTopology = (topology, input, callback) ->
    topology.name = "simulationTests"

    opts =
      cwd: './test'
      report: ->
      input: input
      topology: topology
      kinesisEndpoint: kinesisEndpoint

    topology = TopologyUtils.loadTopology opts

    AWSUtils.deploySimulationStreams opts, topology, (streamNames) ->
      attak.utils.simulation.runSimulations opts, topology, input, {}, (err, results) ->
        callback err, results

  it 'should simulate a simple topology (smoke test)', (done) ->
    topology =
      processors:
        testProc: (event, context, callback) -> context.emit 'test output', {test: 'output'}, callback
        otherProc: (event, context, callback) -> context.emit 'modified', {other: event.test}, callback
        finalProc: (event, context, callback) -> context.emit 'final', null, callback
      streams: [
        ['testProc', 'otherProc']
        ['otherProc', 'finalProc']
      ]

    input =
      testProc: 'test input text'

    simulateTopology topology, input, (err, results) ->
      if results.otherProc?['modified']?.other is 'output'
        done()
      else
        done 'incorrect output'

  it 'should send data between connected processors', (done) ->
    topology =
      processors:
        testProc: (event, context, callback) -> context.emit 'test output', {test: 'output'}, callback
        otherProc: (event, context, callback) -> context.emit 'modified', {other: event.test}, callback
      streams: [
        ['testProc', 'otherProc']
      ]

    input =
      testProc: 'test input text'

    simulateTopology topology, input, (err, results) ->
      if results.testProc?['test output']?.test is 'output'
        done()
      else
        done 'incorrect output'

  it 'should not send data to processors that stream from a different topic', (done) ->
    topology =
      processors:
        testProc: (event, context, callback) -> context.emit 'test output', {test: 'output'}, callback
        otherProc: (event, context, callback) -> context.emit 'modified', {other: event.test}, callback
        finalProc: (event, context, callback) -> context.emit 'final', null, callback
      streams: [
        ['testProc', 'otherProc', 'non existent topic']
        ['otherProc', 'finalProc']
      ]

    input =
      testProc: 'test input text'

    simulateTopology topology, input, (err, results) ->
      if results.otherProc
        done 'emitting data to processors on the wrong topic'
      else
        done()