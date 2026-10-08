<?php
// SnapLens — biblioteca comum: banco (SQLite), limite por IP, token de admin e links anônimos.
declare(strict_types=1);

$CONFIG = require __DIR__ . '/config.php';
define('DATA_DIR', __DIR__ . '/_data');
define('FILES_DIR', DATA_DIR . '/files');
define('DB_PATH', DATA_DIR . '/lens.sqlite');

foreach ([DATA_DIR, FILES_DIR] as $d) {
    if (!is_dir($d)) { @mkdir($d, 0755, true); }
}
if (!file_exists(DATA_DIR . '/.htaccess')) {
    @file_put_contents(DATA_DIR . '/.htaccess', "Require all denied\n");
}

function cfg(string $k, mixed $default = null): mixed {
    global $CONFIG;
    return $CONFIG[$k] ?? $default;
}

// ---------- Banco ----------

function db(): SQLite3 {
    static $db = null;
    if ($db === null) {
        $db = new SQLite3(DB_PATH);
        $db->busyTimeout(5000);
        $db->exec('PRAGMA journal_mode=WAL');
        $db->exec('PRAGMA foreign_keys=OFF');

        // Migração: links deixam de pertencer a contas (coluna user_id).
        $hasUserId = false;
        $info = $db->query('PRAGMA table_info(links)');
        while ($info && ($col = $info->fetchArray(SQLITE3_ASSOC))) {
            if ($col['name'] === 'user_id') { $hasUserId = true; }
        }
        if ($hasUserId) {
            $db->exec('BEGIN');
            $db->exec('CREATE TABLE links_new (
                id TEXT PRIMARY KEY, ext TEXT, mime TEXT, width INTEGER, height INTEGER, size INTEGER,
                created_at INTEGER, expires_at INTEGER, views INTEGER DEFAULT 0, token_hash TEXT)');
            $db->exec('INSERT INTO links_new SELECT id, ext, mime, width, height, size, created_at, expires_at, views, token_hash FROM links');
            $db->exec('DROP TABLE links');
            $db->exec('ALTER TABLE links_new RENAME TO links');
            $db->exec('COMMIT');
        }
        $db->exec('DROP TABLE IF EXISTS users');
        $db->exec('CREATE TABLE IF NOT EXISTS links (
            id TEXT PRIMARY KEY, ext TEXT, mime TEXT, width INTEGER, height INTEGER, size INTEGER,
            created_at INTEGER, expires_at INTEGER, views INTEGER DEFAULT 0, token_hash TEXT)');
        $db->exec('CREATE INDEX IF NOT EXISTS links_exp ON links(expires_at)');
        $db->exec('CREATE TABLE IF NOT EXISTS rate (ip TEXT NOT NULL, created_at INTEGER NOT NULL)');
        $db->exec('CREATE INDEX IF NOT EXISTS rate_ip ON rate(ip, created_at)');
        $db->exec('PRAGMA foreign_keys=ON');
    }
    return $db;
}

function stmt(string $sql, array $p = []): SQLite3Result {
    $st = db()->prepare($sql);
    if (!$st) { throw new RuntimeException(db()->lastErrorMsg()); }
    foreach (array_values($p) as $i => $v) {
        $st->bindValue($i + 1, $v, is_int($v) ? SQLITE3_INTEGER : (is_null($v) ? SQLITE3_NULL : SQLITE3_TEXT));
    }
    $r = $st->execute();
    if ($r === false) { throw new RuntimeException(db()->lastErrorMsg()); }
    return $r;
}
function row(string $sql, array $p = []): ?array { $r = stmt($sql, $p)->fetchArray(SQLITE3_ASSOC); return $r ?: null; }
function rows(string $sql, array $p = []): array {
    $res = stmt($sql, $p); $out = [];
    while ($r = $res->fetchArray(SQLITE3_ASSOC)) { $out[] = $r; }
    return $out;
}
function run(string $sql, array $p = []): void { stmt($sql, $p); }

// ---------- Respostas ----------

function json_out(int $status, array $body): never {
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode($body, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

function redirect(string $to): never { header("Location: $to"); exit; }
function h(?string $s): string { return htmlspecialchars((string) $s, ENT_QUOTES, 'UTF-8'); }

// ---------- Limite de requisições por IP ----------

/** Permite no máximo $max ações por IP dentro de $window segundos. */
function rate_limit_ok(string $ip, int $max, int $window): bool {
    $now = time();
    run('DELETE FROM rate WHERE created_at < ?', [$now - $window]);
    $n = (int) (row('SELECT COUNT(*) AS n FROM rate WHERE ip = ? AND created_at >= ?', [$ip, $now - $window])['n'] ?? 0);
    if ($n >= $max) { return false; }
    run('INSERT INTO rate (ip, created_at) VALUES (?,?)', [$ip, $now]);
    return true;
}

// ---------- Administração ----------

/** Exige o token de administração (config admin_token) passado em ?key=. */
function require_admin_token(): void {
    $expected = (string) cfg('admin_token', '');
    $given = (string) ($_REQUEST['key'] ?? '');
    if ($expected !== '' && hash_equals($expected, $given)) { return; }
    $script = basename((string) ($_SERVER['SCRIPT_NAME'] ?? ''));
    if ($script === 'cleanup.php') { json_out(403, ['error' => 'token de administração inválido']); }
    http_response_code(403);
    exit('Acesso restrito: token de administração ausente ou inválido.');
}

// ---------- Links ----------

function valid_id(?string $id): ?string {
    return ($id !== null && preg_match('/^[A-Za-z0-9]{10}$/', $id)) ? $id : null;
}
function new_id(): string {
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    do {
        $id = '';
        for ($i = 0; $i < 10; $i++) { $id .= $alphabet[random_int(0, strlen($alphabet) - 1)]; }
    } while (row('SELECT 1 FROM links WHERE id = ?', [$id]));
    return $id;
}
function read_meta(string $id): ?array { return row('SELECT * FROM links WHERE id = ?', [$id]); }
function write_meta(string $id, array $m): void { run('UPDATE links SET views = ? WHERE id = ?', [(int) ($m['views'] ?? 0), $id]); }
function is_expired(array $m): bool { return !empty($m['expires_at']) && time() >= (int) $m['expires_at']; }
function delete_share(string $id): void {
    run('DELETE FROM links WHERE id = ?', [$id]);
    foreach (glob(FILES_DIR . "/$id.*") ?: [] as $f) { @unlink($f); }
}
/** Remove links expirados. */
function prune(): int {
    $n = 0;
    foreach (rows('SELECT id FROM links WHERE expires_at IS NOT NULL AND expires_at <= ?', [time()]) as $r) { delete_share($r['id']); $n++; }
    return $n;
}

// ---------- Utilidades ----------

function is_https(): bool {
    return (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') || ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https';
}
function base_url(): string {
    $b = cfg('base_url', '');
    if ($b) { return rtrim($b, '/'); }
    return (is_https() ? 'https' : 'http') . '://' . ($_SERVER['HTTP_HOST'] ?? 'localhost');
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
function fmt_date(?int $ts): string { return $ts ? date('d/m/Y H:i', $ts) : '—'; }
