BaseService = require '../base_service'

class Streams extends BaseService

  paths: [
    'AWS:Kinesis'
    'GCE:PubSub'
  ]

  setup: (config, opts, callback) ->
    @host = '127.0.0.1'
    @port = config.port || 6668
    @endpoint = "http://#{@host}:#{@port}"
    super arguments...

module.exports = Streams