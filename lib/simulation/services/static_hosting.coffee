BaseService = require '../base_service'

class StaticHosting extends BaseService

  paths: [
    'ATTAK:Static'
  ]

  setup: (config, opts, callback) ->
    @port = opts.port || 12342
    super arguments...

module.exports = StaticHosting