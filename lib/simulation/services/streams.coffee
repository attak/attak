BaseService = require '../base_service'

class Streams extends BaseService

  paths: [
    'AWS:Kinesis'
    'GCE:PubSub'
  ]

  setup: (topology, opts, callback) ->
    hostname = '127.0.0.1'
    port = opts.port || 6668
    
    app = express()
    app.use bodyParser.json()
    app.use bodyParser.urlencoded
      extended: false

    app.options '*', (req, res) ->
      headers =
        'Access-Control-Max-Age': '86400'
        'Access-Control-Allow-Origin': '*'
        'Access-Control-Allow-Methods': 'POST, GET, PUT, DELETE, OPTIONS'
        'Access-Control-Allow-Headers': 'X-Requested-With, X-HTTP-Method-Override, Content-Type, Accept, X-Amz-Content-Sha256, X-Amz-User-Agent, x-amz-security-token, X-Amz-Date, X-Amz-Invocation-Type, Authorization'
        'Access-Control-Expose-Headers': 'x-amzn-RequestId,x-amzn-ErrorType,x-amzn-ErrorMessage,Date,x-amz-log-result,x-amz-function-error'
        'Access-Control-Allow-Credentials': false

      res.writeHead 200, headers
      res.end()

    for [route, handler] in (opts.handlers || [])
      [methods, fullPath] = route.split ' '
      methods = methods.split ','

      for method in methods
        app[method.toLowerCase()] fullPath, (req, res, next) ->
          handler topology, opts, req, res, next

    app.listen port, () ->
      callback null, "http://localhost:#{port}"

module.exports = Streams