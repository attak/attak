exports.handler = function(event, context, callback) {
  console.log("GOT STUFF IN REVERSE", event, context);
  context.emit('reversed', event.text.split('').reverse().join(''));
}