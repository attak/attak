S3 = require './services/S3'
API = require './services/api'
IAM = require './services/iam'
async = require 'async'
extend = require 'extend'
AWSAPI = require './services/AWS_API'
Streams = require './services/streams'
Gateway = require './services/gateway'
StaticHosting = require './services/static_hosting'
CloudWatchEvents = require './services/cloudwatch_events'

class ServiceManager

  constructor: (@options) ->
    @app = @options.app

  setup: (state, opts, configs, callback) ->
    @services = [
      new S3 @
      new API @
      new IAM @
      new AWSAPI @
      new Streams @
      new Gateway @
      new StaticHosting @
      new CloudWatchEvents @
    ]

    @handlers = {}
    for service in @services
      for path in service.paths
        @handlers[path] = service

    if opts.simulation in [false, undefined]
      return callback null, @handlers

    settingUp = {}
    async.forEachOf configs, (config, serviceKey, next) =>
      service = @handlers[serviceKey]

      if service is undefined
        return next()

      # If this service is setup already skip it
      if service.isSetup
        return next()

      # If we're already setting up the service that'll handle this key, skip
      if settingUp[service.guid]
        return next()

      settingUp[service.guid] = service
      setupOpts = extend true, opts, config
      setupOpts.services = @handlers

      service.setup config, setupOpts, (err, endpoint) =>
        service = @handlers[serviceKey]
        service.isSetup = true
        settingUp[service.guid] = undefined
        next err
    , (err) =>
      callback err, @handlers

  stopAll: (callback) ->
    async.each @services, (service, next) ->
      service.stop ->
        next()
    , (err) ->
      callback err

module.exports = ServiceManager