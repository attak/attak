AWS = require 'aws-sdk'
uuid = require 'uuid'
async = require 'async'

credentials = new AWS.SharedIniFileCredentials
  profile: 'default'

AWS.config.credentials = credentials
AWS.config.apiVersions =
  kinesis: '2013-12-02'

AWSUtils =
  createStream: (program, topology, stream, [opts]..., callback) ->
    streamOpts =
      ShardCount: opts?.shards || 1
      StreamName: "#{topology}-#{stream}"

    kinesis = new AWS.Kinesis
      region: program.region || 'us-east-1'

    kinesis.createStream streamOpts, (err, results) ->
      callback err, results

  describeStream: (program, topology, stream, callback) ->
    opts =
      StreamName: "#{topology}-#{stream}"

    kinesis = new AWS.Kinesis
      region: program.region || 'us-east-1'

    kinesis.describeStream opts, (err, results) ->
      callback err, results

  deployStreams: (topology, program, lambdas, callback) ->
    console.log "DEPLOYING STREAMS", topology.streams, program
    async.forEachSeries topology.streams, (stream, next) ->
      console.log "STREAM DEFS", stream
      streamName = "#{stream.from}-#{stream.to}"
      AWSUtils.createStream program, topology.name, streamName, stream.opts, (err, results) ->
        AWSUtils.describeStream program, topology.name, streamName, (err, streamResults) ->          
          console.log "HAVE LAMBDAS", lambdas
          lambdaData = lambdas["#{stream.to}-#{program.environment}"]
          AWSUtils.associateStream program, streamResults.StreamDescription, lambdaData, (err, results) ->
            console.log "STREAM CREATE", err, results
            next()
    , ->
      callback()

  associateStream: (program, stream, lambdaData, callback) ->
    console.log "ASSOCIATE STREAM", stream
    console.log "WITH LAMBDA", lambdaData

    lambda = new AWS.Lambda
    lambda.config.region = program.region
    lambda.config.endpoint = 'lambda.us-east-1.amazonaws.com'
    lambda.region = program.region
    lambda.endpoint = 'lambda.us-east-1.amazonaws.com'

    params = 
      BatchSize: 100
      FunctionName: lambdaData.FunctionName
      EventSourceArn: stream.StreamARN
      StartingPosition: 'LATEST'

    lambda.createEventSourceMapping params, (err, data) ->
      console.log "RESULTS", err, data
      callback err, data

  triggerStream: (program, stream, data, callback) ->
    console.log "TRIGGER STREAM", stream, data
    
    kinesis = new AWS.Kinesis
      region: program.region || 'us-east-1'

    params =
      Data: new Buffer JSON.stringify(data)
      StreamName: stream.StreamName
      PartitionKey: uuid.v1()
      # ExplicitHashKey: 'STRING_VALUE'
      # SequenceNumberForOrdering: 'STRING_VALUE'

    kinesis.putRecord params, (err, data) ->
      console.log "PUT RESULTS", err, data
      callback err, data

  triggerProcessor: (program, processor, data, callback) ->

    lambda = new AWS.Lambda
    lambda.config.region = program.region
    lambda.config.endpoint = 'lambda.us-east-1.amazonaws.com'
    lambda.region = program.region
    lambda.endpoint = 'lambda.us-east-1.amazonaws.com'

    params = 
      LogType: 'Tail'
      Payload: new Buffer JSON.stringify(data)
      FunctionName: "#{processor}-#{program.environment}"
      InvocationType: 'Event'
      # Qualifier: '1'
      # ClientContext: 'MyApp'

    lambda.invoke params, (err, data) ->
      if err
        console.log err, err.stack
      else
        console.log data

      callback err, data

module.exports = AWSUtils