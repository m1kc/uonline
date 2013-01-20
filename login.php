<?php

$time_start = microtime(true);

require_once './Twig/Autoloader.php';
Twig_Autoloader::register();
$loader = new Twig_Loader_Filesystem('./templates');
$twig = new Twig_Environment($loader, array(
   //'cache' => './templates_cache', // UNCOMMENT LATER
   'cache' => false,
));



require_once('utils.php');
$error = false; $s = $_COOKIE['sessid'];
if ($s && strlen($s)==64 && sessionExists($s) && sessionActive($s) ) header('Location: index.php');

if ($_POST) {
   $u = $_POST['user']; $p = $_POST['pass'];
   if ( correctUserName($u) && userExists($u) && correctPassword($p) && validPassword($u, $p) ) {
      $s = setSession($u);
      setcookie('sessid', $s);
      header('Location: index.php');
   }
   else {
       if ( !correctUserName($u) || !correctPassword($p) ) $error = true;
       else if ( !userExists($u) ) $error = true;
       else $error = true;
    }
}
else $error = false;


echo $twig->render('login.twig', array(
   'admin' => false,
   'loggedIn' => sessionActive($s),
   'login' => userBySession($s),
   'mail_count' => 0,

   'error' => $error
));

$time_end = microtime(true);
echo "\n<!-- Done in ".( ($time_end - $time_start) *1000).' milliseconds -->';

?>
