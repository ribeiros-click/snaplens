<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';

$id = valid_id($_GET['id'] ?? null);
$m = $id ? read_meta($id) : null;
$gone = !$m || is_expired($m);
if ($m && is_expired($m)) { delete_share($id); }
$once = $m && !empty($m['once']);
$burned = false;
if (!$gone && $once && (int) $m['views'] >= 1) {
    delete_share($id);
    $gone = true;
    $burned = true;
}
// Links "ver apenas uma vez" não contam a página como visualização: quem consome é a imagem.
if (!$gone && !$once) {
    $m['views'] = (int) ($m['views'] ?? 0) + 1;
    write_meta($id, $m);
}
http_response_code($gone ? 410 : 200);
header('Cache-Control: no-store');
$base = base_url();
$h = fn(string $s): string => htmlspecialchars($s, ENT_QUOTES, 'UTF-8');
?>
<!doctype html>
<html lang="<?= html_lang() ?>">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= $gone ? t('Link indisponível') : t('Screenshot') ?> · SnapLens</title>
<meta name="robots" content="noindex">
<?php if (!$gone): ?>
<meta property="og:title" content="<?= $h(t('Compartilhado com') . ' SnapLens') ?>">
<meta property="og:image" content="<?= $h("$base/i/$id") ?>">
<meta property="og:image:width" content="<?= (int) $m['width'] ?>">
<meta property="og:image:height" content="<?= (int) $m['height'] ?>">
<meta name="twitter:card" content="summary_large_image">
<?php endif; ?>
<link rel="icon" href="/favicon.ico" sizes="any"><link rel="icon" type="image/png" sizes="32x32" href="/favicon-32.png?v=6"><link rel="apple-touch-icon" href="/apple-touch-icon.png?v=6">
<link rel="stylesheet" href="/assets/site.css?v=8">
</head>
<body class="share">
<header class="bar">
  <a class="brand" href="<?= home_path() ?>"><img src="/assets/icon-musgo.png" alt="" width="28" height="28"> SnapLens</a>
  <?php if (!$gone): ?>
  <div class="meta">
    <span><?= (int) $m['width'] ?> × <?= (int) $m['height'] ?></span>
    <span><?= $h(human_size((int) $m['size'])) ?></span>
    <span class="exp <?= $m['expires_at'] ? '' : 'never' ?>"><?= $h(human_expiry($m['expires_at'])) ?></span>
    <?php if ($once): ?><span>⏱ <?= t('Esta imagem se autodestrói após a primeira visualização.') ?></span>
    <?php else: ?><span><?= (int) $m['views'] ?> <?= t('visualiz.') ?></span><?php endif; ?>
  </div>
  <div class="actions">
    <button class="btn" id="copy" data-url="<?= $h("$base/s/$id") ?>"><?= t('Copiar link') ?></button>
    <a class="btn" href="/i/<?= $h($id) ?>" target="_blank" rel="noopener"><?= t('Abrir original') ?></a>
    <a class="btn primary" href="/i/<?= $h($id) ?>?dl=1"><?= t('Baixar') ?></a>
  </div>
  <?php endif; ?>
</header>
<main class="stage">
<?php if ($gone): ?>
  <div class="gone">
    <div class="gone-icon">⌛</div>
    <?php if ($burned): ?>
    <h1><?= t('Esta imagem já foi visualizada e se autodestruiu.') ?></h1>
    <p><?= t('Ela foi compartilhada no modo “ver apenas uma vez”: depois da primeira exibição, o arquivo é apagado do servidor.') ?></p>
    <?php else: ?>
    <h1><?= t('Este link não está mais disponível') ?></h1>
    <p><?= t('Ele expirou ou foi revogado por quem o criou. Links do SnapLens têm validade definida na hora do compartilhamento.') ?></p>
    <?php endif; ?>
    <a class="btn primary" href="<?= home_path() ?>"><?= t('Conheça o SnapLens') ?></a>
  </div>
<?php else: ?>
  <a href="/i/<?= $h($id) ?>" target="_blank" rel="noopener">
    <img class="shot" src="/i/<?= $h($id) ?>" alt="Screenshot" width="<?= (int) $m['width'] ?>" height="<?= (int) $m['height'] ?>">
  </a>
<?php endif; ?>
</main>
<footer class="foot"><?= t('Compartilhado com') ?> <a href="<?= home_path() ?>">SnapLens</a> <?= t('para macOS') ?>
  <nav><a href="/politicas/privacidade.html"><?= t('Privacidade') ?></a><a href="/politicas/termos.html"><?= t('Termos') ?></a><a href="/contato?assunto=denuncia&amp;<?= lang_query() ?>"><?= t('Denunciar conteúdo') ?></a><span class="langs"><?= lang_switcher() ?></span></nav>
</footer>
<script>
document.getElementById('copy')?.addEventListener('click', async (e) => {
  const b = e.currentTarget;
  try { await navigator.clipboard.writeText(b.dataset.url); b.textContent = <?= json_encode(t('Copiado ✓')) ?>; setTimeout(() => b.textContent = <?= json_encode(t('Copiar link')) ?>, 1500); }
  catch { prompt(<?= json_encode(t('Copie o link:')) ?>, b.dataset.url); }
});
</script>
</body>
</html>
