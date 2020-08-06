humanize = require "humanize"
pluralize = require "pluralize"
request = require "request"
got = require "got"
fs = require "fs"
util = require "util"

beerbodsUrl = 'https://beerbods.co.uk'

untappdClientId = process.env.UNTAPPD_CLIENT_ID || ''
untappdClientSecret = process.env.UNTAPPD_CLIENT_SECRET || ''
untappdAccessToken = process.env.UNTAPPD_ACCESS_TOKEN || ''
untappdApiRoot = "https://api.untappd.com/v4"

nameOverridePath = __dirname + '/../name-overrides.json'
untappdMappingPath = __dirname + '/../untappd-mapping.json'

beerbodsUntappdMap = {}
beerbodsNameOverrideMap = {}
beerBrewerySplitter = "$$%$$"

if fs.existsSync untappdMappingPath
	file = fs.readFileSync untappdMappingPath
	manualOverrides = try JSON.parse file

	if manualOverrides?.beerbodsUntappdId
		manualOverrides.beerbodsUntappdId.forEach (override) ->
			if override.beerbodsName and override.untappdId
				beerbodsUntappdMap[override.beerbodsName.toLowerCase()] = override.untappdId
				return

if fs.existsSync nameOverridePath
	file = fs.readFileSync nameOverridePath
	manualOverrides = try JSON.parse file

	if manualOverrides?.beerbodsNameOverride
		manualOverrides.beerbodsNameOverride.forEach (override) ->
			key = "#{(override.beerbodsName || '')}#{beerBrewerySplitter}#{(override.beerbodsBrewery || '')}".toLowerCase()
			beerbodsNameOverrideMap[key] = override.overrides

RETRY_ATTEMPT_TIMES = 3

class Config
	constructor: (@weekDescriptors, @relativeDescriptor, @maxIndex = 3, @untappdCredentials) ->

module.exports.config = Config

class Week
	constructor: (@title, @href, @imgSrc) ->

filterNonPlusBeers = (beer) ->
	return !beer.isPlusBeer

fetchBeerbodsData = () ->
	apiPrevCount = process.env.BEERBODS_REQUEST_PREV_COUNT || 8
	apiUpcomingCount = process.env.BEERBODS_REQUEST_UPCOMING_COUNT || 8

	beerbods = got.extend({prefixUrl: 'https://beerbods.co.uk/', responseType: 'json', resolveBodyOnly: true})
	previous = beerbods("umbraco/api/beers/previous/?count=#{apiPrevCount}") #array
	featured = beerbods('umbraco/api/beers/featured/') #single element
	upcoming = beerbods("umbraco/api/beers/upcoming/?count=#{apiUpcomingCount}") #array

	featured = await featured
	splitPoint = new Date(featured.data.featuredDate)

	#bucket by featuredDate to group any multiple beer weeks together, since beerbods API does not group them
	map = new Map()
	array = [...(await previous).data.filter(filterNonPlusBeers), featured.data, ...(await upcoming).data.filter(filterNonPlusBeers)]
	for entry in array
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

	prev.sort(sortFeaturedDateInSubArray).reverse()
	current.sort(sortFeaturedDateInSubArray)

	data = {prev, current}

	return data

sortFeaturedDateInSubArray = (d1, d2) ->
	thing = new Date(d1[0]['featuredDate']) - new Date(d2[0]['featuredDate'])
	return thing

module.exports.fetchBeerbodsData = fetchBeerbodsData

module.exports.scrapeBeerbods = (config, beerbodsData, completionHandler) ->
	output = []
	for week, index in beerbodsData
		if index > config.maxIndex
			break
		beers = []
		beerTitles = []
		for beer in week
			title = beer.name.trim()
			brewery = beer.brewedBy.trim()

			nameOverrideKey = "#{title.toLowerCase()}#{beerBrewerySplitter}#{brewery.toLowerCase()}"
			if beerbodsNameOverrideMap[nameOverrideKey]
				overrides = beerbodsNameOverrideMap[nameOverrideKey]
				console.error "Using name override #{title}/#{brewery} -> #{JSON.stringify overrides}"
				if overrides.beer
					title = overrides.beer.trim()
				if overrides.brewery
					brewery = overrides.brewery.trim()

			beerTitles.push("#{title} by #{brewery}")

			searchTerm = "#{brewery} #{title}"
			images = [beer.imageUrl]
			if beer.altImageUrl and beer.altImageUrl != beerbodsUrl
				images.push beer.altImageUrl

			beers.push {
				name: title,
				beerbodsUrl: beer.url,
				images: images,
				untappd: {
					searchUrl: "https://untappd.com/search?q=" + encodeURIComponent(searchTerm),
					searchTerm: searchTerm,
					match: "auto",
					lookupSuccessful: false
				},
				brewery: {
					name: brewery
				}
			}

		formattedDescriptor = util.format(config.weekDescriptors[index], pluralize('beer', beerTitles.length))
		prefix = "#{formattedDescriptor} #{pluralize(config.relativeDescriptor, beerTitles.length)}"

		output.push {
			pretext: "#{prefix}:",
			beerbodsCaption: "beerbods* fields here are DEPRECATED - Update to use data from individual beers",
			beerbodsUrl: beers[0].beerbodsUrl,
			beerbodsImageUrl: beers[0].images[0],
			beers: beers,
			summary: "#{prefix} #{beerTitles.join(' and/or ')}"
		}

	if output.length == 0
		completionHandler null, output
	if config.untappdCredentials
		untappdClientId = config.untappdCredentials.clientId
		untappdClientSecret = config.untappdCredentials.clientSecret
		untappdAccessToken = config.untappdCredentials.accessToken || ''
	if untappdClientId and untappdClientSecret
		untappd = {id: untappdClientId, secret: untappdClientSecret, accessToken: untappdAccessToken, apiRoot: untappdApiRoot}
		populateUntappdData output, untappd, completionHandler
	else
		completionHandler null, output

populateUntappdData = (messages, untappd, completionHandler) ->
	doneAtIteration = 0
	messages.map (a) ->
		doneAtIteration += a.beers.length

	totalIteration = 0
	output = []
	for message, weekIteration in messages
		output.push message
		for beer, beerIteration in message.beers
			beer.outputIndices = [weekIteration, beerIteration] #context for where to put this back when it returns in the callback
			searchBeerOnUntappd beer.untappd.searchTerm, beer, untappd, (error, updatedMessage) ->
				totalIteration = totalIteration + 1
				outputIndices = updatedMessage.outputIndices
				output[outputIndices[0]].beers[outputIndices[1]] = updatedMessage
				delete output[outputIndices[0]].beers[outputIndices[1]].outputIndices #remove context now, not needed in final output
				if totalIteration == doneAtIteration
					completionHandler null, output
					return

untappdAuthParams = (untappdConfig) ->
	return "client_id=#{untappdConfig.id}&client_secret=#{untappdConfig.secret}&access_token=#{untappdConfig.accessToken}"

searchBeerOnUntappd = (beerTitle, message, untappd, completionHandler, retryCount = 0) ->
	if beerbodsUntappdMap[beerTitle.toLowerCase()]
		message.untappd.match = "manual"
		lookupBeerOnUntappd beerbodsUntappdMap[beerTitle.toLowerCase()], message, untappd, completionHandler
		return

	if retryCount == RETRY_ATTEMPT_TIMES
		completionHandler null, message
		return
	request "#{untappd.apiRoot}/search/beer?q=#{encodeURIComponent beerTitle}&limit=5&#{untappdAuthParams(untappd)}", (error, response, body) ->
		if error or response.statusCode != 200 or !body
			console.error "beerbods-untappd-search", error ||= response.statusCode + body
			searchBeerOnUntappd beerTitle, message, untappd, completionHandler, retryCount + 1
			return

		try
			data = JSON.parse body
		catch error
			console.error "beerbods-untappd-search", error
			searchBeerOnUntappd beerTitle, message, untappd, completionHandler, retryCount + 1
			return

		if !data or !data?.response?.beers?.items
			console.error "beerbods-untappd-search-no-data", body
			searchBeerOnUntappd beerTitle, message, untappd, completionHandler, retryCount + 1

			return

		beers = data.response.beers.items
		if beers.length > 1
			#More than one result, so filter out beers out of production which may reduce us to one remaining result
			beers = (item for item in beers when item.beer.in_production)

		if beers.length != 1
			#Unsure which to pick, so bail and leave the search link
			completionHandler null, message
			return

		untappdBeerId = data.response.beers.items[0].beer.bid
		lookupBeerOnUntappd untappdBeerId, message, untappd, completionHandler

lookupBeerOnUntappd = (untappdBeerId, message, untappd, completionHandler, retryCount = 0) ->
	if retryCount == RETRY_ATTEMPT_TIMES
		completionHandler null, message
		return
	request "#{untappd.apiRoot}/beer/info/#{untappdBeerId}?compact=true&#{untappdAuthParams(untappd)}", (error, response, body) ->
		if error or response.statusCode != 200
			console.error "beerbods-untappd-beer-bid-#{untappdBeerId}", error ||= response.statusCode + body
			lookupBeerOnUntappd untappdBeerId, message, untappd, completionHandler, retryCount + 1
			return

		try
			data = JSON.parse body
		catch error
			console.error "beerbods-untappd-beer-baddata-bid-#{untappdBeerId}", body
			lookupBeerOnUntappd untappdBeerId, message, untappd, completionHandler, retryCount + 1
			return

		if !data or !data?.response?.beer
			console.error "beerbods-untappd-beer-baddata-bid-#{untappdBeerId}", body
			lookupBeerOnUntappd untappdBeerId, message, untappd, completionHandler, retryCount + 1
			return

		beer = data.response.beer

		responseBeer = message
		responseBeer.brewery.logo = beer.brewery.brewery_label
		responseBeer.brewery.url = "https://untappd.com/w/#{beer.brewery.brewery_slug}/#{beer.brewery.brewery_id}"
		untappd = responseBeer.untappd
		untappd.bid = beer.bid
		untappd.detailUrl = "https://untappd.com/b/#{beer.beer_slug}/#{beer.bid}"
		untappd.mobileDeepUrl = "https://untappd.com/qr/beer/#{beer.bid}"
		untappd.abv = "#{beer.beer_abv ||= 'N/A'}%"
		untappd.rating = "#{humanize.numberFormat beer.rating_score} avg, #{humanize.numberFormat beer.rating_count, 0} #{pluralize 'rating', beer.rating_count}"
		untappd.description = beer.beer_description
		untappd.style = beer.beer_style
		untappd.label = beer.beer_label
		untappd.lookupSuccessful = true
		untappd.lookupStale = false

		completionHandler null, message

