[![Attak Distributed Computing Framework](./lib/img/readme.png)](http://attak.io)

ATTAK is a framework that helps you string together serverless functions and message queues to create distributed compute topologies. It aims to be platform agnostic, beginning with support for AWS and Google Cloud.

# Contents

* [Quick Start](#quick-start)
* [Examples](#examples)
* [Components](#components)
  * [Topologies](#topologies)
  * [Processors](#processors)
* [Debugging](#debugging)
  * [Topology Debugger](#topology-debugger)
  * [CLI Simulation](#cli-simulation)

# <a name="quick-start"></a>Quick Start

## Install cli

`npm install -g attak`

## Create an attak topology

Generate a simple boilerplate project by running:

`attak init`

## Setup environment

Rename `.env.example` to `.env` and put in values as appropriate for your deploy. The required fields are:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_ROLE_ARN`

## Topology simulation and debugging

Visit [the ATTAK ui](http://attak.io#local) and run the simulation with the command displayed, which will look like:

`attak simulate -i [simulation id]`

If you want to run the topology without the UI debugger, simply run

`attak simulate` 

## Deploy the topology

ATTAK will deploy all processors and streams in the topology.

```attak deploy```

# <a name="examples"></a>Examples

- [Simple hello world](http://github.com/attak/attak-hello-world) - Emit some text and reverse it
- [Stream github events](http://github.com/attak/attak-github-events) - Monitor the GitHub Events API for updates and process the results

# <a name="components"></a>Components

## <a name="topologies"></a>Topologies

An topology is a structure that defines the features of your application. An ATTAK project is meant to be a node package, so we will `require` the directory, and `index.js` (or whatever is specified in `package.json`) will be loaded.

At its core, a topology is a description of one or more processors and the connections between them. Here's an example of a very simple topology. Processors is a key-value map between processor name and procesor definition, and streams is an array of processor connections.

```js
module.exports = {
  name: 'attak-example',
  processors: {
    reverse: './processors/reverse',
    hello_world_spout: './processors/hello_world'
  },
  streams: [
    ['hello_world_spout', 'reverse']
  ]
}
```

### Processor definitions

We have several ways to define processors on our topology.

#### Inline definition

Processor handler functions can be defined inline

```js
module.exports = {
  processors: {
    inlineProcessor: function(event, context, callback) {
      // process the event...
      event.total += 1
      context.emit('topic name', {your: 'data'})
      callback()
    }
  }
}
```

#### Processor folders

If all processors are in a single folder, processors can be set to the folder path.

```js
module.exports = {
  processors: './processors'
}
```

#### Dynamic definitions

If we want to dynamically generate processors, we have two options.

We can define a function that will return an key-value map of processor name to processor definitions:

```js
module.exports = {
  processors: function() {
    var processors = []
    
    for (var iProcessor=0; iProcessor<10; ++iProcessor) {
      processors.push(
        function(event, context, callback) {
          ...your processor logic...
        }
      )
    }

    return processors
  }
}
```

Or we can define a function that takes a processor name and returns processor definitions:

```js
module.exports = {
  processor: function(name) {
    return function(event, context, callback) {
        ...your processor logic...
    }
  }
}
```

### Stream definitions

Streams setup the flow of data between processors. They can be defined as a static array or dynamic function.

#### Static stream array

The simplest and most common type of stream definition:

```js
module.exports = {
  streams: [
    // Connections can either be an array of strings
    ['processor1', 'processor2'],
    
    // Or an object structure for with options
    {
      from: 'processor4',
      to: 'processor5',
      shards: 50
    }
  ]
}
```

## <a name="processors"></a>Processors

### Handler functions

Processors are simply functions that can be called with an event and context. It may emit any number of events, and must call the callback when finished. A handler funtion takes the following form:

```js
module.exports = {
  handler: function(event, context, callback) {
    console.log(event); // prints {name: 'world'}
    context.emit('output topic', `hello ${event.name}`)
    callback()
  }
}
```

### Emitting data

Processors can emit any number of events on any number of topics.

```js
handler: function(event, context, callback) {
  // Data emitted can be any type, and may be undefined
  context.emit('processing started')
  context.emit('got event', event)

  // If emitting a large number of items, it's safest to
  // do it asynchronously
  context.emit('frequent', 'event', function(err) {
    console.log('done emitting')

    // The handler must call the callback. We can emit
    // errors if we have them
    if (err) {
      callback(err)
    } else {
      callback()
    }
  })
}
```
