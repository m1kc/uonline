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
utils = require './utils.js'
async = require 'async'
sync = require 'sync'
dashdash = require 'dashdash'

anyDB = null
createAnyDBConnection = (url) ->
	anyDB = require 'any-db' unless anyDB?
	anyDB.createConnection(url)


checkError = (error, dontExit) ->
	if error?
		console.error error
		unless dontExit then process.exit 1


checkArgs = (passed, available) ->
	unless passed in available
		console.error "Unknown argument: #{passed}"
		console.error "Available: #{available}"
		process.exit 1


options = [
	names: [
		'help'
		'h'
	]
	type: 'bool'
	help: 'Print this help and exit.'
,
	names: [
		'info'
		'i'
	]
	type: 'bool'
	help: 'Show current revision and status.'
,
	names: [
		'create-database'
		'C'
	]
	type: 'string'
	help: 'Create database: "main", "test" or "both".'
,
	names: [
		'drop-database'
		'D'
	]
	type: 'string'
	help: 'Drop database: "main", "test" or "both".'
,
	names: [
		'migrate-tables'
		'm'
	]
	type: 'bool'
	help: 'Migrate to the latest revision.'
]


parser = dashdash.createParser(options: options)

try
	opts = parser.parse process.argv
catch exception
	console.error 'error: ' + exception.message
	process.exit 1

if opts._args.length > 0
	console.error "error: unexpected argument '#{opts._args[0]}'"
	process.exit 1

if opts._order.length is 0
	opts.help = true
	opts._order.push(key: 'help', value: true, from: 'argv')

# Some other schema:
#  'help', 'h', 'Show this text'
#  'info', 'i', 'Show current revision and status'
#  'tables', 't', 'Migrate tables to the last revision'
#  'unify-validate', 'l', 'Validate unify files'
#  'unify-export', 'u', 'Parse unify files and push them to database'
#  'optimize', 'o', 'O', 'Optimize tables'
#  'test-monsters', 'm', 'Insert test monsters'
#  'drop', 'd', 'Drop all tables and set revision to -1'
# [--database] [--tables] [--unify-validate] [--unify-export] [--optimize] [--test-monsters] [--drop]

#if opts.create_database?
#	func_count = 0
#	create = (db_url) ->
#		func_count++
#		db_path = db_url.match(/.+\//)[0]
#		db_name = db_url.match(/[^\/]+$/)[0]
#		conn = anyDB.createConnection(db_path)
#		conn.query 'CREATE DATABASE ' + db_name, [], (error, result) ->
#			func_count--
#			checkError error, func_count isnt 0
#			console.log "#{db_name} created."
#			process.exit 0 if func_count is 0
#	create config.MYSQL_DATABASE_URL if opts.create_database is 'main' or opts.create_database is 'both'
#	create config.MYSQL_DATABASE_URL_TEST if opts.create_database is 'test' or opts.create_database is 'both'

help = () ->
	console.log "\nUsage: node init.js <commands>\n\n#{parser.help(includeEnv: true).trimRight()}"
	process.exit 2


info = () ->
	mysqlConnection = createAnyDBConnection(config.MYSQL_DATABASE_URL)
	result = utils.migration.getCurrentRevision.sync(null, mysqlConnection)
	newest = utils.migration.getNewestRevision()
	status = if result < newest then 'needs update' else 'up to date'
	console.log "init.js with #{newest + 1} revisions on board."
	console.log "Current revision is #{result} (#{status})."
	process.exit 0


createDatabase = (arg) ->
	checkArgs arg, ['main', 'test', 'both']
	
	create = (db_url) ->
		[_, db_path, db_name] = db_url.match(/(.+)\/(.+)/)
		conn = createAnyDBConnection(db_path)
		try
			conn.query.sync(conn, 'CREATE DATABASE ' + db_name, [])
			console.log "#{db_name} created."
		catch error
			if error.code != 'ER_DB_CREATE_EXISTS'
				throw error
			console.log "#{db_name} already exists."
	
	create config.MYSQL_DATABASE_URL if arg in ['main', 'both']
	create config.MYSQL_DATABASE_URL_TEST if arg in ['test', 'both']


dropDatabase = (arg) ->
	checkArgs opts.drop_database, ['main', 'test', 'both']
	
	drop = (db_url, callback) ->
		[_, db_path, db_name] = db_url.match(/(.+)\/(.+)/)
		conn = createAnyDBConnection(db_path)
		conn.query 'DROP DATABASE ' + db_name, [], (error, result) ->
			if error?
				if error.code != 'ER_DB_DROP_EXISTS'
					callback error
					return
				console.log "#{db_name} already dropped."
			else
				console.log "#{db_name} dropped."
			callback null
	
	fut = []
	fut.push(drop.future null, config.MYSQL_DATABASE_URL) if arg in ['main', 'both']
	fut.push(drop.future null, config.MYSQL_DATABASE_URL_TEST) if arg in ['test', 'both']
	fut.forEach (f) -> f.result


migrateTables = () ->
	mysqlConnection = createAnyDBConnection(config.MYSQL_DATABASE_URL)
	utils.migration.migrate.sync null, mysqlConnection

sync () ->
		help() if opts.help
		info() if opts.info
		dropDatabase(opts.drop_database) if opts.drop_database
		createDatabase(opts.create_database) if opts.create_database
		migrateTables() if opts.migrate_tables
		process.exit 0
	,
		(error) -> throw error if (error) #КАСТЫЛЬ

