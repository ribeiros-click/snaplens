<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';
require __DIR__ . '/_inc.php';

$key = (string) ($_REQUEST['key'] ?? '');
if ($key === '') {
    page_header('Administração');
    ?>
<h1>Administração</h1>
<form method="get" class="form">
  <label class="field"><span>Token de administração</span><input type="password" name="key" required autocomplete="off"></label>
  <button class="btn primary big" type="submit">Entrar</button>
</form>
<?php
    page_footer();
    exit;
}
require_admin_token();

$msg = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = (string) ($_POST['action'] ?? '');
    if ($action === 'revoke') {
        $id = valid_id($_POST['id'] ?? null);
        if ($id && !empty($_POST['confirm'])) { delete_share($id); $msg = 'Link removido.'; }
    } elseif ($action === 'prune') {
        $msg = 'Limpeza: ' . prune() . ' link(s) expirado(s) removido(s).';
    }
}

$links = rows('SELECT * FROM links ORDER BY created_at DESC LIMIT 200');
$tot = row('SELECT COUNT(*) AS n, COALESCE(SUM(size),0) AS bytes FROM links');

page_header('Administração');
?>
<h1>Administração</h1>
<p class="updated"><?= (int) $tot['n'] ?> link(s) ativos · <?= h(human_size((int) $tot['bytes'])) ?> em disco</p>
<?php if ($msg !== ''): ?><div class="flash ok"><?= h($msg) ?></div><?php endif; ?>
<form method="post" class="inline"><input type="hidden" name="key" value="<?= h($key) ?>"><input type="hidden" name="action" value="prune"><button class="btn" type="submit">Rodar limpeza agora</button></form>

<h2>Links</h2>
<table class="list">
  <tr><th>Link</th><th>Criado</th><th>Validade</th><th>Visualiz.</th><th>Tamanho</th><th></th></tr>
  <?php foreach ($links as $l): ?>
  <tr>
    <td><a href="/s/<?= h($l['id']) ?>" target="_blank"><?= h($l['id']) ?></a></td>
    <td><?= fmt_date((int) $l['created_at']) ?></td>
    <td><?= h(human_expiry($l['expires_at'] !== null ? (int) $l['expires_at'] : null)) ?></td>
    <td><?= (int) $l['views'] ?></td>
    <td><?= h(human_size((int) $l['size'])) ?></td>
    <td><form method="post" class="inline"><input type="hidden" name="key" value="<?= h($key) ?>"><input type="hidden" name="action" value="revoke"><input type="hidden" name="id" value="<?= h($l['id']) ?>"><input type="hidden" name="confirm" value="1"><button class="btn small danger" type="submit" onclick="return confirm('Remover este link e a imagem?')">Remover</button></form></td>
  </tr>
  <?php endforeach; ?>
</table>
<?php page_footer();
