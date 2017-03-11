attak = require '../'

describe 'simulate', ->

  simulateTopology = (topology, input, callback) ->
    topology.name = "simulationTests"
    for stream, index in topology.streams
      if stream.constructor is Array
        topology.streams[index] =
          from: stream[0]
          to: stream[1]

    opts =
      cwd: './test'
      report: ->
      input: input
      topology: topology

    attak.simulate opts, (err, results) ->
      callback err, results

  it 'should simulate a simple topology', (done) ->
    topology =
      processors:
        testProc: (event, context, callback) ->
          context.emit 'test output', {test: 'output'}
          callback()
        otherProc: (event, context, callback) ->
          context.emit 'modified', {other: event.test}
          callback()
        finalProc: (event, context, callback) ->
          context.emit 'final'
          callback()
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
