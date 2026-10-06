<?php
declare(strict_types=1);
require __DIR__ . '/../lib.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') { json_out(405, ['error' => 'use POST']); }
require_key();
prune();

$f = $_FILES['file'] ?? null;
if (!$f || ($f['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
    json_out(400, ['error' => 'arquivo ausente ou inválido (' . ($f['error'] ?? 'sem arquivo') . ')']);
}
if ((int) $f['size'] > (int) $CONFIG['max_bytes']) {
    json_out(413, ['error' => 'imagem maior que ' . human_size((int) $CONFIG['max_bytes'])]);
}

$info = @getimagesize($f['tmp_name']);
$ext = match ($info['mime'] ?? '') {
    'image/png' => 'png', 'image/jpeg' => 'jpg', 'image/gif' => 'gif', 'image/webp' => 'webp', default => null,
};
if ($ext === null) { json_out(415, ['error' => 'somente imagens PNG, JPEG, GIF ou WebP']); }

$ttl = max(0, (int) ($_POST['expires'] ?? 0));
if ((int) $CONFIG['max_ttl'] > 0 && ($ttl === 0 || $ttl > (int) $CONFIG['max_ttl'])) { $ttl = (int) $CONFIG['max_ttl']; }

$id = new_id();
if (!move_uploaded_file($f['tmp_name'], FILES_DIR . "/$id.$ext")) { json_out(500, ['error' => 'falha ao gravar o arquivo']); }

$token = bin2hex(random_bytes(16));
$meta = [
    'id'         => $id,
    'ext'        => $ext,
    'mime'       => $info['mime'],
    'width'      => $info[0],
    'height'     => $info[1],
    'size'       => (int) $f['size'],
    'created_at' => time(),
    'expires_at' => $ttl > 0 ? time() + $ttl : null,
    'views'      => 0,
    'token_hash' => hash('sha256', $token),
];
write_meta($id, $meta);

json_out(201, [
    'id'           => $id,
    'url'          => base_url() . "/s/$id",
    'image_url'    => base_url() . "/i/$id",
    'expires_at'   => $meta['expires_at'],
    'delete_token' => $token,
]);
