request = require('request');
exports.handler = function(event, context, callback) {
	let identity = context.clientContext.identity;
	let bearer = identity.token;
	let url = identity.url.replace('/identity', '/git/github/branches');

	request(url, {'auth': {'bearer': bearer}}, function(error, response, body) {
		callback(null, {
			statusCode: 200,
			body: JSON.stringify({'error': error, 'body': body}),
		});
	});


}
