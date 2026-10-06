<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';
logout_user();
header('Location: /');
