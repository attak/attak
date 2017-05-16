test = require 'tape'
TestUtils = require '../utils'

test 'processors', (test) ->
  topology =
    name: 'processors-test'
    processors:
      hello: () -> null

  TestUtils.setupTest {}, topology, {}, (err, {opts, manager, state}) =>
    test.equal state?.processors?.hello?.id,
      'arn:aws:lambda:us-east-1:133713371337:function:hello-development',
      'should have recorded the new processor\'s ARN as its ID'
    test.end()