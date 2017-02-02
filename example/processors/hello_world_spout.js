exports.handler = function(event, context, callback) {
  context.emit('hello world', {text: 'hello world'})
  callback();
}