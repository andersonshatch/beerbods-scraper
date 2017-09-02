request = require "request"
scraper = require './beerbods-scraper'


currentConfig = {
	weekDescriptors: ['This week\'s', 'Next week\'s', 'The week after next\'s', '3 week\'s from now\'s'],
	relativeDescriptor: 'is',
	path: ''
}

previousConfig = {
	weekDescriptors: ['Last week\'s', '2 week\'s ago\'s', '3 week\'s ago\'s', '4 week\'s ago\'s'],
	relativeDescriptor: 'was',
	path: '/archive'
}

previousData = null
if process.argv.length == 3 and process.argv[2].startsWith("https://") and process.argv[2].endsWith(".json")
	request process.argv[2], (error, response, body) ->
		if !error and response.statusCode == 200
			previousData = JSON.parse body
			console.error "previous data successfully loaded"

output = {}

scraper.scrapeBeerbods currentConfig, (response) ->
	output.current = response
	writer()

scraper.scrapeBeerbods previousConfig, (response) ->
	output.previous = response
	writer()

resultsAreEqual = (aBeer, bBeer) ->
	if aBeer.beerbodsCaption != bBeer.beerbodsCaption
		return false
	if aBeer.beerbodsUrl != bBeer.beerbodsUrl
		return false
	if aBeer.beerbodsImageUrl != bBeer.beerbodsImageUrl
		return false
#	if aBeer.brewery.name != bBeer.brewery.name
#		return false

	return true

writer = () ->
	keys = ["previous", "current"]
	for key in keys
		if !output[key]
			return

	if previousData
		for key in keys
			if resultsAreEqual(previousData[key], output[key])
				for beer, index in output[key].beers
					if !beer.untappd.detailUrl
						console.error "substituting older untappd data for #{key}[#{index}]"
						beer.untappd = previousData[key].beers[index].untappd
						beer.untappd.lookupStale = true
						output[key].brewery = previousData[key].brewery

	console.log JSON.stringify output


