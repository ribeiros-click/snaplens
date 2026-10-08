#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Gera a página inicial em 5 idiomas: / (pt-BR), /en/, /es/, /it/, /zh/. Uso: python3 Tools/build_site.py"""
import os, html
ROOT = "server/public_html"
LANGS = {"pt-BR": "", "en": "en/", "es": "es/", "it": "it/", "zh": "zh/"}
NAMES = {"pt-BR": "Português", "en": "English", "es": "Español", "it": "Italiano", "zh": "中文"}
VTT = {"pt-BR": "pt-BR", "en": "en", "es": "es", "it": "it", "zh": "zh-Hans"}
HTMLLANG = {"pt-BR": "pt-BR", "en": "en", "es": "es", "it": "it", "zh": "zh-Hans"}
S = {}
def add(key, pt, en, es, it, zh):
    for l, v in zip(["pt-BR", "en", "es", "it", "zh"], [pt, en, es, it, zh]): S.setdefault(l, {})[key] = v

add("title", "SnapLens — screenshots, OCR e IA para macOS", "SnapLens — screenshots, OCR and AI for macOS", "SnapLens — capturas, OCR e IA para macOS", "SnapLens — screenshot, OCR e IA per macOS", "SnapLens — macOS 截图、OCR 与 AI")
add("desc", "SnapLens: app nativo de barra de menu para macOS com captura anotada, OCR local, descrição por IA, gravação de tela, biblioteca e links públicos que expiram sozinhos.", "SnapLens: native macOS menu-bar app with annotated capture, on-device OCR, AI descriptions, screen recording, a library and public links that expire on their own.", "SnapLens: app nativa de barra de menú para macOS con captura anotada, OCR local, descripción por IA, grabación de pantalla, biblioteca y enlaces públicos que caducan solos.", "SnapLens: app nativa per la barra dei menu di macOS con cattura annotata, OCR locale, descrizione IA, registrazione dello schermo, libreria e link pubblici che scadono da soli.", "SnapLens：macOS 原生菜单栏应用，支持标注截图、本地 OCR、AI 描述、屏幕录制、资料库和自动过期的公开链接。")
add("og_desc", "Capture, anote, extraia texto e compartilhe com link que expira. Grátis, nativo, sem conta.", "Capture, annotate, extract text and share with an expiring link. Free, native, no account.", "Captura, anota, extrae texto y comparte con un enlace que caduca. Gratis, nativo, sin cuenta.", "Cattura, annota, estrai testo e condividi con un link che scade. Gratuito, nativo, senza account.", "截图、标注、提取文字，并通过会过期的链接分享。免费、原生、无需账户。")
add("nav_features", "Recursos", "Features", "Funciones", "Funzioni", "功能")
add("nav_video", "Vídeo", "Video", "Vídeo", "Video", "视频")
add("nav_shots", "Prints", "Screenshots", "Capturas", "Schermate", "截图")
add("nav_keys", "Atalhos", "Shortcuts", "Atajos", "Scorciatoie", "快捷键")
add("nav_links", "Links", "Links", "Enlaces", "Link", "链接")
add("nav_faq", "Dúvidas", "FAQ", "Preguntas", "FAQ", "常见问题")
add("nav_download", "Baixar", "Download", "Descargar", "Scarica", "下载")
add("eyebrow_free", "Grátis", "Free", "Gratis", "Gratuito", "免费")
add("eyebrow", "macOS 15+ · Apple Silicon · sem conta", "macOS 15+ · Apple Silicon · no account", "macOS 15+ · Apple Silicon · sin cuenta", "macOS 15+ · Apple Silicon · senza account", "macOS 15+ · Apple Silicon · 无需账户")
add("h1", 'Capture, anote e <span class="g">compartilhe</span> sem sair do teclado.', 'Capture, annotate and <span class="g">share</span> without leaving the keyboard.', 'Captura, anota y <span class="g">comparte</span> sin salir del teclado.', 'Cattura, annota e <span class="g">condividi</span> senza lasciare la tastiera.', '截图、标注、<span class="g">分享</span>，手不离键盘。')
add("sub", "SnapLens vive na barra de menu do seu Mac. Um atalho congela a tela; você seleciona, anota, extrai o texto ou gera um link que expira sozinho. Nada sai do Mac sem você pedir.", "SnapLens lives in your Mac's menu bar. One shortcut freezes the screen; you select, annotate, extract text or create a link that expires on its own. Nothing leaves your Mac unless you ask.", "SnapLens vive en la barra de menú de tu Mac. Un atajo congela la pantalla; seleccionas, anotas, extraes el texto o generas un enlace que caduca solo. Nada sale del Mac sin que lo pidas.", "SnapLens vive nella barra dei menu del tuo Mac. Una scorciatoia blocca lo schermo; selezioni, annoti, estrai il testo o crei un link che scade da solo. Nulla lascia il Mac senza il tuo consenso.", "SnapLens 常驻于 Mac 菜单栏。一个快捷键冻结屏幕；你可以选择区域、标注、提取文字，或生成会自动过期的链接。未经你允许，任何数据都不会离开 Mac。")
add("cta_download", "Baixar para macOS", "Download for macOS", "Descargar para macOS", "Scarica per macOS", "下载 macOS 版")
add("cta_video", "Ver o vídeo", "Watch the video", "Ver el vídeo", "Guarda il video", "观看视频")
add("hint", "Depois de instalar, pressione <kbd>⌥</kbd><kbd>⌘</kbd><kbd>P</kbd> para capturar.", "After installing, press <kbd>⌥</kbd><kbd>⌘</kbd><kbd>P</kbd> to capture.", "Después de instalar, pulsa <kbd>⌥</kbd><kbd>⌘</kbd><kbd>P</kbd> para capturar.", "Dopo l'installazione premi <kbd>⌥</kbd><kbd>⌘</kbd><kbd>P</kbd> per catturare.", "安装后按 <kbd>⌥</kbd><kbd>⌘</kbd><kbd>P</kbd> 开始截图。")
add("win_overlay", "Overlay de captura — SnapLens", "Capture overlay — SnapLens", "Superposición de captura — SnapLens", "Overlay di cattura — SnapLens", "截图浮层 — SnapLens")
add("step1_t", "Capture", "Capture", "Captura", "Cattura", "截取")
add("step1", "⌥⌘P congela a tela. Arraste para selecionar, ajuste pelas alças ou nudge com as setas.", "⌥⌘P freezes the screen. Drag to select, resize with handles or nudge with the arrow keys.", "⌥⌘P congela la pantalla. Arrastra para seleccionar, ajusta con las asas o mueve con las flechas.", "⌥⌘P blocca lo schermo. Trascina per selezionare, regola con le maniglie o sposta con le frecce.", "⌥⌘P 冻结屏幕。拖动选择，用控制点调整，或用方向键微调。")
add("step2_t", "Anote ou extraia", "Annotate or extract", "Anota o extrae", "Annota o estrai", "标注或提取")
add("step2", "Seta, retângulo, texto e caneta. Ou peça o OCR local e a descrição por IA.", "Arrow, rectangle, text and pen. Or ask for on-device OCR and an AI description.", "Flecha, rectángulo, texto y lápiz. O pide el OCR local y la descripción por IA.", "Freccia, rettangolo, testo e penna. Oppure chiedi l'OCR locale e la descrizione IA.", "箭头、矩形、文字和画笔。或使用本地 OCR 和 AI 描述。")
add("step3_t", "Copie, salve ou compartilhe", "Copy, save or share", "Copia, guarda o comparte", "Copia, salva o condividi", "复制、保存或分享")
add("step3", "Enter copia. ⌘S salva. O 🔗 gera um link anônimo com validade e token de exclusão.", "Enter copies. ⌘S saves. 🔗 creates an anonymous link with an expiry and a delete token.", "Intro copia. ⌘S guarda. El 🔗 genera un enlace anónimo con caducidad y token de eliminación.", "Invio copia. ⌘S salva. 🔗 crea un link anonimo con scadenza e token di eliminazione.", "回车复制，⌘S 保存。🔗 生成带有效期和删除令牌的匿名链接。")
add("feat_h", "Tudo que um screenshot precisa", "Everything a screenshot needs", "Todo lo que necesita una captura", "Tutto ciò che serve a uno screenshot", "截图所需的一切")
add("feat_p", "Rápido como o Lightshot, nativo como o macOS. Sem Electron, sem assinatura, sem telemetria.", "Fast like Lightshot, native like macOS. No Electron, no subscription, no telemetry.", "Rápido como Lightshot, nativo como macOS. Sin Electron, sin suscripción, sin telemetría.", "Veloce come Lightshot, nativo come macOS. Niente Electron, niente abbonamento, niente telemetria.", "像 Lightshot 一样快，像 macOS 一样原生。无 Electron、无订阅、无遥测。")
add("f1_t", "Overlay de captura completo", "A complete capture overlay", "Superposición de captura completa", "Overlay di cattura completo", "完整的截图浮层")
add("f1", "Seleção com alças, movimentação, nudge por teclado, dimensões ao vivo e uma barra de ferramentas com tudo que você precisa. Esc, botão direito ou o botão Cancelar saem a qualquer momento — e se você não mexer em 10 s, ele se fecha sozinho.", "Selection with handles, dragging, keyboard nudging, live dimensions and a toolbar with everything you need. Esc, right-click or the Cancel button exit at any time — and if you don't move for 10 s, it closes by itself.", "Selección con asas, desplazamiento, ajuste por teclado, dimensiones en vivo y una barra con todo lo necesario. Esc, clic derecho o el botón Cancelar salen en cualquier momento, y si no te mueves en 10 s, se cierra solo.", "Selezione con maniglie, spostamento, regolazione da tastiera, dimensioni in tempo reale e una barra con tutto il necessario. Esc, tasto destro o il pulsante Annulla escono in qualsiasi momento, e se non ti muovi per 10 s si chiude da solo.", "带控制点的选区、拖动、键盘微调、实时尺寸，以及一应俱全的工具栏。Esc、右键或“取消”按钮随时退出；10 秒无操作会自动关闭。")
add("f1_chips", "Retângulo|Elipse|Linha|Seta|Caneta|Texto|7 cores|⌘Z", "Rectangle|Ellipse|Line|Arrow|Pen|Text|7 colors|⌘Z", "Rectángulo|Elipse|Línea|Flecha|Lápiz|Texto|7 colores|⌘Z", "Rettangolo|Ellisse|Linea|Freccia|Penna|Testo|7 colori|⌘Z", "矩形|椭圆|直线|箭头|画笔|文字|7 种颜色|⌘Z")
add("f2_t", "OCR 100% local", "100% on-device OCR", "OCR 100% local", "OCR 100% locale", "100% 本地 OCR")
add("f2", "Extraia o texto de qualquer região com o Vision da Apple, offline. O resultado abre numa janela editável, já copiado, com tradução para 9 idiomas pelo tradutor do próprio macOS.", "Extract text from any region with Apple's Vision, offline. The result opens in an editable window, already copied, with translation into 9 languages by macOS's own translator.", "Extrae el texto de cualquier región con Vision de Apple, sin conexión. El resultado se abre en una ventana editable, ya copiado, con traducción a 9 idiomas por el traductor del propio macOS.", "Estrai il testo da qualsiasi area con Vision di Apple, offline. Il risultato si apre in una finestra modificabile, già copiato, con traduzione in 9 lingue tramite il traduttore di macOS.", "通过 Apple Vision 离线提取任意区域的文字。结果在可编辑窗口中打开并已复制，可用 macOS 自带翻译器译成 9 种语言。")
add("f2_chips", "Português e inglês|Detecção automática de idioma|Tradução offline", "Portuguese and English|Automatic language detection|Offline translation", "Portugués e inglés|Detección automática de idioma|Traducción sin conexión", "Portoghese e inglese|Rilevamento automatico della lingua|Traduzione offline", "葡萄牙语和英语|自动语言检测|离线翻译")
add("f3_t", "Descrição por IA", "AI descriptions", "Descripción por IA", "Descrizione IA", "AI 描述")
add("f3", "Claude, OpenAI, DeepSeek ou qualquer API compatível, inclusive Ollama local. Sem chave, usa o modo nativo.", "Claude, OpenAI, DeepSeek or any compatible API, including local Ollama. Without a key, the native mode is used.", "Claude, OpenAI, DeepSeek o cualquier API compatible, incluido Ollama local. Sin clave, usa el modo nativo.", "Claude, OpenAI, DeepSeek o qualsiasi API compatibile, incluso Ollama locale. Senza chiave usa la modalità nativa.", "Claude、OpenAI、DeepSeek 或任何兼容 API，包括本地 Ollama。无密钥时使用原生模式。")
add("f4_t", "Gravação de tela", "Screen recording", "Grabación de pantalla", "Registrazione dello schermo", "屏幕录制")
add("f4", "MP4 H.264 com áudio do sistema e/ou microfone, com cronômetro na barra de menu.", "H.264 MP4 with system audio and/or microphone, with a timer in the menu bar.", "MP4 H.264 con audio del sistema y/o micrófono, con cronómetro en la barra de menú.", "MP4 H.264 con audio di sistema e/o microfono, con timer nella barra dei menu.", "H.264 MP4，支持系统音频和/或麦克风，菜单栏显示计时器。")
add("f5_t", "Biblioteca", "Library", "Biblioteca", "Libreria", "资料库")
add("f5", "Screenshots, vídeos, textos copiados, OCR e descrições num só lugar, com busca e exportação.", "Screenshots, videos, copied text, OCR and descriptions in one place, with search and export.", "Capturas, vídeos, textos copiados, OCR y descripciones en un solo lugar, con búsqueda y exportación.", "Screenshot, video, testi copiati, OCR e descrizioni in un unico posto, con ricerca ed esportazione.", "截图、视频、复制的文字、OCR 和描述集中一处，支持搜索与导出。")
add("f6_t", "Links que expiram", "Links that expire", "Enlaces que caducan", "Link che scadono", "会过期的链接")
add("f6", "1 hora a 30 dias, ou sem expirar. Visualização única opcional: a imagem se autodestrói na primeira abertura.", "1 hour to 30 days, or never. Optional view-once: the image self-destructs on first open.", "De 1 hora a 30 días, o sin caducidad. Visualización única opcional: la imagen se autodestruye al abrirse por primera vez.", "Da 1 ora a 30 giorni, o mai. Visualizzazione singola opzionale: l'immagine si autodistrugge alla prima apertura.", "1 小时到 30 天，或永不过期。可选阅后即焚：图片在首次打开后自毁。")
add("f7_t", "Atalhos configuráveis", "Configurable shortcuts", "Atajos configurables", "Scorciatoie configurabili", "可自定义快捷键")
add("f7", "Grave qualquer combinação em Ajustes. O app avisa se outro programa já usa o atalho.", "Record any combination in Settings. The app warns you if another program already uses the shortcut.", "Graba cualquier combinación en Ajustes. La app avisa si otro programa ya usa el atajo.", "Registra qualsiasi combinazione nelle Impostazioni. L'app avvisa se un altro programma usa già la scorciatoia.", "在设置中录入任意组合。若其他程序已占用该快捷键，应用会提示。")
add("f8_t", "Privado por padrão", "Private by default", "Privado por defecto", "Privato per impostazione", "默认私密")
add("f8", "Chaves no Keychain. Senhas copiadas são ignoradas. Nenhuma telemetria. Código auditável.", "Keys in the Keychain. Copied passwords are ignored. No telemetry. Auditable code.", "Claves en el Llavero. Las contraseñas copiadas se ignoran. Sin telemetría. Código auditable.", "Chiavi nel Portachiavi. Le password copiate vengono ignorate. Nessuna telemetria. Codice verificabile.", "密钥存于钥匙串。忽略复制的密码。无遥测。代码可审计。")
add("video_h", "Veja o SnapLens em 77 segundos", "See SnapLens in 77 seconds", "Mira SnapLens en 77 segundos", "Guarda SnapLens in 77 secondi", "77 秒了解 SnapLens")
add("video_p", "Narração em inglês com legendas em português, inglês, espanhol, italiano e chinês. Interface real do app, renderizada sobre um desktop de demonstração.", "English narration with subtitles in Portuguese, English, Spanish, Italian and Chinese. The real app interface, rendered over a demo desktop.", "Narración en inglés con subtítulos en portugués, inglés, español, italiano y chino. Interfaz real de la app, renderizada sobre un escritorio de demostración.", "Narrazione in inglese con sottotitoli in portoghese, inglese, spagnolo, italiano e cinese. L'interfaccia reale dell'app, renderizzata su un desktop dimostrativo.", "英文旁白，配有葡萄牙语、英语、西班牙语、意大利语和中文字幕。真实应用界面，渲染于演示桌面之上。")
add("video_transcript", "Transcrição", "Transcript", "Transcripción", "Trascrizione", "文字稿")
add("video_dl", "Baixar o vídeo (MP4, 11 MB)", "Download the video (MP4, 11 MB)", "Descargar el vídeo (MP4, 11 MB)", "Scarica il video (MP4, 11 MB)", "下载视频（MP4，11 MB）")
add("shots_h", "Veja em ação", "See it in action", "Míralo en acción", "Guardalo in azione", "实际效果")
add("shots_p", "Interface real do app, renderizada sobre um desktop de demonstração.", "The real app interface, rendered over a demo desktop.", "Interfaz real de la app, renderizada sobre un escritorio de demostración.", "L'interfaccia reale dell'app, renderizzata su un desktop dimostrativo.", "真实应用界面，渲染于演示桌面之上。")
add("s1_win", "Captura de seleção", "Region capture", "Captura de selección", "Cattura di selezione", "区域截图")
add("s1_t", "Overlay de captura", "Capture overlay", "Superposición de captura", "Overlay di cattura", "截图浮层")
add("s1_p", "A tela congela, você seleciona e decide o destino sem trocar de janela.", "The screen freezes; you select and choose the destination without switching windows.", "La pantalla se congela, seleccionas y decides el destino sin cambiar de ventana.", "Lo schermo si blocca, selezioni e decidi la destinazione senza cambiare finestra.", "屏幕冻结，选择区域并决定去向，无需切换窗口。")
add("s1_li", "Alças para redimensionar, arraste para mover, setas para ajustar 1 px|Anotações vetoriais com desfazer|Copiar, salvar, OCR, IA ou link — um clique cada|Cancelar sempre visível; Esc funciona mesmo sem foco", "Handles to resize, drag to move, arrow keys for 1 px nudges|Vector annotations with undo|Copy, save, OCR, AI or link — one click each|Cancel always visible; Esc works even without focus", "Asas para redimensionar, arrastre para mover, flechas para ajustar 1 px|Anotaciones vectoriales con deshacer|Copiar, guardar, OCR, IA o enlace: un clic cada uno|Cancelar siempre visible; Esc funciona incluso sin foco", "Maniglie per ridimensionare, trascina per spostare, frecce per 1 px|Annotazioni vettoriali con annulla|Copia, salva, OCR, IA o link: un clic ciascuno|Annulla sempre visibile; Esc funziona anche senza focus", "控制点调整大小，拖动移动，方向键 1 像素微调|矢量标注，支持撤销|复制、保存、OCR、AI 或链接，各一键|“取消”始终可见；Esc 无焦点也有效")
add("s2_win", "Biblioteca", "Library", "Biblioteca", "Libreria", "资料库")
add("s2_t", "Biblioteca", "Library", "Biblioteca", "Libreria", "资料库")
add("s2_p", "Tudo que você capturou ou copiou, pesquisável e exportável.", "Everything you captured or copied, searchable and exportable.", "Todo lo que capturaste o copiaste, con búsqueda y exportación.", "Tutto ciò che hai catturato o copiato, ricercabile ed esportabile.", "你截取或复制的一切，可搜索、可导出。")
add("s2_li", "Imagens, vídeos e textos em abas|Itens compartilhados mostram link, validade e botão de revogar|OCR e descrição por IA de qualquer item antigo|Até 500 itens; vídeos ficam até você apagar", "Images, videos and text in tabs|Shared items show the link, expiry and a revoke button|OCR and AI description for any older item|Up to 500 items; videos stay until you delete them", "Imágenes, vídeos y textos en pestañas|Los elementos compartidos muestran enlace, caducidad y botón de revocar|OCR y descripción por IA de cualquier elemento antiguo|Hasta 500 elementos; los vídeos se quedan hasta que los borres", "Immagini, video e testi in schede|Gli elementi condivisi mostrano link, scadenza e pulsante di revoca|OCR e descrizione IA di qualsiasi elemento precedente|Fino a 500 elementi; i video restano finché non li elimini", "图片、视频和文字分标签页|已分享项目显示链接、有效期和撤销按钮|可对任意旧项目进行 OCR 和 AI 描述|最多 500 项；视频保留至你删除")
add("s3_win", "Ajustes", "Settings", "Ajustes", "Impostazioni", "设置")
add("s3_t", "Ajustes", "Settings", "Ajustes", "Impostazioni", "设置")
add("s3_p", "Tudo configurável, nada obrigatório.", "Everything configurable, nothing mandatory.", "Todo configurable, nada obligatorio.", "Tutto configurabile, niente di obbligatorio.", "一切可配置，没有强制项。")
add("s3_li", "Idioma do app em 5 opções|Atalhos globais regraváveis|Iniciar com o macOS|Validade padrão e visualização única dos links|Provedores de IA com chave, modelo e URL próprios", "App language in 5 options|Re-recordable global shortcuts|Launch at login|Default expiry and view-once for links|AI providers with their own key, model and URL", "Idioma de la app en 5 opciones|Atajos globales regrabables|Iniciar con macOS|Caducidad predeterminada y visualización única de enlaces|Proveedores de IA con clave, modelo y URL propios", "Lingua dell'app in 5 opzioni|Scorciatoie globali registrabili|Avvio all'accesso|Scadenza predefinita e visualizzazione singola dei link|Provider IA con chiave, modello e URL propri", "5 种应用语言|可重新录入的全局快捷键|登录时启动|链接默认有效期和阅后即焚|各 AI 提供商独立的密钥、模型和 URL")
add("keys_h", "Atalhos padrão", "Default shortcuts", "Atajos predeterminados", "Scorciatoie predefinite", "默认快捷键")
add("keys_p", "Troque qualquer um em Ajustes → Atalhos globais.", "Change any of them in Settings → Global shortcuts.", "Cambia cualquiera en Ajustes → Atajos globales.", "Cambiane uno qualsiasi in Impostazioni → Scorciatoie globali.", "可在“设置 → 全局快捷键”中更改。")
add("k1", "Capturar seleção", "Capture region", "Capturar selección", "Cattura selezione", "截取区域")
add("k2", "Capturar tela inteira", "Capture full screen", "Capturar pantalla completa", "Cattura schermo intero", "截取全屏")
add("k3", "OCR de uma seleção", "OCR a region", "OCR de una selección", "OCR di una selezione", "区域 OCR")
add("k4", "Descrever seleção com IA", "Describe region with AI", "Describir selección con IA", "Descrivi selezione con IA", "AI 描述区域")
add("k5", "Gravar / parar gravação", "Start / stop recording", "Iniciar / detener grabación", "Avvia / ferma registrazione", "开始 / 停止录制")
add("k6", "Biblioteca", "Library", "Biblioteca", "Libreria", "资料库")
add("k7", "No overlay: copiar · salvar · desfazer", "In the overlay: copy · save · undo", "En la superposición: copiar · guardar · deshacer", "Nell'overlay: copia · salva · annulla", "浮层中：复制 · 保存 · 撤销")
add("k8", "No overlay: cancelar · refazer seleção", "In the overlay: cancel · reselect", "En la superposición: cancelar · rehacer selección", "Nell'overlay: annulla · rifai selezione", "浮层中：取消 · 重新选择")
add("k8_keys", "clique direito", "right-click", "clic derecho", "tasto destro", "右键")
add("links_h", "Links públicos com validade", "Public links with an expiry", "Enlaces públicos con caducidad", "Link pubblici con scadenza", "带有效期的公开链接")
add("links_p", "Sem conta, sem cadastro, sem chave. O 🔗 envia a imagem para este servidor e copia a URL na hora.", "No account, no sign-up, no key. 🔗 uploads the image to this server and copies the URL instantly.", "Sin cuenta, sin registro, sin clave. El 🔗 sube la imagen a este servidor y copia la URL al instante.", "Senza account, senza registrazione, senza chiave. 🔗 carica l'immagine su questo server e copia subito l'URL.", "无需账户、无需注册、无需密钥。🔗 将图片上传到此服务器并立即复制网址。")
add("tl1_t", "Escolha a validade", "Choose the expiry", "Elige la caducidad", "Scegli la scadenza", "选择有效期")
add("tl1", "1 hora, 1 dia, 7 dias, 30 dias ou sem expirar. Ative “visualização única” para autodestruir na primeira abertura.", "1 hour, 1 day, 7 days, 30 days or never. Turn on “view once” to self-destruct on first open.", "1 hora, 1 día, 7 días, 30 días o sin caducidad. Activa “visualización única” para autodestruirse al abrirse por primera vez.", "1 ora, 1 giorno, 7 giorni, 30 giorni o mai. Attiva “visualizzazione singola” per l'autodistruzione alla prima apertura.", "1 小时、1 天、7 天、30 天或永不过期。开启“阅后即焚”，首次打开后自毁。")
add("tl2_t", "Receba link e token", "Get a link and a token", "Recibe enlace y token", "Ricevi link e token", "获取链接和令牌")
add("tl2", "O link vai para a área de transferência. Um token de exclusão aparece uma vez — guarde-o para apagar a imagem de qualquer lugar.", "The link goes to the clipboard. A delete token is shown once — keep it to remove the image from anywhere.", "El enlace va al portapapeles. Un token de eliminación aparece una vez: guárdalo para borrar la imagen desde cualquier lugar.", "Il link va negli appunti. Un token di eliminazione compare una sola volta: conservalo per rimuovere l'immagine da ovunque.", "链接进入剪贴板。删除令牌只显示一次，请保存以便随时随地删除图片。")
add("tl3_t", "Compartilhe", "Share", "Comparte", "Condividi", "分享")
add("tl3", "Quem abrir vê uma página limpa com a imagem, tamanho, prazo e botões de baixar e copiar. Sem rastreadores.", "Whoever opens it sees a clean page with the image, size, expiry and download/copy buttons. No trackers.", "Quien lo abra ve una página limpia con la imagen, tamaño, plazo y botones de descargar y copiar. Sin rastreadores.", "Chi lo apre vede una pagina pulita con immagine, dimensioni, scadenza e pulsanti di download e copia. Senza tracker.", "打开者看到简洁页面：图片、大小、期限以及下载/复制按钮。无跟踪器。")
add("tl4_t", "Expira ou revogue", "Expires, or revoke it", "Caduca o revócalo", "Scade, o revocalo", "过期或撤销")
add("tl4", "Passado o prazo, o arquivo é apagado do servidor. Antes disso, revogue pela Biblioteca ou pela página de token.", "After the deadline, the file is deleted from the server. Before that, revoke it from the Library or the token page.", "Pasado el plazo, el archivo se borra del servidor. Antes, revócalo desde la Biblioteca o la página de token.", "Scaduto il termine, il file viene eliminato dal server. Prima, revocalo dalla Libreria o dalla pagina del token.", "到期后文件从服务器删除。在此之前，可通过资料库或令牌页面撤销。")
add("panel_t", "Perdeu o link?", "Lost the link?", "¿Perdiste el enlace?", "Hai perso il link?", "丢失链接？")
add("panel_p", "Com o token de exclusão você localiza a imagem, vê quanto tempo falta e apaga quando quiser — sem precisar do app.", "With the delete token you can find the image, see how long is left and delete it whenever you want — no app needed.", "Con el token de eliminación localizas la imagen, ves cuánto falta y la borras cuando quieras, sin necesidad de la app.", "Con il token di eliminazione trovi l'immagine, vedi quanto manca e la elimini quando vuoi, senza bisogno dell'app.", "使用删除令牌可找到图片、查看剩余时间并随时删除，无需应用。")
add("panel_btn", "Acessar por token", "Access by token", "Acceder por token", "Accedi con il token", "通过令牌访问")
add("panel_btn2", "Política de retenção", "Retention policy", "Política de retención", "Politica di conservazione", "数据保留政策")
add("badges", "HTTPS obrigatório|Sem cookies nem conta|Exclusão automática|Token só como hash", "HTTPS required|No cookies, no account|Automatic deletion|Token stored as hash only", "HTTPS obligatorio|Sin cookies ni cuenta|Eliminación automática|Token solo como hash", "HTTPS obbligatorio|Niente cookie né account|Eliminazione automatica|Token solo come hash", "强制 HTTPS|无 Cookie、无账户|自动删除|令牌仅存哈希")
add("faq_h", "Dúvidas frequentes", "Frequently asked questions", "Preguntas frecuentes", "Domande frequenti", "常见问题")
add("q1", "O macOS diz que o app não pode ser aberto. E agora?", "macOS says the app can't be opened. Now what?", "macOS dice que la app no se puede abrir. ¿Y ahora?", "macOS dice che l'app non può essere aperta. E adesso?", "macOS 提示无法打开应用，怎么办？")
add("a1", "A build atual não é notarizada pela Apple. Clique com o botão direito no SnapLens → <strong>Abrir</strong> → Abrir. É preciso só na primeira vez. Depois, permita “Gravação de Tela” em Ajustes do Sistema → Privacidade e Segurança.", "The current build isn't notarized by Apple. Right-click SnapLens → <strong>Open</strong> → Open. Only needed the first time. Then allow “Screen Recording” in System Settings → Privacy & Security.", "La build actual no está notarizada por Apple. Haz clic derecho en SnapLens → <strong>Abrir</strong> → Abrir. Solo hace falta la primera vez. Luego permite “Grabación de pantalla” en Ajustes del Sistema → Privacidad y seguridad.", "La build attuale non è notarizzata da Apple. Fai clic destro su SnapLens → <strong>Apri</strong> → Apri. Serve solo la prima volta. Poi consenti “Registrazione schermo” in Impostazioni di Sistema → Privacy e sicurezza.", "当前版本未经 Apple 公证。右键点击 SnapLens → <strong>打开</strong> → 打开。仅首次需要。然后在“系统设置 → 隐私与安全性”中允许“屏幕录制”。")
add("q2", "O que sai do meu Mac?", "What leaves my Mac?", "¿Qué sale de mi Mac?", "Cosa esce dal mio Mac?", "哪些数据会离开我的 Mac？")
add("a2", 'Nada, a menos que você peça: o OCR e as anotações rodam localmente. Só o botão de compartilhar envia a imagem para lens.ribeiros.click, e só “Descrever com IA” envia a imagem ao provedor que você configurou. Veja a <a href="/politicas/privacidade.html">Política de Privacidade</a>.', 'Nothing, unless you ask: OCR and annotations run locally. Only the share button uploads the image to lens.ribeiros.click, and only “Describe with AI” sends the image to the provider you configured. See the <a href="/politicas/privacidade.html">Privacy Policy</a> (Portuguese).', 'Nada, a menos que lo pidas: el OCR y las anotaciones se ejecutan localmente. Solo el botón de compartir sube la imagen a lens.ribeiros.click, y solo “Describir con IA” la envía al proveedor que configuraste. Consulta la <a href="/politicas/privacidade.html">Política de Privacidad</a> (en portugués).', 'Nulla, a meno che tu non lo chieda: OCR e annotazioni girano in locale. Solo il pulsante di condivisione carica l\'immagine su lens.ribeiros.click, e solo “Descrivi con IA” la invia al provider che hai configurato. Vedi la <a href="/politicas/privacidade.html">Politica sulla privacy</a> (in portoghese).', '除非你主动操作，否则什么都不会：OCR 和标注都在本地运行。只有分享按钮会把图片上传到 lens.ribeiros.click，只有“AI 描述”会把图片发送给你配置的提供商。参见<a href="/politicas/privacidade.html">隐私政策</a>（葡萄牙语）。')
add("q3", "Preciso de conta para compartilhar?", "Do I need an account to share?", "¿Necesito cuenta para compartir?", "Serve un account per condividere?", "分享需要账户吗？")
add("a3", "Não. O upload é anônimo, limitado por IP para evitar abuso. Você recebe um token de exclusão para apagar a imagem quando quiser.", "No. Uploads are anonymous and rate-limited per IP to prevent abuse. You get a delete token to remove the image whenever you want.", "No. La subida es anónima, limitada por IP para evitar abusos. Recibes un token de eliminación para borrar la imagen cuando quieras.", "No. Il caricamento è anonimo, limitato per IP per evitare abusi. Ricevi un token di eliminazione per rimuovere l'immagine quando vuoi.", "不需要。上传是匿名的，按 IP 限流以防滥用。你会获得删除令牌，可随时删除图片。")
add("q4", "Posso usar meu próprio servidor de links?", "Can I use my own link server?", "¿Puedo usar mi propio servidor de enlaces?", "Posso usare il mio server per i link?", "可以使用自己的链接服务器吗？")
add("a4", "Sim. O backend é PHP puro, auto-hospedável, e o endereço do servidor é configurável em Ajustes → Compartilhar.", "Yes. The backend is plain, self-hostable PHP, and the server address is configurable in Settings → Share.", "Sí. El backend es PHP puro, autoalojable, y la dirección del servidor se configura en Ajustes → Compartir.", "Sì. Il backend è PHP puro, self-hostable, e l'indirizzo del server si configura in Impostazioni → Condividi.", "可以。后端是纯 PHP，可自行托管，服务器地址可在“设置 → 分享”中配置。")
add("q5", "Quanto custa?", "How much does it cost?", "¿Cuánto cuesta?", "Quanto costa?", "价格多少？")
add("a5", "Nada. O app é gratuito, sem assinatura e sem anúncios. Provedores de IA externos cobram por uso na sua própria conta.", "Nothing. The app is free, with no subscription and no ads. External AI providers bill usage on your own account.", "Nada. La app es gratuita, sin suscripción y sin anuncios. Los proveedores de IA externos cobran por uso en tu propia cuenta.", "Niente. L'app è gratuita, senza abbonamento e senza pubblicità. I provider IA esterni addebitano l'uso sul tuo account.", "免费。应用免费、无订阅、无广告。外部 AI 提供商按用量在你自己的账户计费。")
add("q6", "Funciona em Macs Intel ou macOS antigos?", "Does it work on Intel Macs or older macOS?", "¿Funciona en Macs Intel o macOS antiguos?", "Funziona su Mac Intel o macOS precedenti?", "支持 Intel Mac 或旧版 macOS 吗？")
add("a6", "A build é para Apple Silicon e exige macOS 15 (Sequoia) ou mais recente, por causa do ScreenCaptureKit e do tradutor do sistema.", "The build targets Apple Silicon and requires macOS 15 (Sequoia) or later, because of ScreenCaptureKit and the system translator.", "La build es para Apple Silicon y requiere macOS 15 (Sequoia) o posterior, por ScreenCaptureKit y el traductor del sistema.", "La build è per Apple Silicon e richiede macOS 15 (Sequoia) o successivo, a causa di ScreenCaptureKit e del traduttore di sistema.", "该版本面向 Apple Silicon，需要 macOS 15（Sequoia）或更高版本，因依赖 ScreenCaptureKit 和系统翻译器。")
add("cta_h", "Pronto para capturar melhor?", "Ready to capture better?", "¿Listo para capturar mejor?", "Pronto a catturare meglio?", "准备好更好地截图了吗？")
add("cta_p", "Arraste para Aplicativos e pressione ⌥⌘P.", "Drag to Applications and press ⌥⌘P.", "Arrastra a Aplicaciones y pulsa ⌥⌘P.", "Trascina in Applicazioni e premi ⌥⌘P.", "拖入“应用程序”并按 ⌥⌘P。")
add("cta_btn", "Baixar SnapLens.dmg", "Download SnapLens.dmg", "Descargar SnapLens.dmg", "Scarica SnapLens.dmg", "下载 SnapLens.dmg")
add("cta_meta", "macOS 15+ · Apple Silicon · gratuito", "macOS 15+ · Apple Silicon · free", "macOS 15+ · Apple Silicon · gratis", "macOS 15+ · Apple Silicon · gratuito", "macOS 15+ · Apple Silicon · 免费")
add("cta_notes", "notas de versão", "release notes", "notas de la versión", "note di rilascio", "更新说明")
add("foot_tag", "Screenshots, OCR e IA para macOS. Feito para quem vive no teclado.", "Screenshots, OCR and AI for macOS. Made for people who live on the keyboard.", "Capturas, OCR e IA para macOS. Hecho para quien vive en el teclado.", "Screenshot, OCR e IA per macOS. Fatto per chi vive sulla tastiera.", "macOS 截图、OCR 与 AI。为键盘党而生。")
add("foot_product", "Produto", "Product", "Producto", "Prodotto", "产品")
add("foot_policies", "Políticas", "Policies", "Políticas", "Politiche", "政策")
add("foot_policies_note", "", " (Portuguese)", " (en portugués)", " (in portoghese)", "（葡萄牙语）")
add("foot_contact", "Contato", "Contact", "Contacto", "Contatti", "联系")
add("foot_form", "Formulário de contato", "Contact form", "Formulario de contacto", "Modulo di contatto", "联系表单")
add("foot_report", "Denunciar conteúdo", "Report content", "Denunciar contenido", "Segnala contenuto", "举报内容")
add("foot_token", "Acessar por token", "Access by token", "Acceder por token", "Accedi con il token", "通过令牌访问")
add("foot_privacy", "Privacidade", "Privacy", "Privacidad", "Privacy", "隐私")
add("foot_terms", "Termos de uso", "Terms of use", "Términos de uso", "Termini d'uso", "使用条款")
add("foot_aup", "Uso aceitável", "Acceptable use", "Uso aceptable", "Uso accettabile", "可接受使用")
add("foot_sec", "Segurança", "Security", "Seguridad", "Sicurezza", "安全")
add("foot_ret", "Retenção de dados", "Data retention", "Retención de datos", "Conservazione dei dati", "数据保留")
add("foot_copy", "© 2026 SnapLens · Brasil", "© 2026 SnapLens · Brazil", "© 2026 SnapLens · Brasil", "© 2026 SnapLens · Brasile", "© 2026 SnapLens · 巴西")
add("foot_cookie", "Nenhum cookie de rastreamento nesta página.", "No tracking cookies on this page.", "Sin cookies de rastreo en esta página.", "Nessun cookie di tracciamento in questa pagina.", "本页无跟踪 Cookie。")
add("lang_label", "Idioma", "Language", "Idioma", "Lingua", "语言")

GH = "https://github.com/ribeiros-click/snaplens/releases/latest/download/SnapLens.dmg"
ICONS = {
 "overlay": '<path d="M4 7V5a1 1 0 0 1 1-1h2M17 4h2a1 1 0 0 1 1 1v2M20 17v2a1 1 0 0 1-1 1h-2M7 20H5a1 1 0 0 1-1-1v-2"/><rect x="8" y="8" width="8" height="8" rx="1.5"/>',
 "ocr": '<path d="M4 7V5a1 1 0 0 1 1-1h2M17 4h2a1 1 0 0 1 1 1v2M20 17v2a1 1 0 0 1-1 1h-2M7 20H5a1 1 0 0 1-1-1v-2"/><path d="M8 9h8M8 12h8M8 15h5"/>',
 "ai": '<path d="M12 3l1.8 4.6L18.5 9l-4.7 1.4L12 15l-1.8-4.6L5.5 9l4.7-1.4zM5 17l.9 2.1L8 20l-2.1.9L5 23l-.9-2.1L2 20l2.1-.9zM19 15l.7 1.6 1.6.7-1.6.7L19 19.5l-.7-1.5-1.6-.7 1.6-.7z"/>',
 "video": '<rect x="3" y="6" width="13" height="12" rx="2"/><path d="M16 10l5-3v10l-5-3z"/>',
 "lib": '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><path d="M8 13h8"/>',
 "link": '<path d="M10 13a5 5 0 0 0 7.1 0l2.8-2.8a5 5 0 0 0-7.1-7.1L11 4.9"/><path d="M14 11a5 5 0 0 0-7.1 0L4.1 13.8a5 5 0 0 0 7.1 7.1L13 19.1"/>',
 "keys": '<rect x="2" y="6" width="20" height="12" rx="2"/><path d="M6 10h.01M10 10h.01M14 10h.01M18 10h.01M8 14h8"/>',
 "lock": '<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
}
CHECK = '<svg viewBox="0 0 24 24"><path d="M20 6 9 17l-5-5"/></svg>'

def page(lang):
    t = S[lang]; here = LANGS[lang]
    alts = "\n".join(f'<link rel="alternate" hreflang="{HTMLLANG[l]}" href="https://lens.ribeiros.click/{p}">' for l, p in LANGS.items()) + '\n<link rel="alternate" hreflang="x-default" href="https://lens.ribeiros.click/">'
    switcher = " ".join(f'<a href="/{p}"{" class=on" if l == lang else ""}>{NAMES[l]}</a>' for l, p in LANGS.items())
    chips = lambda key: "".join(f"<span>{c}</span>" for c in t[key].split("|"))
    lis = lambda key: "".join(f"<li>{c}</li>" for c in t[key].split("|"))
    badges = "".join(f'<div class="badge">{CHECK}{b}</div>' for b in t["badges"].split("|"))
    tracks = "".join(f'<track kind="subtitles" src="/assets/video/snaplens-demo.{VTT[l]}.vtt" srclang="{HTMLLANG[l]}" label="{NAMES[l]}"{" default" if l == lang else ""}>' for l in LANGS)
    tile = lambda cls, ic, title, body, extra="": f'<div class="tile {cls}"><div class="ic"><svg viewBox="0 0 24 24">{ICONS[ic]}</svg></div><h3>{title}</h3><p>{body}</p>{extra}</div>'
    return f'''<!doctype html>
<html lang="{HTMLLANG[lang]}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{t["title"]}</title>
<meta name="description" content="{html.escape(t["desc"], quote=True)}">
<meta name="theme-color" content="#f3eee4">
<meta property="og:title" content="SnapLens — macOS">
<meta property="og:description" content="{html.escape(t["og_desc"], quote=True)}">
<meta property="og:image" content="https://lens.ribeiros.click/assets/img/overlay.png">
<meta name="twitter:card" content="summary_large_image">
{alts}
<link rel="icon" href="/favicon.ico" sizes="any"><link rel="icon" type="image/png" sizes="32x32" href="/favicon-32.png?v=6"><link rel="apple-touch-icon" href="/apple-touch-icon.png?v=6">
<link rel="stylesheet" href="/assets/site.css?v=7">
</head>
<body>
<header class="bar">
  <a class="brand" href="/{here}"><img src="/assets/icon-musgo.png" alt=""> SnapLens</a>
  <nav>
    <a href="#recursos">{t["nav_features"]}</a>
    <a href="#video">{t["nav_video"]}</a>
    <a href="#prints">{t["nav_shots"]}</a>
    <a href="#atalhos">{t["nav_keys"]}</a>
    <a href="#compartilhar">{t["nav_links"]}</a>
    <a href="#faq">{t["nav_faq"]}</a>
    <span class="langs" aria-label="{t["lang_label"]}">{switcher}</span>
    <a class="btn primary small" href="{GH}">{t["nav_download"]}</a>
  </nav>
</header>

<main>
  <section class="hero">
    <div class="wrap">
      <div class="eyebrow"><b>{t["eyebrow_free"]}</b> {t["eyebrow"]}</div>
      <h1>{t["h1"]}</h1>
      <p class="sub">{t["sub"]}</p>
      <div class="cta">
        <a class="btn primary big" href="{GH}" id="dl">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12m0 0 4-4m-4 4-4-4M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2"/></svg>
          {t["cta_download"]}
        </a>
        <a class="btn big" href="#video">▶ {t["cta_video"]}</a>
        <p class="hint">{t["hint"]}</p>
      </div>
      <div class="window">
        <div class="tb"><i></i><i></i><i></i><span>{t["win_overlay"]}</span></div>
        <img src="/assets/img/overlay.png" alt="SnapLens" width="1440" height="900" fetchpriority="high">
      </div>
    </div>
    <div class="hero-fade"></div>
  </section>

  <section class="wrap" style="padding-top:24px">
    <div class="steps">
      <div class="step"><div class="n">1</div><h3>{t["step1_t"]}</h3><p>{t["step1"]}</p></div>
      <div class="step"><div class="n">2</div><h3>{t["step2_t"]}</h3><p>{t["step2"]}</p></div>
      <div class="step"><div class="n">3</div><h3>{t["step3_t"]}</h3><p>{t["step3"]}</p></div>
    </div>
  </section>

  <section id="recursos" class="wrap">
    <div class="sec-head"><h2>{t["feat_h"]}</h2><p>{t["feat_p"]}</p></div>
    <div class="bento">
      {tile("wide", "overlay", t["f1_t"], t["f1"], f'<div class="chips">{chips("f1_chips")}</div>')}
      {tile("wide violet", "ocr", t["f2_t"], t["f2"], f'<div class="chips">{chips("f2_chips")}</div>')}
      {tile("pink", "ai", t["f3_t"], t["f3"])}
      {tile("green", "video", t["f4_t"], t["f4"])}
      {tile("amber", "lib", t["f5_t"], t["f5"])}
      {tile("", "link", t["f6_t"], t["f6"])}
      {tile("violet", "keys", t["f7_t"], t["f7"])}
      {tile("green", "lock", t["f8_t"], t["f8"])}
    </div>
  </section>

  <section id="video" class="wrap">
    <div class="sec-head"><h2>{t["video_h"]}</h2><p>{t["video_p"]}</p></div>
    <div class="window video-frame">
      <div class="tb"><i></i><i></i><i></i><span>SnapLens — demo</span></div>
      <video controls preload="metadata" playsinline poster="/assets/video/snaplens-demo-poster.jpg" width="1920" height="1200">
        <source src="/assets/video/snaplens-demo.mp4" type="video/mp4">
        {tracks}
      </video>
    </div>
    <p class="video-links"><a class="btn" href="/assets/video/snaplens-demo.mp4" download>{t["video_dl"]}</a> <a class="btn" href="/assets/video/snaplens-demo.{VTT[lang]}.vtt">{t["video_transcript"]} (.vtt)</a></p>
  </section>

  <section id="prints" class="wrap">
    <div class="sec-head"><h2>{t["shots_h"]}</h2><p>{t["shots_p"]}</p></div>
    <div class="showcase">
      <div class="show">
        <div class="window"><div class="tb"><i></i><i></i><i></i><span>{t["s1_win"]}</span></div><img src="/assets/img/overlay.png" alt="{t["s1_t"]}" loading="lazy"></div>
        <div><h3>{t["s1_t"]}</h3><p>{t["s1_p"]}</p><ul>{lis("s1_li")}</ul></div>
      </div>
      <div class="show">
        <div class="window"><div class="tb"><i></i><i></i><i></i><span>{t["s2_win"]}</span></div><img src="/assets/img/biblioteca.png" alt="{t["s2_t"]}" loading="lazy"></div>
        <div><h3>{t["s2_t"]}</h3><p>{t["s2_p"]}</p><ul>{lis("s2_li")}</ul></div>
      </div>
      <div class="show">
        <div class="window"><div class="tb"><i></i><i></i><i></i><span>{t["s3_win"]}</span></div><img src="/assets/img/ajustes.png" alt="{t["s3_t"]}" loading="lazy"></div>
        <div><h3>{t["s3_t"]}</h3><p>{t["s3_p"]}</p><ul>{lis("s3_li")}</ul></div>
      </div>
    </div>
  </section>

  <section id="atalhos" class="wrap">
    <div class="sec-head"><h2>{t["keys_h"]}</h2><p>{t["keys_p"]}</p></div>
    <div class="keys">
      <div class="key"><span>{t["k1"]}</span><span class="ks"><kbd>⌥</kbd><kbd>⌘</kbd><kbd>P</kbd></span></div>
      <div class="key"><span>{t["k2"]}</span><span class="ks"><kbd>⌃</kbd><kbd>⌥</kbd><kbd>F</kbd></span></div>
      <div class="key"><span>{t["k3"]}</span><span class="ks"><kbd>⌃</kbd><kbd>⌥</kbd><kbd>T</kbd></span></div>
      <div class="key"><span>{t["k4"]}</span><span class="ks"><kbd>⌃</kbd><kbd>⌥</kbd><kbd>D</kbd></span></div>
      <div class="key"><span>{t["k5"]}</span><span class="ks"><kbd>⌃</kbd><kbd>⌥</kbd><kbd>R</kbd></span></div>
      <div class="key"><span>{t["k6"]}</span><span class="ks"><kbd>⌃</kbd><kbd>⌥</kbd><kbd>H</kbd></span></div>
      <div class="key"><span>{t["k7"]}</span><span class="ks"><kbd>⏎</kbd><kbd>⌘S</kbd><kbd>⌘Z</kbd></span></div>
      <div class="key"><span>{t["k8"]}</span><span class="ks"><kbd>Esc</kbd><kbd>{t["k8_keys"]}</kbd></span></div>
    </div>
  </section>

  <section id="compartilhar" class="wrap">
    <div class="sec-head"><h2>{t["links_h"]}</h2><p>{t["links_p"]}</p></div>
    <div class="split">
      <div class="timeline">
        <div class="tl"><div class="dot">1</div><h4>{t["tl1_t"]}</h4><p>{t["tl1"]}</p></div>
        <div class="tl"><div class="dot">2</div><h4>{t["tl2_t"]}</h4><p>{t["tl2"]}</p></div>
        <div class="tl"><div class="dot">3</div><h4>{t["tl3_t"]}</h4><p>{t["tl3"]}</p></div>
        <div class="tl"><div class="dot">4</div><h4>{t["tl4_t"]}</h4><p>{t["tl4"]}</p></div>
      </div>
      <div class="panel">
        <h3>{t["panel_t"]}</h3><p>{t["panel_p"]}</p>
        <div class="row"><a class="btn primary" href="/token?lang={lang}">{t["panel_btn"]}</a><a class="btn" href="/politicas/retencao.html">{t["panel_btn2"]}</a></div>
        <div class="badges">{badges}</div>
      </div>
    </div>
  </section>

  <section id="faq" class="wrap">
    <div class="sec-head"><h2>{t["faq_h"]}</h2></div>
    <div class="faq">
      <details><summary>{t["q1"]}</summary><p>{t["a1"]}</p></details>
      <details><summary>{t["q2"]}</summary><p>{t["a2"]}</p></details>
      <details><summary>{t["q3"]}</summary><p>{t["a3"]}</p></details>
      <details><summary>{t["q4"]}</summary><p>{t["a4"]}</p></details>
      <details><summary>{t["q5"]}</summary><p>{t["a5"]}</p></details>
      <details><summary>{t["q6"]}</summary><p>{t["a6"]}</p></details>
    </div>
  </section>

  <section id="baixar" class="wrap">
    <div class="cta-band">
      <img src="/assets/icon-musgo.png" alt="">
      <h2>{t["cta_h"]}</h2><p>{t["cta_p"]}</p>
      <a class="btn primary big" href="{GH}">{t["cta_btn"]}</a>
      <div class="meta">{t["cta_meta"]} · <a href="https://github.com/ribeiros-click/snaplens/releases/latest" rel="noopener">{t["cta_notes"]}</a></div>
    </div>
  </section>
</main>

<footer class="foot">
  <div class="cols">
    <div><a class="brand" href="/{here}" style="margin-bottom:10px"><img src="/assets/icon-musgo.png" alt=""> SnapLens</a><p style="margin:0;max-width:300px">{t["foot_tag"]}</p><p class="langs" style="margin-top:12px">{switcher}</p></div>
    <div><h5>{t["foot_product"]}</h5><ul><li><a href="#recursos">{t["nav_features"]}</a></li><li><a href="#video">{t["nav_video"]}</a></li><li><a href="{GH}">{t["nav_download"]}</a></li><li><a href="/token?lang={lang}">{t["foot_token"]}</a></li></ul></div>
    <div><h5>{t["foot_policies"]}{t["foot_policies_note"]}</h5><ul><li><a href="/politicas/privacidade.html">{t["foot_privacy"]}</a></li><li><a href="/politicas/termos.html">{t["foot_terms"]}</a></li><li><a href="/politicas/uso-aceitavel.html">{t["foot_aup"]}</a></li><li><a href="/politicas/seguranca.html">{t["foot_sec"]}</a></li><li><a href="/politicas/retencao.html">{t["foot_ret"]}</a></li></ul></div>
    <div><h5>{t["foot_contact"]}</h5><ul><li><a href="/contato?lang={lang}">{t["foot_form"]}</a></li><li><a href="mailto:contato@ribeiros.click">contato@ribeiros.click</a></li><li><a href="/contato?assunto=denuncia&amp;lang={lang}">{t["foot_report"]}</a></li></ul></div>
  </div>
  <div class="copy"><span>{t["foot_copy"]}</span><span>{t["foot_cookie"]}</span></div>
</footer>
</body>
</html>
'''

for lang, sub in LANGS.items():
    d = os.path.join(ROOT, sub) if sub else ROOT
    os.makedirs(d, exist_ok=True)
    open(os.path.join(d, "index.html"), "w").write(page(lang))
print("páginas geradas:", ", ".join(f"/{p or ''}" for p in LANGS.values()))
