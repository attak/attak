BaseService = require '../base_service'

class CognitoIdentity extends BaseService

  paths: [
    'AWS:CognitoIdentity'
  ]

  setup: (config, opts, callback) ->
    @port = opts.port || 55223
    super arguments...

module.exports = CognitoIdentity