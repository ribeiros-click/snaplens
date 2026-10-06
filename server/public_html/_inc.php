<?php
// Cabeçalho e rodapé das páginas dinâmicas (cadastro, login, painel, admin).
declare(strict_types=1);

function page_header(string $title): void {
    $u = current_user();
    $f = flash();
    header('Cache-Control: no-store');
    echo '<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">';
    echo '<title>' . h($title) . ' · SnapLens</title><meta name="robots" content="noindex"><link rel="icon" href="/assets/icon.png"><link rel="stylesheet" href="/assets/site.css?v=3"></head><body>';
    echo '<header class="bar"><a class="brand" href="/"><img src="/assets/icon.png" alt="" width="28" height="28"> SnapLens</a><nav>';
    echo '<a href="/#recursos">Recursos</a><a href="/#baixar">Baixar</a><a href="/politicas/">Políticas</a>';
    if ($u) {
        echo '<a href="/painel">Painel</a>';
        if ($u['is_admin']) { echo '<a href="/admin">Admin</a>'; }
        echo '<a href="/sair">Sair</a>';
    } else {
        echo '<a href="/entrar">Entrar</a><a href="/cadastro">Criar conta</a>';
    }
    echo '</nav></header><main class="doc">';
    if ($f) { echo '<div class="flash ' . h($f['kind']) . '">' . h($f['msg']) . '</div>'; }
}

function page_footer(): void {
    echo '</main><footer class="foot">SnapLens · contato: <a href="mailto:' . h(cfg('contact_email', 'contato@ribeiros.click')) . '">' . h(cfg('contact_email', 'contato@ribeiros.click')) . '</a> · © 2026';
    echo '<nav><a href="/politicas/privacidade.html">Privacidade</a><a href="/politicas/termos.html">Termos</a><a href="/politicas/uso-aceitavel.html">Uso aceitável</a></nav></footer></body></html>';
}
