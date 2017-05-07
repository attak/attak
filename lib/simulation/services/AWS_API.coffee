BaseService = require '../base_service'

class AWSAPI extends BaseService

  paths: [
    'AWS:API'
    'AWS:Lambda'
  ]

  setup: (state, config, opts, callback) ->
    @host = '127.0.0.1'
    @port = config.port || 12368
    @endpoint = "http://#{@host}:#{@port}"
    super arguments...

  stop: (callback) ->
    @server.close()
    callback()

module.exports = AWSAPI