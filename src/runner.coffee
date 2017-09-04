request = require "request"
fs = require "fs"
rimraf = require "rimraf"
scraper = require './beerbods-scraper'

currentConfig = {
	weekDescriptors: ['This week\'s %s', 'Next week\'s %s', 'In 2 week\'s the %s', 'In 3 week\'s the %s'],
	relativeDescriptor: 'is',
	path: '',
	maxIndex: 3
}

previousConfig = {
	weekDescriptors: ['Last week\'s %s', '2 week\'s ago the %s', '3 week\'s ago the %s', '4 week\'s ago the %s'],
	relativeDescriptor: 'was',
	path: '/archive',
	maxIndex: 3
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
			for week, weekIndex in output[key]
				previous = previousData[key][weekIndex]
				continue unless previous
				if resultsAreEqual(previous, week)
					for beer, beerIndex in week.beers
						if !beer.untappd.detailUrl
							previousBeer = previous.beers[beerIndex]
							console.error "substituting older untappd data for #{key}[#{weekIndex}][#{beerIndex}] - #{previousBeer.name}"
							beer.untappd = previousBeer.untappd
							beer.untappd.lookupStale = true
							beer.brewery = previousBeer.brewery

	rimraf.sync __dirname + "/../site/*"
	for key in keys
		fs.mkdirSync __dirname + "/../site/#{key}"
		fs.writeFileSync __dirname + "/../site/#{key}.json", JSON.stringify(output[key])
		for week, index in output[key]
			fs.writeFileSync __dirname + "/../site/#{key}/#{index}.json", JSON.stringify(week)

	fs.writeFileSync __dirname + "/../site/beerbods.json", JSON.stringify(output)

