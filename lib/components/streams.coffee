AWS = require 'aws-sdk'
async = require 'async'
AWSUtils = require '../aws'
AttakProc = require 'attak-processor'
TopologyUtils = require '../topology'
BaseComponent = require './base_component'

class Streams extends BaseComponent
  namespace: 'streams'
  platforms: ['AWS']
  simulation:
    services: ->
      'AWS:Kinesis':
        handlers:
          "POST /": @handleKinesisPut

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

  invokeProcessor: (processorName, data, state, opts, callback) ->
    context =
      done: -> callback()
      fail: (err) -> callback err
      success: (results) -> callback null, results
      state: state
      services: opts.services

    processor = TopologyUtils.getProcessor opts, state, processorName
    handler = AttakProc.handler processorName, state, processor, opts
    handler data, context, (err, results) ->
      callback err, results

  getTargetProcessor: (state, targetStream) ->
    for stream in state.streams
      streamName = AWSUtils.getStreamName state.name, stream.from, stream.to
      console.log "STREAM NAME", streamName, "LOOKING FOR", targetStream
      if streamName is targetStream
        return stream.to

  handleKinesisPut: (state, opts, req, res) =>
    console.log "HANDLE KINESIS PUT", req.body.StreamName

    streamExists = false
    for stream in (state.streams || [])
      if AWSUtils.getStreamName(state.name, stream.from, stream.to) is req.body.StreamName
        streamExists = true

    if streamExists
      processorName = @getTargetProcessor state, req.body.StreamName
      data = JSON.parse new Buffer(req.body.Data, 'base64').toString()
      @invokeProcessor processorName, data.data, state, opts, (err, results) ->
        res.json {ok: true}
    else
      res.status 400
      res.header 'x-amzn-errortype', 'ResourceNotFoundException'
      res.json
        message: "Stream not found: #{req.body.StreamName}"

module.exports = Streams