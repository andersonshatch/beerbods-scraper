expect = require('chai').expect
util = require('util')
scraper = require('../src/beerbods-scraper')

describe 'beerbods api without untappd credentials', ->
	config = new scraper.config(["This week's test", "Next week's test", "2 week's test", "3 week's test", "4 week's test"], "is", '/thebeers')

	context 'mock beerbods upcoming beers', ->
		configClub = new scraper.config(["This week's test", "Next week's test", "3 week's test", "4 week's test"], "shall be", '/', 3)

		beerbodsInput = require __dirname + '/replies/beerbods/upcoming.json'
		expected = require __dirname + '/expected/upcoming.json'

		it 'produces scraped data', () ->
			return expect(await util.promisify(scraper.scrapeBeerbods)(config, beerbodsInput)).to.eql expected
