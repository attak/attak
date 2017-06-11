BaseService = require '../base_service'

class Cognito extends BaseService

  paths: [
    'AWS:CognitoIdentityServiceProvider'
  ]

  setup: (config, opts, callback) ->
    @port = opts.port || 55224
    super arguments...

module.exports = Cognito