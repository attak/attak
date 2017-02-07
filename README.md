# attak

*Setup TB-scale realtime streaming distributed computation in minutes at a fraction of the cost*

**attak** helps you string together "serverless" functions and message queues to create distributed compute topologies. It aims to be platform agnostic, beginning with support for AWS and Google Cloud.

### Status

pre-alpha software - not for production use

#### Roadmap

- [AWS Lambda](https://aws.amazon.com/lambda)/[AWS Kinesis](https://aws.amazon.com/kinesis) topologies √
- [Fission](https://github.com/fission/fission)/[PubSub](https://cloud.google.com/pubsub) topologies
- Distributed debugging UI

## Installation

`npm install -g attak`

## Motivation

Serverless functions are awesome because single-purpose microservices are a great way to organize code. However, real-world use cases often require multiple microservices, and then things get complicated - suddenly you have to figure out how to communicate between microservices in a fault tolerant way, how to manage them together, etc.

**attak** is built to combine existing AWS products (Lambdas, Kinesis Streams, CloudWatch, and more) to create a more complete solution to building a distributed compute infrastructure. Compare **attak** to products like Apache Storm

## Why use **attak**?

Traditional distributed computation frameworks like Apache Storm can be cumbersome and opaque, and they require multiple dedicated servers to run in any kind of production way ([this popular example](https://github.com/nathanmarz/storm-deploy) uses 4 m1-large EC2 instances). Using AWS auto-scaling building blocks and modern tooling/frameworks, we can build an easy to use topology system that costs far less to run and work with.

## Usage

In order to get a topology running you need to build a topology file and define one or more processors.

### Topology file

An attak topology is simply a javascript or raw JSON file that we `require`. At its core, a topology is a description of one or more processors and the connections between them. Here's an example of a very simple topology.

```
module.exports = {
  name: 'attak-example',                          // a topology name is required
  processors: {                                   // declare processors
    hello_world_spout: './processors/hello_world'
    reverse: './processors/reverse'
  },
  streams: [                                      // declare processor connections
    {
      to: 'reverse',                              // simple connection example
      from: 'hello_world_spout'
    }
  ]
}
```

### Processors

**attak** has a single concept for all data processing units: processors. In the abstract a processor is triggered in response to some event. The processor can access event data if any, and can emit any number of new events. Here's an example processor:

```js
exports.handler = function(event, context, callback) {
  console.log(event);                             // prints 'hello world'
  reversed = event.split('').reverse().join('')   // process event data (reverse it)
  context.emit('reversed strings', reversed)      // emit a "reversed strings" event
  callback()                                      // close up shop
}
```

### Simulate a topology

`attak simulate`

Simulate pulls in data (from `./input.json` by default) and feeds it through the specified processors. Input data has the following format:

```
{
    "processor_name": {"the_data": "you want to be sent in"},
    "other_processor": "string data is fine",
}
```

### Deploy a topology

`attak deploy`

Assembles and deploys a series of functions pre-baked with topology information, so event emissions go directly from function to stream to function.

### Trigger a live topology

`attak trigger`

Pulls in data (from `./input.json` by default) and sends it to a live topology instance
