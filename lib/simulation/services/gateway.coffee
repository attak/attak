BaseService = require '../base_service'

class Gateway extends BaseService

  paths: [
    'AWS:APIGateway'
  ]

  setup: (state, config, opts, callback) ->
    @host = '127.0.0.1'
    @port = opts.port || 24424
    @endpoint = "http://#{@host}:#{@port}"
    super arguments...

  stop: (callback) ->
    @server?.close()
    callback()

module.exports = Gateway