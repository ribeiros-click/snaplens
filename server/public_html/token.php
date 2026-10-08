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
        $err = t('Muitas tentativas seguidas. Tente novamente em alguns minutos.');
    } elseif (!preg_match('/^[0-9a-f]{32}$/', $token)) {
        $err = t('Token não encontrado ou link já removido.');
    } else {
        $m = row('SELECT * FROM links WHERE token_hash = ?', [hash('sha256', $token)]);
        if ($m && is_expired($m)) { delete_share($m['id']); $m = null; }
        if (!$m) {
            $err = t('Token não encontrado ou link já removido.');
        } elseif ($action === 'delete') {
            if (empty($_POST['confirm'])) {
                $err = t('Marque a confirmação para apagar a imagem.');
                $link = $m;
            } else {
                delete_share($m['id']);
                $done = t('Imagem apagada do servidor.');
            }
        } else {
            $link = $m;
        }
    }
}

page_header(t('Acessar por token'));
?>
<h1><?= t('Acessar por token') ?></h1>
<p class="updated"><?= t('Cole o token de exclusão gerado pelo app para localizar ou apagar sua imagem.') ?></p>
<?php if ($err !== ''): ?><div class="flash error"><?= h($err) ?></div><?php endif; ?>
<?php if ($done !== ''): ?><div class="flash ok"><?= h($done) ?></div><?php endif; ?>
<?php if ($link): $url = base_url() . '/s/' . $link['id']; ?>
<h2><?= t('Imagem encontrada') ?></h2>
<table class="list">
  <tr><th><?= t('Link') ?></th><td><a href="<?= h($url) ?>" target="_blank"><?= h($url) ?></a></td></tr>
  <tr><th><?= t('Criado') ?></th><td><?= fmt_date((int) $link['created_at']) ?></td></tr>
  <tr><th><?= t('Validade') ?></th><td><?= h(human_expiry($link['expires_at'] !== null ? (int) $link['expires_at'] : null)) ?></td></tr>
  <tr><th><?= t('Visualizações') ?></th><td><?= (int) $link['views'] ?></td></tr>
  <tr><th><?= t('Tamanho') ?></th><td><?= h(human_size((int) $link['size'])) ?></td></tr>
  <tr><th><?= t('Ver apenas uma vez') ?></th><td><?= !empty($link['once']) ? t('sim') . ' — ' . t('Esta imagem se autodestrói após a primeira visualização.') : t('não') ?></td></tr>
</table>
<form method="post" class="form">
  <input type="hidden" name="action" value="delete"><input type="hidden" name="lang" value="<?= h(lang()) ?>">
  <input type="hidden" name="token" value="<?= h($token) ?>">
  <label class="check"><input type="checkbox" name="confirm" value="1" required> <?= t('Confirmo que quero apagar esta imagem do servidor.') ?></label>
  <button class="btn danger" type="submit"><?= t('Apagar imagem') ?></button>
</form>
<?php else: ?>
<form method="post" class="form">
  <input type="hidden" name="action" value="lookup"><input type="hidden" name="lang" value="<?= h(lang()) ?>">
  <label class="field"><span><?= t('Token de exclusão') ?></span><input name="token" value="<?= h($token) ?>" required minlength="32" maxlength="32" autocomplete="off"></label>
  <button class="btn primary big" type="submit"><?= t('Localizar imagem') ?></button>
</form>
<?php endif; ?>
<?php page_footer();
