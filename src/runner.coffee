scraper = require './beerbods-scraper'


currentConfig = {
	weekDescriptor: 'This',
	relativeDescriptor: 'is',
	beerIndex: 0,
	path: ''
}

nextConfig = {
	weekDescriptor: 'Next',
	relativeDescriptor: 'is',
	beerIndex: 1,
	path: ''
}

previousConfig = {
	weekDescriptor: 'Last',
	relativeDescriptor: 'was',
	beerIndex: 0,
	path: '/archive'
}

previousData = null
if process.argv.length == 3 and process.argv[2].endsWith ".json"
	previousData = require process.argv[2]
	console.log previousData

output = {}

scraper.lookupBeer currentConfig, (response) ->
	output.current = response
	writer()

scraper.lookupBeer nextConfig, (response) ->
	output.next = response
	writer()

scraper.lookupBeer previousConfig, (response) ->
	output.previous = response
	writer()

resultsAreEqual = (aBeer, bBeer) ->
	if aBeer.beerbodsCaption != bBeer.beerbodsCaption
		return false
	if aBeer.beerbodsUrl != bBeer.beerbodsUrl
		return false
	if aBeer.beerbodsImageUrl != bBeer.beerbodsImageUrl
		return false
	if aBeer.brewery != bBeer.brewery
		return false

	return true

writer = () ->
	keys = ["previous", "current", "next"]
	for key in keys
		if !output[key]
			return

	if previousData
		for key in keys
			if resultsAreEqual(previousData[key], output[key]) and !output[key].beers[0].untappd.detailUrl
				console.err "substituting older untappd data for #{key}"
				output[key].beers[0].untappd = previousData[key].beers[0].untappd

	console.log JSON.stringify output


