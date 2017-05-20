AWS = require 'aws-sdk'
uuid = require 'uuid'
async = require 'async'
extend = require 'extend'
AWSUtils = require '../aws'
BaseComponent = require './base_component'

class API extends BaseComponent
  namespace: 'api'
  platforms: ['AWS']

  dependencies: [
    'name'
    'processors'
  ]

  simulation:
    services: ->
      'AWS:APIGateway':
        handlers:
          "GET /restapis": @handleGetRestApis
          "POST /restapis": @handleCreateRestApis
          "GET /restapis/:apiId/stages": @handleGetStages
          "POST /restapis/:apiId/stages": @handlePostStages
          "GET /restapis/:apiId/resources": @handleGetResources
          "POST /restapis/:apiId/deployments": @handleCreateDeployment
          "POST /restapis/:apiId/resources/:parentResource": @handleCreateResource
          "PUT /restapis/:apiId/resources/:parentResource/methods/:method": @handlePutMethod
          "GET /restapis/:apiId/resources/:parentResource/methods/:method": @handleGetMethod
          "PUT /restapis/:apiId/resources/:parentResource/methods/:method/integration": @handlePutMethodIntegration
          "GET /restapis/:apiId/resources/:parentResource/methods/:method/responses/:statusCode": @handleGetMethodResponse
          "PUT /restapis/:apiId/resources/:parentResource/methods/:method/responses/:statusCode": @handlePutMethodResponse
          "PUT /restapis/:apiId/resources/:parentResource/methods/:method/integration/responses/:statusCode": @handlePutIntegrationResponse

      'AWS:Lambda':
        handlers:
          "GET /:apiVersion/functions/:functionName/policy": @handleGetPolicy
          "POST /:apiVersion/functions/:functionName/policy": @handlePostPolicy

      'ATTAK:API':
        handlers:
          'ALL /*': @handleRequest

  create: (path, newDefs, opts) ->
    [
      {
        msg: 'Create new API'
        run: (state, done) ->
          console.log "CREATING NEW API", path, newDefs, state
          [component, args...] = path
          if component is 'api'
            [property, val] = args
            switch property
              when 'handler'
                gatewayOpts =
                  name: "#{state.name}-#{opts.environment || 'development'}"
                  handler: newDefs

                console.log "SETUP CONFIG", gatewayOpts
                AWSUtils.setupGateway gatewayOpts, opts, (err, results) ->
                  console.log "GATEWAY RESULTS", err, results
                  state.api = extend true, state.api,
                    name: gatewayOpts.name
                    handler: newDefs
                    resources:
                      root: results.root
                      proxy: results.proxy
                    gateway: results.gateway
                    deployment: results.deployment

                  done null, state
              else
                console.log "UNKNOWN API PROPERTY CHANGE EVENT", property
          else
            console.log "API CHANGE THAT ISNT FROM API", path, newDefs
      }
    ]

  delete: (path, oldDefs, opts) ->
    [
      {
        msg: 'Remove API'
        run: (state, done) ->
          console.log "REMOVING API", path[0], oldDefs
          done()
      }
    ]

  handleCreateRestApis: (state, opts, req, res, done) ->
    console.log "HANDLE CREATE REST API", req.url, req.body, req.headers
    allData = ""
    req.on 'data', (data) -> allData += data.toString()
    req.on 'end', ->
      apiDefs = JSON.parse allData
      guid = uuid.v1()

      gateway =
        id: guid
        name: apiDefs.name

      console.log "SENDING BACK GATEWAY DEFS", gateway
      
      state = extend true, state,
        api:
          gateway: gateway

      res.json gateway
      done null

  handleGetRestApis: (state, opts, req, res) ->
    res.json
      item: []

  handleCreateResource: (state, opts, req, res, done) ->
    allData = ""
    req.on 'data', (data) -> allData += data.toString()
    req.on 'end', ->
      resource = JSON.parse allData
      console.log "HANDLE CREATE RESOURCE", req.params, resource

      if resource.pathPart.indexOf('proxy') isnt -1
        resourceType = 'proxy'
      else
        resourceType = 'root'

      state = extend true, state,
        api:
          resources:
            "#{resourceType}":
              id: uuid.v1()

      res.json state.api.resources.proxy
      done null, state

  handleGetResources: (state, opts, req, res, done) ->
    console.log 'HANDLE GET RESOURCES', req.params
  
    guid = uuid.v1()
    if state.api?.resources?.root?.id is undefined
      state = extend true, state,
        api:
          resources:
            root:
              id: guid

    res.json
      item: [{
        id: guid
        path: '/'
        resourceMethods:
          ANY: {}
      }]

    done null, state


  handleGetMethod: (state, opts, req, res) ->
    console.log "HANDLE handleGetMethod", req.params.parentResource in [state.api?.methods?.proxy?.id, state.api?.methods?.root?.id]

    if req.params.parentResource in [state.api?.methods?.proxy?.id, state.api?.methods?.root?.id]

      res.json
        'httpMethod': 'ANY'
        'authorizationType': 'NONE'
        'apiKeyRequired': false
        'methodResponses':
          '200':
            'statusCode': '200'
            'responseModels': 'application/json': 'Empty'
          '201':
            'statusCode': '201'
            'responseParameters': 'method.response.header.Location': true
            'responseModels': 'application/json': 'Empty'
          '301':
            'statusCode': '301'
            'responseParameters': 'method.response.header.Location': true
            'responseModels': 'application/json': 'Empty'
          '302':
            'statusCode': '302'
            'responseParameters': 'method.response.header.Location': true
            'responseModels': 'application/json': 'Empty'
          '404':
            'statusCode': '404'
            'responseModels': 'application/json': 'Empty'
        'methodIntegration':
          'type': 'AWS_PROXY'
          'httpMethod': 'POST'
          'uri': "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:133713371337:function:#{state.api.handler}-#{opts.environment || 'development'}/invocations"
          'passthroughBehavior': 'WHEN_NO_MATCH'

    else
      res.status 400
      res.header 'x-amzn-errortype', 'ResourceNotFoundException'
      res.json
        message: "Method not found"

  handlePutMethod: (state, opts, req, res) ->
    console.log "HANDLE handlePutMethod", req.params, req.body

    res.json
      statusCode: '301'
      responseParameters:
        'method.response.header.Location': true
        responseModels:
          'application/json': 'Empty'

  handlePutMethodResponse: (state, opts, req, res) ->
    res.json ok: true

  handleGetMethodResponse: (state, opts, req, res) ->
    res.status 400
    res.header 'x-amzn-errortype', 'ResourceNotFoundException'
    res.json
      message: "Method response not found"

  handlePutMethodIntegration: (state, opts, req, res) ->
    res.json ok: true

  handlePutIntegrationResponse: (state, opts, req, res) ->
    res.json ok: true

  handleGetPolicy: (state, opts, req, res) ->
    console.log "HANDLE GET POLICY", req.params
    environment = opts.environment || 'development'
    processorName = req.params.functionName.split(environment)[0]
    
    processor = state.processors?[processorName] || {}

    policy =
      Id: "default"
      Version: "2012-10-17"
      Statement: []

    for id, defs of (processor.policies || {})
      policy.Statement.push
        Sid: id
        Effect: 'Allow'
        Resource: "arn:aws:lambda:us-east-1:133713371337:function:#{req.params.functionName}"

    res.json
      Policy: JSON.stringify policy

  handlePostPolicy: (state, opts, req, res) ->
    res.json ok: true

  handleCreateDeployment: (state, opts, req, res) ->
    res.json
      id: uuid.v1()

  handleGetStages: (state, opts, req, res) ->
    res.json item: []

  handlePostStages: (state, opts, req, res) ->
    res.json ok: true

  handleRequest: (state, opts, req, res) ->
    awsLambda = new AWS.Lambda
      apiVersion: '2015-03-31'
      endpoint: opts.services['AWS:Lambda'].endpoint

    event =
      path: req.url
      body: req.body
      headers: req.headers
      httpMethod: req.method
      queryStringParameters: req.query

    functionName = AWSUtils.getFunctionName state.name, state.api.handler, opts.environment || 'development'

    params = 
      Payload: new Buffer JSON.stringify(event)
      FunctionName: functionName
      InvocationType: 'Event'

    awsLambda.invoke params, (err, results) ->
      if err
        res.status 400
        res.header 'x-amzn-errortype', 'ResourceNotFoundException'
        res.json
          message: "Method not found"
      else
        res.send results.Payload

module.exports = API