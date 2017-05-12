BaseService = require '../base_service'

class Gateway extends BaseService

  paths: [
    'AWS:APIGateway'
  ]

  setup: (config, opts, callback) ->
    @host = '127.0.0.1'
    @port = opts.port || 24424
    @endpoint = "http://#{@host}:#{@port}"
    super arguments...

module.exports = Gateway