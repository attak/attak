BaseService = require '../base_service'

class S3 extends BaseService

  paths: [
    'AWS:S3'
  ]

  setup: (config, opts, callback) ->
    @disableParsing = true
    @vhost = '*'
    @port = opts.port || 42245
    super arguments...

module.exports = S3