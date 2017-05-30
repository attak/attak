nodePath = require 'path'
dynalite = require 'dynalite'
BaseService = require '../base_service'

class DynamoDB extends BaseService

  paths: [
    'AWS:DynamoDB'
  ]

  setup: (config, opts, callback) ->
    @port = opts.port || 44225
    @host = 'localhost'
    @endpoint = "http://#{@host}:#{@port}"

    workingDir = opts.cwd || process.cwd()

    @dynaliteServer = dynalite
      path: nodePath.resolve workingDir, './.attak-dynamodb-sim'

    @dynaliteServer.listen @port, (err) =>
      callback err

module.exports = DynamoDB