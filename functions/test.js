request = require('request');
exports.handler = function(event, context, callback) {

	callback(null, {
		statusCode: 200,
		body: `I'm at ${process.env.DEPLOY_URL}`,
	});
}
