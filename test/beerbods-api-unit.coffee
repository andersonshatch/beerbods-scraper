expect = require('chai').expect
nock = require 'nock'

scraper = require '../src/beerbods-scraper'

beforeEach ->
	do nock.disableNetConnect

afterEach ->
	global.nockBeerbodsSite.done()

describe 'beerbods api without untappd credentials', ->
	config = new scraper.config(["This week's test", "Next week's test"], "shall be", '/thebeers')
	attachment = require './expected/current-output-sans-untappd.json'

	context 'mock beerbods returns page with expected layout', ->
		beforeEach ->
			global.nockBeerbodsSite = nock("https://beerbods.co.uk")
				.get("/thebeers")
				.replyWithFile(200, __dirname + '/replies/valid.html')

		it 'produces json with info on 2 weeks beers', (done) ->
			output = null
			scraper.scrapeBeerbods config, (result) ->
				output = result
				expect(output).to.not.be.null
				expect(output).to.have.length 2
				output.forEach (week) ->
					expect(week.beers).to.have.length 1
					expect(week.beers[0].untappd.lookupSuccessful).to.be.false
					expect(week.beers[0].untappd.match).to.eql 'auto'


				expect(output).to.eql(attachment)
				do done


	context 'mock beerbods returns modified page layout', ->
		beforeEach ->
			global.nockBeerbodsSite = nock("https://beerbods.co.uk")
				.get("/thebeers")
				.replyWithFile(200, __dirname + '/replies/invalid.html')

		it 'produces no beer info', ->
			output = null
			scraper.scrapeBeerbods config, (result) ->
				output = result
				expect(output).to.not.be.null
				expect(output).to.have.length 0

	context 'mock beerbods returns an error', ->
		beforeEach ->
			global.nockBeerbodsSite = nock("https://beerbods.co.uk")
				.get("/thebeers")
				.replyWithError("intentional mock request fail")

		it 'produces no beer info', (done) ->
			output = null
			scraper.scrapeBeerbods config, (result) ->
				output = result
				expect(output).to.not.be.null
				expect(output).to.have.length 0
				do done

	context 'mock beerbods returns a non 200 status', ->
		beforeEach ->
			global.nockBeerbodsSite = nock("https://beerbods.co.uk")
				.get("/thebeers")
				.reply(500, '', [])

		it 'produces no beer info', (done) ->
			output = null
			scraper.scrapeBeerbods config, (result) ->
				output = result
				expect(output).to.not.be.null
				expect(output).to.have.length 0
				do done

describe 'beerbods api without untappd credentials uses name override', ->
	config = new scraper.config(["This week's test", "Next week's test"], "shall be", '/thebeers')
	attachment = require './expected/current-output-sans-untappd-manual-map.json'

	context 'mock beerbods returns page with expected layout', ->
		beforeEach ->
			global.nockBeerbodsSite = nock("https://beerbods.co.uk")
				.get("/thebeers")
				.replyWithFile(200, __dirname + '/replies/valid-needing-name-override.html')

		it 'produces json with info on 2 weeks beers using the name override', (done) ->
			output = null
			scraper.scrapeBeerbods config, (result) ->
				output = result
				expect(output).to.not.be.null
				expect(output).to.have.length 1

				expect(output).to.eql(attachment)
				do done