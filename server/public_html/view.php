<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';

$id = valid_id($_GET['id'] ?? null);
$m = $id ? read_meta($id) : null;
$gone = !$m || is_expired($m);
if ($m && is_expired($m)) { delete_share($id); }
if (!$gone) {
    $m['views'] = (int) ($m['views'] ?? 0) + 1;
    write_meta($id, $m);
}
http_response_code($gone ? 410 : 200);
header('Cache-Control: no-store');
$base = base_url();
$h = fn(string $s): string => htmlspecialchars($s, ENT_QUOTES, 'UTF-8');
?>
<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= $gone ? 'Link indisponível' : 'Screenshot' ?> · SnapLens</title>
<meta name="robots" content="noindex">
<?php if (!$gone): ?>
<meta property="og:title" content="Screenshot compartilhado com SnapLens">
<meta property="og:image" content="<?= $h("$base/i/$id") ?>">
<meta property="og:image:width" content="<?= (int) $m['width'] ?>">
<meta property="og:image:height" content="<?= (int) $m['height'] ?>">
<meta name="twitter:card" content="summary_large_image">
<?php endif; ?>
<link rel="icon" href="/assets/icon.png">
<link rel="stylesheet" href="/assets/site.css">
</head>
<body class="share">
<header class="bar">
  <a class="brand" href="/"><img src="/assets/icon.png" alt="" width="28" height="28"> SnapLens</a>
  <?php if (!$gone): ?>
  <div class="meta">
    <span><?= (int) $m['width'] ?> × <?= (int) $m['height'] ?></span>
    <span><?= $h(human_size((int) $m['size'])) ?></span>
    <span class="exp <?= $m['expires_at'] ? '' : 'never' ?>"><?= $h(human_expiry($m['expires_at'])) ?></span>
    <span><?= (int) $m['views'] ?> visualiz.</span>
  </div>
  <div class="actions">
    <button class="btn" id="copy" data-url="<?= $h("$base/s/$id") ?>">Copiar link</button>
    <a class="btn" href="/i/<?= $h($id) ?>" target="_blank" rel="noopener">Abrir original</a>
    <a class="btn primary" href="/i/<?= $h($id) ?>?dl=1">Baixar</a>
  </div>
  <?php endif; ?>
</header>
<main class="stage">
<?php if ($gone): ?>
  <div class="gone">
    <div class="gone-icon">⌛</div>
    <h1>Este link não está mais disponível</h1>
    <p>Ele expirou ou foi revogado por quem o criou. Links do SnapLens têm validade definida na hora do compartilhamento.</p>
    <a class="btn primary" href="/">Conheça o SnapLens</a>
  </div>
<?php else: ?>
  <a href="/i/<?= $h($id) ?>" target="_blank" rel="noopener">
    <img class="shot" src="/i/<?= $h($id) ?>" alt="Screenshot" width="<?= (int) $m['width'] ?>" height="<?= (int) $m['height'] ?>">
  </a>
<?php endif; ?>
</main>
<footer class="foot">Compartilhado com <a href="/">SnapLens</a> para macOS
  <nav><a href="/politicas/privacidade.html">Privacidade</a><a href="/politicas/termos.html">Termos</a><a href="mailto:contato@ribeiros.click?subject=Den%C3%BAncia%20de%20conte%C3%BAdo%20<?= $h($id ?? '') ?>">Denunciar conteúdo</a></nav>
</footer>
<script>
document.getElementById('copy')?.addEventListener('click', async (e) => {
  const b = e.currentTarget;
  try { await navigator.clipboard.writeText(b.dataset.url); b.textContent = 'Copiado ✓'; setTimeout(() => b.textContent = 'Copiar link', 1500); }
  catch { prompt('Copie o link:', b.dataset.url); }
});
</script>
</body>
</html>
