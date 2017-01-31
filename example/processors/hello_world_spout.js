exports.handler = function(event, context, callback) {
  console.log(arguments);
  context.emit({text: 'hello world'})
  callback();
}