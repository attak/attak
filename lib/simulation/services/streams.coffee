BaseService = require '../base_service'

class Streams extends BaseService

  paths: [
    'AWS:Kinesis'
    'GCE:PubSub'
  ]

  setup: (config, opts, callback) ->
    @port = config.port || 6668
    super arguments...

module.exports = Streams