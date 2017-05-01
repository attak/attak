uuid = require 'uuid'

class BaseService

  constructor: (@options) ->
    @guid = uuid.v1()
    
  setup: (topology, callback) ->
    throw new Error "Unimplemented"

module.exports = BaseService