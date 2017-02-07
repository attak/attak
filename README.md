# attak

*Setup TB-scale realtime streaming distributed computation in minutes at a fraction of the cost*

**attak** helps you string together "serverless" functions and message queues to create distributed compute topologies. It aims to be platform agnostic, beginning with support for AWS and Google Cloud.

### Status

pre-alpha software - not for production use

#### Roadmap

- Basic Topology Support
  - (AWS) [Lambda](https://aws.amazon.com/lambda)/[Kinesis](https://aws.amazon.com/kinesis) topologies √
  - (GCloud) [Fission](https://github.com/fission/fission)/[PubSub](https://cloud.google.com/pubsub) topologies
  - Others? Open an issue! We'd love to hear about your use case.
- Sources
  - Clock events
  - DynamoDB/BigTable
  - Webhooks

## Installation

`npm install -g attak`

## Motivation

Serverless functions are awesome because single-purpose microservices are a great way to organize code. However, real-world use cases often require multiple microservices, and communicating between them in a fault tolerant way takes some thought.

Existing solutions like Apache Storm use queues to stream data between functions, but require special hosting which can be expensive and cumbersome. They're also mostly focused on Java and JVM technologies.

**attak** is built to combine existing, proven products (Lambdas, Kinesis Streams, Kubernetes, PubSub, etc.) to create a better solution using more modern technologies.

## Why use **attak**?

***attak** has several advantages*:

***Speed and Simplicity***

It's just node (or whatever shell processes you want to call)

Running a local Storm topology can take several minutes (you have to compile an uber-jar and then boot up the JVM and all the bolt/spout processes). Simulating an **attak** topology takes seconds.

***Price***

Apache Storm requires several dedicated servers to run. [this popular example](https://github.com/nathanmarz/storm-deploy) uses 4 m1-large EC2 instances which costs something like $500/mo even when inactive.

**attak** uses auto-scaling building blocks, so it mostly sits idle when not in use. An inactive topology will likely cost under $10/mo, and will be significantly cheaper at scale also.

***Debugging***

Serverless functions and queuing systems have existing error handling solutions, so any existing debugging infrastructure will still work. For instance, logs from AWS Lambdas are automatically sent to CloudWatch, where they can be easly monitored.

***Maintenance***

**attak** uses auto-scaling components, so there are no servers to be juggled, no CPUs or disks to monitor, no logs to rotate, etc. Everything just works...and did we mention it's cheaper?

## Usage

In order to get a topology running you need to build a topology file and define one or more processors.

### Topology file

An attak topology is simply a javascript or raw JSON file that we `require`. At its core, a topology is a description of one or more processors and the connections between them. Here's an example of a very simple topology.

```js
module.exports = {
  name: 'attak-example',                          // a topology name is required
  processors: {                                   // declare processors
    reverse: './processors/reverse',
    hello_world_spout: './processors/hello_world'
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
