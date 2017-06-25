require 'coffee-errors'
test = require 'tape'
AWSUtils = require '../../lib/aws'
TestUtils = require '../utils'

test 'deploy', (test) ->
  topology =
    name: 'deploy-test'
    processors:
      hello: (event, context, callback) ->
        callback null, 
          event: event
          context: context
          resp: {ok: true}

  testOpts =
    simulation: false

  TestUtils.setupTest {}, topology, testOpts, (err, {opts, manager, state, cleanup}) =>
    opts.simulation = false

    test.equal err, null, 'should setup test without error'
    test.equal state?.processors?.hello?.id,
      'arn:aws:lambda:us-east-1:900558755912:function:deploy-test-hello-development',
      'should have recorded the new processor\'s ARN as its ID'
    
    AWSUtils.triggerProcessor state, 'hello', {test: 'works'}, opts, (err, results) ->
      test.equal err, null, 'should run without error'
      
      raw = JSON.parse results?.Payload || '{}'
      data = JSON.parse raw.body || '{}'

      test.equal data.resp?.ok, true, 'should be able to invoke a processor'
      test.equal data.event?.test, 'works', 'should be getting event data to the processor'

      test.end()
