<?php
// SnapLens — biblioteca comum: banco (SQLite), contas, sessão, chaves de API e links.
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
        $db->exec('PRAGMA foreign_keys=ON');
        $db->exec('CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY, email TEXT UNIQUE NOT NULL, name TEXT NOT NULL, pass_hash TEXT NOT NULL,
            api_key_hash TEXT UNIQUE, api_key_hint TEXT, is_admin INTEGER DEFAULT 0, is_blocked INTEGER DEFAULT 0,
            created_at INTEGER, last_login_at INTEGER, failed_logins INTEGER DEFAULT 0, locked_until INTEGER DEFAULT 0)');
        $db->exec('CREATE TABLE IF NOT EXISTS links (
            id TEXT PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            ext TEXT, mime TEXT, width INTEGER, height INTEGER, size INTEGER,
            created_at INTEGER, expires_at INTEGER, views INTEGER DEFAULT 0, token_hash TEXT)');
        $db->exec('CREATE INDEX IF NOT EXISTS links_user ON links(user_id)');
        $db->exec('CREATE INDEX IF NOT EXISTS links_exp ON links(expires_at)');
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

// ---------- Sessão e autenticação web ----------

function session(): void {
    if (session_status() === PHP_SESSION_ACTIVE) { return; }
    session_name('lens_sess');
    session_set_cookie_params(['lifetime' => 0, 'path' => '/', 'secure' => is_https(), 'httponly' => true, 'samesite' => 'Lax']);
    session_start();
}
function is_https(): bool {
    return (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') || ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https';
}
function current_user(): ?array {
    session();
    if (empty($_SESSION['uid'])) { return null; }
    $u = row('SELECT * FROM users WHERE id = ?', [(int) $_SESSION['uid']]);
    if (!$u || $u['is_blocked']) { unset($_SESSION['uid']); return null; }
    return $u;
}
function require_login(): array {
    $u = current_user();
    if (!$u) { flash('Entre para continuar.'); redirect('/entrar?next=' . urlencode($_SERVER['REQUEST_URI'] ?? '/painel')); }
    return $u;
}
function require_admin(): array {
    $u = require_login();
    if (!$u['is_admin']) { http_response_code(403); exit('Acesso restrito.'); }
    return $u;
}
function login_user(int $id): void {
    session();
    session_regenerate_id(true);
    $_SESSION['uid'] = $id;
    run('UPDATE users SET last_login_at = ?, failed_logins = 0, locked_until = 0 WHERE id = ?', [time(), $id]);
}
function logout_user(): void {
    session();
    $_SESSION = [];
    if (ini_get('session.use_cookies')) { setcookie(session_name(), '', time() - 3600, '/'); }
    session_destroy();
}
function flash(?string $msg = null, string $kind = 'info'): ?array {
    session();
    if ($msg !== null) { $_SESSION['flash'] = ['msg' => $msg, 'kind' => $kind]; return null; }
    $f = $_SESSION['flash'] ?? null; unset($_SESSION['flash']); return $f;
}
function csrf_token(): string {
    session();
    if (empty($_SESSION['csrf'])) { $_SESSION['csrf'] = bin2hex(random_bytes(16)); }
    return $_SESSION['csrf'];
}
function csrf_check(): void {
    session();
    if (!hash_equals($_SESSION['csrf'] ?? '', (string) ($_POST['csrf'] ?? ''))) { http_response_code(400); exit('Sessão expirada. Volte e tente de novo.'); }
}

// ---------- Chaves de API ----------

function new_api_key(): string { return 'lens_' . bin2hex(random_bytes(20)); }
function set_api_key(int $uid): string {
    $k = new_api_key();
    run('UPDATE users SET api_key_hash = ?, api_key_hint = ? WHERE id = ?', [hash('sha256', $k), substr($k, -4), $uid]);
    return $k;
}
/** Autentica uma chamada de API pelo header X-Lens-Key. Devolve o usuário. */
function require_key(): array {
    $given = trim((string) ($_SERVER['HTTP_X_LENS_KEY'] ?? ''));
    if ($given === '') { json_out(401, ['error' => 'chave de API ausente — crie sua conta em ' . base_url() . '/cadastro']); }
    $u = row('SELECT * FROM users WHERE api_key_hash = ?', [hash('sha256', $given)]);
    if (!$u) { json_out(401, ['error' => 'chave de API inválida — confira no seu painel em ' . base_url() . '/painel']); }
    if ($u['is_blocked']) { json_out(403, ['error' => 'conta bloqueada — fale com ' . cfg('contact_email', 'contato@ribeiros.click')]); }
    return $u;
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
function user_usage(int $uid): array {
    $r = row('SELECT COUNT(*) AS n, COALESCE(SUM(size),0) AS bytes FROM links WHERE user_id = ?', [$uid]);
    return ['links' => (int) $r['n'], 'bytes' => (int) $r['bytes']];
}

// ---------- Utilidades ----------

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
