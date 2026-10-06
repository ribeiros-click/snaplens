<?php
// SnapLens — biblioteca comum do serviço de links públicos.
declare(strict_types=1);

$CONFIG = require __DIR__ . '/config.php';
define('DATA_DIR', __DIR__ . '/_data');
define('META_DIR', DATA_DIR . '/meta');
define('FILES_DIR', DATA_DIR . '/files');

foreach ([DATA_DIR, META_DIR, FILES_DIR] as $d) {
    if (!is_dir($d)) { @mkdir($d, 0755, true); }
}
if (!file_exists(DATA_DIR . '/.htaccess')) {
    @file_put_contents(DATA_DIR . '/.htaccess', "Require all denied\n");
}

function json_out(int $status, array $body): never {
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode($body, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

function require_key(): void {
    global $CONFIG;
    $given = $_SERVER['HTTP_X_LENS_KEY'] ?? '';
    if ($CONFIG['upload_key'] === '' || !hash_equals($CONFIG['upload_key'], $given)) {
        json_out(401, ['error' => 'chave de upload inválida']);
    }
}

function valid_id(?string $id): ?string {
    return ($id !== null && preg_match('/^[A-Za-z0-9]{10}$/', $id)) ? $id : null;
}

function new_id(): string {
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    do {
        $id = '';
        for ($i = 0; $i < 10; $i++) { $id .= $alphabet[random_int(0, strlen($alphabet) - 1)]; }
    } while (file_exists(META_DIR . "/$id.json"));
    return $id;
}

function read_meta(string $id): ?array {
    $p = META_DIR . "/$id.json";
    if (!is_file($p)) { return null; }
    $m = json_decode((string) file_get_contents($p), true);
    return is_array($m) ? $m : null;
}

function write_meta(string $id, array $m): void {
    file_put_contents(META_DIR . "/$id.json", json_encode($m), LOCK_EX);
}

function is_expired(array $m): bool {
    return !empty($m['expires_at']) && time() >= (int) $m['expires_at'];
}

function delete_share(string $id): void {
    @unlink(META_DIR . "/$id.json");
    foreach (glob(FILES_DIR . "/$id.*") ?: [] as $f) { @unlink($f); }
}

/** Remove links expirados. Barato o suficiente para rodar a cada upload. */
function prune(): int {
    $n = 0;
    foreach (glob(META_DIR . '/*.json') ?: [] as $p) {
        $m = json_decode((string) file_get_contents($p), true);
        if (is_array($m) && is_expired($m)) { delete_share(basename($p, '.json')); $n++; }
    }
    return $n;
}

function base_url(): string {
    global $CONFIG;
    if (!empty($CONFIG['base_url'])) { return rtrim($CONFIG['base_url'], '/'); }
    $https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') || ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https';
    return ($https ? 'https' : 'http') . '://' . ($_SERVER['HTTP_HOST'] ?? 'localhost');
}

function human_size(int $b): string {
    if ($b < 1024) { return "$b B"; }
    if ($b < 1048576) { return round($b / 1024) . ' KB'; }
    return round($b / 1048576, 1) . ' MB';
}

function human_expiry(?int $ts): string {
    if (!$ts) { return 'não expira'; }
    $s = $ts - time();
    if ($s <= 0) { return 'expirado'; }
    if ($s < 3600) { return 'expira em ' . max(1, intdiv($s, 60)) . ' min'; }
    if ($s < 2 * 86400) { return 'expira em ' . (int) round($s / 3600) . ' h'; }
    return 'expira em ' . (int) round($s / 86400) . ' dias';
}
