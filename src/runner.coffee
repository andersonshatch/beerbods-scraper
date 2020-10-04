got = require "got"
fs = (require "fs").promises
rimraf = require "rimraf"
scraper = require './beerbods-scraper'
util = require "util"

nextConfig = new scraper.config \
  ['This week\'s %s', 'Next week\'s %s', 'In 2 week\'s the %s', 'In 3 week\'s the %s', 'In 4 week\'s the %s'], \
  ['This week\'s plus %s', 'Next week\'s plus %s', 'In 2 week\'s the plus %s', 'In 3 week\'s the plus %s', 'In 4 week\'s the plus %s'], \
  'is', \
  4

previousConfig = new scraper.config \
  ['Last week\'s %s', '2 week\'s ago the %s', '3 week\'s ago the %s', '4 week\'s ago the %s'],
  ['Last week\'s plus %s', '2 week\'s ago the plus %s', '3 week\'s ago the plus %s', '4 week\'s ago the plus %s'],
  'was', \
  3

scrape = () ->
	beerbodsData = await scraper.fetchBeerbodsData()
	scrape = util.promisify(scraper.scrapeBeerbods)
	previousBeers = scrape(previousConfig, beerbodsData.prev)
	currentBeers = scrape(nextConfig, beerbodsData.current)

	writer({previous: await previousBeers, current: await currentBeers})

previousData = null

init = () ->
  if process.argv.length == 3 and process.argv[2].startsWith("https://") and process.argv[2].endsWith(".json")
    try
      previousData = await got({url: process.argv[2], responseType: 'json', resolveBodyOnly: true})
      console.error "previous data successfully loaded"
      scrape()
    catch e
      console.error "previous data error", e
      scrape()
  else
    scrape()

init()

resultsAreEqual = (aBeer, bBeer) ->
	if aBeer.beerbodsUrl != bBeer.beerbodsUrl
		return false

	return true

writer = (data) ->
	keys = ["previous", "current"]
	for key in keys
		if !data[key]
			return

	if previousData
		for key in keys
			if !data[key] or data[key].length == 0
				console.error "'#{key}' output is empty, substituting entire old '#{key}' data"
				data[key] = previousData[key]
				continue

			for week, weekIndex in data[key]
				previous = previousData[key][weekIndex]
				continue unless previous
				if resultsAreEqual(previous, week)
					for beer, beerIndex in week.beers
						previousBeer = previous.beers[beerIndex]
						if !beer.untappd.detailUrl and previousBeer.untappd?.detailUrl
							console.error "substituting older untappd data for #{key}[#{weekIndex}][#{beerIndex}] - #{week.beerbodsUrl}"
							beer.untappd = previousBeer.untappd
							beer.untappd.lookupStale = true
							beer.untappd.match = "cached - #{previousBeer.untappd.match}"
							beer.brewery = previousBeer.brewery

	outdir = "#{__dirname}/../site/v1"

	await util.promisify(rimraf)("#{outdir}/*")
	writes = []
	for key in keys
		await fs.mkdir "#{outdir}/#{key}"
		writes.push fs.writeFile "#{outdir}/#{key}.json", JSON.stringify(data[key])
		for week, index in data[key]
			writes.push fs.writeFile "#{outdir}/#{key}/#{index}.json", JSON.stringify(week)

	writes.push fs.writeFile "#{outdir}/beerbods.json", JSON.stringify(data)
	Promise.all writes

