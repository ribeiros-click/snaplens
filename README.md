<p align="center">
  <img src="https://lens.ribeiros.click/assets/icon-musgo.png" width="128" alt="SnapLens">
</p>

<h1 align="center">SnapLens</h1>

<p align="center">
  <strong>Capture, anote, compartilhe. O canivete suíço de screenshots para macOS.</strong><br>
  Barra de menu, anotações, OCR local, descrição com IA, gravação de tela e links instantâneos — sem conta, sem cadastro.
</p>

<p align="center">
  <a href="https://lens.ribeiros.click/download/SnapLens.dmg"><strong>⬇️ Baixar SnapLens.dmg</strong></a> ·
  <a href="https://github.com/joserribeiro26/snaplens/releases/latest">Releases</a> ·
  <a href="https://lens.ribeiros.click/">Site do projeto</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B-black" alt="macOS 15+">
  <img src="https://img.shields.io/badge/licença-MIT-blue" alt="MIT">
  <img src="https://img.shields.io/badge/preço-grátis-green" alt="grátis">
</p>

---

<p align="center">
  <img src="https://lens.ribeiros.click/assets/img/overlay.png" width="720" alt="Overlay de captura com anotações">
</p>

## Por que SnapLens?

- **Captura instantânea** — seleção ou tela inteira, direto da barra de menu ou por atalho global.
- **Anotações completas** — retângulo, elipse, linha, seta, caneta e texto, sem sair da captura.
- **OCR 100% local** — extraia texto de qualquer imagem com o Vision da Apple. Nada sai do seu Mac.
- **Descrição com IA** — entenda o que há em uma imagem com um atalho (provedores configuráveis).
- **Gravação de tela** — vídeo com áudio do sistema e/ou microfone.
- **Compartilhamento anônimo** — um clique gera um link público na hora, com token de exclusão para apagar quando quiser. Sem conta, sem chave, sem fricção.
- **Biblioteca** — todo o histórico de capturas organizado, com exportação e revogação de links.

## Compartilhar em um clique

Clique no 🔗 e pronto: o link é gerado e copiado automaticamente. Uma tela mostra o link e o **token de exclusão** — guarde-o para apagar a imagem de qualquer lugar, ou revogue pela Biblioteca. Você escolhe a validade: 1 hora, 1 dia, 7 dias, 30 dias ou sem expirar.

Links expirados são apagados do servidor automaticamente. Hospedagem própria em [lens.ribeiros.click](https://lens.ribeiros.click/) — ou aponte para o seu servidor em Ajustes.

<p align="center">
  <img src="https://lens.ribeiros.click/assets/img/biblioteca.png" width="720" alt="Biblioteca de capturas">
</p>

## Atalhos padrão

| Ação | Atalho |
|---|---|
| Capturar seleção | ⌘⌥P |
| Capturar tela inteira | ⌃⌥F |
| OCR de seleção | ⌃⌥T |
| Descrever com IA | ⌃⌥D |
| Gravar tela | ⌃⌥R |
| Biblioteca | ⌃⌥H |

Todos configuráveis em Ajustes.

## Instalação

1. Baixe o [SnapLens.dmg](https://lens.ribeiros.click/download/SnapLens.dmg) (ou em [Releases](https://github.com/joserribeiro26/snaplens/releases/latest)).
2. Arraste o SnapLens para a pasta **Aplicativos**.
3. Se o macOS bloquear a abertura (build sem notarização): clique direito → **Abrir**.
4. Permita **Gravação de Tela** (e Microfone, se for usar) em Ajustes do Sistema → Privacidade e Segurança.

Requer **macOS 15 (Sequoia) ou superior**.

## Privacidade

OCR e anotações acontecem localmente. Imagens só saem do Mac quando você clica em compartilhar — e você pode apagá-las a qualquer momento com o token de exclusão. Nenhuma conta, nenhum rastreamento.

## Para desenvolvedores

```bash
./build.sh          # gera SnapLens.app (ICON=1|2|3 escolhe o ícone)
./make_dmg.sh       # gera SnapLens.dmg
./make_appstore.sh  # gera SnapLens.pkg para a Mac App Store (exige certificados + perfil)
```

Backend de compartilhamento em PHP puro (`server/public_html`), auto-hospedável:

- `POST /api/upload` (multipart `file`, `expires` em segundos; rate limit por IP) → `{id, url, expires_at, delete_token}`
- `POST /api/delete` `{id, token}`
- `GET /s/{id}` página do link · `GET /i/{id}` imagem (`?dl=1` baixa)
- `admin.php` protegido por `admin_token` (em `config.php`)

Deploy na Hostinger: `./server/deploy.sh` (token em `.hostinger/token` ou `HOSTINGER_API_TOKEN`).

## Autor

Criado por [contato@ribeiros.click](mailto:contato@ribeiros.click)
