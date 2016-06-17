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

NS = 'health-check'; exports[NS] = {}  # namespace
{test, requireCovered, legacyConfig} = require '../lib/test-utils.coffee'

async = require 'asyncawait/async'


exports[NS] =
	'2+2 should be 4': ->
		test.strictEqual 2 + 2, 4
	'2+2 should be 4 in asynchronous manner': (done) ->
		test.strictEqual 2 + 2, 4
		process.nextTick done
	'2+2 should be 4 with async wrapper': async ->
		test.strictEqual 2 + 2, 4


# describe = require('mocha').describe
# it = require('mocha').it

# describe 'BDD via require UI', ->
# 	it 'should just work', ->
# 		test.isTrue true
# 	it '2+2 should also be 4', ->
# 		test.strictEqual 2+2, 4
