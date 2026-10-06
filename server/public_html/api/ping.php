<?php
declare(strict_types=1);
require __DIR__ . '/../lib.php';
$u = require_key();
$usage = user_usage((int) $u['id']);
json_out(200, ['ok' => true, 'message' => 'Conectado como ' . $u['email'] . ' · ' . $usage['links'] . ' link(s) ativo(s) · ' . human_size($usage['bytes'])]);
