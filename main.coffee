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
mysqlConnection = anyDB.createPool config.MYSQL_DATABASE_URL, min: 2, max: 20
utils = require './utils.js'
async = require 'async'
express = require 'express'

app = express()
app.enable 'trust proxy'
app.use express.logger()
app.use express.cookieParser()
app.use express.json()
app.use express.urlencoded()
app.use express.compress()
app.use '/bootstrap', express.static(__dirname + '/bootstrap')
app.use '/img', express.static(__dirname + '/img')
app.use '/browserified', express.static(__dirname + '/browserified')

swig = require 'swig'
stubFilter = (input) -> input
swig.setFilter 'tf', stubFilter # TODO: actually implement
swig.setFilter 'nl2p', stubFilter # TODO: actually implement
swig.setFilter 'nl2br', stubFilter # TODO: actually implement
swig.setFilter 'length', -> 0 # TODO: actually implement

app.engine 'html', swig.renderFile
app.engine 'twig', swig.renderFile
app.engine 'swig', swig.renderFile
app.set 'view engine', 'twig' # historical reasons
app.set 'views', __dirname + '/templates'
phpgate = require('./cgi.js').phpgate

app.use (request, response, next) ->
	response.header 'Content-Security-Policy-Report-Only',
		"default-src 'self'; script-src 'self' http://code.jquery.com"
	next()

app.use (request, response, next) ->
	request.uonline = {}
	request.uonline.basicOpts = {}
	utils.user.sessionInfoRefreshing mysqlConnection, request.cookies.sessid, config.sessionExpireTime,
		(error, result) ->
			if error?
				response.send 500
			else
				request.uonline.basicOpts.now = new Date()
				request.uonline.basicOpts.loggedIn = result.sessionIsActive
				request.uonline.basicOpts.login = result.username
				request.uonline.basicOpts.admin = result.admin
				request.uonline.basicOpts.userid = result.userid
				next()


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
	async.auto
		usernameIsValid: (callback, results) ->
			callback null, utils.validation.usernameIsValid(request.body.user)

		passwordIsValid: (callback, results) ->
			callback null, utils.validation.passwordIsValid(request.body.pass)

		userExists: ['usernameIsValid', (callback, results) ->
			utils.user.userExists mysqlConnection, request.body.user, callback
		]
		register: ['usernameIsValid', 'passwordIsValid', 'userExists', (callback, results) ->
			if results.usernameIsValid is true and results.passwordIsValid is true and results.userExists is false
				utils.user.registerUser(
					mysqlConnection
					request.body.user
					request.body.pass
					config.PERMISSIONS_USER
					callback
				)
			else
				callback null, 'validation fail'
		],
		(error, results) ->
			if !!error or results.register is 'validation fail'
				options.error = true # TODO: report mysql errors explicitly
				# TODO: simplify template params
				options.invalidLogin = not results.usernameIsValid
				options.invalidPass = not results.passwordIsValid
				options.loginIsBusy = results.userExists
				options.user = request.body.user
				options.pass = request.body.pass
				response.render 'register', options
			else
				# TODO: set sessid
				#response.redirect(config.defaultInstanceForUsers);
				response.redirect '/login/'


app.get '/login/', (request, response) ->
	quickRender request, response, 'login'


app.post '/login/', (request, response) ->
	options = request.uonline.basicOpts
	options.instance = 'login'
	async.auto
		accessGranted: (callback) ->
			utils.user.accessGranted mysqlConnection, request.body.user, request.body.pass, callback
		setSession: ['accessGranted', (callback, results) ->
			if results.accessGranted is true
				utils.user.setSession mysqlConnection, request.body.user, callback
			else
				callback 'access denied', null
		]
		cookie: ['setSession', (callback, results) ->
			response.cookie 'sessid', results.setSession
			callback null, null
		],
		(error, results) ->
			if error?
				# TODO: report mysql errors explicitly
				options.error = true
				options.user = request.body.user
				response.render 'login', options
			else
				response.redirect '/'


app.get '/profile/', phpgate # PHP
app.get '/profile/id/:id/', phpgate # PHP
app.get '/profile/user/:user/', phpgate # PHP


app.get '/action/logout', (request, response) ->
	# TODO: move sessid to uonline{}
	utils.user.closeSession mysqlConnection, request.cookies.sessid, (error, result) ->
		if error?
			response.send 500
		else
			response.redirect '/'


app.get '/game/', phpgate # PHP


app.get '/node-game/', (request, response) ->
	if request.uonline.basicOpts.loggedIn is true
		options = request.uonline.basicOpts
		options.instance = 'game'
		utils.game.getUserLocation mysqlConnection, request.uonline.basicOpts.userid, (error, result) ->
			if error? then throw new Error(error)
			options.location_name = result.title
			options.area_name = 'FIXME! FIXME! FIXME!' # TODO: FIXME
			options.pic = options.picture  unless not options.picture
			options.description = result.description
			options.ways = result.goto
			options.ways.forEach (i) -> # facepalm
				i.name = i.text
				i.to = i.id
			options.players_list = [] # TODO: broken
			options.monsters_list = [] # TODO: broken
			options.fight_mode = false # TODO: broken
			options.autoinvolved_fm = false # TODO: broken
			response.render 'game', options
	else
		response.redirect '/login/'


app.get '/action/go/:to', (request, response) ->
	utils.game.changeLocation mysqlConnection, request.uonline.basicOpts.userid, request.param('to'),
		(error, result) ->
			if error? then throw new Error(error)
			response.redirect '/game/'


app.get '/action/attack', (request, response) ->
	unless request.uonline.basicOpts.loggedIn
		response.redirect '/login/'
	else
		utils.game.goAttack mysqlConnection, request.uonline.basicOpts.userid, (error, result) ->
			if error?
				throw new Error(error)
			else
				response.redirect '/game/'


app.get '/action/escape', (request, response) ->
	unless request.uonline.basicOpts.loggedIn
		response.redirect '/login/'
	else
		utils.game.goEscape mysqlConnection, request.uonline.basicOpts.userid, (error, result) ->
			if error?
				throw new Error(error)
			else
				response.redirect '/game/'


app.get '/ajax/isNickBusy/:nick', (request, response) ->
	utils.user.userExists mysqlConnection, request.param('nick'), (error, result) ->
		if error?
			response.send 500
			return
		response.json
			nick: request.param('nick')
			isNickBusy: result


#app.get('/stats/', phpgate);
#app.get('/world/', phpgate);
#app.get('/development/', phpgate);


# 404 handling
app.get '*', (request, response) ->
	quickRenderError request, response, 404


# Exception handling
app.use (error, request, response, next) ->
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
