<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';
require __DIR__ . '/_inc.php';

$subjects = ['Dúvida', 'Sugestão', 'Denunciar link/imagem', 'Outro'];

$err = [];
$done = false;
$nome = '';
$email = '';
$mensagem = '';
$assunto = (($_GET['assunto'] ?? '') === 'denuncia') ? 'Denunciar link/imagem' : $subjects[0];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $nome = trim((string) ($_POST['nome'] ?? ''));
    $email = trim((string) ($_POST['email'] ?? ''));
    $assunto = (string) ($_POST['assunto'] ?? '');
    $mensagem = trim((string) ($_POST['mensagem'] ?? ''));

    // Honeypot: campo invisível que robôs preenchem. Finge sucesso e descarta.
    if (trim((string) ($_POST['website'] ?? '')) !== '') {
        $done = true;
    } else {
        if (!in_array($assunto, $subjects, true)) { $assunto = $subjects[0]; }
        if (mb_strlen($nome) > 100) { $err[] = 'Nome muito longo (máx. 100 caracteres).'; }
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) { $err[] = 'Informe um e-mail válido.'; }
        if ($mensagem === '') { $err[] = 'Escreva sua mensagem.'; }
        elseif (mb_strlen($mensagem) > 5000) { $err[] = 'Mensagem muito longa (máx. 5000 caracteres).'; }

        $ip = (string) ($_SERVER['REMOTE_ADDR'] ?? 'cli');
        if (!$err && !rate_limit_ok($ip, (int) cfg('rate_limit_contact', 5), (int) cfg('rate_limit_window', 3600))) {
            $err[] = 'Muitas mensagens seguidas. Tente novamente em alguns minutos.';
        }

        if (!$err) {
            $to = (string) cfg('contact_email', 'contato@ribeiros.click');
            $host = parse_url((string) cfg('base_url', ''), PHP_URL_HOST) ?: 'lens.ribeiros.click';
            // Cabeçalhos não podem conter quebras de linha vindas do usuário.
            $hNome = str_replace(["\r", "\n"], ' ', $nome);
            $hEmail = str_replace(["\r", "\n"], '', $email);
            $subject = '[SnapLens] ' . $assunto;
            $body = "Nome: $hNome\nE-mail: $hEmail\nAssunto: $assunto\nIP: $ip\nData: " . date('d/m/Y H:i:s') . "\n\nMensagem:\n$mensagem\n";
            $headers = implode("\r\n", [
                'From: SnapLens <contato@' . $host . '>',
                'Reply-To: ' . $hEmail,
                'Content-Type: text/plain; charset=UTF-8',
            ]);
            $sent = @mail($to, '=?UTF-8?B?' . base64_encode($subject) . '?=', $body, $headers);
            if (!$sent) {
                // Fallback: guarda em _data/contact.log (JSON lines) se mail() falhar.
                $line = json_encode(['ts' => time(), 'ip' => $ip, 'nome' => $nome, 'email' => $email, 'assunto' => $assunto, 'mensagem' => $mensagem], JSON_UNESCAPED_UNICODE) . "\n";
                $sent = @file_put_contents(DATA_DIR . '/contact.log', $line, FILE_APPEND | LOCK_EX) !== false;
            }
            if ($sent) { $done = true; } else { $err[] = 'Não foi possível enviar agora. Tente de novo em alguns minutos ou escreva para ' . $to . '.'; }
        }
    }
}

page_header('Contato');
?>
<h1>Contato</h1>
<?php if ($done): ?>
<div class="flash ok">Mensagem enviada! Respondemos no e-mail informado.</div>
<p><a class="btn" href="/">Voltar ao início</a></p>
<?php else: ?>
<p class="updated">Dúvidas, sugestões ou denúncias: preencha abaixo ou escreva para <a href="mailto:<?= h(cfg('contact_email', 'contato@ribeiros.click')) ?>"><?= h(cfg('contact_email', 'contato@ribeiros.click')) ?></a>.</p>
<?php foreach ($err as $e): ?><div class="flash error"><?= h($e) ?></div><?php endforeach; ?>
<form method="post" class="form">
  <label class="field"><span>Nome <small class="muted">(opcional)</small></span><input name="nome" value="<?= h($nome) ?>" maxlength="100" autocomplete="name"></label>
  <label class="field"><span>E-mail</span><input type="email" name="email" value="<?= h($email) ?>" required autocomplete="email"></label>
  <label class="field"><span>Assunto</span>
    <select name="assunto">
      <?php foreach ($subjects as $s): ?>
      <option value="<?= h($s) ?>"<?= $s === $assunto ? ' selected' : '' ?>><?= h($s) ?></option>
      <?php endforeach; ?>
    </select>
    <?php if ($assunto === 'Denunciar link/imagem'): ?><small>Cole o link que quer denunciar na mensagem.</small><?php endif; ?>
  </label>
  <label class="field"><span>Mensagem</span><textarea name="mensagem" required maxlength="5000" rows="8"><?= h($mensagem) ?></textarea></label>
  <input type="text" name="website" value="" tabindex="-1" autocomplete="off" style="position:absolute;left:-9999px" aria-hidden="true">
  <button class="btn primary big" type="submit">Enviar mensagem</button>
</form>
<?php endif; ?>
<?php page_footer();
