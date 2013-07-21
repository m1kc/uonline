<?php


/*
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

require_once './config.php';

if (isset($argv)) {
	if (array_key_exists(1, $argv) && $argv[1] == "--validate") {
		$p = new Parser();
		if (!(array_key_exists(2, $argv) && get_path($argv[2]))) die("Path not exists.");
		$p->processDir(get_path($argv[2]), null, true);
		echo "\n".report($p)."\n";
	}
	else if (array_key_exists(1, $argv) && $argv[1] == "--export") {
		$p = new Parser();
		if (!(array_key_exists(2, $argv) && get_path($argv[2]))) die("Path not exists.");
		$p->processDir(get_path($argv[2]), null, true);
		echo "\n".report($p)."\n";

		$i = new Injector($p->areas, $p->locations);
		$i->inject();
	}
	else if (array_key_exists(1, $argv) && $argv[1] == "--help") die(help());
}

function report($p) {
	return
		"found areas: ".count($p->areas)."\n".
		"found locations: ".count($p->locations->locations);
}

function get_path($p) {
	if (is_dir($p) && is_dir(__DIR__."/".$p)) return $p;
	else if (is_dir(__DIR__."/".$p)) return __DIR__."/".$p;
	else if (is_dir($p)) return $p;
	else return false;
}

function help() {
	return
	"[ --validate | --export ] path";
}

class Area {
	public $label, $name, $description, $id;

	public function &__construct($label = "", $name = "", $description = "") {
		if (!$this->label) $this->label = $label;
		if (!$this->name) $this->name = $name;
		if (!$this->description) $this->description = $description;
		if (!$this->id) $this->id = round(abs(crc32($label))/2);
		return $this;
	}
}

class Location {
	public $label, $name, $description = "", $actions, $area, $id;

	public function &__construct($label = "", $name = "", $area = null, $description = "", $actions = "") {
		if (!$this->label) $this->label = $label;
		if (!$this->name) $this->name = $name;
		if (!$this->description) $this->description = $description;
		if (!$this->actions) $this->actions = $actions;
		if (!$this->area) $this->area = $area;
		if (!$this->id) $this->id = round(abs(crc32($label))/2);
		return $this;
	}
}

class Locations {
	public $locations = array();
	public $links = array();
	public $ids = array();

	public function count() {
		return count($this->locations);
	}

	public function push($loc) {
		$this->links[$loc->label] = $loc->id;
		$this->ids[$loc->id] = $loc;
		$this->locations[] = $loc;
	}

	public function get($ind) {
		return $this->locations[$ind];
	}

	public function getById($id) {
		return $this->ids[$id];
	}

	public function last() {
		return end($this->locations);
	}

	public function unlink($label) {
		// fatal error #1
		if (!array_key_exists($label, $this->links)) die("required location not exists");
		return $this->links[$label];
	}

	public function trimDesc() {
		foreach ($this->locations as $l) {
			$l->description = trim($l->description);
		}
	}

	public function &__construct() {
		return $this;
	}
}

class Parser {

	public $areas = array(), $locations;

	function processDir($dir, $previousLabel, $root) {
		if ($root === false) {
			$splittedStr = explode(" - ", myexplode("/", $dir, -1));
			// fatal error #4
			if (!$splittedStr[1]) die("can't find label of area");
			$label = $splittedStr[1];
			if ($previousLabel != null) $label = $previousLabel."-".$label;
			$name = $splittedStr[0];
			$this->areas[] = new Area(iconv(mb_detect_encoding($label, "utf-8, cp1251"), 'utf-8', $label), iconv(mb_detect_encoding($name, "utf-8, cp1251"), 'utf-8', $name));

			$this->processMap($dir."/map.ht.md", end($this->areas));
		}
		$myDirectory=opendir($dir);
			while($name=readdir($myDirectory)) {
			if (is_dir($dir.'/'.$name) && ($name != ".") && ($name != "..") && !startsWith($name, ".")) {
				if ($root) {
					$this->processDir($dir.'/'.$name, null, false);
				}
				else {
					$this->processDir($dir.'/'.$name, end($this->areas)->label, false);
				}
			}
		}
	}

	function fileWarning($warning, $filename, $line, $str = null)
	{
		echo "Warning: ${warning}\n";
		if ($str !== null) echo "    ${str}\n";
		echo "    line ${line} in ${filename}\n";
	}

	function fileFatal($warning, $filename, $line, $str = null)
	{
		echo "Fatal: ${warning}\n";
		if ($str !== null) echo "    ${str}\n";
		echo "    line ${line} in ${filename}\n";
		die();
	}

	function processMap($filename, $area) {
		$inLocation = false;
		foreach(explode("\n", str_replace("\r\n", "\n", file_get_contents($filename))) as $k => $s) {
			$k++;
			// warning #1
			if (preg_match('/^#[^# ].+/', $s))
			{
				$this->fileWarning("missing space after '#'",$filename,$k,$s);
			}
			// warning #2
			if (preg_match('/^###[^ ].+/', $s))
			{
				$this->fileWarning("missing space after '###'",$filename,$k,$s);
			}
			// warning #3
			if (preg_match('/^\\*[^ \\*].+/', $s))
			{
				$this->fileWarning("missing space after '*'",$filename,$k,$s);
			}
			// warning #4
			if (preg_match('/^\\s+$/', $s))
			{
				$this->fileWarning("string with spaces only",$filename,$k);
			}
			// warning #5
			if (preg_match('/[^\\s]\\s+$/', $s))
			{
				$this->fileWarning("string ends with spaces",$filename,$k,$s);
			}
			// warning #6
			if (preg_match('/^\\s+[^\\s]/', $s))
			{
				$this->fileWarning("string starts with spaces",$filename,$k,$s);
			}
			// warning #7
			if (preg_match('/^\\s+[^\\s]/', $s))
			{
				$this->fileWarning("non-empty string before area header",$filename,$k,$s);
			}

			if (startsWith($s, "# ")) {
				// fatal error #6
				if (substr($s, 2) != $area->name) die("area's names from directory and file not equals");
			}
			else if (startsWith($s, "### ")) {
				$inLocation = true;
				$tmp = substr($s, 4);
				// fatal error #3
				if (!myexplode(" - ", $tmp, 1)) die("can't find label of location");
				// fatal error #5
				if (count(explode("/", myexplode(" - ", $tmp, 1)))>1) die("more than one slash at location label");
				$l = new Location($area->label . "/" . myexplode(" - ", $tmp, 1), myexplode(" - ", $tmp, 0), $area);
				$this->locations->push($l);
			}
			else if (startsWith($s, "* ")) {
				$tmp = substr($s, 2);
				$tmpAction = myexplode(" - ", $tmp, 0);
				$tmpTarget = myexplode(" - ", $tmp, 1);
				// fatal error #2
				if (!$tmpTarget) die("can't find target of transition");
				if (strpos($tmpTarget, '/') === false) $tmpTarget = $area->label . "/" . $tmpTarget;
				$this->locations->last()->actions[$tmpAction] = $tmpTarget;
			}
			else {
				if ($inLocation) {
					$this->locations->last()->description .= $s."\n";
				}
				else {
					end($this->areas)->description .= $s."\n";
				}
			}
		}
		$this->locations->trimDesc();
		foreach ($this->areas as $a) {
			$a->description = trim($a->description);
		}
	}

	public function &__construct() {
		$this->locations = new Locations();
		return $this;
	}
}

class Injector {

	public $areas, $locations;

	public function &__construct($areas, $locations) {
		$this->areas = $areas;
		$this->locations = $locations;
		return $this;
	}

	public function inject($host = MYSQL_HOST, $user = MYSQL_USER, $pass = MYSQL_PASS, $base = MYSQL_BASE) {
		$conn = mysqli_connect($host, $user, $pass);
		mysqli_select_db($conn, $base);

		foreach ($this->areas as $v) {
			$r = mysqli_query($conn,
							"REPLACE `areas`".
							"(`title`, `description`, `id`)".
							"VALUES ('".
								mysqli_real_escape_string($conn, $v->name)."', '".
								mysqli_real_escape_string($conn, $v->description)."', ".
								mysqli_real_escape_string($conn, $v->id).")");
			if (!$r) echo($conn->error);
		}
		foreach ($this->locations->locations as $v) {
			$goto = array();
			foreach ($v->actions as $k1 => $v1) {
				$goto[] = $k1."=".$this->locations->unlink($v1);
			}
			$r = mysqli_query($conn,
							'REPLACE `locations`'.
							'(`title`, `goto`, `description`, `id`, `area`, `default`)'.
							'VALUES ("'.
								mysqli_real_escape_string($conn, $v->name).'", "'.
								mysqli_real_escape_string($conn, implode($goto, "|")).'", "'.
								mysqli_real_escape_string($conn, $v->description).'", "'.
								mysqli_real_escape_string($conn, $v->id).'", '.
								mysqli_real_escape_string($conn, $v->area->id).', 0)');
			if (!$r) echo($conn->error);
			$r = $conn->query("SELECT * FROM `locations` WHERE `id` = $v->id");
			if (!$r) echo("export location \"$v->name - $v->label\" failed");
		}
	}
}

function startsWith($haystack, $needle) {
	return !strncmp($haystack, $needle, strlen($needle));
}

function endsWith($haystack, $needle) {
	$length = strlen($needle);
	if ($length == 0) {
		return true;
	}
	return (substr($haystack, -$length) === $needle);
}

function myexplode($pattern , $string, $index) {
	$tmp = explode($pattern, $string);
	if ($index == -1) $index = count($tmp) - 1;
	return array_key_exists($index, $tmp) ? $tmp[$index] : false;
}

?>
