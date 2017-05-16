test = require 'tape'
TestUtils = require '../utils'

test 'streams', (test) ->
  topology =
    name: 'streams-test'
    processors:
      first: () -> null
      second: () -> null
    streams:
      'streams-test-first-second':
        from: 'first'
        to: 'second'

  TestUtils.setupTest {}, topology, {}, (err, {opts, manager, state}) =>
    test.equal state?['streams-test-first-second']?.id,
      'arn:aws:kinesis:us-east-1:133713371337:stream/streams-test-first-second',
      'should have recorded the new stream\'s ARN as its ID'
    test.end()
