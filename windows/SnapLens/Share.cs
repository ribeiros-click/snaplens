using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using static SnapLens.Loc;

namespace SnapLens;

/// Compartilhamento por link público (servidor PHP em `server/`).
/// Validade escolhida na hora de compartilhar (mesmas opções do app macOS).
public enum ShareChoice { Once, D1, D5, Custom, Never }

public static class ShareConfig
{
    public const string DefaultServer = "https://lens.ribeiros.click";
    public static readonly ShareChoice[] AllChoices = { ShareChoice.Once, ShareChoice.D1, ShareChoice.D5, ShareChoice.Custom, ShareChoice.Never };

    public static string Title(this ShareChoice c) => c switch
    {
        ShareChoice.Once => L("Ver uma vez"),
        ShareChoice.D1 => L("Durante 1 dia"),
        ShareChoice.D5 => L("Durante 5 dias"),
        ShareChoice.Custom => L("Durante…"),
        _ => L("Nunca expirar"),
    };

    /// (segundos de validade, visualização única). "Ver uma vez" tem 30 dias como vida máxima.
    public static (int Seconds, bool Once) Resolve(this ShareChoice c, int customDays) => c switch
    {
        ShareChoice.Once => (30 * 86400, true),
        ShareChoice.D1 => (86400, false),
        ShareChoice.D5 => (5 * 86400, false),
        ShareChoice.Custom => (Math.Clamp(customDays, 1, 365) * 86400, false),
        _ => (0, false),
    };

    public static ShareChoice LastChoice
    {
        get => Enum.TryParse<ShareChoice>(Settings.Data.ShareChoice, out var c) ? c : ShareChoice.D1;
        set { Settings.Data.ShareChoice = value.ToString(); Settings.Save(); }
    }
    public static int CustomDays
    {
        get => Math.Clamp(Settings.Data.ShareCustomDays <= 0 ? 7 : Settings.Data.ShareCustomDays, 1, 365);
        set { Settings.Data.ShareCustomDays = Math.Clamp(value, 1, 365); Settings.Save(); }
    }

    public static string Server
    {
        get
        {
            var s = Settings.Data.ShareServer;
            return (string.IsNullOrWhiteSpace(s) ? DefaultServer : s).Trim().TrimEnd('/');
        }
    }
}

public sealed class ShareResult
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("url")] public string Url { get; set; } = "";
    [JsonPropertyName("expires_at")] public double? ExpiresAt { get; set; }
    [JsonPropertyName("delete_token")] public string DeleteToken { get; set; } = "";
    [JsonPropertyName("once")] public bool? Once { get; set; }
}

public sealed class AppError(string message) : Exception(message);

public static class ShareClient
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(60) };

    public static async Task<ShareResult> Upload(byte[] png, int expirySeconds, bool once)
    {
        using var form = new MultipartFormDataContent("SnapLens-" + Guid.NewGuid());
        form.Add(new StringContent(expirySeconds.ToString()), "expires");
        form.Add(new StringContent(once ? "1" : "0"), "once");
        var file = new ByteArrayContent(png);
        file.Headers.ContentType = new MediaTypeHeaderValue("image/png");
        form.Add(file, "file", "screenshot.png");
        var json = await Send("/api/upload", form);
        return JsonSerializer.Deserialize<ShareResult>(json) ?? throw new AppError(L("Compartilhar: %@", "JSON"));
    }

    public static async Task Revoke(string id, string token)
    {
        var body = new StringContent(JsonSerializer.Serialize(new { id, token }), Encoding.UTF8, "application/json");
        await Send("/api/delete", body);
    }

    private static async Task<string> Send(string path, HttpContent content)
    {
        using var resp = await Http.PostAsync(ShareConfig.Server + path, content);
        var text = await resp.Content.ReadAsStringAsync();
        if (!resp.IsSuccessStatusCode)
        {
            string msg = "HTTP " + (int)resp.StatusCode;
            try
            {
                using var doc = JsonDocument.Parse(text);
                if (doc.RootElement.TryGetProperty("error", out var e) && e.ValueKind == JsonValueKind.String) msg = e.GetString()!;
            }
            catch { }
            throw new AppError(L("Compartilhar: %@", msg));
        }
        return text;
    }

    public static string ExpiryText(DateTime? date)
    {
        if (date == null) return L("sem expirar");
        var secs = (date.Value - DateTime.Now).TotalSeconds;
        if (secs <= 0) return L("expirado");
        if (secs < 3600) return L("expira em %@ min", Math.Max(1, (int)(secs / 60)));
        if (secs < 86400 * 2) return L("expira em %@ h", (int)Math.Round(secs / 3600));
        return L("expira em %@ dias", (int)Math.Round(secs / 86400));
    }
}
