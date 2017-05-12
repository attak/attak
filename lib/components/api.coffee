AWS = require 'aws-sdk'
uuid = require 'uuid'
async = require 'async'
extend = require 'extend'
AWSUtils = require '../aws'
BaseComponent = require './base_component'

class API extends BaseComponent
  namespace: 'api'
  platforms: ['AWS']

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

  create: (path, newDefs, opts) ->
    [
      {
        msg: 'Create new API'
        run: (state, done) ->
          console.log "CREATING NEW API", state
          [component, args...] = path
          if component is 'api'
            [property, val] = args
            switch property
              when 'handler'
                gatewayOpts =
                  name: "#{state.name}-#{opts.environment || 'development'}"
                  handler: val

                AWSUtils.setupGateway gatewayOpts, opts, (err, results) ->
                  console.log "GATEWAY RESULTS", err, results
                  state.api = extend true, state.api,
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
        run: (done) ->
          console.log "REMOVING API", path[0], oldDefs
          done()
      }
    ]

  handleCreateRestApis: (state, opts, req, res) ->
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
      opts.target.api.gateway = gateway
      res.json gateway

  handleGetRestApis: (state, opts, req, res) ->
    res.json
      items: []

  handleCreateResource: (state, opts, req, res) ->
    allData = ""
    req.on 'data', (data) -> allData += data.toString()
    req.on 'end', ->
      resource = JSON.parse allData
      console.log "HANDLE CREATE RESOURCE", req.params, resource

      guid = uuid.v1()

      if opts.target.api.resources is undefined
        opts.target.api.resources =
          root:
            id: uuid.v1()
      opts.target.api.resources.proxy =
        id: guid

      res.json opts.target.api.resources.proxy

  handleGetResources: (state, opts, req, res) ->
    console.log 'HANDLE GET RESOURCES', req.params, opts.target
  
    res.json
      item: [{
        id: 'jkwkjmwd2d'
        path: '/'
        resourceMethods:
          ANY: {}
      }]

  handleGetMethod: (state, opts, req, res) ->
    console.log "HANDLE handleGetMethod", req.params.parentResource in [opts.target.api.methods?.proxy?.id, opts.target.api.methods?.root?.id] 

    if req.params.parentResource in [opts.target.api.methods?.proxy?.id, opts.target.api.methods?.root?.id]

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
          'uri': "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:133713371337:function:#{opts.target.api.handler}-#{opts.environment || 'development'}/invocations"
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
    environment = opts.environment || 'development'
    processorName = req.params.functionName.split(environment)[0]
    
    processor = opts.target.processors[processorName] || {}

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

module.exports = API