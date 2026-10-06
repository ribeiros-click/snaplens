<?php
// Limpeza de links expirados. Rode via cron: php /home/.../public_html/cleanup.php
// Via HTTP exige a chave: curl -H "X-Lens-Key: ..." https://lens.ribeiros.click/cleanup.php
declare(strict_types=1);
require __DIR__ . '/lib.php';
if (PHP_SAPI !== 'cli') { require_key(); }
$n = prune();
if (PHP_SAPI === 'cli') { echo "removidos: $n\n"; } else { json_out(200, ['removed' => $n]); }
