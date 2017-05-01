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
    console.log "CREATING NEW STREAM", newDefs
    @state[path[0]] = newDefs
    callback null

  delete: (path, oldDefs, callback) ->
    console.log "REMOVING STREAM", path[0], oldDefs
    callback null

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