AWS = require 'aws-sdk'
uuid = require 'uuid'
async = require 'async'
extend = require 'extend'
AWSUtils = require '../aws'
queryString = require 'query-string'
BaseComponent = require './base_component'

class Auth extends BaseComponent
  namespace: 'permissions'
  platforms: ['AWS']

  dependencies: [
    'name'
  ]

  simulation:
    services: ->
      'AWS:CognitoIdentity':
        handlers:
          'POST /': @handleCognitoRequest
      'AWS:CognitoIdentityServiceProvider':
        handlers:
          'POST /': @handleCognitoRequest
      'AWS:IAM':
        handlers:
          "POST /": @handleIAMRequest

  create: (path, newDefs, opts) ->
    [
      {
        msg: 'create cognito resources'
        run: (state, done) ->
          async.forEachOf newDefs, (defs, authName, next) ->

            state = extend true, state,
              auth:
                "#{authName}": defs

            AWSUtils.setupCognito authName, state, opts, (err, results) ->
              state = extend true, state,
                auth:
                  "#{authName}":
                    id: results

              next err          
      }
    ]

  delete: (path, oldDefs, callback) ->
    []

  handleGetUser: (data, state, opts, req, res) ->
    res.send """
      <GetUserResponse xmlns="https://iam.amazonaws.com/doc/2010-05-08/">
        <GetUserResult>
          <User>
            <UserId>133713371337</UserId>
            <Path>/division_abc/subdivision_xyz/</Path>
            <UserName>Bob</UserName>
            <Arn>arn:aws:iam::133713371337:user/division_abc/subdivision_xyz/Bob</Arn>
            <CreateDate>2013-10-02T17:01:44Z</CreateDate>
            <PasswordLastUsed>2014-10-10T14:37:51Z</PasswordLastUsed>
          </User>
        </GetUserResult>
        <ResponseMetadata>
          <RequestId>#{uuid.v1()}</RequestId>
        </ResponseMetadata>
      </GetUserResponse>
    """

  handleCreateRole: (data, state, opts, req, res) ->
    console.log "HANDLE CREATE ROLE", req.headers
    randId = (Math.random().toString(36)+'00000000000000000').slice(2, 23)
    res.send """
      <CreateRoleResponse xmlns="https://iam.amazonaws.com/doc/2010-05-08/">
        <CreateRoleResult>
          <Role>
            <Path>/</Path>
            <Arn>arn:aws:iam::133713371337:role/#{data.RoleName}</Arn>
            <RoleName>#{data.RoleName}</RoleName>
            <CreateDate>2012-05-08T23:34:01.495Z</CreateDate>
            <RoleId>#{randId}</RoleId>
          </Role>
        </CreateRoleResult>
        <ResponseMetadata>
          <RequestId>#{uuid.v1()}</RequestId>
        </ResponseMetadata>
      </CreateRoleResponse>
    """

  handleIAMRequest: (state, opts, req, res) =>
    allData = ""
    req.on 'data', (data) -> allData += data.toString()
    req.on 'end', =>
      data = queryString.parse allData

      switch data.Action
        when 'GetUser' then @handleGetUser data, state, opts, req, res
        when 'CreateRole' then @handleCreateRole data, state, opts, req, res

  handleCreateIdentityPool: (state, opts, req, res) ->
    res.send
      IdentityPoolId: "us-east-1:#{uuid.v1()}"
      IdentityPoolName: req.body.IdentityPoolName
      AllowUnauthenticatedIdentities: req.body.AllowUnauthenticatedIdentities

  handleUpdateIdentityPool: (state, opts, req, res) ->
    res.send extend true, req.body,
      IdentityPoolId: uuid.v1()

  handleCreateUserPool: (state, opts, req, res) ->
    res.send
      UserPool:
        Id: uuid.v1()

  handleCreateUserPoolClient: (state, opts, req, res) ->
    res.send
      UserPoolClient:
        ClientId: uuid.v1()
        ClientName: req.body.PoolName

  handleSetIdentityPoolRoles: (state, opts, req, res) ->
    res.status 200
    res.end()

  handleCognitoRequest: (state, opts, req, res) =>
    target = req.headers['x-amz-target']
    [service, action] = target.split '.'

    switch action
      when 'CreateIdentityPool' then @handleCreateIdentityPool arguments...
      when 'UpdateIdentityPool' then @handleUpdateIdentityPool arguments...
      when 'SetIdentityPoolRoles' then @handleSetIdentityPoolRoles arguments...
      when 'CreateUserPool' then @handleCreateUserPool arguments...
      when 'CreateUserPoolClient' then @handleCreateUserPoolClient arguments...
      else
        console.log "Unknown Cognito target", target

module.exports = Auth