<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';

$id = valid_id($_GET['id'] ?? null);
$m = $id ? read_meta($id) : null;
if (!$m || is_expired($m)) {
    if ($m) { delete_share($id); }
    http_response_code(410);
    header('Content-Type: text/plain; charset=utf-8');
    exit('Link expirado ou inexistente.');
}
$path = FILES_DIR . "/$id." . $m['ext'];
if (!is_file($path)) { http_response_code(404); exit; }

header('Content-Type: ' . $m['mime']);
header('Content-Length: ' . (string) filesize($path));
header('Cache-Control: private, max-age=300');
header('X-Content-Type-Options: nosniff');
if (isset($_GET['dl'])) { header("Content-Disposition: attachment; filename=\"snaplens-$id." . $m['ext'] . '"'); }
readfile($path);
