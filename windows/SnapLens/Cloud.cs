using System.Globalization;
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

    /// Destinos utilizáveis agora (o servidor sempre; os Drives só se exibidos e conectados).
    public static ShareDestination[] Available =>
        Enum.GetValues<ShareDestination>().Where(d => d.Drive() is not CloudDrive c || (Cloud.Visible.Contains(c) && c.IsConnected())).ToArray();

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

public sealed class DriveFolderInfo
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
}

public static class Cloud
{
    public const string FolderName = "SnapLens";
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromMinutes(15) };

    /// Drives exibidos no app. O OneDrive está pronto no código, mas oculto por enquanto:
    /// para reativá-lo, basta voltar a incluir `CloudDrive.OneDrive` aqui.
    public static readonly CloudDrive[] Visible = { CloudDrive.GDrive };
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

    /// Chave de API do Google, usada só pelo seletor de pastas (Google Picker).
    public static string ApiKey(this CloudDrive d) =>
        d == CloudDrive.GDrive ? Config(Settings.Data.GoogleApiKey, "GoogleApiKey") : "";

    /// Número do projeto do Google (o prefixo do ID do cliente), exigido pelo Google Picker.
    private static string ProjectNumber(this CloudDrive d) => new(d.ClientId().TakeWhile(char.IsDigit).ToArray());

    /// No Windows, só o Google tem seletor de pastas (o OneDrive está oculto).
    public static bool CanPickFolder(this CloudDrive d) => d == CloudDrive.GDrive && d.IsConnected() && d.ApiKey().Length > 0;

    // MARK: Pasta de destino

    /// Pasta escolhida pelo usuário; null = pasta "SnapLens" criada pelo app na raiz.
    public static DriveFolderInfo? Folder(this CloudDrive d) =>
        Settings.Data.CloudFolders.TryGetValue(d.Key(), out var f) && f.Id.Length > 0 ? f : null;

    public static void SetFolder(this CloudDrive d, DriveFolderInfo? f)
    {
        if (f == null) Settings.Data.CloudFolders.Remove(d.Key());
        else Settings.Data.CloudFolders[d.Key()] = f;
        Settings.Save();
    }

    public static string FolderDisplay(this CloudDrive d) => d.Folder()?.Name ?? FolderName;

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
        Settings.Data.CloudFolders.Remove(d.Key());
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
        if (CredentialStore.Get(RefreshKey(d)) != refresh)
            throw new AppError(L("Não foi possível guardar o acesso ao %@ no Gerenciador de Credenciais.", d.Name()));
        if (tok["access_token"]?.GetValue<string>() is string access) PutToken(d, access, tok);

        string name = "";
        try { name = await FetchAccountName(d); } catch (Exception e) { Trace.Log("cloud: nome da conta: " + e.Message); }
        Settings.Data.CloudAccounts[d.Key()] = name;
        Settings.Save();
        Trace.Log($"cloud: {d.Key()} conectado");
        return name;
    }

    // MARK: Upload / exclusão

    /// Envia para o Drive e cria um link de leitura público (compartilhar).
    public static async Task<CloudUpload> Upload(CloudDrive d, byte[] png, string fileName, DateTime? expires)
    {
        var file = await UploadFile(d, () => new MemoryStream(png, writable: false), png.Length, fileName, "image/png");
        return d == CloudDrive.OneDrive ? await OneDriveLink(file.Id, expires) : await GoogleLink(file.Id, file.WebLink);
    }

    /// Envia um arquivo para a pasta escolhida (ou "SnapLens"), sem link público. Usado também pelo backup.
    /// `open` é chamado a cada tentativa (um conteúdo HTTP não pode ser reenviado após renovar o token).
    public static Task<(string Id, string? WebLink)> UploadFile(CloudDrive d, Func<Stream> open, long length, string fileName, string mime) =>
        d == CloudDrive.OneDrive ? OneDrivePut(open, fileName, mime) : GooglePut(open, length, fileName, mime);

    /// Apaga o arquivo do Drive (o link deixa de funcionar). Arquivo já inexistente conta como sucesso.
    public static async Task Delete(CloudDrive d, string id)
    {
        var url = d == CloudDrive.OneDrive
            ? $"https://graph.microsoft.com/v1.0/me/drive/items/{Uri.EscapeDataString(id)}"
            : $"https://www.googleapis.com/drive/v3/files/{Uri.EscapeDataString(id)}";
        await Api(d, HttpMethod.Delete, url, allow404: true);
    }

    private static async Task DeleteQuietly(CloudDrive d, string id)
    {
        try { await Delete(d, id); } catch (Exception e) { Trace.Log($"cloud: não apagou {id}: {e.Message}"); }
    }

    private static HttpContent StreamBody(Func<Stream> open, string mime)
    {
        var c = new StreamContent(open());
        c.Headers.ContentType = MediaTypeHeaderValue.Parse(mime);
        return c;
    }

    // OneDrive (oculto por enquanto): envio simples, suficiente para imagens e textos.
    private static async Task<(string, string?)> OneDrivePut(Func<Stream> open, string fileName, string mime)
    {
        var url = CloudDrive.OneDrive.Folder() is DriveFolderInfo f
            ? $"https://graph.microsoft.com/v1.0/me/drive/items/{Uri.EscapeDataString(f.Id)}:/{Uri.EscapeDataString(fileName)}:/content?@microsoft.graph.conflictBehavior=rename"
            : $"https://graph.microsoft.com/v1.0/me/drive/root:/{Uri.EscapeDataString(FolderName)}/{Uri.EscapeDataString(fileName)}:/content?@microsoft.graph.conflictBehavior=rename";
        var item = await Api(CloudDrive.OneDrive, HttpMethod.Put, url, () => StreamBody(open, mime));
        return (item["id"]?.GetValue<string>() ?? throw new AppError(L("Resposta inesperada do %@.", "OneDrive")), null);
    }

    private static async Task<CloudUpload> OneDriveLink(string id, DateTime? expires)
    {
        // Link anônimo com validade; contas pessoais não aceitam validade e algumas empresas bloqueiam links anônimos.
        var attempts = new List<object>();
        if (expires is DateTime e) attempts.Add(new { type = "view", scope = "anonymous", expirationDateTime = e.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture) });
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
        await DeleteQuietly(CloudDrive.OneDrive, id); // sem link, não deixa o arquivo órfão no Drive
        throw last ?? new AppError(L("Resposta inesperada do %@.", "OneDrive"));
    }

    /// Pasta de destino: a escolhida no seletor do Google ou a "SnapLens" criada pelo app.
    private static async Task<string> GoogleTarget() =>
        CloudDrive.GDrive.Folder() is DriveFolderInfo f ? f.Id : await GoogleFolder();

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

    private static async Task<(string, string?)> GooglePut(Func<Stream> open, long length, string fileName, string mime,
        string? parent = null, Dictionary<string, string>? appProperties = null)
    {
        var folder = parent ?? await GoogleTarget();
        object meta = appProperties == null
            ? new { name = fileName, parents = new[] { folder } }
            : new { name = fileName, parents = new[] { folder }, appProperties };
        JsonObject file;
        if (length <= 5 * 1024 * 1024)
        {
            // Upload "multipart": metadados + conteúdo numa só requisição (limite de 5 MB).
            HttpContent Body()
            {
                var multi = new MultipartContent("related", "SnapLens-" + Guid.NewGuid());
                multi.Add(Json(meta));
                multi.Add(StreamBody(open, mime));
                return multi;
            }
            file = await Api(CloudDrive.GDrive, HttpMethod.Post,
                "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,webViewLink", Body);
        }
        else
        {
            // Upload "resumable" (vídeos): abre a sessão e envia o conteúdo num único PUT.
            var (_, location) = await Send(CloudDrive.GDrive, HttpMethod.Post,
                "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id,webViewLink", () =>
                {
                    var c = Json(meta);
                    c.Headers.TryAddWithoutValidation("X-Upload-Content-Type", mime);
                    c.Headers.TryAddWithoutValidation("X-Upload-Content-Length", length.ToString(CultureInfo.InvariantCulture));
                    return c;
                });
            if (location == null) throw new AppError(L("Resposta inesperada do %@.", "Google Drive"));
            (file, _) = await Send(CloudDrive.GDrive, HttpMethod.Put, location.ToString(), () => StreamBody(open, mime));
        }
        var id = file["id"]?.GetValue<string>() ?? throw new AppError(L("Resposta inesperada do %@.", "Google Drive"));
        return (id, file["webViewLink"]?.GetValue<string>());
    }

    private static async Task<CloudUpload> GoogleLink(string id, string? webLink)
    {
        try
        {
            await Api(CloudDrive.GDrive, HttpMethod.Post, $"https://www.googleapis.com/drive/v3/files/{id}/permissions",
                () => Json(new { role = "reader", type = "anyone" }));
        }
        catch
        {
            await DeleteQuietly(CloudDrive.GDrive, id); // ex.: domínio do Workspace bloqueia link público
            throw;
        }
        return new CloudUpload(id, webLink ?? $"https://drive.google.com/file/d/{id}/view");
    }

    // MARK: Sincronização entre dispositivos (Google Drive)
    // Pasta "SnapLens Sync" criada pelo app na raiz do Drive. Cada item é um arquivo com os metadados em
    // appProperties (privados do app); como todos os computadores usam o mesmo app OAuth, o escopo
    // drive.file deixa cada um ver os arquivos criados pelos outros.

    public const string SyncFolderName = "SnapLens Sync";
    public sealed record SyncFile(string Id, Dictionary<string, string> Props, DateTime Created);

    private static async Task<string> SyncFolder()
    {
        var cached = Settings.Data.SyncFolderId;
        if (cached.Length > 0)
        {
            try
            {
                var f = await Api(CloudDrive.GDrive, HttpMethod.Get, $"https://www.googleapis.com/drive/v3/files/{cached}?fields=id,trashed");
                if (f["trashed"]?.GetValue<bool>() != true) return cached;
            }
            catch { }
        }
        var query = Uri.EscapeDataString($"name='{SyncFolderName}' and mimeType='application/vnd.google-apps.folder' and trashed=false");
        var found = await Api(CloudDrive.GDrive, HttpMethod.Get, $"https://www.googleapis.com/drive/v3/files?q={query}&fields=files(id)&spaces=drive&orderBy=createdTime");
        var id = found["files"]?.AsArray().FirstOrDefault()?["id"]?.GetValue<string>();
        if (id == null)
        {
            var created = await Api(CloudDrive.GDrive, HttpMethod.Post, "https://www.googleapis.com/drive/v3/files?fields=id",
                () => Json(new { name = SyncFolderName, mimeType = "application/vnd.google-apps.folder" }));
            id = created["id"]?.GetValue<string>() ?? throw new AppError(L("Resposta inesperada do %@.", "Google Drive"));
        }
        Settings.Data.SyncFolderId = id;
        Settings.Save();
        return id;
    }

    /// Envia um item para a pasta de sincronização, com os metadados em appProperties.
    public static async Task<string> SyncUpload(Func<Stream> open, long length, string fileName, string mime, Dictionary<string, string> props)
    {
        var folder = await SyncFolder();
        return (await GooglePut(open, length, fileName, mime, folder, props)).Item1;
    }

    /// Arquivos da pasta de sincronização. `after`: criados depois; `before` + `device`: antigos deste aparelho.
    public static async Task<List<SyncFile>> SyncList(DateTime? after = null, DateTime? before = null, string? device = null)
    {
        var folder = await SyncFolder();
        static string Iso(DateTime d) => d.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture);
        var q = $"'{folder}' in parents and trashed=false";
        if (after is DateTime a) q += $" and createdTime > '{Iso(a)}'";
        if (before is DateTime b) q += $" and createdTime < '{Iso(b)}'";
        if (device != null) q += $" and appProperties has {{ key='device' and value='{device}' }}";
        var result = new List<SyncFile>();
        string? page = null;
        do
        {
            var url = $"https://www.googleapis.com/drive/v3/files?q={Uri.EscapeDataString(q)}&pageSize=1000&fields={Uri.EscapeDataString("nextPageToken,files(id,createdTime,appProperties)")}"
                + (page != null ? "&pageToken=" + Uri.EscapeDataString(page) : "");
            var r = await Api(CloudDrive.GDrive, HttpMethod.Get, url);
            foreach (var f in r["files"]?.AsArray() ?? new JsonArray())
            {
                if (f?["id"]?.GetValue<string>() is not string id) continue;
                var props = new Dictionary<string, string>();
                if (f["appProperties"] is JsonObject ap)
                    foreach (var (k, v) in ap) if (v is JsonValue jv && jv.TryGetValue<string>(out var s)) props[k] = s;
                var created = DateTime.TryParse(f["createdTime"]?.GetValue<string>(), CultureInfo.InvariantCulture,
                    DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out var c) ? c : DateTime.UtcNow;
                result.Add(new SyncFile(id, props, created));
            }
            page = r["nextPageToken"]?.GetValue<string>();
        } while (page != null);
        return result;
    }

    /// Conteúdo de um arquivo do Drive.
    public static async Task<byte[]> Download(CloudDrive d, string id)
    {
        for (int attempt = 0; ; attempt++)
        {
            var token = await AccessToken(d);
            using var req = new HttpRequestMessage(HttpMethod.Get, $"https://www.googleapis.com/drive/v3/files/{Uri.EscapeDataString(id)}?alt=media");
            req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            using var resp = await Http.SendAsync(req);
            if (resp.StatusCode == HttpStatusCode.Unauthorized && attempt == 0) { lock (Tokens) Tokens.Remove(d); continue; }
            if (!resp.IsSuccessStatusCode) throw new AppError($"{d.Name()}: HTTP {(int)resp.StatusCode}");
            return await resp.Content.ReadAsByteArrayAsync();
        }
    }

    /// Abre o seletor de pastas do Google (Google Picker) no navegador. Escolher uma pasta lá dá ao SnapLens
    /// acesso só àquela pasta, sem pedir permissão para ver o Drive inteiro. Retorna null se cancelado.
    public static async Task<DriveFolderInfo?> PickGoogleFolder()
    {
        var d = CloudDrive.GDrive;
        if (d.ApiKey().Length == 0) throw new AppError(L("Falta a chave de API do Google (veja “avançado”)."));
        var token = await AccessToken(d);
        var cfg = JsonSerializer.Serialize(new Dictionary<string, string>
        {
            ["token"] = token, ["key"] = d.ApiKey(), ["app"] = d.ProjectNumber(),
            ["hl"] = L10n.Code == "zh-Hans" ? "zh-CN" : L10n.Code,
            ["title"] = L("Escolha a pasta do SnapLens"),
            ["ok"] = L("Pronto! Pode fechar esta aba e voltar ao SnapLens."),
            ["cancel"] = L("Cancelado. Pode fechar esta aba."),
        }).Replace("</", "<\\/");
        var page = PickerPage(cfg);
        using var receiver = new LoopbackReceiver((path, _) => path switch
        {
            "/" => (page, false),
            "/picked" => ("ok", true),
            _ => null,
        });
        TrayApp.Open($"http://localhost:{receiver.Port}/");
        var reply = await receiver.WaitForCallback(TimeSpan.FromMinutes(10));
        if (!reply.TryGetValue("id", out var id) || id.Length == 0) return null;
        var name = reply.GetValueOrDefault("name", "");
        return new DriveFolderInfo { Id = id, Name = name.Length > 0 ? name : "Google Drive" };
    }

    private static string PickerPage(string configJson) => """
        <!doctype html><meta charset=utf-8><title>SnapLens</title>
        <body style="font:16px 'Segoe UI',sans-serif;text-align:center;padding-top:60px;color:#333">
        <h2>SnapLens</h2><p id=msg>…</p>
        <script>
        const CFG = %CFG%;
        function done(q, text) {
          fetch('/picked?' + q).finally(() => { document.getElementById('msg').textContent = text; });
        }
        function onPick(data) {
          if (data.action === google.picker.Action.PICKED) {
            const d = data.docs[0];
            done('id=' + encodeURIComponent(d.id) + '&name=' + encodeURIComponent(d.name), CFG.ok);
          } else if (data.action === google.picker.Action.CANCEL) {
            done('cancel=1', CFG.cancel);
          }
        }
        function start() {
          const view = new google.picker.DocsView(google.picker.ViewId.FOLDERS)
            .setIncludeFolders(true).setSelectFolderEnabled(true)
            .setMimeTypes('application/vnd.google-apps.folder');
          new google.picker.PickerBuilder().addView(view)
            .setOAuthToken(CFG.token).setDeveloperKey(CFG.key).setAppId(CFG.app)
            .setLocale(CFG.hl).setTitle(CFG.title).setCallback(onPick)
            .build().setVisible(true);
        }
        </script>
        <script src="https://apis.google.com/js/api.js" onload="gapi.load('picker', start)"></script>
        """.Replace("%CFG%", configJson);

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
    private static async Task<JsonObject> Api(CloudDrive d, HttpMethod method, string url, Func<HttpContent>? body = null, bool allow404 = false) =>
        (await Send(d, method, url, body, allow404)).Json;

    private static async Task<(JsonObject Json, Uri? Location)> Send(CloudDrive d, HttpMethod method, string url, Func<HttpContent>? body = null, bool allow404 = false)
    {
        for (int attempt = 0; ; attempt++)
        {
            var token = await AccessToken(d);
            using var req = new HttpRequestMessage(method, url) { Content = body?.Invoke() };
            req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            using var resp = await Http.SendAsync(req);
            var text = await resp.Content.ReadAsStringAsync();
            if (resp.StatusCode == HttpStatusCode.Unauthorized && attempt == 0) { lock (Tokens) Tokens.Remove(d); continue; }
            if (allow404 && resp.StatusCode == HttpStatusCode.NotFound) return (new JsonObject(), null);
            if (!resp.IsSuccessStatusCode) throw new AppError($"{d.Name()}: {ErrorMessage(text, (int)resp.StatusCode)}");
            return (Parse(text), resp.Headers.Location);
        }
    }

    private static async Task<string> AccessToken(CloudDrive d)
    {
        lock (Tokens) if (Tokens.TryGetValue(d, out var t) && t.Until > DateTime.UtcNow) return t.Token;
        var refresh = RefreshToken(d) ?? throw new AppError(L("Conecte o %@ em Ajustes.", d.Name()));
        var form = new Dictionary<string, string> { ["client_id"] = d.ClientId(), ["grant_type"] = "refresh_token", ["refresh_token"] = refresh };
        if (d == CloudDrive.OneDrive) form["scope"] = Scope(d);
        if (d.ClientSecret().Length > 0) form["client_secret"] = d.ClientSecret();
        // Só um 400/401 do servidor de login significa acesso revogado/expirado; rede e 5xx propagam como estão.
        var tok = await TokenRequest(d, form, expiredMessage: L("A conexão com o %@ expirou. Conecte de novo em Ajustes.", d.Name()));
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

    private static async Task<JsonObject> TokenRequest(CloudDrive d, Dictionary<string, string> form, string? expiredMessage = null)
    {
        using var resp = await Http.PostAsync(TokenUrl(d), new FormUrlEncodedContent(form));
        var text = await resp.Content.ReadAsStringAsync();
        if (expiredMessage != null && resp.StatusCode is HttpStatusCode.BadRequest or HttpStatusCode.Unauthorized)
            throw new AppError(expiredMessage);
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

        /// (caminho, query) → (html, encerra a espera?) ou null = 404.
        private readonly Func<string, Dictionary<string, string>, (string Html, bool Done)?> route;

        /// Padrão: qualquer `/?…` é o retorno do login OAuth.
        private static (string Html, bool Done)? OAuthRoute(string path, Dictionary<string, string> query) =>
            path == "/" && query.Count > 0
                ? ($"<!doctype html><meta charset=utf-8><title>SnapLens</title><body style='font:16px Segoe UI,sans-serif;text-align:center;padding-top:80px'><h2>SnapLens ✓</h2><p>{WebUtility.HtmlEncode(L("Pronto! Pode fechar esta aba e voltar ao SnapLens."))}</p>", true)
                : null;

        public LoopbackReceiver(Func<string, Dictionary<string, string>, (string Html, bool Done)?>? route = null)
        {
            this.route = route ?? ((p, q) => OAuthRoute(p, q));
            v4 = new TcpListener(IPAddress.Loopback, 0);
            v4.Start();
            Port = ((IPEndPoint)v4.LocalEndpoint).Port;
            try { v6 = new TcpListener(IPAddress.IPv6Loopback, Port); v6.Start(); }
            catch { v6 = null; } // sem IPv6: o navegador tenta 127.0.0.1
        }

        private readonly TaskCompletionSource<Dictionary<string, string>> result = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public async Task<Dictionary<string, string>> WaitForCallback(TimeSpan timeout)
        {
            _ = AcceptLoop(v4);
            if (v6 != null) _ = AcceptLoop(v6);
            try { return await result.Task.WaitAsync(timeout, cts.Token); }
            catch (TimeoutException) { throw new AppError(L("Tempo de login esgotado.")); }
            finally { cts.Cancel(); }
        }

        /// Cada conexão é atendida em paralelo: navegadores abrem conexões "preconnect" ociosas
        /// que não podem segurar a requisição real do redirecionamento.
        private async Task AcceptLoop(TcpListener listener)
        {
            while (!cts.IsCancellationRequested)
            {
                TcpClient client;
                try { client = await listener.AcceptTcpClientAsync(cts.Token); }
                catch { return; }
                _ = Task.Run(() => Handle(client));
            }
        }

        private async Task Handle(TcpClient client)
        {
            using var conn = client;
            try
            {
                using var readTimeout = CancellationTokenSource.CreateLinkedTokenSource(cts.Token);
                readTimeout.CancelAfter(TimeSpan.FromSeconds(10));
                var stream = client.GetStream();
                var buf = new byte[65536];
                int n = await stream.ReadAsync(buf, readTimeout.Token);
                if (n <= 0) return;
                var line = Encoding.UTF8.GetString(buf, 0, n).Split("\r\n")[0];
                var target = line.Split(' ').ElementAtOrDefault(1) ?? "";
                var qi = target.IndexOf('?');
                var path = qi >= 0 ? target[..qi] : target;
                var query = qi < 0 ? new Dictionary<string, string>() : target[(qi + 1)..].Split('&', StringSplitOptions.RemoveEmptyEntries)
                    .Select(p => p.Split('=', 2))
                    .GroupBy(p => WebUtility.UrlDecode(p[0]))
                    .ToDictionary(g => g.Key, g => WebUtility.UrlDecode(g.First().ElementAtOrDefault(1) ?? ""));
                var response = route(path, query);
                var body = Encoding.UTF8.GetBytes(response?.Html ?? "Not found");
                var head = Encoding.ASCII.GetBytes($"HTTP/1.1 {(response == null ? "404 Not Found" : "200 OK")}\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: {body.Length}\r\nConnection: close\r\n\r\n");
                await stream.WriteAsync(head, readTimeout.Token);
                await stream.WriteAsync(body, readTimeout.Token);
                if (response?.Done == true) result.TrySetResult(query);
            }
            catch (Exception e) { Trace.Log("oauth loopback: " + e.Message); } // conexão ociosa ou resetada: ignora
        }

        public void Dispose()
        {
            cts.Cancel();
            v4.Stop();
            v6?.Stop();
        }
    }
}
