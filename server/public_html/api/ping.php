<?php
declare(strict_types=1);
require __DIR__ . '/../lib.php';
require_key();
$n = count(glob(META_DIR . '/*.json') ?: []);
json_out(200, ['ok' => true, 'message' => "Conectado a " . ($_SERVER['HTTP_HOST'] ?? '') . " · $n link(s) ativo(s)"]);
