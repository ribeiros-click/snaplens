<?php
// Limpeza de links expirados. Cron: php /home/.../public_html/cleanup.php
// Via HTTP exige o token de administração (?key=...).
declare(strict_types=1);
require __DIR__ . '/lib.php';
if (PHP_SAPI !== 'cli') { require_admin_token(); }
$n = prune();
if (PHP_SAPI === 'cli') { echo "removidos: $n\n"; } else { json_out(200, ['removed' => $n]); }
