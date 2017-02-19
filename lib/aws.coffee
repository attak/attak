AWS = require 'aws-sdk'
uuid = require 'uuid'
async = require 'async'
nodePath = require 'path'

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
    async.forEachSeries topology.streams, (stream, next) ->
      streamName = "#{stream.from}-#{stream.to}"
      AWSUtils.createStream program, topology.name, streamName, stream.opts, (err, results) ->
        AWSUtils.describeStream program, topology.name, streamName, (err, streamResults) ->          
          lambdaData = lambdas["#{stream.to}-#{program.environment}"]
          AWSUtils.associateStream program, streamResults.StreamDescription, lambdaData, (err, results) ->
            next()
    , ->
      callback()

  associateStream: (program, stream, lambdaData, callback) ->
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
      callback err, data

  triggerStream: (program, stream, data, callback) ->
    console.log "TRIGGER STREAM", stream, data
    
    kinesis = new AWS.Kinesis
      region: program.region || 'us-east-1'

    params =
      Data: new Buffer JSON.stringify(data)
      StreamName: stream.StreamName || stream
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

      callback err, data

  monitorLogs: (program, processor, callback) ->
    logs = new AWS.CloudWatchLogs

    streamParams =
      logGroupName: "/aws/lambda/#{processor}-#{program.environment}"
      descending: true
      orderBy: 'LastEventTime'
      limit: 10

    logParams =
      startTime: program.startTime.getTime()
      logGroupName: "/aws/lambda/#{processor}-#{program.environment}"
      # logStreamName: results.logStreams[0].logStreamName
      # endTime: 0,
      # limit: 0,
      # nextToken: 'STRING_VALUE',
      # startFromHead: true || false,

    logInterval = setInterval ->
      logs.describeLogStreams streamParams, (err, results) ->
        results.logStreams.sort (a, b) ->
          b.lastEventTimestamp > a.lastEventTimestamp

        monitorStart = new Date().getTime()
        # console.log "STREAM", processor, results.logStreams[0]

        logParams.logStreamName = results.logStreams[0].logStreamName

        logs.getLogEvents logParams, (err, logEvents) ->
          if new Date().getTime() - monitorStart > 60000
            clearInterval logInterval
            callback()

          for event in logEvents.events
            console.log processor, ": ", event.message.trim()

            logParams.startTime = event.timestamp + 1
            if event.message.indexOf('END RequestId') != -1
              clearInterval logInterval
              callback()
    , 2000

  getNext: (topology, topic, current) ->
    next = []
    for stream in topology.streams
      if stream.from is current and (stream.topic || topic) is topic
        next.push stream.to
    next

  getProcessor: (program, topology, name) ->
    workingDir = program.cwd || process.cwd()

    if topology.processors.constructor is String
      procData = "#{topology.processors}/#{name}"
    else
      procData = topology.processors[name]

    if procData.constructor is String 
      source = procData
    else if procData.constructor is Function 
      source = procData
    else
      source = procData.source

    if source.constructor is Function
      processor = {handler: source}
    else
      processor = program.processor || require nodePath.resolve(workingDir, source)

  simulate: (program, topology, processorName, data, emitCallback, callback) ->
    results = {}
    workingDir = program.cwd || process.cwd()
    
    processor = AWSUtils.getProcessor program, topology, processorName

    emit = ->
      try
        emitCallback arguments...
      catch e
        null

    context =
      emit: emit
      done: -> callback()
      fail: (err) -> callback err
      success: (results) -> callback null, results
      topology: topology

    try
      processor.handler data, context, (err, resultData) ->
        if resultData
          results['results'] = resultData

        callback err, results
    catch e
      console.log "Error running #{processorName}:\n#{e} #{e.stack}"

module.exports = AWSUtils