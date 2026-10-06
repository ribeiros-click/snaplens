<?php
// Copie para config.php e preencha. config.php NÃO vai para o git.
return [
    // Chave que o app envia no header X-Lens-Key. Gere com: openssl rand -hex 24
    'upload_key' => '',
    // URL pública (sem barra final). Vazio = detectar pelo host da requisição.
    'base_url'   => 'https://lens.ribeiros.click',
    // Tamanho máximo por imagem, em bytes.
    'max_bytes'  => 25 * 1024 * 1024,
    // Validade máxima permitida, em segundos (0 = permitir "sem expirar").
    'max_ttl'    => 0,
];
