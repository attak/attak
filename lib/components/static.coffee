fs = require 'fs'
url = require 'url'
AWS = require 'aws-sdk'
async = require 'async'
extend = require 'extend'
nodePath = require 'path'
AWSUtils = require '../aws'
staticHost = require 'node-static'
BaseComponent = require './base_component'

class Static extends BaseComponent
  namespace: 'static'
  dependencies: ['name']

  simulation:
    services: ->
      'ATTAK:Static':
        handlers:
          'GET /:staticName': @handleStaticRequest
          'GET /:staticName/*': @handleStaticRequest
      'AWS:S3':
        handlers:
          'ALL *': @handleS3Request

  create: (path, newDefs, opts) ->
    # Creating a new name is a noop
    [
      msg: 'setup static hosting'
      run: (state, done) ->

        state.static = extend true, state.static, newDefs

        async.forEachOf newDefs, (defs, staticName, next) ->
          AWSUtils.setupStatic state, staticName, opts, (err, results) ->
            next err
        , (err) ->
          done err, state
    ]

  delete: (path, oldDefs, callback) ->
    [
      {
        msg: 'remove static hosting'
        run: (state, done) ->
          done null, state
      }
    ]

  handleS3Request: (state, opts, req, res) ->    
    s3Endpoint = opts.services['AWS:S3'].endpoint
    if req.headers.host isnt url.parse(s3Endpoint).host
      res.send ""
    else
      staticName = req.params.staticName
      if staticName is undefined and req.headers.referer?
        actualPath = req.headers.referer.split(s3Endpoint)[1]
        staticName = actualPath?.split('/')[0]

      staticName = staticName || 'default'

      path = req.url.split("/#{staticName}")[1] || req.url
      if path[0] is '/'
        path = path.slice 1, path.length

      workingDir = opts.workingDir || process.cwd()

      staticDir = nodePath.resolve workingDir, state.static[staticName].dir
      fullPath = "#{staticDir}/#{path}"

      if fs.existsSync(fullPath) and fs.lstatSync(fullPath).isFile()
        stream = fs.createReadStream fullPath
        stream.pipe res
      else
        res.status 404
          .send 'not found'

module.exports = Static