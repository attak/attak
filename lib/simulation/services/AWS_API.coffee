BaseService = require '../base_service'

class AWSAPI extends BaseService

  paths: [
    'AWS:API'
    'AWS:Lambda'
  ]

  setup: (config, opts, callback) ->
    @port = config.port || 12368
    super arguments...

module.exports = AWSAPI