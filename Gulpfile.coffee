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

console.time 'Loading gulp'
gulp = require 'gulp'
console.timeEnd 'Loading gulp'

console.time 'Loading deps'
chalk = require 'chalk'
cleanDest = require 'gulp-clean-dest'
merge = require('./gulp-tasks/multimerge.coffee')(require('gulp-merge'))
source = require 'vinyl-source-stream'
buffer = require 'vinyl-buffer'
debug = require 'gulp-debug'
seq = require 'gulp-sequence'
console.timeEnd 'Loading deps'


gulp.task 'default', ->
	console.log ''
	console.log chalk.green "Specify a task, like #{chalk.blue 'build'} or #{chalk.blue 'watch'}."
	console.log chalk.green "Run #{chalk.blue 'gulp --tasks'} for some hints."
	console.log ''


gulp.task 'build', ->
	coffee = require 'gulp-coffee'
	uglify = require 'gulp-uglify'
	concat = require 'gulp-concat'
	browserify = require 'browserify'
	coffeeify = require 'coffeeify'
	return merge(
		gulp
		.src './bower_components/jquery/dist/jquery.min.js'
	,
		gulp
		.src './bower_components/bootstrap/dist/js/bootstrap.min.js'
	,
		gulp
		.src './bower_components/jquery-pjax/jquery.pjax.js'
		.pipe uglify()
	,
		gulp
		.src './browser.coffee'
		.pipe coffee()
		.pipe uglify()
	,
		browserify()
		.transform coffeeify
		.require './lib/validation.coffee', expose: 'validation'
		.bundle().pipe(source('validation.js')).pipe(buffer())  # epic wrapper, don't ask how does it work
		.pipe uglify()
	)
	.pipe concat 'scripts.js'
	.pipe cleanDest './assets'
	.pipe gulp.dest './assets'


gulp.task 'build-and-notify', ['build'], ->
	notify = require 'gulp-notify'
	return gulp
		.src ''
		.pipe notify 'Assets were rebuilt.'


gulp.task 'watch', ['build'], ->
	return gulp.watch ['./browser.coffee', './lib/validation.coffee'], ['build-and-notify']


# Experimental stuff

gulp.task 'check', ['jshint', 'coffee-jshint', 'coffeelint', 'mustcontain']

gulp.task 'test', seq 'nodeunit', 'jscoverage-report', 'force-exit'

gulp.task 'nodeunit', ->
	nodeunit = require 'gulp-nodeunit-runner'
	return gulp
		.src [
			'tests/health-check.js'
			'tests/health-check.coffee'
			'tests/*.js'
			#'tests/validation.coffee'
			'tests/*.coffee'
		]
		.pipe nodeunit(reporter: 'minimal')

gulp.task 'force-exit', ->
	process.exit 0


gulp.task 'jshint', ->
	jshint = require 'gulp-jshint'
	return gulp
		.src [
			'*.js'
			'lib/*.js'
			'tests/*.js'
			'grunt-custom-tasks/*.js'
		]
		.pipe jshint()
		.pipe jshint.reporter 'non_error'


gulp.task 'mustcontain', ->
	# TODO: mustcontain
	console.log 'mustcontain: Not implemented.'


gulp.task 'coffeelint', ->
	coffeelint = require 'gulp-coffeelint'
	return gulp
		.src [
			'*.coffee'
			'lib/*.coffee'
			'tests/*.coffee'
			'grunt-custom-tasks/*.coffee'
		]
		.pipe coffeelint './.coffeelintrc'
		.pipe coffeelint.reporter()


gulp.task 'coffee-jshint', ->
	# TODO: coffee-jshint
	console.log 'coffee-jshint: Not implemented.'


# This shit doesn't work 'cause it wants global codo
gulp.task 'docs', ->
	console.log chalk.red "Got a minute? Email the author of gulp-codo he's a faggot."
	return
	###
	codo = require 'gulp-codo'
	return gulp
		.src 'lib/*.coffee', read: false
		.pipe codo {
			name: 'uonline'
			title: 'uonline documentation'
			undocumented: true
			stats: false
		}
	###

gulp.task 'jscoverage-report', ->
	jscr = require './gulp-tasks/jscoverage-report.coffee'
	jscr()

# TODO: jscoverage write lcov

# TODO: coveralls
