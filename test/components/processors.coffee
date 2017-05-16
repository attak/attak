test = require 'tape'
AWSUtils = require '../../lib/aws'
TestUtils = require '../utils'

test 'processors', (test) ->
  topology =
    name: 'processors-test'
    processors:
      hello: (event, context, callback) ->
        callback null, 
          event: event
          context: context
          resp: {ok: true}

  TestUtils.setupTest {}, topology, {}, (err, {opts, manager, state, cleanup}) =>
    test.equal state?.processors?.hello?.id,
      'arn:aws:lambda:us-east-1:133713371337:function:processors-test-hello-development',
      'should have recorded the new processor\'s ARN as its ID'
    
    AWSUtils.triggerProcessor 'hello', {test: 'works'}, opts, (err, results) ->
      data = JSON.parse results.Payload
      test.equal data.resp.ok, true, 'should be able to invoke a processor'
      cleanup test.end