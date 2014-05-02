all:
	# No. Specify a target.


monitor:
	./node_modules/nodemon/bin/nodemon.js -e 'coffee,js,twig,css' -x coffee main.coffee

grunt:
	./node_modules/grunt-cli/bin/grunt

david:
	./node_modules/david/bin/david.js

david-update:
	./node_modules/david/bin/david.js update

whattodo:
	( find -name '*.js' -or -name '*.coffee' -or -name '*.jade' ) | grep -v node_modules | xargs grep TODO -n --color
