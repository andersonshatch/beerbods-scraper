expect = require('chai').expect
nock = require('nock')
util = require('util')
scraper = require('../src/beerbods-scraper')

describe 'bucket beerbods beers by date and return sorted', ->
	beforeEach ->
		do nock.disableNetConnect
		beerbods = nock('https://beerbods.co.uk/umbraco/api/beers/')
		beerbods.get('/previous/?count=8').replyWithFile(200, __dirname + '/replies/beerbods/previous.json')
		beerbods.get('/featured/').replyWithFile(200, __dirname + '/replies/beerbods/featured.json')
		beerbods.get('/upcoming/?count=8').replyWithFile(200, __dirname + '/replies/beerbods/upcoming.json')

	context 'mis-sorted-input', ->
		it 'sorts and buckets data', () ->
			data = await scraper.fetchBeerbodsData()
			expect(data).to.have.property('prev').to.be.an('array').with.lengthOf(5)
			expect(data['prev'].map((e) -> e.length)).to.eql [1, 1, 1, 1, 1]
			expect(data).to.have.property('current').to.be.an('array').with.lengthOf(5)
			expect(data['current'][0]).to.be.an('array').with.lengthOf(2)
			expect(data['current'].map((e) -> e.length)).to.eql [2, 1, 1, 2, 1]

			dates = []
			for week in data['prev']
				uniq = new Set()
				dates.push new Date week[0]['featuredDate']
				for beer in week
					uniq.add(beer['featuredDate'])

				#only one date per bucket
				expect(uniq.size).to.eql(1)

			#dates should be descending for previous
			expect(dates).to.eql(Array.from(dates).sort((d1, d2) -> d1+d2))

			dates = []
			for week in data['current']
				uniq = new Set()
				dates.push new Date week[0]['featuredDate']
				for beer in week
					uniq.add(beer['featuredDate'])

				#only one date per bucket
				expect(uniq.size).to.eql(1)

			#dates should be ascending for current
			expect(dates).to.eql(Array.from(dates).sort((d1, d2) -> d1-d2))


describe 'beerbods api without untappd credentials', ->
	config = new scraper.config(
		["This week's test", "Next week's test", "2 week's test", "3 week's test", "4 week's test"], \
		["This week's test plus", "Next week's test plus", "2 week's test plus", "3 week's test plus", "4 week's test plus"], \
		"is", '/thebeers')

	context 'mock beerbods upcoming beers', ->
		beerbodsInput = require __dirname + '/replies/beerbods/upcoming-bucketed.json'
		expected = require __dirname + '/expected/upcoming.json'

		it 'produces scraped data', () ->
			return expect(await util.promisify(scraper.scrapeBeerbods)(config, beerbodsInput)).to.eql expected
