request = require "request"
fs = require "fs"
rimraf = require "rimraf"
scraper = require './beerbods-scraper'

currentConfig = new scraper.config \
	['This week\'s %s', 'Next week\'s %s', 'In 2 week\'s the %s', 'In 3 week\'s the %s'], \
	'is'

previousConfig = new scraper.config \
	['Last week\'s %s', '2 week\'s ago the %s', '3 week\'s ago the %s', '4 week\'s ago the %s'],
	'was', \
	'/archive', \
	3

previousData = null
output = {}

if process.argv.length == 3 and process.argv[2].startsWith("https://") and process.argv[2].endsWith(".json")
	request process.argv[2], (error, response, body) ->
		if !error and response.statusCode == 200
			try
				previousData = JSON.parse body
				console.error "previous data successfully loaded"
				scrape()
			catch error
				console.error "previous data parsing error", error
				scrape()
		else
			console.error "previous data error", error || response.statusCode
			scrape()
else
	scrape()

scrape = () ->
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

	return true

writer = () ->
	keys = ["previous", "current"]
	for key in keys
		if !output[key]
			return

	if previousData
		for key in keys
			if !output[key] or output[key].length == 0
				console.error "'#{key}' output is empty, substituting entire old '#{key}' data"
				output[key] = previousData[key]
				continue

			for week, weekIndex in output[key]
				previous = previousData[key][weekIndex]
				continue unless previous
				if resultsAreEqual(previous, week)
					for beer, beerIndex in week.beers
						previousBeer = previous.beers[beerIndex]
						if !beer.untappd.detailUrl and previousBeer.untappd.detailUrl
							console.error "substituting older untappd data for #{key}[#{weekIndex}][#{beerIndex}] - #{previousBeer.name}"
							beer.untappd = previousBeer.untappd
							beer.untappd.lookupStale = true
							beer.brewery = previousBeer.brewery

	outdir = "#{__dirname}/../site/v1"

	rimraf.sync "#{outdir}/*"
	for key in keys
		fs.mkdirSync "#{outdir}/#{key}"
		fs.writeFileSync "#{outdir}/#{key}.json", JSON.stringify(output[key])
		for week, index in output[key]
			fs.writeFileSync "#{outdir}/#{key}/#{index}.json", JSON.stringify(week)

	fs.writeFileSync "#{outdir}/beerbods.json", JSON.stringify(output)

