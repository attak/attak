url = require 'url'
AWS = require 'aws-sdk'
uuid = require 'uuid'
chalk = require 'chalk'
async = require 'async'
nodePath = require 'path'
kinesisStreams = require 'kinesis'

DEBUG = false
log = -> if DEBUG then console.log arguments...

credentials = new AWS.SharedIniFileCredentials
  profile: 'default'

AWS.config.credentials = credentials
AWS.config.apiVersions =
  kinesis: '2013-12-02'

padding =
  "201": "",
  "301": " ",
  "302": "  "

locationRegex = "https://.*|http://.*|/.*"
responseDelimeter = "__lambdaexpress_delim__"

selectionPatterns =
  responseDelimeter: responseDelimeter
  padding: padding
  regex:
    "404": "STATUS404" + responseDelimeter + ".*",
    "201": padding["201"] + locationRegex,
    "301": padding["301"] + locationRegex,
    "302": padding["302"] + locationRegex

integrationResponses =
  error: """
    #set ($errorMessage = $input.path('$.errorMessage'))
    #set ($response = $errorMessage.split("#{selectionPatterns.responseDelimeter}"))
    $response[1]
  """,

  standard: """
    #set ($message = $input.path('$'))
    #set ($response = $message.split("#{selectionPatterns.responseDelimeter}"))
    $response[1]
  """

statusCodesMap = 
  '200':
    selectionPattern: null
    responseTemplates: 'application/json': integrationResponses.standard
  '201':
    selectionPattern: selectionPatterns.regex['201']
    responseTemplates: 'application/json': ''
  '301':
    selectionPattern: selectionPatterns.regex['301']
    responseTemplates: 'application/json': ''
  '302':
    selectionPattern: selectionPatterns.regex['302']
    responseTemplates: 'application/json': ''
  '404':
    selectionPattern: selectionPatterns.regex['404']
    responseTemplates: 'application/json': integrationResponses.error

methodResponsesParameters = 
  '200': null
  '201': 'method.response.header.Location': true
  '301': 'method.response.header.Location': true
  '302': 'method.response.header.Location': true
  '404': null

integrationResponsesParameters = 
  '200': null
  '201': 'method.response.header.Location': 'integration.response.body.errorMessage'
  '301': 'method.response.header.Location': 'integration.response.body.errorMessage'
  '302': 'method.response.header.Location': 'integration.response.body.errorMessage'
  '404': null

integrationTemplate = """
  {
    "body" : $input.json('$'),
    "headers": {
      #foreach($header in $input.params().header.keySet())
      "$header": "$util.escapeJavaScript($input.params().header.get($header))" #if($foreach.hasNext),#end
      #end
    },
    "method": "$context.httpMethod",
    "params": {
      #foreach($param in $input.params().path.keySet())
      "$param": "$util.escapeJavaScript($input.params().path.get($param))" #if($foreach.hasNext),#end
      #end
    },
    "query": {
      #foreach($queryParam in $input.params().querystring.keySet())
      "$queryParam": "$util.escapeJavaScript($input.params().querystring.get($queryParam))" #if($foreach.hasNext),#end
      #end
    }
  }
"""

AWSUtils =
  getApiByName: (name, opts, callback) ->
    gateway = new AWS.APIGateway
      region: opts.region || 'us-east-1'

    gateway.getRestApis (err, results) ->
      if err then return callback(err)
      for result in results.items
        if result.name is name
          return callback null, result
      callback()

  getApis: (opts={}, callback) ->
    gateway = new AWS.APIGateway
      region: opts.region || 'us-east-1'

    gateway.getRestApis (err, results) ->
      console.log "GET REST APIS", err, results
      callback err, results

  setupGateway: (handler, opts, callback) ->
    log "SETUP GATEWAY", handler, opts

    region = opts.region || 'us-east-1'
    environment = opts.environment || 'development'
    functionName = "#{handler}-#{environment}"

    apiGateway = new AWS.APIGateway
      region: region

    lambda = new AWS.Lambda
      region: region

    async.waterfall [
      (done) ->
        params =
          limit: 500

        apiGateway.getRestApis params, (err, apis) ->   
          log "EXISTING APIS", err, apis
          done err, {apis}
      ({apis}, done) ->
        existing = undefined
        for api in apis.items
          if api.name is opts.name
            existing = api
            break

        if existing
          params =
            restApiId: existing.id

          apiGateway.deleteRestApi params, (err, results) ->
            log "DELETED API", existing.id, err, results
            done()
        else
          log "API DOESNT EXIST YET"
          done()
      (done) ->
        params =
          name: opts.name

        apiGateway.createRestApi params, (err, gateway) ->
          log "CREATED API", err, gateway
          done err, {gateway}

      ({gateway}, done) ->
        params =
          restApiId: gateway.id

        apiGateway.getResources params, (err, results) ->
          root = results?.items?[0]
          log "GOT ROOT RESOURCE", err, root
          done err, {gateway, root}

      ({gateway, root}, done) ->
        params =
          # path: '/{proxy+}'
          pathPart: '{proxy+}'
          parentId: root.id
          restApiId: gateway.id

        apiGateway.createResource params, (err, proxy) ->
          log "CREATED PROXY RESOURCE", err, proxy
          done err, {gateway, root, proxy}

      ({gateway, root, proxy}, done) ->
        iam = new AWS.IAM
          region: region

        iam.getUser (err, results) ->
          log "GOT ACCOUNT INFO", gateway, results
          account = results?.User?.UserId
          done err, {gateway, root, account, proxy}

      ({gateway, root, account, proxy}, done) ->
        params =
          restApiId: gateway.id
          resourceId: root.id
          httpMethod: 'ANY'
          authorizationType: "NONE"

        apiGateway.putMethod params, (err, results) ->
          log "CREATE ROOT METHOD RESULTS", results
          done err, {gateway, root, account, proxy}

      ({gateway, root, account, proxy}, done) ->
        log "CREATE 'ANY' METHOD", gateway, root, account

        params =
          restApiId: gateway.id
          resourceId: proxy.id
          httpMethod: 'ANY'
          authorizationType: "NONE"

        apiGateway.putMethod params, (err, results) ->
          log "CREATE PROXY METHOD RESULTS", results
          done err, {gateway, root, account, proxy}
    
      ({gateway, root, account, proxy}, done) ->
        async.forEachOfSeries statusCodesMap, (defs, code, next) ->
          params =
            restApiId: gateway.id
            resourceId: root.id
            httpMethod: 'ANY'
            statusCode: code
            responseModels: 'application/json': 'Empty'
            responseParameters: methodResponsesParameters[code]
          
          apiGateway.putMethodResponse params, (err, results) ->
            log "CREATE METHOD RESPONSE RESULTS", err, results
            next err
        , (err) ->
          done err, {gateway, root, account, proxy}

      ({gateway, root, account, proxy}, done) ->
        async.forEachOfSeries statusCodesMap, (defs, code, next) ->
          params =
            restApiId: gateway.id
            resourceId: proxy.id
            httpMethod: 'ANY'
            statusCode: code
            responseModels: 'application/json': 'Empty'
            responseParameters: methodResponsesParameters[code]
          
          apiGateway.putMethodResponse params, (err, results) ->
            log "CREATE PROXY METHOD RESPONSE RESULTS", err, results
            next err
        , (err) ->
          done err, {gateway, root, account, proxy}
      
      ({gateway, root, account, proxy}, done) ->
        functionArn = "arn:aws:lambda:#{region}:#{account}:function:#{functionName}"

        params =
          uri: "arn:aws:apigateway:#{region}:lambda:path/2015-03-31/functions/#{functionArn}/invocations"
          type: "AWS_PROXY",
          restApiId: gateway.id,
          resourceId: root.id,
          httpMethod: 'ANY',
          passthroughBehavior: "when_no_match",
          integrationHttpMethod: "POST",
          requestTemplates:
            "application/json" : integrationTemplate

        apiGateway.putIntegration params, (err, results) ->
          log "CREATE INTEGRATION RESULTS", err, results
          done err, {gateway, root, account, proxy}

      ({gateway, root, account, proxy}, done) ->
        async.forEachOfSeries statusCodesMap, (defs, code, next) ->
          params =
            restApiId: gateway.id
            resourceId: root.id
            httpMethod: 'ANY'
            statusCode: code,
            selectionPattern: statusCodesMap[code].selectionPattern,
            responseTemplates: statusCodesMap[code].responseTemplates,
            responseParameters: integrationResponsesParameters[code]
          
          apiGateway.putIntegrationResponse params, (err, results) ->
            log "CREATE INTEGRATION RESPONSE RESULTS", code, err, results
            next err

        , (err) ->
          done err, {gateway, root, account, proxy}

      ({gateway, root, account, proxy}, done) ->
        functionArn = "arn:aws:lambda:#{region}:#{account}:function:#{functionName}"

        params =
          uri: "arn:aws:apigateway:#{region}:lambda:path/2015-03-31/functions/#{functionArn}/invocations"
          type: "AWS_PROXY",
          restApiId: gateway.id,
          resourceId: proxy.id,
          httpMethod: 'ANY',
          passthroughBehavior: "when_no_match",
          integrationHttpMethod: "POST",
          requestTemplates:
            "application/json" : integrationTemplate

        apiGateway.putIntegration params, (err, results) ->
          log "CREATE PROXY INTEGRATION RESULTS", err, results
          done err, {gateway, root, account, proxy}

      ({gateway, root, account, proxy}, done) ->
        async.forEachOfSeries statusCodesMap, (defs, code, next) ->
          params =
            restApiId: gateway.id
            resourceId: proxy.id
            httpMethod: 'ANY'
            statusCode: code,
            selectionPattern: statusCodesMap[code].selectionPattern,
            responseTemplates: statusCodesMap[code].responseTemplates,
            responseParameters: integrationResponsesParameters[code]
          
          apiGateway.putIntegrationResponse params, (err, results) ->
            log "CREATE PROXY INTEGRATION RESPONSE RESULTS", code, err, results
            next err

        , (err) ->
          done err, {gateway, root, account}

      ({gateway, root, account}, done) ->
        params =
          Action: "lambda:InvokeFunction"
          Principal: "apigateway.amazonaws.com"
          SourceArn: "arn:aws:execute-api:#{region}:#{account}:#{gateway.id}/*/*/"
          StatementId: "apigateway-#{gateway.name}-#{uuid.v1()}"
          FunctionName: functionName

        lambda.addPermission params, (err, results) ->
          log "ADD STAR PERMISSIONS RESULTS", results
          done err, {gateway, root, account}

      ({gateway, root, account}, done) ->
        params =
          Action: "lambda:InvokeFunction"
          Principal: "apigateway.amazonaws.com"
          SourceArn: "arn:aws:execute-api:#{region}:#{account}:#{gateway.id}/#{environment}/ANY/"
          StatementId: "apigateway-#{gateway.name}-#{uuid.v1()}"
          FunctionName: functionName

        lambda.addPermission params, (err, results) ->
          log "ADD PERMISSIONS RESULTS", results, params
          done err, {gateway, root, account}

      ({gateway, root, account}, done) ->
        params =
          Action: "lambda:InvokeFunction"
          Principal: "apigateway.amazonaws.com"
          SourceArn: "arn:aws:execute-api:#{region}:#{account}:#{gateway.id}/#{environment}/ANY/{proxy+}"
          StatementId: "apigateway-#{gateway.name}-#{uuid.v1()}"
          FunctionName: functionName

        lambda.addPermission params, (err, results) ->
          log "ADD PROXY PERMISSIONS RESULTS", err, results, params
          done err, {gateway, root, account}

      ({gateway, root, account}, done) ->
        params =
          restApiId: gateway.id
          stageName: environment

        apiGateway.createDeployment params, (err, deployment) ->
          log "DEPLOYMENT RESULTS", err, deployment
          done err, {gateway, root, account, deployment}

      ({gateway, root, account, deployment}, done) ->
        params =
          restApiId: gateway.id
          deploymentId: deployment.id

        apiGateway.getStages params, (err, results) ->
          existing = undefined
          for stage in results.item
            if stage.stageName is environment
              existing = stage
              break

          if existing
            done null, {gateway, root, account, deployment}
          else
            params.stageName = environment
            apiGateway.createStage params, (err, results) ->
              log "CREATE STAGE RESULTS", err, results
              done err, {gateway, root, account, deployment}

    ], (err, results) ->
      {gateway, root, account} = results || {}
      log "CREATE GATEWAY RESULTS", err, results
      if err
        console.log "GOT ERROR", err
      console.log "API RUNNING AT https://#{gateway.id}.execute-api.#{region}.amazonaws.com/#{environment}/"
      callback err, results

  getStreamName: (topologyName, sourceProcessor, destProcessor) ->
    "#{topologyName}-#{sourceProcessor}-#{destProcessor}"

  createStream: (program, topology, stream, [opts]..., callback) ->
    streamOpts =
      ShardCount: opts?.shards || 1
      StreamName: stream

    kinesis = new AWS.Kinesis
      region: program.region || 'us-east-1'
      endpoint: program.kinesisEndpoint

    kinesis.createStream streamOpts, (err, results) ->
      callback err, results

  describeStream: (program, topology, stream, callback) ->
    opts =
      StreamName: stream

    kinesis = new AWS.Kinesis
      region: program.region || 'us-east-1'
      endpoint: program.kinesisEndpoint
    kinesis.describeStream opts, (err, results) ->
      callback err, results

  deployStreams: (topology, program, lambdas, callback) ->
    async.forEachSeries topology.streams, (stream, next) ->
      streamName = AWSUtils.getStreamName topology.name, stream.from, stream.to
      AWSUtils.createStream program, topology.name, streamName, stream.opts, (err, results) ->
        AWSUtils.describeStream program, topology.name, streamName, (err, streamResults) ->          
          lambdaData = lambdas["#{stream.to}-#{program.environment}"]
          AWSUtils.associateStream program, streamResults.StreamDescription, lambdaData, (err, results) ->
            next()
    , ->
      callback()

  deploySimulationStreams: (program, topology, callback) ->
    names = []
    async.forEachSeries topology.streams, (stream, next) ->
      streamName = AWSUtils.getStreamName topology.name, stream.from, stream.to,
        host: url.parse(program.kinesisEndpoint).hostname
        port: url.parse(program.kinesisEndpoint).port

      AWSUtils.createStream program, topology.name, streamName, stream.opts, (err, results) ->
        AWSUtils.describeStream program, topology.name, streamName, (err, streamResults) ->
          names.push streamName
          next()
    , (err) ->
      callback names

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
      endpoint: program.kinesisEndpoint

    params =
      Data: new Buffer JSON.stringify(data)
      StreamName: stream.StreamName || stream
      PartitionKey: uuid.v1()

    kinesis.putRecord params, (err, data) ->
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

  nextByTopic: (topology, current) ->
    next = {}
    for stream in topology.streams
      if stream.from is current
        next[stream.topic || 'all'] = stream.to
    next

  getIterators: (kinesis, processorName, nextByTopic, topology, callback) ->
    iterators = {}

    async.forEachOf nextByTopic, (nextProc, topic, done) ->
      streamName = AWSUtils.getStreamName topology.name, processorName, nextProc
      
      try
        kinesis.describeStream
          StreamName: streamName
        , (err, streamData) ->
          if err
            return done(err)

          shardId = streamData.StreamDescription.Shards[0].ShardId

          kinesis.getShardIterator
            ShardId: shardId
            StreamName: streamName
            ShardIteratorType: 'LATEST'
          , (err, iterator) ->
            iterators[streamName] = iterator
            done()

      catch err
        console.log 'CAUGHT ERR', err
      
    , (err) ->
      callback err, iterators

module.exports = AWSUtils