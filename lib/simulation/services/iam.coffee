BaseService = require '../base_service'

class IAM extends BaseService

  paths: [
    'AWS:IAM'
  ]

  setup: (state, config, opts, callback) ->
    console.log "SETUP IAM SERVICE"
    @host = '127.0.0.1'
    @port = opts.port || 143523
    @endpoint = "http://#{@host}:#{@port}"
    super arguments...

  stop: (callback) ->
    @server?.close()
    callback()

module.exports = IAM