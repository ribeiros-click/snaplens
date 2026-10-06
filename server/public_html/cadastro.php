<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';
require __DIR__ . '/_inc.php';

if (current_user()) { redirect('/painel'); }
$err = []; $name = ''; $email = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();
    if (!cfg('allow_registration', true)) { $err[] = 'Cadastros estão temporariamente fechados.'; }
    $name = trim((string) ($_POST['name'] ?? ''));
    $email = strtolower(trim((string) ($_POST['email'] ?? '')));
    $pass = (string) ($_POST['password'] ?? '');
    if (mb_strlen($name) < 2 || mb_strlen($name) > 80) { $err[] = 'Informe seu nome (2 a 80 caracteres).'; }
    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) { $err[] = 'E-mail inválido.'; }
    if (strlen($pass) < 8) { $err[] = 'A senha precisa ter pelo menos 8 caracteres.'; }
    if (empty($_POST['accept'])) { $err[] = 'É preciso aceitar os Termos de Uso e a Política de Privacidade.'; }
    if (!$err && row('SELECT 1 FROM users WHERE email = ?', [$email])) { $err[] = 'Já existe uma conta com este e-mail. Tente entrar.'; }
    if (!$err) {
        $first = !row('SELECT 1 FROM users LIMIT 1');
        $admin = $first || strcasecmp($email, (string) cfg('admin_email', '')) === 0;
        run('INSERT INTO users (email, name, pass_hash, is_admin, created_at) VALUES (?,?,?,?,?)',
            [$email, $name, password_hash($pass, PASSWORD_DEFAULT), $admin ? 1 : 0, time()]);
        $uid = (int) db()->lastInsertRowID();
        $key = set_api_key($uid);
        login_user($uid);
        $_SESSION['new_key'] = $key;
        redirect('/painel');
    }
}

page_header('Criar conta');
?>
<h1>Criar conta</h1>
<p class="updated">Gratuita. Necessária para publicar links pelo SnapLens.</p>
<?php foreach ($err as $e): ?><div class="flash error"><?= h($e) ?></div><?php endforeach; ?>
<form method="post" class="form">
  <input type="hidden" name="csrf" value="<?= h(csrf_token()) ?>">
  <label class="field"><span>Nome</span><input name="name" value="<?= h($name) ?>" required maxlength="80" autocomplete="name"></label>
  <label class="field"><span>E-mail</span><input type="email" name="email" value="<?= h($email) ?>" required autocomplete="email"></label>
  <label class="field"><span>Senha</span><input type="password" name="password" required minlength="8" autocomplete="new-password"><small>Mínimo de 8 caracteres.</small></label>
  <label class="check"><input type="checkbox" name="accept" value="1" required> Li e aceito os <a href="/politicas/termos.html" target="_blank">Termos de Uso</a>, a <a href="/politicas/uso-aceitavel.html" target="_blank">Política de Uso Aceitável</a> e a <a href="/politicas/privacidade.html" target="_blank">Política de Privacidade</a>.</label>
  <button class="btn primary big" type="submit">Criar conta</button>
  <p class="muted">Já tem conta? <a href="/entrar">Entrar</a></p>
</form>
<?php page_footer();