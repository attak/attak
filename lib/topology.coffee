nodePath = require 'path'

TopologyUtils =
  loadTopology: (opts) ->
    workingDir = opts.cwd || process.cwd()
    topology = opts.topology || require workingDir

    if topology.name is undefined
      throw new Error "Error loading topology: missing name"

    if topology.streams?.constructor is Function
      topology.streams = topology.streams()
    
    for stream, index in (topology.streams || [])
      if stream.constructor is Array
        topology.streams[index] =
          from: stream[0]
          to: stream[1]
          topic: stream[2]

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
    else if topology.processors is undefined and topology.processor.constructor is Function
      processors = {}
      for stream in topology.streams
        if processors[stream.to] is undefined
          processors[stream.to] = stream.to
        if processors[stream.from] is undefined
          processors[stream.from] = stream.from

      topology.processors = processors

    return topology

  getProcessor: (program, topology, name) ->
    workingDir = program.cwd || process.cwd()

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

    if procData.constructor is String
      source = procData
    else if procData?.constructor is Function or typeof(procData?.constructor) is 'function'
      source = procData
    else
      source = procData.source

    if source.handler
      processor = source
    else if source.constructor is Function
      processor = {handler: source}
    else
      processor = program.processor || require nodePath.resolve(workingDir, source)

module.exports = TopologyUtils