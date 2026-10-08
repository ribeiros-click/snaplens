<?php
// Cabeçalho e rodapé das páginas dinâmicas (admin).
declare(strict_types=1);

function page_header(string $title): void {
    header('Cache-Control: no-store');
    $lq = lang_query();
    echo '<!doctype html><html lang="' . html_lang() . '"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">';
    echo '<title>' . h($title) . ' · SnapLens</title><meta name="robots" content="noindex"><link rel="icon" href="/favicon.ico" sizes="any"><link rel="icon" type="image/png" sizes="32x32" href="/favicon-32.png?v=6"><link rel="apple-touch-icon" href="/apple-touch-icon.png?v=6"><link rel="stylesheet" href="/assets/site.css?v=8"></head><body>';
    echo '<header class="bar"><a class="brand" href="' . home_path() . '"><img src="/assets/icon-musgo.png" alt="" width="28" height="28"> SnapLens</a><nav>';
    echo '<a href="' . home_path() . '#recursos">' . t('Recursos') . '</a><a href="/token?' . $lq . '">' . t('Acessar por token') . '</a><a href="/politicas/">' . t('Políticas') . '</a><a href="/contato?' . $lq . '">' . t('Contato') . '</a>';
    echo '<span class="langs">' . lang_switcher() . '</span>';
    echo '<a class="btn primary small" href="https://github.com/ribeiros-click/snaplens/releases/latest/download/SnapLens.dmg">' . t('Baixar') . '</a>';
    echo '</nav></header><main class="doc">';
}

function page_footer(): void {
    echo '</main><footer class="foot simple">SnapLens · <a href="/contato?' . lang_query() . '">' . t('Contato') . '</a> (<a href="mailto:' . h(cfg('contact_email', 'contato@ribeiros.click')) . '">' . h(cfg('contact_email', 'contato@ribeiros.click')) . '</a>) · © 2026';
    echo '<nav><a href="/politicas/">' . t('Políticas') . '</a><a href="/politicas/privacidade.html">' . t('Privacidade') . '</a><a href="/politicas/termos.html">' . t('Termos') . '</a><a href="/politicas/uso-aceitavel.html">' . t('Uso aceitável') . '</a><a href="/politicas/seguranca.html">' . t('Segurança') . '</a></nav></footer></body></html>';
}
