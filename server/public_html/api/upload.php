<?php
declare(strict_types=1);
require __DIR__ . '/../lib.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') { json_out(405, ['error' => 'use POST']); }
prune();

if (!rate_limit_ok((string) ($_SERVER['REMOTE_ADDR'] ?? 'cli'), (int) cfg('rate_limit_uploads', 30), (int) cfg('rate_limit_window', 3600))) {
    json_out(429, ['error' => 'Muitos uploads seguidos. Tente novamente em alguns minutos.']);
}

$f = $_FILES['file'] ?? null;
if (!$f || ($f['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
    json_out(400, ['error' => 'arquivo ausente ou inválido (' . ($f['error'] ?? 'sem arquivo') . ')']);
}
$maxBytes = (int) cfg('max_bytes', 25 * 1024 * 1024);
if ((int) $f['size'] > $maxBytes) { json_out(413, ['error' => 'imagem maior que ' . human_size($maxBytes)]); }

$info = @getimagesize($f['tmp_name']);
$ext = match ($info['mime'] ?? '') {
    'image/png' => 'png', 'image/jpeg' => 'jpg', 'image/gif' => 'gif', 'image/webp' => 'webp', default => null,
};
if ($ext === null) { json_out(415, ['error' => 'somente imagens PNG, JPEG, GIF ou WebP']); }

$ttl = max(0, (int) ($_POST['expires'] ?? 0));
$maxTtl = (int) cfg('max_ttl', 0);
if ($maxTtl > 0 && ($ttl === 0 || $ttl > $maxTtl)) { $ttl = $maxTtl; }

$id = new_id();
if (!move_uploaded_file($f['tmp_name'], FILES_DIR . "/$id.$ext")) { json_out(500, ['error' => 'falha ao gravar o arquivo']); }

$token = bin2hex(random_bytes(16));
$expires = $ttl > 0 ? time() + $ttl : null;
run('INSERT INTO links (id, ext, mime, width, height, size, created_at, expires_at, views, token_hash) VALUES (?,?,?,?,?,?,?,?,0,?)',
    [$id, $ext, $info['mime'], (int) $info[0], (int) $info[1], (int) $f['size'], time(), $expires, hash('sha256', $token)]);

json_out(201, [
    'id'           => $id,
    'url'          => base_url() . "/s/$id",
    'image_url'    => base_url() . "/i/$id",
    'expires_at'   => $expires,
    'delete_token' => $token,
]);
