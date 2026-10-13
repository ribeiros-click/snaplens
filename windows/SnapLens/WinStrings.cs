namespace SnapLens;

/// Textos que só existem na versão Windows (os demais vêm dos Localizable.strings do macOS).
/// Chave = texto em pt-BR. Colunas: en, es, it, zh-Hans.
public static class WinStrings
{
    private static readonly (string pt, string en, string es, string it, string zh)[] T =
    {
        ("Mostrar log no Explorer", "Show log in Explorer", "Mostrar registro en el Explorador", "Mostra log in Esplora file", "在资源管理器中显示日志"),
        ("Mostrar no Explorer", "Show in Explorer", "Mostrar en el Explorador", "Mostra in Esplora file", "在资源管理器中显示"),
        ("Iniciar com o Windows", "Launch at Windows startup", "Iniciar con Windows", "Avvia con Windows", "开机时启动"),
        ("Desfazer (Ctrl+Z)", "Undo (Ctrl+Z)", "Deshacer (Ctrl+Z)", "Annulla (Ctrl+Z)", "撤销 (Ctrl+Z)"),
        ("Salvar (Ctrl+S)", "Save (Ctrl+S)", "Guardar (Ctrl+S)", "Salva (Ctrl+S)", "保存 (Ctrl+S)"),
        ("Copiar (Ctrl+C / Enter)", "Copy (Ctrl+C / Enter)", "Copiar (Ctrl+C / Intro)", "Copia (Ctrl+C / Invio)", "复制 (Ctrl+C / Enter)"),
        ("Clique no atalho e pressione a nova combinação (precisa incluir Ctrl, Alt ou Win).",
         "Click the shortcut and press the new combination (must include Ctrl, Alt or Win).",
         "Haz clic en el atajo y pulsa la nueva combinación (debe incluir Ctrl, Alt o Win).",
         "Fai clic sulla scorciatoia e premi la nuova combinazione (deve includere Ctrl, Alt o Win).",
         "点击快捷键并按下新的组合键（须包含 Ctrl、Alt 或 Win）。"),
        ("Nativo (Windows OCR, offline)", "Native (Windows OCR, offline)", "Nativo (OCR de Windows, sin conexión)", "Nativo (OCR di Windows, offline)", "本机（Windows OCR，离线）"),
        ("“Descrever com IA” usa o provedor ativo. Sem provedor (ou sem chave configurada), usa o modo nativo. O OCR de texto sempre roda localmente com o Windows OCR.",
         "“Describe with AI” uses the active provider. Without a provider (or without a key), native mode is used. Text OCR always runs locally with Windows OCR.",
         "“Describir con IA” usa el proveedor activo. Sin proveedor (o sin clave), se usa el modo nativo. El OCR de texto siempre se ejecuta localmente con el OCR de Windows.",
         "“Descrivi con IA” usa il provider attivo. Senza provider (o senza chiave) usa la modalità nativa. L'OCR del testo gira sempre in locale con l'OCR di Windows.",
         "“用 AI 描述”使用当前提供商。没有提供商（或未配置密钥）时使用本机模式。文字 OCR 始终通过 Windows OCR 在本地运行。"),
        ("Não foi possível capturar a tela", "Couldn't capture the screen", "No se pudo capturar la pantalla", "Impossibile catturare lo schermo", "无法截取屏幕"),
        ("SnapLens está na bandeja do sistema, perto do relógio. Use %@ para capturar uma seleção.",
         "SnapLens lives in the system tray, next to the clock. Press %@ to capture a region.",
         "SnapLens está en la bandeja del sistema, junto al reloj. Pulsa %@ para capturar una región.",
         "SnapLens è nell'area di notifica, vicino all'orologio. Premi %@ per catturare una selezione.",
         "SnapLens 位于任务栏通知区域（时钟旁）。按 %@ 截取选区。"),
        ("Nenhum idioma de OCR instalado no Windows. Adicione um idioma em Configurações › Hora e idioma.",
         "No OCR language is installed in Windows. Add a language in Settings › Time & language.",
         "No hay ningún idioma de OCR instalado en Windows. Añade un idioma en Configuración › Hora e idioma.",
         "Nessuna lingua OCR installata in Windows. Aggiungi una lingua in Impostazioni › Data/ora e lingua.",
         "Windows 未安装 OCR 语言。请在“设置 › 时间和语言”中添加语言。"),
        ("Imagem de %@ × %@ pixels.", "%@ × %@ pixel image.", "Imagen de %@ × %@ píxeles.", "Immagine di %@ × %@ pixel.", "%@ × %@ 像素的图片。"),
        ("Imagem PNG", "PNG image", "Imagen PNG", "Immagine PNG", "PNG 图片"),
        ("Traduzindo com %@…", "Translating with %@…", "Traduciendo con %@…", "Traduzione con %@…", "正在用 %@ 翻译…"),
        ("Apagar todos os itens de “%@” da biblioteca?", "Delete all “%@” items from the library?", "¿Borrar todos los elementos de “%@” de la biblioteca?", "Eliminare tutti gli elementi di “%@” dalla libreria?", "从资料库中删除所有“%@”项目？"),
    };

    public static IEnumerable<KeyValuePair<string, string>> For(string code)
    {
        foreach (var t in T)
        {
            var v = code switch { "en" => t.en, "es" => t.es, "it" => t.it, "zh-Hans" => t.zh, _ => t.pt };
            yield return new(t.pt, v);
        }
    }
}
