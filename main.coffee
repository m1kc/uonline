#!/usr/bin/env coffee

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


'use strict'

config = require './config.js'

anyDB = require 'any-db'
dbConnection = anyDB.createPool config.DATABASE_URL, min: 2, max: 20

# Attach profiler?
if process.env.SQLPROF is 'true'
	dbConnection._query = dbConnection.query
	dbConnection.query = (q, data, cb) ->
		logged = q
		for value, index in data
			index++
			while logged.indexOf("$#{index}") isnt -1
				logged = logged.replace "$#{index}", "<#{value}>"
		Date start = new Date()
		@_query q, data, (error, result) ->
			time = new Date() - start
			console.log "\n#{time} ms: #{logged}\n"
			cb(error, result)
	dbConnection._begin = dbConnection.begin
	dbConnection.begin = ->
		console.log "\nBEGIN TRANSACTION\n"
		tx = @_begin()
		tx.____start = new Date()
		tx.__query = tx.query
		tx.query = (q, data, cb) ->
			logged = q
			for value, index in data
				index++
				while logged.indexOf("$#{index}") isnt -1
					logged = logged.replace "$#{index}", "<#{value}>"
			Date start = new Date()
			@__query q, data, (error, result) ->
				time = new Date() - start
				console.log "\n#{time} ms: t: #{logged}\n"
				cb(error, result)
		# doesn't work
		#tx.__commit = tx.commit
		#tx.commit = (a) ->
			#console.log "\nCOMMIT, the whole thing took #{new Date() - tx.____start} ms\n"
			#tx.__commit a
		return tx

lib = require './lib.coffee'
async = require 'async'
express = require 'express'
sync = require 'sync'

app = express()
app.enable 'trust proxy'
app.use express.logger()
app.use express.cookieParser()
app.use express.json()
app.use express.urlencoded()
app.use express.compress()

app.use '/static/bootstrap', express.static(__dirname + '/bootstrap')
#app.use '/img', express.static(__dirname + '/img')
app.use '/static/browserified', express.static(__dirname + '/browserified')
app.use '/static/bower_components', express.static(__dirname + '/bower_components')

app.set 'view engine', 'jade'
app.locals.pretty = true
app.set 'views', __dirname + '/views'


app.use ((request, response) ->
	# Read basic stuff
	request.uonline = {}
	request.uonline.basicOpts = {}
	request.uonline.basicOpts.now = new Date()
	request.uonline.basicOpts.pjax = false
	sessionData = lib.user.sessionInfoRefreshing.sync(null,
		dbConnection, request.cookies.sessid, config.sessionExpireTime)
	request.uonline.basicOpts.loggedIn = sessionData.sessionIsActive
	request.uonline.basicOpts.login = sessionData.username
	request.uonline.basicOpts.admin = sessionData.admin
	request.uonline.basicOpts.userid = sessionData.userid
	# CSP
	response.header 'Content-Security-Policy-Report-Only',
		"default-src 'self'; script-src 'self' http://code.jquery.com"
	# Anti-clickjacking
	response.header 'X-Frame-Options', 'DENY'
	# PJAX
	if request.header('X-PJAX')?
		request.uonline.basicOpts.pjax = true
	return
).asyncMiddleware()


# routing routines

app.get '/node/', (request, response) ->
	response.send 'Node.js is up and running.'


app.get '/explode/', (request, response) ->
	throw new Error 'Emulated error.'


# real ones

quickRender = (request, response, template) ->
	options = request.uonline.basicOpts
	options.instance = template
	response.render template, options


quickRenderError = (request, response, code) ->
	options = request.uonline.basicOpts
	options.code = code
	options.instance = 'error'
	response.status code
	response.render 'error', options


app.get '/', (request, response) ->
	if request.uonline.basicOpts.loggedIn is true
		response.redirect config.defaultInstanceForUsers
	else
		response.redirect config.defaultInstanceForGuests


app.get '/about/', (request, response) ->
	quickRender request, response, 'about'


app.get '/register/', (request, response) ->
	quickRender request, response, 'register'


app.post '/register/', (request, response) ->
	options = request.uonline.basicOpts
	options.instance = 'register'
	usernameIsValid = lib.validation.usernameIsValid(request.body.user)
	passwordIsValid = lib.validation.passwordIsValid(request.body.pass)
	userExists = lib.user.userExists.sync(null, dbConnection, request.body.user)
	if (usernameIsValid is true) and (passwordIsValid is true) and (userExists is false)
		result = lib.user.registerUser.sync(
			null
			dbConnection
			request.body.user
			request.body.pass
			config.PERMISSIONS_USER
		)
		response.cookie 'sessid', result.sessid
		response.redirect '/'
	else
		options.error = true
		options.invalidLogin = !usernameIsValid
		options.invalidPass = !passwordIsValid
		options.loginIsBusy = userExists
		options.user = request.body.user
		options.pass = request.body.pass
		response.render 'register', options


app.get '/login/', (request, response) ->
	quickRender request, response, 'login'


app.post '/login/', (request, response) ->
	if lib.user.accessGranted.sync null, dbConnection, request.body.user, request.body.pass
		sessid = lib.user.createSession.sync null, dbConnection, request.body.user
		response.cookie 'sessid', sessid
		response.redirect '/'
	else
		options = request.uonline.basicOpts
		options.instance = 'login'
		options.error = true
		options.user = request.body.user
		response.render 'login', options


app.get '/profile/', (request, response) -> sync ->
	if request.uonline.basicOpts.loggedIn is true
		options = request.uonline.basicOpts
		options.instance = 'profile'
		options.username = request.uonline.basicOpts.login
		options.profileIsMine = true
		options.id = request.uonline.basicOpts.userid
		chars = lib.game.getUserCharacters.sync null, dbConnection, request.uonline.basicOpts.userid
		for i of chars
			options[i] = chars[i]
		response.render 'profile', options
	else
		response.redirect '/login/'


app.get '/profile/:username/', (request, response) ->
	username = request.param('username')
	chars = lib.game.getUserCharacters.sync null, dbConnection, username
	if chars is null
		throw new Error '404'
	options = request.uonline.basicOpts
	options.instance = 'profile'
	options.profileIsMine = (options.loggedIn is true) and (chars.id == options.userid)
	for i of chars
		options[i] = chars[i]
	options.username = username
	response.render 'profile', options


app.get '/action/logout', (request, response) ->
	# TODO: move sessid to uonline{}
	lib.user.closeSession dbConnection, request.cookies.sessid, (error, result) ->
		if error?
			response.send 500
		else
			response.redirect '/'


app.get '/game/', (request, response) -> sync ->
	if request.uonline.basicOpts.loggedIn is true
		userid = request.uonline.basicOpts.userid
		options = request.uonline.basicOpts
		options.instance = 'game'

		try
			location = lib.game.getUserLocation.sync null, dbConnection, userid
		catch e
			console.log e.stack
			location = lib.game.getDefaultLocation.sync null, dbConnection
			lib.game.changeLocation.sync null, dbConnection, userid, location.id, true

		area = lib.game.getUserArea.sync null, dbConnection, userid
		options.location_name = location.title
		options.area_name = area.title
		options.pic = options.picture  if options.picture?
		options.description = location.description
		options.ways = location.goto
		options.ways.forEach (i) -> # Facepalm. #273
			i.name = i.text
			i.to = i.id
		tmpUsers = lib.game.getNearbyUsers.sync null,
			dbConnection, userid, location.id
		tmpUsers.forEach (i) -> # Facepalm. Refs #273 too.
			i.name = i.user
		options.players_list = tmpUsers
		tmpMonsters = lib.game.getNearbyMonsters.sync null, dbConnection, location.id
		options.monsters_list = tmpMonsters
		options.fight_mode = lib.game.isInFight.sync null, dbConnection, userid
		options.autoinvolved_fm = lib.game.isAutoinvolved.sync null, dbConnection, userid

		chars = lib.game.getUserCharacters.sync null, dbConnection, request.uonline.basicOpts.userid
		for i of chars
			options[i] = chars[i]

		response.header 'X-PJAX-URL', '/game/'
		response.render 'game', options
	else
		response.redirect '/login/'


app.get '/inventory/', (request, response) ->
	if request.uonline.basicOpts.loggedIn is true
		userid = request.uonline.basicOpts.userid
		options = request.uonline.basicOpts
		options.instance = 'inventory'
		options.fight_mode = lib.game.isInFight.sync null, dbConnection, userid
		response.render 'inventory', options
	else
		response.redirect '/login/'


app.get '/action/go/:to', (request, response) ->
	unless request.uonline.basicOpts.loggedIn
		response.redirect '/login/'
	else
		lib.game.changeLocation.sync null, dbConnection, request.uonline.basicOpts.userid, request.param('to')
		response.redirect '/game/'


app.get '/action/attack', (request, response) ->
	unless request.uonline.basicOpts.loggedIn
		response.redirect '/login/'
	else
		lib.game.goAttack.sync null, dbConnection, request.uonline.basicOpts.userid
		response.redirect '/game/'


app.get '/action/escape', (request, response) ->
	unless request.uonline.basicOpts.loggedIn
		response.redirect '/login/'
	else
		lib.game.goEscape.sync null, dbConnection, request.uonline.basicOpts.userid
		response.redirect '/game/'


app.get '/ajax/isNickBusy/:nick', (request, response) ->
	response.json
		nick: request.param('nick')
		isNickBusy: lib.user.userExists.sync null, dbConnection, request.param('nick')


# 404 handling
app.get '*', (request, response) ->
	throw new Error '404'


# Exception handling
app.use (error, request, response, next) ->
	if error.message is '404'
		quickRenderError request, response, 404
	else
		console.error error.stack
		quickRenderError request, response, 500


# main

DEFAULT_PORT = 5000
port = process.env.PORT or process.env.OPENSHIFT_NODEJS_PORT or DEFAULT_PORT
ip = process.env.OPENSHIFT_NODEJS_IP or undefined
console.log "Starting up on port #{port}, and IP is #{ip}"
startupFinished = () ->
	console.log "Listening on port #{port}"
	if port is DEFAULT_PORT then console.log "Try http://localhost:#{port}/"

if ip?
	app.listen port, ip, startupFinished
else
	app.listen port, startupFinished
