BaseService = require '../base_service'

class AWSAPI extends BaseService

  paths: [
    'AWS:API'
    'AWS:Lambda'
  ]

  setup: (config, opts, callback) ->
    @host = '127.0.0.1'
    @port = config.port || 12368
    @endpoint = "http://#{@host}:#{@port}"
    super arguments...

module.exports = AWSAPI