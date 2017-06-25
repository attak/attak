BaseService = require '../base_service'

class CognitoServiceProvider extends BaseService

  paths: [
    'AWS:CognitoIdentityServiceProvider'
  ]

  setup: (config, opts, callback) ->
    @port = opts.port || 55224
    super arguments...

module.exports = CognitoServiceProvider