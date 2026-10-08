# SnapLens

App de barra de menu para macOS: screenshots, gravação de tela (com áudio do sistema e/ou microfone), OCR local (Vision), descrição de imagens com IA e biblioteca com exportação.

Requer macOS 15+.

## Compilar
```bash
./build.sh          # gera SnapLens.app (ICON=1|2|3 escolhe o ícone)
./make_dmg.sh       # gera SnapLens.dmg
./make_appstore.sh  # gera SnapLens.pkg para a Mac App Store (exige certificados + perfil)
```

## Atalhos padrão
| Ação | Atalho |
|---|---|
| Capturar seleção | ⌘⌥P |
| Capturar tela inteira | ⌃⌥F |
| OCR de seleção | ⌃⌥T |
| Descrever com IA | ⌃⌥D |
| Gravar tela | ⌃⌥R |
| Biblioteca | ⌃⌥H |

## Overlay de captura
Anotações (retângulo, elipse, linha, seta, caneta, texto), OCR, descrição com IA, copiar (⏎/⌘C) e salvar (⌘S).
Cancelar: botão "Cancelar" no topo, **Esc** (global), botão direito (refaz a seleção), Cmd-Tab/Dock, item "Cancelar captura em andamento" no menu, ou 60 s sem interação.

## Links públicos (lens.ribeiros.click)
O botão 🔗 no overlay ou na Biblioteca envia a imagem para o servidor e abre uma tela com o link e o token de exclusão (a URL também é copiada). Compartilhamento anônimo: sem conta, sem chave. Validade: 1 h, 1 dia, 7 dias, 30 dias ou sem expirar (padrão em Ajustes). Links podem ser revogados na Biblioteca ou com o token; expirados são apagados do servidor (cron diário + limpeza a cada upload).

Backend em PHP puro (`server/public_html`), hospedagem compartilhada Hostinger:
- `POST /api/upload` (multipart `file`, `expires` em segundos; sem autenticação, com rate limit por IP) → `{id, url, expires_at, delete_token}`
- `POST /api/delete` `{id, token}`
- `GET /s/{id}` página do link · `GET /i/{id}` imagem (`?dl=1` baixa)
- `admin.php` protegido por `admin_token` (em `config.php`)

Deploy: `./server/deploy.sh` (token em `.hostinger/token` ou `HOSTINGER_API_TOKEN`). Na primeira execução gera `server/public_html/config.php` — defina nele um `admin_token` secreto. O site do projeto (com prints gerados por `SnapLens --render-shots <pasta>`) e o DMG mais recente são publicados junto.

## Instalação via DMG
Baixe o `.dmg` em Releases, arraste o SnapLens para Applications. Se o macOS bloquear a abertura (build sem notarização), use clique direito → Abrir. Permita "Gravação de Tela" (e Microfone, se for usar) em Ajustes do Sistema → Privacidade e Segurança.

## Autor
Criado por contato@ribeiros.click
