'use strict';

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.default = {
  'name': 'deploy-test',
  'processors': { 'hello': function hello(event, context, callback) {
      return callback(null, {
        event: event,
        context: context,
        resp: {
          ok: true
        }
      });
    } }
};