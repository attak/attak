attak = require '../'

describe 'attak', ->

  it 'should do a thing', (done) ->
    program =
      inputFile: 'test/input.json'
      topology:
        input: 'test input text'
        processors:
          test_proc:
            source: './test/test_proc'
        streams: [
          {
            to: 'reverse',
            from: 'hello_world_spout',
            fields:
              source_field_1: 'processor_field_1'
          }
        ]

    attak.simulate program, (err, results) ->
      console.log "SIMULATED", err, results

      done()