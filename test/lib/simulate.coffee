attak = require '../../'
nodePath = require 'path'
AWSUtils = require '../../lib/aws'
kinesalite = require 'kinesalite'
TopologyUtils = require '../../lib/topology'

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
      input: input
      report: -> null
      topology: topology
      endpoints:
        kinesis: kinesisEndpoint

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
      if results.otherProc?.emits?['modified']?[0]?.other is 'output'
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
      if results.testProc?.emits?['test output']?[0]?.test is 'output'
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

  it 'should send back callback data', (done) ->
    topology =
      processors:
        testProc: (event, context, callback) -> callback null, {ok: true}
      streams: []

    input =
      testProc: 'test input text'

    simulateTopology topology, input, (err, results) ->
      resp = results.testProc?.callback?.results?.body
      if JSON.parse(resp).ok
        done()
      else
        done 'didn\'t get callback data'

  it 'local processor invocation should work', (done) ->
    topology =
      processors:
        testProc: (event, context, callback) ->
          context.invokeLocal 'otherProc', {ok: true}, (err, results) ->
            callback null, results
        otherProc: (event, context, callback) ->
          callback null, event

      streams: []

    input =
      testProc: 'test input text'

    simulateTopology topology, input, (err, results) ->
      resp = results.testProc?.callback?.results?.body
      if JSON.parse(resp).ok
        done()
      else
        done 'didn\'t get callback data'