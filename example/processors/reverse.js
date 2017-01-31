exports.handler = function(event, context, callback) {
  console.log("GOT STUFF IN REVERSE", event, context);
  callback(null, event.text.split().reverse().join());
}