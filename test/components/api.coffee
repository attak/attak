test = require 'tape'
TestUtils = require '../utils'

test 'streams', (test) ->
  topology =
    name: 'api-test'
    api: 'endpoint'
    processors:
      endpoint: (event, context, callback) -> callback null, {ok: true}

  TestUtils.setupTest {}, topology, {}, (err, {opts, manager, state}) =>
    test.notEqual state.api.gateway?.id, undefined, 'should have created a gateway'
    test.notEqual state.api.resources?.root?.id, undefined, 'should have created a root resource'
    test.notEqual state.api.resources?.proxy?.id, undefined, 'should have created a proxy resource'
    test.end()
