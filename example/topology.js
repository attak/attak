module.exports = {
  name: 'attak-example',
  processors: {
    hello_world_spout: {
      source: './processors/hello_world_spout',
      outputs: ['text']
    },
    reverse: {
      source: './processors/reverse',
      inputs: ['text'],
      outputs: ['text']
    }
  },
  streams: [
    {
      to: 'reverse',
      from: 'hello_world_spout',
      fields: {
        source_field_1: 'processor_field_1'
      }
    }
  ]
};