cheerio = require "cheerio"
humanize = require "humanize"
pluralize = require "pluralize"
request = require "request"
fs = require "fs"

beerbodsUrl = 'https://beerbods.co.uk'

untappdClientId = process.env.UNTAPPD_CLIENT_ID || ''
untappdClientSecret = process.env.UNTAPPD_CLIENT_SECRET || ''
untappdApiRoot = "https://api.untappd.com/v4"

beerbodsUntappdMap = {}
if fs.existsSync __dirname + '/../beerbods-untappd-map.json'
	file = fs.readFileSync __dirname + '/../beerbods-untappd-map.json', 'utf8'
	beerbodsUntappdMap = JSON.parse file


RETRY_ATTEMPT_TIMES = 3

module.exports.scrapeBeerbods = (config, completionHandler) ->
	request beerbodsUrl + config.path, (error, response, body) ->
		if error
			console.error "beerbods", error
			completionHandler {}
			return
		$ = cheerio.load body
		div = $('div.beerofweek-container')
		title = $('h3', div).eq(config.beerIndex).text()
		href = $('a', div).eq(config.beerIndex).attr('href')

		if !title or !href
			console.error "beerbods beer not found - page layout unexpected"
			completionHandler {}
			return

		beerUrl = beerbodsUrl + href

		text = "#{config.weekDescriptor} week's beer #{config.relativeDescriptor} #{title} - #{beerUrl}"

		brewery = ''
		beer = title

		searchTerm = title
		if title.indexOf(',') != -1
			components = title.split(',')
			if components.length == 2
				brewery = components[0].trim()
				beer = components[1].trim()
				searchTerm = "#{brewery} #{beer}"

		slackMessage = {
			pretext: "#{config.weekDescriptor} week's beer:",
			beerbodsCaption: title,
			beerbodsUrl: beerUrl,
			beerbodsImageUrl: beerbodsUrl + $('img', div).eq(config.beerIndex).attr("src"),
			brewery: {name: brewery},
			beers: [{
				name: beer,
				untappd: {
					searchUrl: "https://untappd.com/search?q=" + encodeURIComponent(searchTerm),
					match: "auto",
					lookupSuccessful: false
				}
			}],
			fallback: text
		}

		if untappdClientId and untappdClientSecret
			searchBeerOnUntappd searchTerm, slackMessage, {id: untappdClientId, secret: untappdClientSecret, apiRoot: untappdApiRoot}, completionHandler
		else
			completionHandler slackMessage

searchBeerOnUntappd = (beerTitle, slackMessage, untappd, completionHandler, retryCount = 0) ->
	if beerbodsUntappdMap[beerTitle]
		slackMessage.beers[0].untappd.match = "manual"
		lookupBeerOnUntappd beerbodsUntappdMap[beerTitle], slackMessage, untappd, completionHandler
		return

	if retryCount == RETRY_ATTEMPT_TIMES
		completionHandler slackMessage
		return
	request "#{untappd.apiRoot}/search/beer?q=#{encodeURIComponent beerTitle}&limit=5&client_id=#{untappd.id}&client_secret=#{untappd.secret}", (error, response, body) ->
		if error or response.statusCode != 200 or !body
			console.error "beerbods-untappd-search", error ||= response.statusCode + body
			searchBeerOnUntappd beerTitle, slackMessage, untappd, completionHandler, retryCount + 1
			return

		try
			data = JSON.parse body
		catch error
			console.error "beerbods-untappd-search", error
			searchBeerOnUntappd beerTitle, slackMessage, untappd, completionHandler, retryCount + 1
			return

		if !data or !data?.response?.beers?.items
			console.error "beerbods-untappd-search-no-data", body
			searchBeerOnUntappd beerTitle, slackMessage, untappd, completionHandler, retryCount + 1

			return

		beers = data.response.beers.items
		if beers.length > 1
			#More than one result, so filter out beers out of production which may reduce us to one remaining result
			beers = (item for item in beers when item.beer.in_production)

		if beers.length != 1
			#Unsure which to pick, so bail and leave the search link
			completionHandler slackMessage
			return

		untappdBeerId = data.response.beers.items[0].beer.bid
		lookupBeerOnUntappd untappdBeerId, slackMessage, untappd, completionHandler

lookupBeerOnUntappd = (untappdBeerId, slackMessage, untappd, completionHandler, retryCount = 0) ->
	if retryCount == RETRY_ATTEMPT_TIMES
		completionHandler slackMessage
		return
	request "#{untappd.apiRoot}/beer/info/#{untappdBeerId}?compact=true&client_id=#{untappd.id}&client_secret=#{untappd.secret}", (error, response, body) ->
		if error or response.statusCode != 200
			console.error "beerbods-untappd-beer-bid-#{untappdBeerId}", error ||= response.statusCode + body
			lookupBeerOnUntappd untappdBeerId, slackMessage, untappd, completionHandler, retryCount + 1
			return

		try
			data = JSON.parse body
		catch error
			console.error "beerbods-untappd-beer-baddata-bid-#{untappdBeerId}", body
			lookupBeerOnUntappd untappdBeerId, slackMessage, untappd, completionHandler, retryCount + 1
			return

		if !data or !data?.response?.beer
			console.error "beerbods-untappd-beer-baddata-bid-#{untappdBeerId}", body
			lookupBeerOnUntappd untappdBeerId, slackMessage, untappd, completionHandler, retryCount + 1
			return

		beer = data.response.beer

		slackMessage.brewery.logo = beer.brewery.brewery_label
		slackMessage.brewery.url = "https://untappd.com/w/#{beer.brewery.brewery_slug}/#{beer.brewery.brewery_id}"

		responseBeer = slackMessage.beers[0].untappd
		responseBeer.detailUrl = "https://untappd.com/b/#{beer.beer_slug}/#{beer.bid}"
		responseBeer.abv = "#{beer.beer_abv ||= 'N/A'}%"
		responseBeer.rating = "#{humanize.numberFormat beer.rating_score} avg, #{humanize.numberFormat beer.rating_count, 0} #{pluralize 'rating', beer.rating_count}"
		responseBeer.description = beer.beer_description
		responseBeer.label = beer.beer_label
		responseBeer.lookupSuccessful = true

		completionHandler slackMessage

