<?php
// Cabeçalho e rodapé das páginas dinâmicas (admin).
declare(strict_types=1);

function page_header(string $title): void {
    header('Cache-Control: no-store');
    echo '<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">';
    echo '<title>' . h($title) . ' · SnapLens</title><meta name="robots" content="noindex"><link rel="icon" href="/assets/icon.png"><link rel="stylesheet" href="/assets/site.css?v=5"></head><body>';
    echo '<header class="bar"><a class="brand" href="/"><img src="/assets/icon.png" alt="" width="28" height="28"> SnapLens</a><nav>';
    echo '<a href="/#recursos">Recursos</a><a href="/token">Acessar por token</a><a href="/politicas/">Políticas</a><a href="/contato">Contato</a><a class="btn primary small" href="/download/SnapLens.dmg">Baixar</a>';
    echo '</nav></header><main class="doc">';
}

function page_footer(): void {
    echo '</main><footer class="foot simple">SnapLens · <a href="/contato">Contato</a> (<a href="mailto:' . h(cfg('contact_email', 'contato@ribeiros.click')) . '">' . h(cfg('contact_email', 'contato@ribeiros.click')) . '</a>) · © 2026';
    echo '<nav><a href="/politicas/">Políticas</a><a href="/politicas/privacidade.html">Privacidade</a><a href="/politicas/termos.html">Termos</a><a href="/politicas/uso-aceitavel.html">Uso aceitável</a><a href="/politicas/seguranca.html">Segurança</a></nav></footer></body></html>';
}
