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


requireCovered = require '../require-covered.coffee'
queryUtils = requireCovered __dirname, '../lib/query_utils.coffee'
config = require '../config'
sync = require 'sync'
anyDB = require 'any-db'
transaction = require 'any-db-transaction'
mg = require '../lib/migration'
_conn = null
conn = null
query = null

exports.setUp = (->
	unless _conn?
		_conn = anyDB.createConnection(config.DATABASE_URL_TEST)
		mg.migrate.sync mg, _conn
	conn = transaction(_conn)
	conn.query.sync conn, 'CREATE TABLE test_table (id INT, data TEXT)'
	conn.query.sync conn, "INSERT INTO test_table (id, data) VALUES (1, 'first')"
	conn.query.sync conn, "INSERT INTO test_table (id, data) VALUES (2, 'second')"
	query = queryUtils.getFor conn
).async()

exports.tearDown = (->
	conn.rollback.sync(conn)
).async()


exports.itself = (test) ->
	result = query "INSERT INTO test_table (id, data) VALUES (3, 'third')"
	test.deepEqual typeof(result), 'object', 'should return dbConnection.query result'
	test.deepEqual result.command, 'INSERT', 'should return correct dbConnection.query result'

	result = query.all 'SELECT * FROM test_table'
	test.strictEqual result.length, 3, 'should execute the given query'
	test.done()


exports.all = (test) ->
	rows = query.all 'SELECT * FROM test_table ORDER BY id'
	test.deepEqual rows, [
		{id: 1, data: 'first'}
		{id: 2, data: 'second'}
	], 'should return rows from query'
	test.done()


exports.row = (test) ->
	row = query.row 'SELECT * FROM test_table WHERE id = 1'
	test.deepEqual row, {id: 1, data: 'first'}, 'should return the first and only row from query'

	test.throws (->
		query.row 'SELECT * FROM test_table'
	), Error, 'should throw error if more than one row returned'

	test.throws (->
		query.row 'SELECT * FROM test_table WHERE id = 3'
	), Error, 'should throw error if no rows returned'
	test.done()

exports.val = (test) ->
	data = query.val 'SELECT data FROM test_table WHERE id = 2'
	test.deepEqual data, 'second', 'should return the first and only value from the first and only row'

	test.throws (->
		query.val 'SELECT id, data FROM test_table WHERE id = 2'
	), Error, 'should throw error if more than one value returned'

	test.throws (->
		query.val 'SELECT * FROM test_table'
	), Error, 'should throw error if more than one row returned'

	test.throws (->
		query.val 'SELECT * FROM test_table WHERE id = 3'
	), Error, 'should throw error if no rows returned'
	test.done()

exports.ins = (test) ->
	query.ins 'test_table', id: 3, data: 'third'
	count = +query.val 'SELECT count(*) FROM test_table'
	data = query.val 'SELECT data FROM test_table WHERE id = 3'

	test.strictEqual count, 3, 'should insert one row'
	test.strictEqual data, 'third', 'should add strings correctly'
	test.done()


exports.doInTransaction = (test) ->
	count = -> +query.val 'SELECT count(*) FROM test_table'

	# normal test
	queryUtils.doInTransaction conn, (tx) ->
		tx.query.sync tx, "INSERT INTO test_table VALUES (3, 'something')"
		tx.query.sync tx, "INSERT INTO test_table VALUES (4, 'very something')"
	test.strictEqual count(), 4, 'should execute function and commit transaction'

	# error in query
	test.throws(
		-> queryUtils.doInTransaction conn, (tx) ->
			# uncomment this line and it will break all DB connection
			#tx.query.sync tx, "SELECT first transaction query with error"
			tx.query.sync tx, "INSERT INTO test_table VALUES (3, 'something')"
			tx.query.sync tx, "INSERT INTO no_such_table VALUES ('nothing')"
		Error
		'should throw exception from inner function'
	)
	test.strictEqual count(), 4, 'should rollback transaction'

	# non-query error
	test.throws(
		-> queryUtils.doInTransaction conn, (tx) ->
			tx.query.sync tx, "INSERT INTO test_table VALUES (3, 'something')"
			throw new Error 'something fell up and broke down'
		Error
		'should throw exception from inner function'
	)
	test.strictEqual count(), 4, 'should rollback transaction'

	# normal test, again
	queryUtils.doInTransaction conn, (tx) ->
		tx.query.sync tx, "INSERT INTO test_table VALUES (5, 'one more thing')"
	test.strictEqual count(), 5, 'should correctly perform after some errors'
	test.done()

