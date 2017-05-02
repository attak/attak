async = require 'async'
AWSAPI = require './services/AWS_API'
Streams = require './services/streams'
StaticHosting = require './services/static_hosting'

class ServiceManager

  setup: (topology, opts, configs, callback) ->
    services = [
      new AWSAPI
      # new Streams
      new StaticHosting
    ]

    @handlers = {}
    for service in services
      for path in service.paths
        @handlers[path] = service

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
      service.setup topology, config, (err, endpoint) ->
        service.isSetup = true
        delete settingUp[service.guid]
        next err
    , (err) =>
      callback err, @handlers

module.exports = ServiceManager