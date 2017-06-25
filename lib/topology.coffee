nodePath = require 'path'

TopologyUtils =
  loadTopology: (opts) ->
    workingDir = opts.cwd || process.cwd()
    environment = opts.environment || 'development'

    if opts.topology
      if opts.topology.constructor is String
        topology = require nodePath.resolve(workingDir, opts.topology)
      else
        topology = opts.topology
    else
      topology = require workingDir

    if topology.streams?.constructor is Function
      topology.streams = topology.streams()
    
    if topology.streams?.constructor is Array
      streamsObj = {}
      for streamName, stream of (topology.streams || {})
        if stream.constructor is Array
          stream =
            from: stream[0]
            to: stream[1]
            topic: stream[2]
        streamName = "#{topology.name}-#{stream.from}-#{stream.to}-#{environment}"
        streamsObj[streamName] = stream
      topology.streams = streamsObj

    if topology.processors?.constructor is Function
      topology.processors = topology.processors()

    else if topology.processors?.constructor is String
      processorPath = nodePath.resolve(workingDir, topology.processors)
      files = fs.readdirSync processorPath
      
      processors = {}
      for file in files
        if file is '.DS_Store'
          continue
        name = nodePath.basename file, nodePath.extname(file)
        processors[name] = "#{topology.processors}/#{file}"

      topology.processors = processors

    # If we don't specify all processors at once, we can give
    # a function 'topology.processor' that takes a processor
    # name and returns a processor. We look at streams on the
    # topology to find the full list of processors used.
    else if topology.processors is undefined and topology.processor?.constructor is Function
      processors = {}
      for streamName, stream of topology.streams
        if processors[stream.to] is undefined
          processors[stream.to] = stream.to
        if processors[stream.from] is undefined
          processors[stream.from] = stream.from

      topology.processors = processors

    for procName, procData of (topology.processors || {})
      if procData.constructor is String
        topology.processors[procName] =
          path: procData

    if topology.api?.constructor is String
      objDefs =
        handler: topology.api
      topology.api = objDefs

    if topology.static
      if topology.static.constructor is String
        topology.static =
          default:
            dir: topology.static
      else if topology.static.dir
        topology.static =
          default: topology.static

    if topology.auth
      if topology.auth is true
        topology.auth =
          default: {}

    return topology

  getProcessor: (opts, topology, name) ->
    workingDir = opts.cwd || process.cwd()

    if topology.processor
      procData = topology.processor name
    else if topology.processors.constructor is String
      procData = "#{topology.processors}/#{name}"
    else if topology.processors.constructor is Function
      procData = topology.processors()[name]
    else
      procData = topology.processors[name]

    if procData is undefined
      throw new Error "Failed to find processor #{name}"

    loading = {}
    if procData.constructor is String
      loading =
        type: 'path'
        path: procData
    else if procData?.constructor is Function
      loading =
        type: 'dynamic'
        impl: procData
    else if procData?.handler is Function
      loading =
        type: 'dynamic'
        impl: procData.handler
    else if procData?.source or procData?.path
      loading =
        type: 'path'
        path: procData.path
    else
      loading =
        type: 'dynamic'
        impl: procData

    switch loading.type
      when 'path'
        loading.impl = opts.processor || require nodePath.resolve(workingDir, loading.path)

    return loading

module.exports = TopologyUtils