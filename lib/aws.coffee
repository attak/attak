fs = require 'fs'
url = require 'url'
AWS = require 'aws-sdk'
uuid = require 'uuid'
chalk = require 'chalk'
async = require 'async'
level = require 'level'
rimraf = require 'rimraf'
s3sync = require 's3-sync-aws'
nodePath = require 'path'
readdirp = require 'readdirp'
publicIp = require 'public-ip'
kinesisStreams = require 'kinesis'

DEBUG = true
log = -> if DEBUG then console.log arguments...

if process.env.TRAVIS
  AWS.config.update
    accessKeyId: "FAKEKEY"
    secretAccessKey: "FAKESECRET"

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
  """

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

federatedPolicies =
  google: (config) ->
    """
      {
        "Version":"2012-10-17",
        "Statement": [{
          "Effect":"Allow",
          "Principal":{
            "Federated":"accounts.google.com"
          },
          "Action":"sts:AssumeRoleWithWebIdentity",
          "Condition":{
            "StringEquals":{
              "accounts.google.com:aud":"#{config.key}"
            }
          }
        }]
      }
    """

AWSUtils =

  setupStatic: (topology, opts, callback) ->
    workingDir = opts.cwd || process.cwd()

    if topology.static.constructor is String
      staticDir = nodePath.resolve workingDir, topology.static
    else
      staticDir = nodePath.resolve workingDir, topology.static.dir
    
    bucketName = "#{topology.name}-#{opts.environment || 'development'}"

    AWSUtils.setupBucket bucketName, opts, (err, results) ->
      log "DONE SETTING UP BUCKET"
      AWSUtils.uploadDir bucketName, staticDir, opts, (err, results) ->
        AWSUtils.setupBucketPermissions topology, opts, bucketName, ->
          callback()

  getBucketPolicy: (bucketName, type, opts, callback) ->
    switch type
      when 'public'
        callback null, """
          {
            "Version":"2012-10-17",
            "Statement":[
              {
                "Sid":"AddPerm",
                "Effect":"Allow",
                "Principal": "*",
                "Action":["s3:GetObject"],
                "Resource":["arn:aws:s3:::#{bucketName}/*"]
              }
            ]
          }
        """

      when 'me'
        publicIp.v4().then (ip) ->
          callback null, """
            {
              "Version":"2012-10-17",
              "Statement":[
                {
                  "Sid":"IPDeny",
                  "Effect":"Allow",
                  "Principal": "*",
                  "Action": ["s3:GetObject"],
                  "Resource": "arn:aws:s3:::#{bucketName}/*",
                  "Condition": {
                     "IpAddress": {"aws:SourceIp": "#{ip}/24"}
                  }
                }
              ]
            }
          """
        .catch (err) ->
          console.log "CAUGHT IP ERR", err
          callback err

      else
        callback "Unknown bucket policy type #{type}"

  setupBucket: (bucketName, opts, callback) ->
    s3 = new AWS.S3
      region: opts.region || 'us-east-1'

    params =
      Bucket: bucketName

    s3.headBucket params, (err, results) ->
      if err and err.code is 'NotFound'
        params =
          # ACL: 'public-read'
          Bucket: bucketName

        s3.createBucket params, (err, results) ->
          log "CREATE BUCKET RESULTS", err, results
          callback()
      else
        callback()

  setupAuthRole: (topology, opts, callback) ->
    if topology.static.auth?.federated is undefined
      return callback()

    iam = new AWS.IAM
      region: opts.region || 'us-east-1'

    environment = opts.environment || 'development'
    roleName = "static-auth-#{topology.name}-#{environment}"

    iam.listRoles {}, (err, results) ->
      existing = undefined
      for role in results.Roles
        if role.RoleName is roleName
          existing = role

      if existing isnt undefined
        return callback null, existing.Arn

      federatedProvider = Object.keys(topology.static.auth.federated)[0]
      policyConfig = topology.static.auth.federated[federatedProvider]
      policyDoc = federatedPolicies[federatedProvider](policyConfig)

      params =
        AssumeRolePolicyDocument: policyDoc
        Path: '/'
        RoleName: roleName

      iam.createRole params, (err, results) ->
        log "CREATE STATIC ROLE RESULTS", err, results
        callback err, results.Arn

  setupBucketPermissions: (topology, opts, bucketName, callback) ->
    log "SETUP BUCKET PERMISSIONS", bucketName

    AWSUtils.setupBucketPolicy topology, opts, bucketName, (err) ->
      AWSUtils.setupAuthRole topology, opts, (err, roleArn) ->
        AWSUtils.setupInvocationPolicies topology, opts, roleArn, callback

  getPolicyByName: (iam, policyName, callback) ->
    iam.listPolicies {}, (err, results) ->
      existing = undefined
      for policy in results.Policies
        if policy.PolicyName is policyName
          existing = policy

      if existing is undefined
        return callback()

      params =
        PolicyArn: existing.Arn

      iam.getPolicy params, (err, results) ->
        callback err, results

  setupBucketPolicy: (topology, opts, bucketName, callback) ->
    log "SETUP BUCKET POLICY", bucketName
    s3 = new AWS.S3
      region: opts.region || 'us-east-1'

    environment = opts.environment || 'development'
    policyName = "static-access-#{topology.name}-#{environment}"


    policyType = topology.static.access?.type || topology.static.access || 'public'
    AWSUtils.getBucketPolicy bucketName, policyType, opts, (err, policyDoc) ->
      if err then return callback err

      if policyDoc is undefined
        return callback()

      params =
        Bucket: bucketName
        Policy: policyDoc

      log "CREATING STATIC ACCESS POLICY", policyName, policyDoc

      s3.putBucketPolicy params, (err, results) ->
        log "CREATE STATIC POLICY RESULTS", err, results
        callback err, results.Arn

  setupInvocationPolicies: (topology, opts, roleArn, callback) ->
    if topology.static.permissions?.invoke is undefined
      return callback()

    lambda = new AWS.Lambda
      region: opts.region || 'us-east-1'

    splitArn = roleArn.split ':'
    accountId = splitArn[4]

    async.each topology.static.permissions.invoke, (target, next) ->
      environment = opts.environment || 'development'
      functionName = "#{target}-#{environment}"

      async.waterfall [
        (done) ->
          params =
            FunctionName: functionName

          lambda.getPolicy params, (err, results) ->
            log "GET POLICY RESULTS", results
            if err
              policy = undefined
            else
              policy = JSON.parse(results?.Policy)
            
            done null, policy

        # (policy, done) ->
        #   params =
        #     StatementId: "static-#{topology.name}-#{opts.environment || 'development'}"
        #     FunctionName: functionName

        #   lambda.removePermission params, (err, results) ->
        #     console.log "REMOVE PERMISSION RESULTS", err, results
        #     setTimeout ->
        #       console.log "DONE REMOVING PERMISSIONS"
        #       done null, policy
        #     , 60000

        (policy, done) ->
          statementName = "static-#{topology.name}-#{target}-#{opts.environment || 'development'}"
          for statement in (policy?.Statement || [])
            if statement.Sid is statementName
              return done null

          params =
            Action: "lambda:InvokeFunction"
            Principal: roleArn
            # SourceArn: "arn:aws:sts::#{accountId}:assumed-role/#{statementName}/#{topology.name}"
            StatementId: statementName
            FunctionName: functionName

          lambda.addPermission params, (err, results) ->
            log "ADD STATIC #{target} PERMISSIONS RESULTS", err, results
            done err
      ], (err, results) ->
        next err
    , (err) ->
      callback()

  uploadDir: (bucketName, staticDir, opts, callback) ->
    s3 = new AWS.S3
      region: opts.region || 'us-east-1'

    log "UPLOADING STATIC FILES FROM", staticDir

    # To cache the S3 HEAD results and speed up the upload process.
    cacheDbPath = nodePath.resolve __dirname, '../uploadcache'

    db = level cacheDbPath
    files = readdirp
      root: staticDir
      directoryFilter: [
        '!.git'
        '!cache'
        '!.DS_Store'
      ]

    log "WRITING TO BUCKET", bucketName

    params =
      key: opts.accessKey
      acl: 'public-read'
      secret: opts.secretKey
      bucket: bucketName
      concurrency: 16

    uploader = s3sync(db, params).on 'data', (file) ->
      log "UPLOADING #{file.fullPath} -> #{file.url}"

    files.pipe uploader

    uploader.on 'fail', (err) ->
      log "UPLOAD FAILED", err

    uploader.on 'end', ->
      rimraf cacheDbPath, ->
        callback()

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

  setupSchedule: (topology, opts, callback) ->
    log "SETUP SCHEDULE", topology.schedule

    region = opts.region || 'us-east-1'
    environment = opts.environment || 'development'

    lambda = new AWS.Lambda
      region: region
      endpoint: opts.services['AWS:Lambda'].endpoint

    apiGateway = new AWS.APIGateway
      region: region
      endpoint: opts.services['AWS:APIGateway'].endpoint

    cloudWatchEvents = new AWS.CloudWatchEvents
      region: region
      endpoint: opts.services['AWS:CloudWatchEvents'].endpoint

    scheduleId = undefined
    async.forEachOf topology.schedule, (defs, scheduleName, next) ->
      console.log "SETUP SCHEDULE", scheduleName, defs, opts.services['AWS:CloudWatchEvents'].endpoint
      functionName = "#{defs.processor}-#{environment}"
      
      async.waterfall [
        (done) ->
          params =
            Name: "#{topology.name}-#{scheduleName}"
            ScheduleExpression: "#{defs.type}(#{defs.value})"

          cloudWatchEvents.putRule params, (err, results) ->
            log "PUT RULE RESULTS", params, err, results
            done err, {arn: results.RuleArn}
        
        ({arn}, done) ->
          params =
            FunctionName: functionName

          lambda.getPolicy params, (err, results) ->
            log "GET POLICY RESULTS", results
            if err
              policy = undefined
            else
              policy = JSON.parse(results?.Policy)
            
            done null, {arn, policy}

        ({arn, policy}, done) ->
          for statement in (policy?.Statement || [])
            if statement.Sid is "schedule-#{topology.name}-#{scheduleName}-#{defs.processor}"
              return done null, {arn, policy}

          params =
            Action: "lambda:InvokeFunction"
            Principal: "events.amazonaws.com"
            SourceArn: arn
            StatementId: "schedule-#{topology.name}-#{scheduleName}-#{defs.processor}"
            FunctionName: functionName

          lambda.addPermission params, (err, results) ->
            log "ADD SCHEDULE #{scheduleName} PERMISSIONS RESULTS", err, results
            done err, {arn, policy}
        
        ({arn, policy}, done) ->
          splitArn = arn.split ':'
          region = splitArn[3]
          accountId = splitArn[4]

          params =
            Rule: "#{topology.name}-#{scheduleName}"
            Targets: [{
              Id: "target-#{topology.name}-#{scheduleName}-#{functionName}"
              Arn: "arn:aws:lambda:#{region}:#{accountId}:function:#{functionName}"
            }]

          cloudWatchEvents.putTargets params, (err, results) ->
            log "PUT TARGETS RESULTS", params, err, params.Targets[0].Id, results
            scheduleId = params.Targets[0].Id
            done err
      ], (err) ->
        next err
    , (err) ->
      callback err, scheduleId

  setupGateway: (config, opts, callback) ->
    region = opts.region || 'us-east-1'
    environment = opts.environment || 'development'
    functionName = "#{config.handler}-#{environment}"

    log "SETUP GATEWAY", region, environment, functionName, config
    apiGateway = new AWS.APIGateway
      region: region
      endpoint: opts.services['AWS:APIGateway'].endpoint

    lambda = new AWS.Lambda
      region: region
      endpoint: opts.services['AWS:Lambda'].endpoint

    async.waterfall [
      (done) ->
        params =
          limit: 500

        apiGateway.getRestApis params, (err, apis) ->   
          log "EXISTING APIS", err, apis
          done err, {apis}
      ({apis}, done) ->
        existing = undefined
        for api in (apis.items || {})
          if api.name is config.name
            existing = api
            break

        if existing
          log "API EXISTS ALREADY"
          done null, {gateway: existing}
        else
          log "API DOESNT EXIST YET"
          params =
            name: config.name

          apiGateway.createRestApi params, (err, gateway) ->
            log "CREATED API", err, gateway
            done err, {gateway}


      # ({gateway}, done) ->
      #   ids = [
      #     "apigateway-#{gateway.name}-star"
      #     "apigateway-#{gateway.name}-any"
      #     "apigateway-#{gateway.name}-proxy"
      #   ]

      #   async.each ids, (id, next) ->
      #     params =
      #       StatementId: id
      #       FunctionName: functionName

      #     lambda.removePermission params, (err, results) ->
      #       log "REMOVE PERMISSIONS RESULTS", id, results
      #       next()
      #   , (err) ->
      #     setTimeout ->
      #       done null, {gateway}
      #     , 30000

      ({gateway}, done) ->
        params =
          restApiId: gateway.id

        apiGateway.getResources params, (err, results) ->
          root = undefined
          for item in (results?.items || [])
            if item.path is '/'
              root = item
              break

          log "GOT ROOT RESOURCE", err, root, results
          done err, {gateway, root, resources: results?.items || []}

      ({gateway, root, resources}, done) ->
        for item in resources
          if item.pathPart is '{proxy+}'
            return done null, {gateway, root, proxy: item}

        params =
          pathPart: '{proxy+}'
          parentId: root.id
          restApiId: gateway.id

        log "CREATING PROXY RESOURCE", params
        apiGateway.createResource params, (err, proxy) ->
          log "CREATED PROXY RESOURCE", err, proxy
          done err, {gateway, root, proxy}

      ({gateway, root, proxy}, done) ->
        iam = new AWS.IAM
          region: region
          endpoint: opts.services['AWS:IAM'].endpoint

        iam.getUser (err, results) ->
          log "GOT ACCOUNT INFO", gateway, results, opts.services['AWS:IAM'].endpoint
          account = results?.User?.UserId
          done err, {gateway, root, account, proxy}

      ({gateway, root, account, proxy}, done) ->
        params =
          restApiId: gateway.id
          resourceId: root.id
          httpMethod: 'ANY'

        apiGateway.getMethod params, (err, results) ->
          if results
            return done null, {gateway, root, account, proxy}

          params =
            restApiId: gateway.id
            resourceId: root.id
            httpMethod: 'ANY'
            authorizationType: "NONE"


          log "CREATING ROOT METHOD", params, results
          apiGateway.putMethod params, (err, results) ->
            log "CREATE ROOT METHOD RESULTS", err, results
            done err, {gateway, root, account, proxy}

      ({gateway, root, account, proxy}, done) ->
        log "CREATE 'ANY' METHOD", gateway, root, account

        params =
          restApiId: gateway.id
          resourceId: proxy.id
          httpMethod: 'ANY'

        apiGateway.getMethod params, (err, results) ->
          if results
            return done null, {gateway, root, account, proxy}

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

          apiGateway.getMethodResponse params, (err, results) ->
            if results
              return next()

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

          apiGateway.getMethodResponse params, (err, results) ->
            if results
              return next()

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
          done err, {gateway, root, account, proxy}

      ({gateway, root, account, proxy}, done) ->
        params =
          FunctionName: functionName

        lambda.getPolicy params, (err, results) ->
          policy = JSON.parse(results?.Policy || '{}')
          done err, {gateway, root, account, policy, proxy}

      ({gateway, root, account, policy, proxy}, done) ->
        for statement in policy.Statement
          if statement.Sid is "apigateway-#{gateway.name}-star"
            return done null, {gateway, root, account, policy}

        params =
          Action: "lambda:InvokeFunction"
          Principal: "apigateway.amazonaws.com"
          SourceArn: "arn:aws:execute-api:#{region}:#{account}:#{gateway.id}/*/*/"
          StatementId: "apigateway-#{gateway.name}-star"
          FunctionName: functionName

        lambda.addPermission params, (err, results) ->
          log "ADD STAR PERMISSIONS RESULTS", results
          done null, {gateway, root, account, policy, proxy}

      ({gateway, root, account, policy, proxy}, done) ->
        for statement in policy.Statement
          if statement.Sid is "apigateway-#{gateway.name}-any"
            return done null, {gateway, root, account, policy}

        params =
          Action: "lambda:InvokeFunction"
          Principal: "apigateway.amazonaws.com"
          SourceArn: "arn:aws:execute-api:#{region}:#{account}:#{gateway.id}/#{environment}/ANY/"
          StatementId: "apigateway-#{gateway.name}-any"
          FunctionName: functionName

        lambda.addPermission params, (err, results) ->
          log "ADD PERMISSIONS RESULTS", results, params
          done null, {gateway, root, account, policy, proxy}

      ({gateway, root, account, policy, proxy}, done) ->
        for statement in policy.Statement
          if statement.Sid is "apigateway-#{gateway.name}-proxy"
            return done null, {gateway, root, account, policy}

        params =
          Action: "lambda:InvokeFunction"
          Principal: "apigateway.amazonaws.com"
          SourceArn: "arn:aws:execute-api:#{region}:#{account}:#{gateway.id}/#{environment}/ANY/{proxy+}"
          StatementId: "apigateway-#{gateway.name}-proxy"
          FunctionName: functionName

        lambda.addPermission params, (err, results) ->
          log "ADD PROXY PERMISSIONS RESULTS", err, results, params
          done null, {gateway, root, account, proxy}

      ({gateway, root, account, proxy}, done) ->
        params =
          restApiId: gateway.id
          stageName: environment

        apiGateway.createDeployment params, (err, deployment) ->
          log "DEPLOYMENT RESULTS", err, deployment
          done err, {gateway, root, account, deployment, proxy}

      ({gateway, root, account, deployment, proxy}, done) ->
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
            done null, {gateway, root, account, deployment, proxy}
          else
            params.stageName = environment
            apiGateway.createStage params, (err, results) ->
              log "CREATE STAGE RESULTS", err, results
              done err, {gateway, root, account, deployment, proxy}

    ], (err, results) ->
      {gateway, root, account} = results || {}
      log "CREATE GATEWAY RESULTS", err, results
      if err
        console.log "GOT ERROR", err

      if opts.simulate
        console.log "API RUNNING AT https://#{gateway.id}.execute-api.#{region}.amazonaws.com/#{environment}/"
      else
        console.log "API RUNNING AT #{opts.services['ATTAK:API'].endpoint}"

      callback err, results

  getStreamName: (topologyName, sourceProcessor, destProcessor) ->
    "#{topologyName}-#{sourceProcessor}-#{destProcessor}"

  createStream: (opts, topology, streamName, callback) ->
    streamOpts =
      ShardCount: opts?.shards || 1
      StreamName: streamName

    kinesis = new AWS.Kinesis
      region: opts.region || 'us-east-1'
      endpoint: opts.services['AWS:Kinesis'].endpoint

    kinesis.createStream streamOpts, (err, results) ->
      callback err, results

  describeStream: (opts, topology, stream, callback) ->
    params =
      StreamName: stream

    kinesis = new AWS.Kinesis
      region: opts.region || 'us-east-1'
      endpoint: opts.services['AWS:Kinesis'].endpoint
    kinesis.describeStream params, (err, results) ->
      callback err, results

  associateStream: (state, stream, lambdaData, opts, callback) ->
    lambda = new AWS.Lambda
      region: opts.region || 'us-east-1'
      endpoint: opts.services['AWS:Lambda'].endpoint

    params = 
      BatchSize: 100
      FunctionName: lambdaData.name
      EventSourceArn: stream.id
      StartingPosition: 'LATEST'

    lambda.createEventSourceMapping params, (err, data) ->
      callback err, data

  triggerStream: (program, stream, data, callback) ->
    console.log "TRIGGER STREAM", stream, data
    
    kinesis = new AWS.Kinesis
      region: program.region || 'us-east-1'
      endpoint: program.endpoints.kinesis

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
    for streamName, stream of (topology.streams || {})
      if stream.from is current and (stream.topic || topic) is topic
        next.push stream.to
    next

  nextByTopic: (topology, current) ->
    next = {}
    for streamName, stream of (topology.streams || {})
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