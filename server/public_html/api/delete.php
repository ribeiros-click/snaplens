<?php
declare(strict_types=1);
require __DIR__ . '/../lib.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') { json_out(405, ['error' => 'use POST']); }
require_key();

$in = json_decode((string) file_get_contents('php://input'), true) ?: $_POST;
$id = valid_id($in['id'] ?? null);
$token = (string) ($in['token'] ?? '');
if (!$id) { json_out(400, ['error' => 'id inválido']); }

$m = read_meta($id);
if (!$m) { json_out(404, ['error' => 'link não encontrado']); }
if (!hash_equals($m['token_hash'], hash('sha256', $token))) { json_out(403, ['error' => 'token inválido']); }

delete_share($id);
json_out(200, ['ok' => true]);
