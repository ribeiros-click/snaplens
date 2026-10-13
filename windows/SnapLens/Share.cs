using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using static SnapLens.Loc;

namespace SnapLens;

/// Compartilhamento por link público (servidor PHP em `server/`).
public enum ShareExpiry { H1 = 3600, D1 = 86400, D7 = 604800, D30 = 2592000, Never = 0 }

public static class ShareConfig
{
    public const string DefaultServer = "https://lens.ribeiros.click";
    public static readonly ShareExpiry[] AllExpiries = { ShareExpiry.H1, ShareExpiry.D1, ShareExpiry.D7, ShareExpiry.D30, ShareExpiry.Never };

    public static string Title(this ShareExpiry e) => e switch
    {
        ShareExpiry.H1 => L("1 hora"),
        ShareExpiry.D1 => L("1 dia"),
        ShareExpiry.D7 => L("7 dias"),
        ShareExpiry.D30 => L("30 dias"),
        _ => L("Sem expirar"),
    };

    public static string Server
    {
        get
        {
            var s = Settings.Data.ShareServer;
            return (string.IsNullOrWhiteSpace(s) ? DefaultServer : s).Trim().TrimEnd('/');
        }
    }
    public static bool Once => Settings.Data.ShareOnce;
    public static ShareExpiry Expiry =>
        Enum.IsDefined(typeof(ShareExpiry), Settings.Data.ShareExpiry) ? (ShareExpiry)Settings.Data.ShareExpiry : ShareExpiry.D7;
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

    public static async Task<ShareResult> Upload(byte[] png, ShareExpiry expiry, bool once)
    {
        using var form = new MultipartFormDataContent("SnapLens-" + Guid.NewGuid());
        form.Add(new StringContent(((int)expiry).ToString()), "expires");
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
