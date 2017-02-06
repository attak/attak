attak = require '../'

describe 'attak', ->
  describe 'simulate', ->

    it 'should simulate a simple topology', (done) ->
      program =
        cwd: './test'
        report: ->
        inputFile: 'test/input.json'
        topology:
          input:
            test_proc: 'test input text'
          processors:
            test_proc: (event, context, callback) ->
              context.emit 'test output', {test: 'output'}
              callback()
            other_proc: (event, context, callback) ->
              context.emit 'modified', {other: event.test}
              callback()
          streams: [
            {
              to: 'other_proc',
              from: 'test_proc'
            }
          ]

      attak.simulate program, (err, results) ->
        if results.other_proc?['modified']?.other is 'output'
          done()
        else
          done 'incorrect output'