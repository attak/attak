BaseService = require '../base_service'

class IAM extends BaseService

  paths: [
    'AWS:IAM'
  ]

  setup: (config, opts, callback) ->
    @disableParsing = true
    @port = opts.port || 14352
    super arguments...

module.exports = IAM