AWS = require 'aws-sdk'
async = require 'async'
BaseComponent = require './base_component'

class Streams extends BaseComponent
  namespace: 'streams'
  platforms: ['AWS']
  simulation:
    services:
      'AWS:Kinesis':
        handlers:
          "POST /": @simulateStreamPutItem

  create: (path, newDefs, callback) ->
    [
      {
        msg: "Create new stream"
        run: (done) ->
          console.log "CREATING NEW STREAM", newDefs
          done()
      }
    ]

  delete: (path, oldDefs, callback) ->
    [
      {
        msg: "Remove stream"
        run: (done) ->
          console.log "REMOVING STREAM", path[0], oldDefs
          done()
      }
    ]

  simulateStreamPutItem: (topology, opts, req, res) ->
    console.log "PUT ITEM", req.body, opts

    lambda = new AWS.Lambda
      region: opts.region || 'us-east-1'
      endpoint: opts.endpoints['AWS:Kinesis']

    params =
      Payload: new Buffer JSON.stringify(data)
      FunctionName: "#{processor}-#{program.environment}"
      InvocationType: 'Event'

    lambda.invoke params, (err, results) ->
      res.json ok: true

module.exports = Streams