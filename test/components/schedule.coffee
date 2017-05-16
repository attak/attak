test = require 'tape'
TestUtils = require '../utils'

test 'schedule', (test) ->
  topology =
    name: 'schedule-test'
    schedule:
      everyMinute:
        type: 'rate'
        value: '1 minute'
        handler: 'onEvent' 
    processors:
      onEvent: (event, context, callback) -> callback null, {ok: true}

  TestUtils.setupTest {}, topology, {}, (err, {opts, manager, state, cleanup}) =>
    test.notEqual state.schedule?.everyMinute?.id, undefined, 'should have created a schedule'
    cleanup test.end