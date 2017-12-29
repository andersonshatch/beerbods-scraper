cheerio = require "cheerio"
humanize = require "humanize"
pluralize = require "pluralize"
request = require "request"
fs = require "fs"
util = require "util"

beerbodsUrl = 'https://beerbods.co.uk'

untappdClientId = process.env.UNTAPPD_CLIENT_ID || ''
untappdClientSecret = process.env.UNTAPPD_CLIENT_SECRET || ''
untappdAccessToken = process.env.UNTAPPD_ACCESS_TOKEN || ''
untappdApiRoot = "https://api.untappd.com/v4"

beerbodsLoadTimeout = process.env.BEERBODS_LOAD_TIMEOUT || 3000

beerbodsUntappdMapPath = __dirname + '/../beerbods-untappd-map.json'
beerbodsNameOverrideMapPath = __dirname + '/../beerbods-name-override-map.json'

beerbodsUntappdMap = {}
if fs.existsSync beerbodsUntappdMapPath
	file = fs.readFileSync beerbodsUntappdMapPath
	beerbodsUntappdMap = JSON.parse file

beerbodsNameOverrideMap = {}
if fs.existsSync beerbodsNameOverrideMapPath
	file = fs.readFileSync beerbodsNameOverrideMapPath
	beerbodsNameOverrideMap = JSON.parse file

RETRY_ATTEMPT_TIMES = 3

class Config
	constructor: (@weekDescriptors, @relativeDescriptor, @beerbodsPath = "", @maxIndex = 3) ->

module.exports.config = Config

module.exports.scrapeBeerbods = (config, completionHandler) ->
	request beerbodsUrl + config.beerbodsPath, {timeout: beerbodsLoadTimeout}, (error, response, body) ->
		if error or response.statusCode != 200
			console.error "beerbods", error || response.statusCode
			completionHandler []
			return
		$ = cheerio.load body
		div = $('div.beerofweek-container').get()
		output = []
		for d, index in div
			if index > config.maxIndex
				break
			title = $('h3', d).text()
			href = $('a', d).attr('href')

			if !title or !href
				console.error "beerbods beer not found - page layout unexpected (index: #{index})"
				continue

			beerUrl = beerbodsUrl + href

			beerTitles = [title]

			if beerbodsNameOverrideMap[title]
				override = beerbodsNameOverrideMap[title]
				console.error "Using name override #{title} -> #{override}"
				if Array.isArray(override)
					beerTitles = override
				else
					beerTitles[0] = override

			brewery = ''

			beers = []
			formattedDescriptor = util.format(config.weekDescriptors[index], pluralize('beer', beerTitles.length))
			prefix = "#{formattedDescriptor} #{pluralize(config.relativeDescriptor, beerTitles.length)}"
			text = "#{prefix} #{beerTitles.join(' and/or ')}"

			for beer in beerTitles
				if beer.indexOf(',') != -1
					components = beer.split(',')
					if components.length == 2
						brewery = components[0].trim()
						beer = components[1].trim()
				searchTerm = "#{brewery} #{beer}"

				beers.push {
					name: beer,
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

			output.push {
				pretext: "#{prefix}:",
				beerbodsCaption: title,
				beerbodsUrl: beerUrl,
				beerbodsImageUrl: beerbodsUrl + $('img', d).attr("src"),
				beers: beers,
				summary: text
			}

		if untappdClientId and untappdClientSecret
			untappd = {id: untappdClientId, secret: untappdClientSecret, accessToken: untappdAccessToken, apiRoot: untappdApiRoot}
			populateUntappdData output, untappd, completionHandler
		else
			completionHandler output

populateUntappdData = (messages, untappd, completionHandler) ->
	doneAtIteration = 0
	messages.map (a) ->
		doneAtIteration = doneAtIteration + a.beers.length

	totalIteration = 0
	output = []
	for message, weekIteration in messages
		output.push message
		for beer, beerIteration in message.beers
			beer.outputIndices = [weekIteration, beerIteration] #context for where to put this back when it returns in the callback
			searchBeerOnUntappd beer.untappd.searchTerm, beer, untappd, (updatedMessage) ->
				totalIteration = totalIteration + 1
				outputIndices = updatedMessage.outputIndices
				output[outputIndices[0]].beers[outputIndices[1]] = updatedMessage
				delete output[outputIndices[0]].beers[outputIndices[1]].outputIndices #remove context now, not needed in final output
				if totalIteration == doneAtIteration
					completionHandler output
					return

untappdAuthParams = (untappdConfig) ->
	return "client_id=#{untappdConfig.id}&client_secret=#{untappdConfig.secret}&access_token=#{untappdConfig.accessToken}"

searchBeerOnUntappd = (beerTitle, message, untappd, completionHandler, retryCount = 0) ->
	if beerbodsUntappdMap[beerTitle.toLowerCase()]
		message.untappd.match = "manual"
		lookupBeerOnUntappd beerbodsUntappdMap[beerTitle.toLowerCase()], message, untappd, completionHandler
		return

	if retryCount == RETRY_ATTEMPT_TIMES
		completionHandler message
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
			completionHandler message
			return

		untappdBeerId = data.response.beers.items[0].beer.bid
		lookupBeerOnUntappd untappdBeerId, message, untappd, completionHandler

lookupBeerOnUntappd = (untappdBeerId, message, untappd, completionHandler, retryCount = 0) ->
	if retryCount == RETRY_ATTEMPT_TIMES
		completionHandler message
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

		completionHandler message

