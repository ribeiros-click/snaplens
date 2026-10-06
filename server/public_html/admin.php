<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';
require __DIR__ . '/_inc.php';

$me = require_admin();

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();
    $action = (string) ($_POST['action'] ?? '');
    $uid = (int) ($_POST['uid'] ?? 0);
    if ($action === 'block' && $uid !== (int) $me['id']) { run('UPDATE users SET is_blocked = 1 WHERE id = ?', [$uid]); flash('Usuário bloqueado.', 'ok'); }
    elseif ($action === 'unblock') { run('UPDATE users SET is_blocked = 0, failed_logins = 0, locked_until = 0 WHERE id = ?', [$uid]); flash('Usuário desbloqueado.', 'ok'); }
    elseif ($action === 'delete_user' && $uid !== (int) $me['id']) {
        foreach (rows('SELECT id FROM links WHERE user_id = ?', [$uid]) as $r) { delete_share($r['id']); }
        run('DELETE FROM users WHERE id = ?', [$uid]); flash('Usuário e links removidos.', 'ok');
    }
    elseif ($action === 'revoke') { $id = valid_id($_POST['id'] ?? null); if ($id) { delete_share($id); flash('Link removido.', 'ok'); } }
    elseif ($action === 'prune') { flash('Limpeza: ' . prune() . ' link(s) expirado(s) removido(s).', 'ok'); }
    redirect('/admin');
}

$users = rows('SELECT u.*, (SELECT COUNT(*) FROM links l WHERE l.user_id = u.id) AS n_links, (SELECT COALESCE(SUM(size),0) FROM links l WHERE l.user_id = u.id) AS bytes FROM users u ORDER BY created_at DESC');
$links = rows('SELECT l.*, u.email FROM links l JOIN users u ON u.id = l.user_id ORDER BY l.created_at DESC LIMIT 200');
$tot = row('SELECT COUNT(*) AS n, COALESCE(SUM(size),0) AS bytes FROM links');

page_header('Administração');
?>
<h1>Administração</h1>
<p class="updated"><?= count($users) ?> conta(s) · <?= (int) $tot['n'] ?> link(s) ativos · <?= h(human_size((int) $tot['bytes'])) ?> em disco</p>
<form method="post" class="inline"><input type="hidden" name="csrf" value="<?= h(csrf_token()) ?>"><input type="hidden" name="action" value="prune"><button class="btn" type="submit">Executar limpeza de expirados</button></form>

<h2>Contas</h2>
<table class="list">
  <tr><th>Usuário</th><th>Criada</th><th>Último acesso</th><th>Links</th><th>Uso</th><th>Estado</th><th></th></tr>
  <?php foreach ($users as $x): ?>
  <tr>
    <td><?= h($x['name']) ?><br><small class="muted"><?= h($x['email']) ?><?= $x['is_admin'] ? ' · admin' : '' ?></small></td>
    <td><?= fmt_date((int) $x['created_at']) ?></td>
    <td><?= fmt_date($x['last_login_at'] ? (int) $x['last_login_at'] : null) ?></td>
    <td><?= (int) $x['n_links'] ?></td>
    <td><?= h(human_size((int) $x['bytes'])) ?></td>
    <td><?= $x['is_blocked'] ? '<span class="tag bad">bloqueado</span>' : '<span class="tag ok">ativo</span>' ?></td>
    <td class="actions">
      <?php if ((int) $x['id'] !== (int) $me['id']): ?>
      <form method="post" class="inline"><input type="hidden" name="csrf" value="<?= h(csrf_token()) ?>"><input type="hidden" name="uid" value="<?= (int) $x['id'] ?>">
        <?php if ($x['is_blocked']): ?><button class="btn small" name="action" value="unblock">Desbloquear</button>
        <?php else: ?><button class="btn small" name="action" value="block">Bloquear</button><?php endif; ?>
        <button class="btn small danger" name="action" value="delete_user" onclick="return confirm('Excluir usuário e todos os links?')">Excluir</button></form>
      <?php endif; ?>
    </td>
  </tr>
  <?php endforeach; ?>
</table>

<h2>Links recentes</h2>
<table class="list">
  <tr><th>Link</th><th>Usuário</th><th>Criado</th><th>Validade</th><th>Visualiz.</th><th>Tamanho</th><th></th></tr>
  <?php foreach ($links as $l): ?>
  <tr>
    <td><a href="/s/<?= h($l['id']) ?>" target="_blank"><?= h($l['id']) ?></a></td>
    <td><small><?= h($l['email']) ?></small></td>
    <td><?= fmt_date((int) $l['created_at']) ?></td>
    <td><?= h(human_expiry($l['expires_at'] !== null ? (int) $l['expires_at'] : null)) ?></td>
    <td><?= (int) $l['views'] ?></td>
    <td><?= h(human_size((int) $l['size'])) ?></td>
    <td><form method="post" class="inline"><input type="hidden" name="csrf" value="<?= h(csrf_token()) ?>"><input type="hidden" name="action" value="revoke"><input type="hidden" name="id" value="<?= h($l['id']) ?>"><button class="btn small danger" type="submit">Remover</button></form></td>
  </tr>
  <?php endforeach; ?>
</table>
<?php page_footer();