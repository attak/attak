BaseService = require '../base_service'

class API extends BaseService

  paths: [
    'ATTAK:API'
  ]

  setup: (config, opts, callback) ->
    @host = '127.0.0.1'
    @port = opts.port || 31248
    @endpoint = "http://#{@host}:#{@port}"
    super arguments...

module.exports = API