BaseService = require '../base_service'

class Streams extends BaseService

  paths: [
    'AWS:Kinesis'
    'GCE:PubSub'
  ]

  setup: (state, config, opts, callback) ->
    @host = '127.0.0.1'
    @port = config.port || 6668
    @endpoint = "http://#{@host}:#{@port}"
    super arguments...

  stop: (callback) ->
    @server?.close()
    callback()

module.exports = Streams