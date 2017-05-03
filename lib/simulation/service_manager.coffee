async = require 'async'
extend = require 'extend'
AWSAPI = require './services/AWS_API'
Streams = require './services/streams'
StaticHosting = require './services/static_hosting'

class ServiceManager

  setup: (state, opts, configs, callback) ->
    @services = [
      new AWSAPI
      new Streams
      new StaticHosting
    ]

    @handlers = {}
    for defs in @services
      for path in defs.paths
        @handlers[path] = defs

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

      service.setup state, config, (err, endpoint) ->
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