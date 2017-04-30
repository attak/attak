
class BaseService

  constructor: (@options) ->

  setup: (topology, callback) ->
    throw new Error "Unimplemented"

module.exports = BaseService