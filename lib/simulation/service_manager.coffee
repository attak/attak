IAM = require './services/iam'
async = require 'async'
extend = require 'extend'
AWSAPI = require './services/AWS_API'
Streams = require './services/streams'
Gateway = require './services/gateway'
StaticHosting = require './services/static_hosting'

class ServiceManager

  setup: (state, opts, configs, callback) ->
    @services = [
      new IAM
      new AWSAPI
      new Streams
      new Gateway
      new StaticHosting
    ]

    @handlers = {}
    for service in @services
      for path in service.paths
        @handlers[path] = service

    settingUp = {}
    async.forEachOf configs, (config, serviceKey, next) =>
      config.services = @handlers
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

      setupOpts = extend opts, config

      service.setup state, config, opts, (err, endpoint) ->
        service.isSetup = true
        delete settingUp[service.guid]
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