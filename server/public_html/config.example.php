<?php
// Copie para config.php e ajuste. config.php NÃO vai para o git.
return [
    // URL pública (sem barra final). Vazio = detectar pelo host da requisição.
    'base_url'           => 'https://lens.ribeiros.click',
    // E-mail de contato exibido nas páginas e usado para suporte.
    'contact_email'      => 'contato@ribeiros.click',
    // Token de administração (página /admin.php e limpeza via HTTP): defina um segredo longo.
    'admin_token'        => '',
    // Limite de uploads por IP.
    'rate_limit_uploads' => 30,     // uploads
    'rate_limit_window'  => 3600,   // por janela de segundos
    // Tamanho máximo por imagem.
    'max_bytes'          => 25 * 1024 * 1024,
    // Validade máxima permitida, em segundos (0 = permitir "sem expirar").
    'max_ttl'            => 0,
];
