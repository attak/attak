test = require 'tape'
AWSUtils = require '../../lib/aws'
TestUtils = require '../utils'

test 'streams', (test) ->
  didCallFirst = false
  didCallSecond = false
  didEmitFirst = false
  didEmitSecond = false

  topology =
    name: 'streams-test'
    processors:
      first: (event, context, callback) ->
        didCallFirst = true
        context.emit 'testTopic', {test: 'event'}
        callback()
      second: (event, context, callback) ->
        didCallSecond = true
        context.emit 'secondTopic', {other: 'event'}
        callback()
    streams: [
      ['first', 'second']
    ]

  opts =
    onEmit:
      first: (topic, data, opts, done) ->
        didEmitFirst = true
        done()
      second: (topic, data, opts, done) ->
        didEmitSecond = true
        done()

  TestUtils.setupTest {}, topology, opts, (err, {opts, manager, state, cleanup}) =>
    streamName = 'streams-test-first-second-development'
    test.notEqual state.streams?[streamName]?.to, undefined, 'Should have a destination processor'
    test.notEqual state.streams?[streamName]?.from, undefined, 'Should have a source processor'

    test.equal state.streams?[streamName]?.id,
      "arn:aws:kinesis:us-east-1:133713371337:stream/#{streamName}",
      'should have recorded the new stream\'s ARN as its ID'

    AWSUtils.triggerProcessor state, 'first', {test: 'works'}, opts, (err, results) ->
      test.equal didCallFirst, true, 'should have called the first processor'
      test.equal didCallSecond, true, 'should have called the second processor'
      test.equal didEmitFirst, true, 'should have emitted from the first processor'
      test.equal didEmitSecond, true, 'should have emitted from the second processor'
      cleanup test.end
