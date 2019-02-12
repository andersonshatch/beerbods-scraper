expect = require('chai').expect
nock = require 'nock'

process.env.UNTAPPD_CLIENT_ID = 'not-real-id'
process.env.UNTAPPD_CLIENT_SECRET = 'not-real-secret'
scraper = require '../src/beerbods-scraper'

beforeEach ->
	do nock.disableNetConnect

afterEach ->
	global.nockBeerbodsSite.done()

describe 'beerbods api with untappd credentials', ->
	config = new scraper.config(["This week's test", "Next week's test"], "shall be", '/thebeers', 0, {
		clientId: "not-real-id",
		clientSecret: "not-real-secret"
	})

	beforeEach ->
		@nockUntappd = nock("https://api.untappd.com")
		@searchUrl = "/v4/search/beer?q=#{encodeURIComponent 'The Dharma Initiative Beer?'}&limit=5&client_id=not-real-id&client_secret=not-real-secret&access_token="
		@infoUrl = '/v4/beer/info/481516?compact=true&client_id=not-real-id&client_secret=not-real-secret&access_token='
		global.nockBeerbodsSite = nock("https://beerbods.co.uk")
			.get("/thebeers")
			.replyWithFile(200, __dirname + '/replies/valid.html')

	afterEach ->
		@nockUntappd.done()

	context 'mock services return valid responses, 1 match on untappd', ->
		expected = require './expected/current-output-plus-untappd.json'
		beforeEach ->
			@nockUntappd.get(@searchUrl)
				.replyWithFile(200, __dirname + '/replies/untappd/valid-search.json')
			@nockUntappd.get(@infoUrl)
				.replyWithFile(200, __dirname + '/replies/untappd/valid-info.json')

		it 'produces json with info on the beer with populated untappd data', (done) ->
			output = null
			scraper.scrapeBeerbods config, (result) ->
				output = result
				expect(output).is.not.null
				expect(output).to.eql expected
				done()

	context 'mock services return valid responses, 1 match on untappd with 1 rating, no abv', ->
		expected = require './expected/current-output-plus-untappd-one-rating-no-abv.json'
		beforeEach ->
			@nockUntappd.get(@searchUrl)
				.replyWithFile(200, __dirname + '/replies/untappd/valid-search.json')
			@nockUntappd.get(@infoUrl)
				.replyWithFile(200, __dirname + '/replies/untappd/valid-info-one-rating-no-abv.json')

		it 'produces json with info on the beer with populated untappd data', (done) ->
			output = null
			scraper.scrapeBeerbods config, (result) ->
				output = result
				expect(output).is.not.null
				expect(output).to.eql expected
				done()

	context 'mock services return valid responses, several matches on untappd', ->
		expected = require './expected/current-output-sans-untappd.json'
		expected = [expected[0]]
		beforeEach ->
			@nockUntappd.get(@searchUrl)
				.replyWithFile(200, __dirname + '/replies/untappd/valid-search-with-more-than-one-result.json')

		it 'produces json with info on the beer, but no untappd data', (done) ->
			output = null
			scraper.scrapeBeerbods config, (result) ->
				output = result
				expect(output).is.not.null
				expect(expected).to.eql output
				done()

	context 'mock services return valid responses, several matches on untappd, ony one in production', ->
		expected = require './expected/current-output-plus-untappd.json'
		beforeEach ->
			@nockUntappd.get(@searchUrl)
				.replyWithFile(200, __dirname + '/replies/untappd/valid-search-only-one-in-production-beer.json')
			@nockUntappd.get(@infoUrl)
				.replyWithFile(200, __dirname + '/replies/untappd/valid-info.json')

		it 'produces json with info on the beer and populated untappd data for the in production beer', (done) ->
			output = null
			scraper.scrapeBeerbods config, (result) ->
				output = result
				expect(output).is.not.null
				expect(output).to.eql expected
				done()

	context 'mock untappd fails twice, then succeeds', ->
		expected = require './expected/current-output-plus-untappd.json'
		beforeEach ->
			@nockUntappd.get(@searchUrl)
				.replyWithError("intentional mock request fail")
			@nockUntappd.get(@searchUrl)
				.reply(500, '', [])
			@nockUntappd.get(@searchUrl)
				.replyWithFile(200, __dirname + '/replies/untappd/valid-search.json')
			@nockUntappd.get(@infoUrl)
				.reply(500, '', [])
			@nockUntappd.get(@infoUrl)
				.replyWithError("intentional mock request fail")
			@nockUntappd.get(@infoUrl)
				.replyWithFile(200, __dirname + '/replies/untappd/valid-info.json')

		it 'produces json with info on the beer with populated untappd data having retried', (done) ->
			output = null
			scraper.scrapeBeerbods config, (result) ->
				output = result
				expect(output).is.not.null
				expect(output).to.eql expected
				done()

	context 'mock untappd search fails three times', ->
		expected = require './expected/current-output-sans-untappd.json'
		expected = [expected[0]]
		beforeEach ->
			@nockUntappd.get(@searchUrl)
				.replyWithError("intentional mock request fail")
			@nockUntappd.get(@searchUrl)
				.reply(500, '', [])
			@nockUntappd.get(@searchUrl)
				.reply(404, '', [])

		it 'produces json with info on the beer, but no untappd data', (done) ->
			output = null
			scraper.scrapeBeerbods config, (result) ->
				output = result
				expect(output).to.eql expected
				done()

	context 'mock untappd search returns bad data repeatedly', ->
		expected = require './expected/current-output-sans-untappd.json'
		expected = [expected[0]]
		beforeEach ->
			@nockUntappd.get(@searchUrl)
				.reply(200, 'unexpected error', [])
			@nockUntappd.get(@searchUrl)
				.reply(200, '""', [])
			@nockUntappd.get(@searchUrl)
				.reply(200, '{"response": "sorry"}', [])

		it 'produces json with info on the beer, but no untappd data', (done) ->
			output = null
			scraper.scrapeBeerbods config, (result) ->
				output = result
				expect(output).to.eql expected
				done()

	context 'mock untappd beer lookup fails three times', ->
		expected = require './expected/current-output-sans-untappd.json'
		expected = [expected[0]]
		beforeEach ->
			@nockUntappd.get(@searchUrl)
				.replyWithFile(200, __dirname + '/replies/untappd/valid-search.json')
			@nockUntappd.get(@infoUrl)
				.replyWithError("intentional mock request fail")
			@nockUntappd.get(@infoUrl)
				.reply(404, '', [])
			@nockUntappd.get(@infoUrl)
				.reply(500, '', [])

		it 'produces json with info on the beer, but no untappd data', (done) ->
			output = null
			scraper.scrapeBeerbods config, (result) ->
				output = result
				expect(output).to.eql expected
				done()

	context 'mock untappd beer lookup returns bad data at first', ->
		expected = require './expected/current-output-plus-untappd.json'
		expected = [expected[0]]
		beforeEach ->
			@nockUntappd.get(@searchUrl)
				.replyWithFile(200, __dirname + '/replies/untappd/valid-search.json')
			@nockUntappd.get(@infoUrl)
				.reply(200, 'we are down', [])
			@nockUntappd.get(@infoUrl)
				.reply(200, '""', [])
			@nockUntappd.get(@infoUrl)
				.replyWithFile(200, __dirname + '/replies/untappd/valid-info.json')

		it 'produces json with info on the beer with populated untappd data having retried', (done) ->
			output = null
			scraper.scrapeBeerbods config, (result) ->
				output = result
				expect(output).to.eql expected
				done()


	context 'mock untappd beer lookup returns bad data repeatedly', ->
		expected = require './expected/current-output-sans-untappd.json'
		expected = [expected[0]]
		beforeEach ->
			@nockUntappd.get(@searchUrl)
				.replyWithFile(200, __dirname + '/replies/untappd/valid-search.json')
			@nockUntappd.get(@infoUrl)
				.reply(200, 'we are down', [])
			@nockUntappd.get(@infoUrl)
				.reply(200, '""', [])
			@nockUntappd.get(@infoUrl)
				.reply(200, '{"response": "sorry"}', [])

		it 'produces json with info on the beer, but no untappd data', (done) ->
			output = null
			scraper.scrapeBeerbods config, (result) ->
				output = result
				expect(output).to.eql expected
				done()

describe 'beerbods api with untappd credentials and multiple beer week', ->
	config = new scraper.config(["This week's test", "Next week's test"], "is", '/thebeers', 0)

	beforeEach ->
		@nockUntappd = nock("https://api.untappd.com")
		global.nockBeerbodsSite = nock("https://beerbods.co.uk")
			.get("/thebeers")
			.replyWithFile(200, __dirname + '/replies/valid-multiple-beer-week.html')

	afterEach ->
		@nockUntappd.done()

	context 'mock services return valid responses, multiple beer week', ->
		expected = require './expected/current-output-plus-untappd-multiple-beer-week.json'
		beforeEach ->
			@nockUntappd.get("/v4/search/beer?q=#{encodeURIComponent 'Hillstown Brewery Saturn + Saucer'}&limit=5&client_id=not-real-id&client_secret=not-real-secret&access_token=")
				.replyWithFile(200, __dirname + '/replies/untappd/valid-search.json')
			@nockUntappd.get("/v4/search/beer?q=#{encodeURIComponent 'Hillstown Brewery Pamoja'}&limit=5&client_id=not-real-id&client_secret=not-real-secret&access_token=")
				.replyWithFile(200, __dirname + '/replies/untappd/valid-search.json')
			@nockUntappd.get("/v4/beer/info/481516?compact=true&client_id=not-real-id&client_secret=not-real-secret&access_token=")
				.replyWithFile(200, __dirname + '/replies/untappd/valid-info.json')
			@nockUntappd.get("/v4/beer/info/481516?compact=true&client_id=not-real-id&client_secret=not-real-secret&access_token=")
				.replyWithFile(200, __dirname + '/replies/untappd/valid-info.json')

		it 'produces json with info on the beer and populated untappd data using the manual mapping', (done) ->
			output = null
			scraper.scrapeBeerbods config, (result) ->
				output = result
				expect(output).is.not.null
				expect(output).to.eql expected
				done()

describe 'beerbods api with untappd credentials and manual mapping', ->
	config = new scraper.config(["This week's test", "Next week's test"], "shall be", '/thebeers', 0)

	beforeEach ->
		@nockUntappd = nock("https://api.untappd.com")
		global.nockBeerbodsSite = nock("https://beerbods.co.uk")
			.get("/thebeers")
			.replyWithFile(200, __dirname + '/replies/valid-needing-manual-map.html')

	afterEach ->
		@nockUntappd.done()

	context 'mock services return valid responses, several matches on untappd, with manual mapping', ->
		expected = require './expected/current-output-plus-untappd-manual-map.json'
		expected = [expected[0]]
		beforeEach ->
			@nockUntappd.get("/v4/beer/info/447705?compact=true&client_id=not-real-id&client_secret=not-real-secret&access_token=")
				.replyWithFile(200, __dirname + '/replies/untappd/valid-info.json')

		it 'produces json with info on the beer and populated untappd data using the manual mapping', (done) ->
			output = null
			scraper.scrapeBeerbods config, (result) ->
				output = result
				expect(output).is.not.null
				expect(output).to.eql expected
				done()