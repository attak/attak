BaseService = require '../base_service'

class CloudWatchEvents extends BaseService

  paths: [
    'AWS:CloudWatchEvents'
  ]

  setup: (state, config, opts, callback) ->
    @host = '127.0.0.1'
    @port = config.port || 21321
    @endpoint = "http://#{@host}:#{@port}"
    console.log "SETUP CLOUDWATCH EVENTS", @endpoint
    super arguments...

  stop: (callback) ->
    @server?.close()
    callback()

module.exports = CloudWatchEvents