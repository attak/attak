
TopologyUtils =
  load: (opts) ->
    workingDir = opts.cwd || process.cwd()
    topology = opts.topology || require workingDir

    if topology.streams.constructor is Function
      topology.streams = topology.streams()
      for stream in topology.streams
        if stream.constructor is Array
          stream =
            from: stream[0]
            to: stream[1]

    if topology.processors?.constructor is Function
      topology.processors = topology.processors()

    else if topology.processors.constructor is String
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

module.exports = TopologyUtils