<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';
require __DIR__ . '/_inc.php';

if (current_user()) { redirect('/painel'); }
$err = null; $email = '';
$next = (string) ($_GET['next'] ?? $_POST['next'] ?? '/painel');
if (!str_starts_with($next, '/') || str_starts_with($next, '//')) { $next = '/painel'; }

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();
    $email = strtolower(trim((string) ($_POST['email'] ?? '')));
    $pass = (string) ($_POST['password'] ?? '');
    $u = row('SELECT * FROM users WHERE email = ?', [$email]);
    if ($u && (int) $u['locked_until'] > time()) {
        $err = 'Muitas tentativas. Tente novamente em ' . max(1, intdiv((int) $u['locked_until'] - time(), 60)) . ' min.';
    } elseif ($u && password_verify($pass, $u['pass_hash'])) {
        if ($u['is_blocked']) { $err = 'Conta bloqueada. Fale com ' . cfg('contact_email', 'contato@ribeiros.click') . '.'; }
        else { login_user((int) $u['id']); redirect($next); }
    } else {
        if ($u) {
            $n = (int) $u['failed_logins'] + 1;
            run('UPDATE users SET failed_logins = ?, locked_until = ? WHERE id = ?', [$n, $n >= 8 ? time() + 900 : 0, (int) $u['id']]);
        }
        usleep(300000);
        $err = 'E-mail ou senha incorretos.';
    }
}

page_header('Entrar');
?>
<h1>Entrar</h1>
<p class="updated">Acesse seu painel para ver a chave de API e seus links.</p>
<?php if ($err): ?><div class="flash error"><?= h($err) ?></div><?php endif; ?>
<form method="post" class="form">
  <input type="hidden" name="csrf" value="<?= h(csrf_token()) ?>">
  <input type="hidden" name="next" value="<?= h($next) ?>">
  <label class="field"><span>E-mail</span><input type="email" name="email" value="<?= h($email) ?>" required autocomplete="email" autofocus></label>
  <label class="field"><span>Senha</span><input type="password" name="password" required autocomplete="current-password"></label>
  <button class="btn primary big" type="submit">Entrar</button>
  <p class="muted">Não tem conta? <a href="/cadastro">Criar conta</a> · Esqueceu a senha? Escreva para <a href="mailto:<?= h(cfg('contact_email', 'contato@ribeiros.click')) ?>"><?= h(cfg('contact_email', 'contato@ribeiros.click')) ?></a>.</p>
</form>
<?php page_footer();