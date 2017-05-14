BaseService = require '../base_service'

class IAM extends BaseService

  paths: [
    'AWS:IAM'
  ]

  setup: (config, opts, callback) ->
    @disableParsing = true
    @host = '127.0.0.1'
    @port = opts.port || 14352
    @endpoint = "http://#{@host}:#{@port}"
    super arguments...

module.exports = IAM