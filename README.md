<p align="center">
  <img src="https://lens.ribeiros.click/assets/icon-musgo.png" width="128" alt="SnapLens">
</p>

<h1 align="center">SnapLens</h1>

<p align="center">
  <strong>Capture, annotate, share. The Swiss Army knife of screenshots for macOS.</strong><br>
  Menu-bar app with annotations, on-device OCR, AI descriptions, screen recording and expiring links — no account, no sign-up.
</p>

<p align="center">
  <a href="https://github.com/ribeiros-click/snaplens/releases/latest/download/SnapLens.dmg"><strong>⬇️ Download SnapLens.dmg</strong></a> ·
  <a href="https://github.com/ribeiros-click/snaplens/releases/latest">Releases</a> ·
  <a href="https://lens.ribeiros.click/">Project website</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B-black" alt="macOS 15+">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT">
  <img src="https://img.shields.io/badge/price-free-green" alt="free">
</p>

---

<p align="center">
  <img src="https://lens.ribeiros.click/assets/img/overlay.png" width="720" alt="Capture overlay with annotations">
</p>

## Why SnapLens?

- **Instant capture** — region or full screen, from the menu bar or a global shortcut. The screen freezes; you select, resize with handles, nudge with arrow keys.
- **Full annotation toolkit** — rectangle, ellipse, line, arrow, pen and text, seven colors, undo. All without leaving the capture.
- **100% on-device OCR** — extract text from any region with Apple's Vision framework. Nothing leaves your Mac. Results open in an editable window with offline translation to nine languages.
- **AI descriptions** — describe an image with Claude, OpenAI, DeepSeek or any OpenAI-compatible endpoint (including local Ollama). Without a key, a native offline mode is used.
- **Screen recording** — MP4 (H.264) with system audio and/or microphone, with a timer in the menu bar.
- **Anonymous sharing** — one click uploads the image and copies a public link. Pick an expiry (1 hour to 30 days, or never), optionally **view-once** (self-destructs on first open). You get a **delete token** to remove the image from anywhere. No account, no key.
- **Library** — every screenshot, recording, copied text, OCR result and AI description in one searchable, exportable place. Shared items show link, expiry and a revoke button.
- **Private by default** — no telemetry, API keys in the Keychain, concealed clipboard content (password managers) is ignored.

## Share in one click

Click 🔗 and you're done: the link is generated and copied. A dialog shows the link and the **delete token** — keep it to remove the image later, or revoke from the Library. Expired links are deleted from the server automatically.

Hosted at [lens.ribeiros.click](https://lens.ribeiros.click/) — or point the app at your own server in Settings.

<p align="center">
  <img src="https://lens.ribeiros.click/assets/img/biblioteca.png" width="720" alt="Library window">
</p>

## Languages

The app, the website and the demo video subtitles are available in **Portuguese (Brazil), English, Spanish, Italian and Simplified Chinese**. The app follows the system language by default; pick another one in Settings → Language. Website: [/](https://lens.ribeiros.click/) · [/en/](https://lens.ribeiros.click/en/) · [/es/](https://lens.ribeiros.click/es/) · [/it/](https://lens.ribeiros.click/it/) · [/zh/](https://lens.ribeiros.click/zh/).

## Demo video

A 79-second walkthrough with English narration and subtitles in the five languages: [watch on the website](https://lens.ribeiros.click/en/#video) · [MP4](https://lens.ribeiros.click/assets/video/snaplens-demo.mp4). It is assembled from the real UI with `Tools/make_video.sh` (frames via `SnapLens --video-frames`, narration via ElevenLabs or macOS `say`, subtitles generated from `Tools/narration.json`).

## Default shortcuts

| Action | Shortcut |
|---|---|
| Capture region | ⌥⌘P |
| Capture full screen | ⌃⌥F |
| OCR a region | ⌃⌥T |
| Describe with AI | ⌃⌥D |
| Start / stop recording | ⌃⌥R |
| Library | ⌃⌥H |
| In the overlay: copy · save · undo · cancel | ⏎ · ⌘S · ⌘Z · Esc |

All of them are configurable in Settings. The app warns you if another program already owns a shortcut.

## Install

1. Download [SnapLens.dmg](https://github.com/ribeiros-click/snaplens/releases/latest/download/SnapLens.dmg) (or grab it from [Releases](https://github.com/ribeiros-click/snaplens/releases/latest)).
2. Drag SnapLens to **Applications**.
3. The build is not notarized yet: on first launch, right-click → **Open**.
4. Allow **Screen Recording** (and Microphone, if you want it) in System Settings → Privacy & Security.

Requires **macOS 15 (Sequoia) or later**, Apple Silicon.

## Privacy

OCR, translation and annotations happen on your Mac. An image only leaves the machine when you click share (to the link server) or “Describe with AI” (to the provider you configured). Links are public to anyone with the URL; you can delete them at any time with the token. Full policies (in Portuguese): [privacy](https://lens.ribeiros.click/politicas/privacidade.html), [terms](https://lens.ribeiros.click/politicas/termos.html), [security](https://lens.ribeiros.click/politicas/seguranca.html).

## For developers

Pure Swift (AppKit + SwiftUI), no third-party dependencies. ScreenCaptureKit for capture and recording, Vision for OCR, Translation for offline translation, Carbon hotkeys for global shortcuts.

```bash
./build.sh          # builds SnapLens.app (ICON=1|2|3|4 picks the icon; 4 = default)
./make_dmg.sh       # builds SnapLens.dmg
./make_appstore.sh  # builds SnapLens.pkg for the Mac App Store (needs certificates + profile)
SnapLens.app/Contents/MacOS/SnapLens --render-shots <dir>   # renders the website screenshots from the real UI
```

Diagnostics: the app writes a trace to `~/Library/Logs/SnapLens/snaplens.log` (menu → Diagnóstico).

### Link server

Plain PHP 8 + SQLite (`server/public_html`), self-hostable on shared hosting:

- `POST /api/upload` — multipart `file`, `expires` (seconds, 0 = never), `once` (`1` = view-once); rate-limited per IP → `{id, url, image_url, expires_at, delete_token}`
- `POST /api/delete` — `{id, token}`
- `GET /s/{id}` — share page · `GET /i/{id}` — raw image (`?dl=1` downloads)
- `/token` — find or delete an image by its delete token · `/contato` — contact form · `admin.php?key=…` — admin (token in `config.php`)

Deploy to Hostinger shared hosting: `./server/deploy.sh` (API token in `.hostinger/token` or `HOSTINGER_API_TOKEN`). On first run it creates `config.php` from the example.

## Author

Created by [José Ribeiro Junior](mailto:contato@ribeiros.click) · [contato@ribeiros.click](mailto:contato@ribeiros.click)

## License

[MIT](LICENSE)
