using System.Net;
using System.Net.Http.Headers;
using System.Net.Sockets;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using static SnapLens.Loc;

namespace SnapLens;

/// Destino do compartilhamento: servidor SnapLens (padrão), OneDrive ou Google Drive (mesmo comportamento do macOS).
public enum ShareDestination { Server, OneDrive, GDrive }
public enum CloudDrive { OneDrive, GDrive }

public static class ShareDestinations
{
    public static string Title(this ShareDestination d) => d switch
    {
        ShareDestination.OneDrive => "OneDrive",
        ShareDestination.GDrive => "Google Drive",
        _ => L("Servidor SnapLens"),
    };

    public static CloudDrive? Drive(this ShareDestination d) => d switch
    {
        ShareDestination.OneDrive => CloudDrive.OneDrive,
        ShareDestination.GDrive => CloudDrive.GDrive,
        _ => null,
    };

    /// Destinos utilizáveis agora (o servidor sempre; os Drives só se conectados).
    public static ShareDestination[] Available =>
        Enum.GetValues<ShareDestination>().Where(d => d.Drive() is not CloudDrive c || c.IsConnected()).ToArray();

    public static ShareDestination Current
    {
        get
        {
            var d = Enum.TryParse<ShareDestination>(Settings.Data.ShareDestination, out var v) ? v : ShareDestination.Server;
            return Available.Contains(d) ? d : ShareDestination.Server;
        }
        set { Settings.Data.ShareDestination = value.ToString(); Settings.Save(); }
    }
}

public sealed record CloudUpload(string Id, string Url);

public static class Cloud
{
    public const string FolderName = "SnapLens";
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(120) };
    private static readonly Dictionary<CloudDrive, (string Token, DateTime Until)> Tokens = new();

    // MARK: Configuração (IDs gravados no build a partir de variáveis de ambiente, ou Ajustes → avançado)

    public static string Name(this CloudDrive d) => d == CloudDrive.OneDrive ? "OneDrive" : "Google Drive";
    public static string Key(this CloudDrive d) => d == CloudDrive.OneDrive ? "onedrive" : "gdrive";

    public static string ClientId(this CloudDrive d) => Config(
        d == CloudDrive.OneDrive ? Settings.Data.OneDriveClientId : Settings.Data.GoogleClientId,
        d == CloudDrive.OneDrive ? "OneDriveClientId" : "GoogleClientId");

    /// O Google exige o "client secret" mesmo em apps de desktop (não é tratado como segredo; o PKCE protege o fluxo).
    public static string ClientSecret(this CloudDrive d) =>
        d == CloudDrive.GDrive ? Config(Settings.Data.GoogleClientSecret, "GoogleClientSecret") : "";

    public static bool IsConfigured(this CloudDrive d) =>
        d.ClientId().Length > 0 && (d == CloudDrive.OneDrive || d.ClientSecret().Length > 0);

    private static string Config(string custom, string metadataKey)
    {
        if (!string.IsNullOrWhiteSpace(custom)) return custom.Trim();
        return typeof(Cloud).Assembly.GetCustomAttributes<AssemblyMetadataAttribute>()
            .FirstOrDefault(a => a.Key == metadataKey)?.Value?.Trim() ?? "";
    }

    private static string AuthorizeUrl(CloudDrive d) => d == CloudDrive.OneDrive
        ? "https://login.microsoftonline.com/common/oauth2/v2.0/authorize" : "https://accounts.google.com/o/oauth2/v2/auth";
    private static string TokenUrl(CloudDrive d) => d == CloudDrive.OneDrive
        ? "https://login.microsoftonline.com/common/oauth2/v2.0/token" : "https://oauth2.googleapis.com/token";
    /// Escopos mínimos: OneDrive lê/grava os arquivos do usuário; Google só vê os arquivos criados pelo próprio SnapLens.
    private static string Scope(CloudDrive d) => d == CloudDrive.OneDrive
        ? "Files.ReadWrite offline_access" : "https://www.googleapis.com/auth/drive.file";

    // MARK: Conta

    private static string RefreshKey(CloudDrive d) => $"cloud.{d.Key()}.refresh";
    private static string? RefreshToken(CloudDrive d) => CredentialStore.Get(RefreshKey(d)) is { Length: > 0 } t ? t : null;
    public static bool IsConnected(this CloudDrive d) => RefreshToken(d) != null;
    public static string AccountName(this CloudDrive d) => Settings.Data.CloudAccounts.GetValueOrDefault(d.Key(), "");

    public static void Disconnect(this CloudDrive d)
    {
        CredentialStore.Set(RefreshKey(d), "");
        Settings.Data.CloudAccounts.Remove(d.Key());
        Settings.Save();
        lock (Tokens) Tokens.Remove(d);
    }

    /// Abre o login no navegador, recebe o código em http://localhost:porta/ e guarda o refresh token.
    public static async Task<string> Connect(CloudDrive d)
    {
        if (!d.IsConfigured()) throw new AppError(L("%@ não está configurado neste build.", d.Name()));
        using var receiver = new LoopbackReceiver();
        var redirect = $"http://localhost:{receiver.Port}";
        var verifier = RandomUrlSafe(48);
        var challenge = Base64Url(SHA256.HashData(Encoding.ASCII.GetBytes(verifier)));
        var state = RandomUrlSafe(16);

        var q = new Dictionary<string, string>
        {
            ["client_id"] = d.ClientId(),
            ["response_type"] = "code",
            ["redirect_uri"] = redirect,
            ["scope"] = Scope(d),
            ["state"] = state,
            ["code_challenge"] = challenge,
            ["code_challenge_method"] = "S256",
            ["prompt"] = d == CloudDrive.GDrive ? "consent" : "select_account",
        };
        if (d == CloudDrive.GDrive) q["access_type"] = "offline";
        TrayApp.Open(AuthorizeUrl(d) + "?" + string.Join("&", q.Select(kv => kv.Key + "=" + Uri.EscapeDataString(kv.Value))));

        var reply = await receiver.WaitForCallback(TimeSpan.FromMinutes(5));
        if (reply.TryGetValue("error", out var err)) throw new AppError(reply.GetValueOrDefault("error_description", err));
        if (reply.GetValueOrDefault("state") != state || !reply.TryGetValue("code", out var code) || code.Length == 0)
            throw new AppError(L("Resposta de login inválida."));

        var form = new Dictionary<string, string>
        {
            ["client_id"] = d.ClientId(), ["grant_type"] = "authorization_code", ["code"] = code,
            ["redirect_uri"] = redirect, ["code_verifier"] = verifier, ["scope"] = Scope(d),
        };
        if (d.ClientSecret().Length > 0) form["client_secret"] = d.ClientSecret();
        var tok = await TokenRequest(d, form);
        var refresh = tok["refresh_token"]?.GetValue<string>() ?? throw new AppError(L("O provedor não devolveu um token de renovação."));
        CredentialStore.Set(RefreshKey(d), refresh);
        if (tok["access_token"]?.GetValue<string>() is string access) PutToken(d, access, tok);

        string name = "";
        try { name = await FetchAccountName(d); } catch (Exception e) { Trace.Log("cloud: nome da conta: " + e.Message); }
        Settings.Data.CloudAccounts[d.Key()] = name;
        Settings.Save();
        Trace.Log($"cloud: {d.Key()} conectado");
        return name;
    }

    // MARK: Upload / exclusão

    public static Task<CloudUpload> Upload(CloudDrive d, byte[] png, string fileName, DateTime? expires) =>
        d == CloudDrive.OneDrive ? OneDriveUpload(png, fileName, expires) : GoogleUpload(png, fileName);

    /// Apaga o arquivo do Drive (o link deixa de funcionar). Arquivo já inexistente conta como sucesso.
    public static async Task Delete(CloudDrive d, string id)
    {
        var url = d == CloudDrive.OneDrive
            ? $"https://graph.microsoft.com/v1.0/me/drive/items/{Uri.EscapeDataString(id)}"
            : $"https://www.googleapis.com/drive/v3/files/{Uri.EscapeDataString(id)}";
        await Api(d, HttpMethod.Delete, url, allow404: true);
    }

    private static async Task<CloudUpload> OneDriveUpload(byte[] png, string fileName, DateTime? expires)
    {
        var path = Uri.EscapeDataString(FolderName) + "/" + Uri.EscapeDataString(fileName);
        var item = await Api(CloudDrive.OneDrive, HttpMethod.Put,
            $"https://graph.microsoft.com/v1.0/me/drive/root:/{path}:/content?@microsoft.graph.conflictBehavior=rename",
            () => Bytes(png, "image/png"));
        var id = item["id"]?.GetValue<string>() ?? throw new AppError(L("Resposta inesperada do %@.", "OneDrive"));

        // Link anônimo com validade; contas pessoais não aceitam validade e algumas empresas bloqueiam links anônimos.
        var attempts = new List<object>();
        if (expires is DateTime e) attempts.Add(new { type = "view", scope = "anonymous", expirationDateTime = e.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") });
        attempts.Add(new { type = "view", scope = "anonymous" });
        attempts.Add(new { type = "view", scope = "organization" });
        Exception? last = null;
        foreach (var body in attempts)
        {
            try
            {
                var r = await Api(CloudDrive.OneDrive, HttpMethod.Post, $"https://graph.microsoft.com/v1.0/me/drive/items/{id}/createLink", () => Json(body));
                if (r["link"]?["webUrl"]?.GetValue<string>() is string link) return new CloudUpload(id, link);
            }
            catch (Exception ex) { last = ex; }
        }
        throw last ?? new AppError(L("Resposta inesperada do %@.", "OneDrive"));
    }

    private static async Task<string> GoogleFolder()
    {
        var cached = Settings.Data.GoogleFolderId;
        if (cached.Length > 0)
        {
            try
            {
                var f = await Api(CloudDrive.GDrive, HttpMethod.Get, $"https://www.googleapis.com/drive/v3/files/{cached}?fields=id,trashed");
                if (f["trashed"]?.GetValue<bool>() != true) return cached;
            }
            catch { }
        }
        // Com o escopo drive.file, a busca só enxerga pastas criadas pelo próprio SnapLens.
        var query = Uri.EscapeDataString($"name='{FolderName}' and mimeType='application/vnd.google-apps.folder' and trashed=false");
        var found = await Api(CloudDrive.GDrive, HttpMethod.Get, $"https://www.googleapis.com/drive/v3/files?q={query}&fields=files(id)&spaces=drive");
        var id = found["files"]?.AsArray().FirstOrDefault()?["id"]?.GetValue<string>();
        if (id == null)
        {
            var created = await Api(CloudDrive.GDrive, HttpMethod.Post, "https://www.googleapis.com/drive/v3/files?fields=id",
                () => Json(new { name = FolderName, mimeType = "application/vnd.google-apps.folder" }));
            id = created["id"]?.GetValue<string>() ?? throw new AppError(L("Resposta inesperada do %@.", "Google Drive"));
        }
        Settings.Data.GoogleFolderId = id;
        Settings.Save();
        return id;
    }

    private static async Task<CloudUpload> GoogleUpload(byte[] png, string fileName)
    {
        var folder = await GoogleFolder();
        HttpContent Body()
        {
            var multi = new MultipartContent("related", "SnapLens-" + Guid.NewGuid());
            multi.Add(Json(new { name = fileName, parents = new[] { folder } }));
            multi.Add(Bytes(png, "image/png"));
            return multi;
        }
        var file = await Api(CloudDrive.GDrive, HttpMethod.Post,
            "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,webViewLink", Body);
        var id = file["id"]?.GetValue<string>() ?? throw new AppError(L("Resposta inesperada do %@.", "Google Drive"));
        await Api(CloudDrive.GDrive, HttpMethod.Post, $"https://www.googleapis.com/drive/v3/files/{id}/permissions",
            () => Json(new { role = "reader", type = "anyone" }));
        return new CloudUpload(id, file["webViewLink"]?.GetValue<string>() ?? $"https://drive.google.com/file/d/{id}/view");
    }

    private static async Task<string> FetchAccountName(CloudDrive d)
    {
        if (d == CloudDrive.OneDrive)
        {
            var r = await Api(d, HttpMethod.Get, "https://graph.microsoft.com/v1.0/me/drive?$select=owner");
            var u = r["owner"]?["user"];
            return u?["email"]?.GetValue<string>() ?? u?["displayName"]?.GetValue<string>() ?? "";
        }
        var g = await Api(d, HttpMethod.Get, "https://www.googleapis.com/drive/v3/about?fields=user(emailAddress,displayName)");
        return g["user"]?["emailAddress"]?.GetValue<string>() ?? g["user"]?["displayName"]?.GetValue<string>() ?? "";
    }

    // MARK: HTTP

    private static HttpContent Json(object o) => new StringContent(JsonSerializer.Serialize(o), Encoding.UTF8, "application/json");

    private static HttpContent Bytes(byte[] data, string type)
    {
        var c = new ByteArrayContent(data);
        c.Headers.ContentType = new MediaTypeHeaderValue(type);
        return c;
    }

    /// `body` é uma fábrica: um HttpContent não pode ser reenviado após um 401 (token renovado).
    private static async Task<JsonObject> Api(CloudDrive d, HttpMethod method, string url, Func<HttpContent>? body = null, bool allow404 = false)
    {
        for (int attempt = 0; ; attempt++)
        {
            var token = await AccessToken(d);
            using var req = new HttpRequestMessage(method, url) { Content = body?.Invoke() };
            req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            using var resp = await Http.SendAsync(req);
            var text = await resp.Content.ReadAsStringAsync();
            if (resp.StatusCode == HttpStatusCode.Unauthorized && attempt == 0) { lock (Tokens) Tokens.Remove(d); continue; }
            if (allow404 && resp.StatusCode == HttpStatusCode.NotFound) return new JsonObject();
            if (!resp.IsSuccessStatusCode) throw new AppError($"{d.Name()}: {ErrorMessage(text, (int)resp.StatusCode)}");
            return Parse(text);
        }
    }

    private static async Task<string> AccessToken(CloudDrive d)
    {
        lock (Tokens) if (Tokens.TryGetValue(d, out var t) && t.Until > DateTime.UtcNow) return t.Token;
        var refresh = RefreshToken(d) ?? throw new AppError(L("Conecte o %@ em Ajustes.", d.Name()));
        var form = new Dictionary<string, string> { ["client_id"] = d.ClientId(), ["grant_type"] = "refresh_token", ["refresh_token"] = refresh };
        if (d == CloudDrive.OneDrive) form["scope"] = Scope(d);
        if (d.ClientSecret().Length > 0) form["client_secret"] = d.ClientSecret();
        JsonObject tok;
        try { tok = await TokenRequest(d, form); }
        catch (AppError) { throw new AppError(L("A conexão com o %@ expirou. Conecte de novo em Ajustes.", d.Name())); }
        var access = tok["access_token"]?.GetValue<string>() ?? throw new AppError(L("Resposta de login inválida."));
        if (tok["refresh_token"]?.GetValue<string>() is { Length: > 0 } newRefresh) CredentialStore.Set(RefreshKey(d), newRefresh);
        PutToken(d, access, tok);
        return access;
    }

    private static void PutToken(CloudDrive d, string access, JsonObject tok)
    {
        double secs = 3000;
        try { secs = tok["expires_in"]?.GetValue<double>() ?? 3000; } catch { }
        lock (Tokens) Tokens[d] = (access, DateTime.UtcNow.AddSeconds(Math.Max(60, secs - 120)));
    }

    private static async Task<JsonObject> TokenRequest(CloudDrive d, Dictionary<string, string> form)
    {
        using var resp = await Http.PostAsync(TokenUrl(d), new FormUrlEncodedContent(form));
        var text = await resp.Content.ReadAsStringAsync();
        if (!resp.IsSuccessStatusCode) throw new AppError($"{d.Name()}: {ErrorMessage(text, (int)resp.StatusCode)}");
        return Parse(text);
    }

    private static JsonObject Parse(string text)
    {
        try { return JsonNode.Parse(text) as JsonObject ?? new JsonObject(); }
        catch { return new JsonObject(); }
    }

    private static string ErrorMessage(string text, int status)
    {
        var o = Parse(text);
        if (o["error"] is JsonObject e && e["message"]?.GetValue<string>() is string m) return m;
        if (o["error_description"]?.GetValue<string>() is string desc) return desc;
        if (o["error"] is JsonValue v && v.TryGetValue<string>(out var s)) return s;
        return "HTTP " + status;
    }

    private static string RandomUrlSafe(int bytes) => Base64Url(RandomNumberGenerator.GetBytes(bytes));
    private static string Base64Url(byte[] b) => Convert.ToBase64String(b).Replace('+', '-').Replace('/', '_').TrimEnd('=');

    // MARK: Receptor do redirecionamento OAuth

    /// Servidor HTTP mínimo só no loopback (127.0.0.1 e ::1, mesma porta): não abre porta na rede nem aciona o firewall.
    private sealed class LoopbackReceiver : IDisposable
    {
        private readonly TcpListener v4;
        private readonly TcpListener? v6;
        private readonly CancellationTokenSource cts = new();
        public int Port { get; }

        public LoopbackReceiver()
        {
            v4 = new TcpListener(IPAddress.Loopback, 0);
            v4.Start();
            Port = ((IPEndPoint)v4.LocalEndpoint).Port;
            try { v6 = new TcpListener(IPAddress.IPv6Loopback, Port); v6.Start(); }
            catch { v6 = null; } // sem IPv6: o navegador tenta 127.0.0.1
        }

        public async Task<Dictionary<string, string>> WaitForCallback(TimeSpan timeout)
        {
            cts.CancelAfter(timeout);
            var tasks = new List<Task<Dictionary<string, string>>> { Loop(v4) };
            if (v6 != null) tasks.Add(Loop(v6));
            try { return await await Task.WhenAny(tasks); }
            catch (OperationCanceledException) { throw new AppError(L("Tempo de login esgotado.")); }
            finally { cts.Cancel(); }
        }

        private async Task<Dictionary<string, string>> Loop(TcpListener listener)
        {
            while (true)
            {
                using var client = await listener.AcceptTcpClientAsync(cts.Token);
                using var stream = client.GetStream();
                var buf = new byte[65536];
                int n = await stream.ReadAsync(buf, cts.Token);
                var line = Encoding.UTF8.GetString(buf, 0, n).Split("\r\n")[0];
                var target = line.Split(' ').ElementAtOrDefault(1) ?? "";
                var qi = target.IndexOf('?');
                bool isCallback = qi >= 0 && target[..qi] == "/";
                var html = isCallback
                    ? $"<!doctype html><meta charset=utf-8><title>SnapLens</title><body style='font:16px Segoe UI,sans-serif;text-align:center;padding-top:80px'><h2>SnapLens ✓</h2><p>{WebUtility.HtmlEncode(L("Pronto! Pode fechar esta aba e voltar ao SnapLens."))}</p>"
                    : "Not found";
                var body = Encoding.UTF8.GetBytes(html);
                var head = Encoding.ASCII.GetBytes($"HTTP/1.1 {(isCallback ? "200 OK" : "404 Not Found")}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {body.Length}\r\nConnection: close\r\n\r\n");
                await stream.WriteAsync(head, cts.Token);
                await stream.WriteAsync(body, cts.Token);
                if (!isCallback) continue;
                return target[(qi + 1)..].Split('&', StringSplitOptions.RemoveEmptyEntries)
                    .Select(p => p.Split('=', 2))
                    .GroupBy(p => WebUtility.UrlDecode(p[0]))
                    .ToDictionary(g => g.Key, g => WebUtility.UrlDecode(g.First().ElementAtOrDefault(1) ?? ""));
            }
        }

        public void Dispose()
        {
            cts.Cancel();
            v4.Stop();
            v6?.Stop();
            cts.Dispose();
        }
    }
}
