async = require 'async'
express = require 'express'
bodyParser = require 'body-parser'
BaseService = require '../base_service'

class Gateway extends BaseService

  paths: [
    'AWS:APIGateway'
  ]

  setup: (state, opts, callback) ->
    @host = '127.0.0.1'
    @port = opts.port || 24424
    @endpoint = "http://#{@host}:#{@port}"
    
    @app = express()
    @app.use bodyParser.json
      type: '*/*'
    @app.use bodyParser.urlencoded
      extended: true

    @app.options '*', (req, res) ->
      headers =
        'Access-Control-Max-Age': '86400'
        'Access-Control-Allow-Origin': '*'
        'Access-Control-Allow-Methods': 'POST, GET, PUT, DELETE, OPTIONS'
        'Access-Control-Allow-Headers': 'X-Requested-With, X-HTTP-Method-Override, Content-Type, Accept, X-Amz-Content-Sha256, X-Amz-User-Agent, x-amz-security-token, X-Amz-Date, X-Amz-Invocation-Type, Authorization'
        'Access-Control-Expose-Headers': 'x-amzn-RequestId,x-amzn-ErrorType,x-amzn-ErrorMessage,Date,x-amz-log-result,x-amz-function-error'
        'Access-Control-Allow-Credentials': false

      res.writeHead 200, headers
      res.end()

    async.forEachOf opts.handlers || {}, (handler, route, next) =>
      [methods, fullPath] = route.split ' '
      methods = methods.split ','

      for method in methods
        console.log "GATEWAY HANDLER", method, fullPath
        @app[method.toLowerCase()] fullPath, (req, res, next) ->
          handler state, opts, req, res, next
      next()
    , =>
      @app.use (req, res, next) ->
        console.log "UNHANDLED API GATEWAY REQUEST", req.method, req.url, req.body
        next()

    @server = @app.listen @port, () =>
      callback null, @endpoint

  stop: (callback) ->
    @server?.close()
    callback()

module.exports = Gateway