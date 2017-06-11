BaseService = require '../base_service'

class Cognito extends BaseService

  paths: [
    'AWS:CognitoIdentity'
  ]

  setup: (config, opts, callback) ->
    @port = opts.port || 55223
    super arguments...

module.exports = Cognito