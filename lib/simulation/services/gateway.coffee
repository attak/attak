BaseService = require '../base_service'

class Gateway extends BaseService

  paths: [
    'AWS:APIGateway'
  ]

  setup: (config, opts, callback) ->
    @port = opts.port || 24424
    super arguments...

module.exports = Gateway