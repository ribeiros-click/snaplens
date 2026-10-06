<?php
// Limpeza de links expirados. Cron: php /home/.../public_html/cleanup.php
// Via HTTP exige chave de API de um administrador.
declare(strict_types=1);
require __DIR__ . '/lib.php';
if (PHP_SAPI !== 'cli') { $u = require_key(); if (!$u['is_admin']) { json_out(403, ['error' => 'somente administradores']); } }
$n = prune();
if (PHP_SAPI === 'cli') { echo "removidos: $n\n"; } else { json_out(200, ['removed' => $n]); }
