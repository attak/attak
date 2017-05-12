uuid = require 'uuid'
async = require 'async'
express = require 'express'
bodyParser = require 'body-parser'
BaseComponent = require '../components/base_component'

class BaseService

  constructor: (@options) ->
    @guid = uuid.v1()
    
  setup: (config, opts, callback) ->
    @app = express()
    @app.use bodyParser.json
      type: '*/*'
    @app.use bodyParser.urlencoded
      extended: false

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

    async.forEachOf config.handlers || {}, (handler, route, next) =>
      [methods, fullPath] = route.split ' '
      methods = methods.split ','

      for method in methods
        @app[method.toLowerCase()] fullPath, (req, res, next) ->
          state = BaseComponent::loadState()
          handler state, opts, req, res, (err, changedState) ->
            console.log "BASE SERVICE HANDLER RESULTS", err, changedState
            BaseComponent::saveState changedState
            next err
    , =>
      @app.use (req, res, next) =>
        console.log "UNHANDLED #{@constructor.name} API REQUEST", req.method, req.url, req.body
        next()

    @server = @app.listen @port, () =>
      callback null, @endpoint

  stop: (callback) ->
    console.log "STOP", @constructor.name
    @server?.close()
    callback()

module.exports = BaseService