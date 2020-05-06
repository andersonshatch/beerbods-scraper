got = require "got"
fs = (require "fs").promises
rimraf = require "rimraf"
scraper = require './beerbods-scraper'
util = require "util"

nextConfig = new scraper.config \
  ['This week\'s %s', 'Next week\'s %s', 'In 2 week\'s the %s', 'In 3 week\'s the %s', 'In 4 week\'s the %s'], \
  'is', \
  4

previousConfig = new scraper.config \
  ['Last week\'s %s', '2 week\'s ago the %s', '3 week\'s ago the %s', '4 week\'s ago the %s'],
  'was', \
  3

fetchBeerbodsData = () ->
	beerbods = got.extend({prefixUrl: 'https://beerbods.co.uk/', responseType: 'json', resolveBodyOnly: true})
	previous = beerbods('umbraco/api/beers/previous/') #array, in descending order
	featured = beerbods('umbraco/api/beers/featured/') #single element
	upcoming = beerbods('umbraco/api/beers/upcoming/') #array, in ascending order

	featured = await featured
	splitPoint = new Date(featured.data.featuredDate)

	#bucket by featuredDate to group any multiple beer weeks together, since beerbods API does not group them
	map = new Map()
	for entry in [...(await previous).data.reverse(), featured.data, ...(await upcoming).data]
		date = entry.featuredDate
		if !map.has date
			map.set date, []
		if !map.get(date).map((e) => e.url).includes(entry.url)
			map.get(date).push(entry)

	prev = []
	current = []

	#anything before featuredDate of the featured beer has passed
	for elem in Array.from(map.values())
		if new Date(elem[0].featuredDate) < splitPoint
			prev.push(elem)
		else
			current.push(elem)

	data = {prev, current}

	return data

scrape = () ->
	beerbodsData = await fetchBeerbodsData()
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

