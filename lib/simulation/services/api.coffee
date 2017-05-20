BaseService = require '../base_service'

class API extends BaseService

  paths: [
    'ATTAK:API'
  ]

  setup: (config, opts, callback) ->
    @port = opts.port || 31248
    super arguments...

module.exports = API