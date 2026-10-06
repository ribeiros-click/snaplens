<?php
// Copie para config.php e ajuste. config.php NÃO vai para o git.
return [
    // URL pública (sem barra final). Vazio = detectar pelo host da requisição.
    'base_url'           => 'https://lens.ribeiros.click',
    // E-mail de contato exibido nas páginas e usado para suporte.
    'contact_email'      => 'contato@ribeiros.click',
    // Quem se cadastrar com este e-mail vira administrador (o primeiro cadastro também é admin).
    'admin_email'        => 'contato@ribeiros.click',
    // Permitir novos cadastros.
    'allow_registration' => true,
    // Cotas por conta.
    'max_bytes'          => 25 * 1024 * 1024,   // por imagem
    'max_active_links'   => 100,
    'max_total_bytes'    => 200 * 1024 * 1024,  // soma das imagens ativas
    // Validade máxima permitida, em segundos (0 = permitir "sem expirar").
    'max_ttl'            => 0,
];
