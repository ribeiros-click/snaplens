<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';
require __DIR__ . '/_inc.php';

$err = '';
$done = '';
$link = null;
$token = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = (string) ($_POST['action'] ?? '');
    $token = trim((string) ($_POST['token'] ?? ''));
    $ip = (string) ($_SERVER['REMOTE_ADDR'] ?? 'cli');
    if (!rate_limit_ok($ip, (int) cfg('rate_limit_token', 30), (int) cfg('rate_limit_window', 3600))) {
        $err = 'Muitas tentativas seguidas. Tente novamente em alguns minutos.';
    } elseif (!preg_match('/^[0-9a-f]{32}$/', $token)) {
        $err = 'Token não encontrado ou link já removido.';
    } else {
        $m = row('SELECT * FROM links WHERE token_hash = ?', [hash('sha256', $token)]);
        if ($m && is_expired($m)) { delete_share($m['id']); $m = null; }
        if (!$m) {
            $err = 'Token não encontrado ou link já removido.';
        } elseif ($action === 'delete') {
            if (empty($_POST['confirm'])) {
                $err = 'Marque a confirmação para apagar a imagem.';
                $link = $m;
            } else {
                delete_share($m['id']);
                $done = 'Imagem apagada.';
            }
        } else {
            $link = $m;
        }
    }
}

page_header('Acessar por token');
?>
<h1>Acessar por token</h1>
<p class="updated">Cole o token de exclusão gerado pelo app para localizar ou apagar sua imagem.</p>
<?php if ($err !== ''): ?><div class="flash error"><?= h($err) ?></div><?php endif; ?>
<?php if ($done !== ''): ?><div class="flash ok"><?= h($done) ?></div><?php endif; ?>
<?php if ($link): $url = base_url() . '/s/' . $link['id']; ?>
<h2>Imagem encontrada</h2>
<table class="list">
  <tr><th>Link</th><td><a href="<?= h($url) ?>" target="_blank"><?= h($url) ?></a></td></tr>
  <tr><th>Criado</th><td><?= fmt_date((int) $link['created_at']) ?></td></tr>
  <tr><th>Validade</th><td><?= h(human_expiry($link['expires_at'] !== null ? (int) $link['expires_at'] : null)) ?></td></tr>
  <tr><th>Visualizações</th><td><?= (int) $link['views'] ?></td></tr>
  <tr><th>Tamanho</th><td><?= h(human_size((int) $link['size'])) ?></td></tr>
  <tr><th>Ver apenas uma vez</th><td><?= !empty($link['once']) ? 'sim — se autodestrói após a primeira visualização' : 'não' ?></td></tr>
</table>
<form method="post" class="form">
  <input type="hidden" name="action" value="delete">
  <input type="hidden" name="token" value="<?= h($token) ?>">
  <label class="check"><input type="checkbox" name="confirm" value="1" required> Confirmo que quero apagar esta imagem do servidor.</label>
  <button class="btn danger" type="submit">Apagar imagem</button>
</form>
<?php else: ?>
<form method="post" class="form">
  <input type="hidden" name="action" value="lookup">
  <label class="field"><span>Token de exclusão</span><input name="token" value="<?= h($token) ?>" required minlength="32" maxlength="32" autocomplete="off"></label>
  <button class="btn primary big" type="submit">Localizar imagem</button>
</form>
<?php endif; ?>
<?php page_footer();
