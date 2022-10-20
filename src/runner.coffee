got = require "got"
fs = (require "fs").promises
rimraf = require "rimraf"
util = require "util"

writer = (data) ->
	keys = ["previous", "current"]

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

scrape = () ->
	week = {
		pretext: "Beerbods has closed:",
		beerbodsCaption: "beerbods* fields here are DEPRECATED - Update to use data from individual beers",
		beerbodsUrl: "https://andersonshatch.com",
		beerbodsImageUrl: "",
		beers: [{
			name: "Beerbods has closed",
			detailUrl: "https://andersonshatch.com",
			brewery: {
				name: "Sad",
				logo: "https://andersonshatch.com"
			},
			untappd: {
				detailUrl: "https://untappd.com",
				searchUrl: "https://untappd.com"
			}
		}],
		summary: "Beerbods has closed",
		plusBeers: [],
		plusPretext: "",
		plusSummary: ""
	}
	writer({
		previous: [week, week, week, week],
		current: [week, week, week, week]
	})


scrape()



