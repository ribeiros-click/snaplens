<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';
require __DIR__ . '/_inc.php';

$u = require_login();
$uid = (int) $u['id'];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();
    $action = (string) ($_POST['action'] ?? '');
    if ($action === 'regen') {
        $_SESSION['new_key'] = set_api_key($uid);
        flash('Nova chave gerada. A anterior parou de funcionar.', 'ok');
    } elseif ($action === 'revoke') {
        $id = valid_id($_POST['id'] ?? null);
        if ($id && row('SELECT 1 FROM links WHERE id = ? AND user_id = ?', [$id, $uid])) { delete_share($id); flash('Link revogado e imagem apagada.', 'ok'); }
    } elseif ($action === 'revoke_all') {
        foreach (rows('SELECT id FROM links WHERE user_id = ?', [$uid]) as $r) { delete_share($r['id']); }
        flash('Todos os seus links foram revogados.', 'ok');
    } elseif ($action === 'delete_account') {
        if (password_verify((string) ($_POST['password'] ?? ''), $u['pass_hash'])) {
            foreach (rows('SELECT id FROM links WHERE user_id = ?', [$uid]) as $r) { delete_share($r['id']); }
            run('DELETE FROM users WHERE id = ?', [$uid]);
            logout_user();
            redirect('/?conta=excluida');
        }
        flash('Senha incorreta; a conta não foi excluída.', 'error');
    }
    redirect('/painel');
}

prune();
$newKey = $_SESSION['new_key'] ?? null; unset($_SESSION['new_key']);
$usage = user_usage($uid);
$links = rows('SELECT * FROM links WHERE user_id = ? ORDER BY created_at DESC', [$uid]);
$base = base_url();
$maxLinks = (int) cfg('max_active_links', 100);
$maxBytes = (int) cfg('max_total_bytes', 200 * 1024 * 1024);

page_header('Painel');
?>
<h1>Olá, <?= h($u['name']) ?></h1>
<p class="updated"><?= h($u['email']) ?> · conta criada em <?= fmt_date((int) $u['created_at']) ?></p>

<h2>Chave de API</h2>
<?php if ($newKey): ?>
  <div class="note"><strong>Copie agora — ela não será mostrada de novo.</strong>
    <div class="key"><code id="k"><?= h($newKey) ?></code> <button class="btn" type="button" onclick="navigator.clipboard.writeText(document.getElementById('k').textContent).then(()=>this.textContent='Copiado ✓')">Copiar</button></div>
    <p style="margin:12px 0 6px"><a class="btn primary" href="snaplens://auth?key=<?= rawurlencode($newKey) ?>&amp;server=<?= rawurlencode($base) ?>">Abrir no SnapLens e conectar</a>
      <span class="muted">— o app recebe a chave sozinho (precisa do SnapLens 1.4+ instalado).</span></p>
    Ou cole manualmente em <em>SnapLens → Ajustes → Compartilhar por link público → Chave de API</em> e clique em “Testar conexão”.</div>
<?php else: ?>
  <p>Chave ativa terminando em <code>…<?= h((string) $u['api_key_hint']) ?></code>. Se a perdeu, gere outra (a atual deixa de funcionar).</p>
<?php endif; ?>
<form method="post" class="inline"><input type="hidden" name="csrf" value="<?= h(csrf_token()) ?>"><input type="hidden" name="action" value="regen">
  <button class="btn" type="submit" onclick="return confirm('Gerar nova chave? A atual para de funcionar.')">Gerar nova chave</button></form>

<h2>Uso</h2>
<p><?= $usage['links'] ?> de <?= $maxLinks ?> links ativos · <?= h(human_size($usage['bytes'])) ?> de <?= h(human_size($maxBytes)) ?></p>

<h2>Seus links</h2>
<?php if (!$links): ?>
  <p class="muted">Nenhum link ativo. Capture algo no SnapLens e clique no ícone 🔗.</p>
<?php else: ?>
<table class="list">
  <tr><th>Link</th><th>Criado</th><th>Validade</th><th>Visualiz.</th><th>Tamanho</th><th></th></tr>
  <?php foreach ($links as $l): ?>
  <tr>
    <td><a href="/s/<?= h($l['id']) ?>" target="_blank"><?= h($l['id']) ?></a> <small class="muted"><?= (int) $l['width'] ?>×<?= (int) $l['height'] ?></small></td>
    <td><?= fmt_date((int) $l['created_at']) ?></td>
    <td><?= h(human_expiry($l['expires_at'] !== null ? (int) $l['expires_at'] : null)) ?></td>
    <td><?= (int) $l['views'] ?></td>
    <td><?= h(human_size((int) $l['size'])) ?></td>
    <td><form method="post" class="inline"><input type="hidden" name="csrf" value="<?= h(csrf_token()) ?>"><input type="hidden" name="action" value="revoke"><input type="hidden" name="id" value="<?= h($l['id']) ?>"><button class="btn small" type="submit">Revogar</button></form></td>
  </tr>
  <?php endforeach; ?>
</table>
<form method="post" class="inline"><input type="hidden" name="csrf" value="<?= h(csrf_token()) ?>"><input type="hidden" name="action" value="revoke_all">
  <button class="btn" type="submit" onclick="return confirm('Revogar todos os links e apagar as imagens?')">Revogar todos</button></form>
<?php endif; ?>

<h2>Excluir conta</h2>
<p class="muted">Apaga sua conta, sua chave e todos os seus links imediatamente.</p>
<form method="post" class="form compact"><input type="hidden" name="csrf" value="<?= h(csrf_token()) ?>"><input type="hidden" name="action" value="delete_account">
  <label class="field"><span>Confirme sua senha</span><input type="password" name="password" autocomplete="current-password" required></label>
  <button class="btn danger" type="submit" onclick="return confirm('Excluir a conta definitivamente?')">Excluir minha conta</button></form>
<?php page_footer();