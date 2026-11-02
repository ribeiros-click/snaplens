using System.Net.Http.Headers;
using System.Text.Json.Nodes;
using static SnapLens.Loc;

namespace SnapLens;

/// Aviso de versão nova: consulta a última release pública no GitHub ao abrir e uma vez por dia.
/// Não baixa nada sozinho; mostra o item "SnapLens X disponível" no menu e um aviso uma vez por versão.
public static class UpdateChecker
{
    private const string Api = "https://api.github.com/repos/ribeiros-click/snaplens/releases/latest";
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(20) };
    private static readonly System.Windows.Forms.Timer Daily = new() { Interval = 24 * 3600 * 1000 };

    /// Versão nova encontrada (null = está atualizado ou ainda não verificou).
    public static (string Version, string Url)? Available { get; private set; }
    public static event Action? Changed;

    public static string CurrentVersion
    {
        get
        {
            var v = typeof(UpdateChecker).Assembly.GetName().Version;
            if (v == null) return "0";
            // 1.10.0.0 → "1.10"; 1.10.1.0 → "1.10.1"
            return v.Build > 0 ? $"{v.Major}.{v.Minor}.{v.Build}" : $"{v.Major}.{v.Minor}";
        }
    }

    public static void Start()
    {
        Daily.Tick += async (_, _) => await Check();
        Daily.Start();
        // Primeira verificação 10 s depois de abrir (timer da interface: roda na thread da UI).
        var first = new System.Windows.Forms.Timer { Interval = 10_000 };
        first.Tick += async (_, _) => { first.Stop(); first.Dispose(); await Check(); };
        first.Start();
    }

    /// `manual`: chamado pelo menu; avisa também quando já está na versão mais recente ou dá erro.
    public static async Task Check(bool manual = false)
    {
        if (!manual && !Settings.Data.CheckUpdates) return;
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, Api);
            req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
            req.Headers.UserAgent.ParseAdd($"SnapLens/{CurrentVersion}");
            using var resp = await Http.SendAsync(req);
            resp.EnsureSuccessStatusCode();
            var obj = JsonNode.Parse(await resp.Content.ReadAsStringAsync());
            var tag = obj?["tag_name"]?.GetValue<string>() ?? throw new InvalidDataException("tag_name");
            var page = obj?["html_url"]?.GetValue<string>() ?? "https://github.com/ribeiros-click/snaplens/releases/latest";
            var latest = tag.TrimStart('v');
            if (IsNewer(latest, CurrentVersion))
            {
                Available = (latest, page);
                Trace.Log($"update: {latest} disponível (atual {CurrentVersion})");
                if (manual || Settings.Data.UpdateNotified != latest)
                {
                    Settings.Data.UpdateNotified = latest;
                    Settings.Save();
                    Toast.Show(L("SnapLens %@ disponível — veja no menu", latest), Icons.Download);
                }
            }
            else
            {
                Available = null;
                if (manual) Toast.Show(L("Você está na versão mais recente (%@)", CurrentVersion), Icons.Check);
            }
            Changed?.Invoke();
        }
        catch (Exception e)
        {
            Trace.Log("update: falha ao verificar: " + e.Message);
            if (manual) Toast.Show(L("Não foi possível verificar atualizações"), Icons.Warning);
        }
    }

    /// Compara versões "1.10" > "1.9" número a número (não como texto).
    public static bool IsNewer(string a, string b)
    {
        static int[] Parts(string s) => s.Split('.').Select(p => int.TryParse(new string(p.TakeWhile(char.IsDigit).ToArray()), out var n) ? n : 0).ToArray();
        var pa = Parts(a);
        var pb = Parts(b);
        for (int i = 0; i < Math.Max(pa.Length, pb.Length); i++)
        {
            int x = i < pa.Length ? pa[i] : 0, y = i < pb.Length ? pb[i] : 0;
            if (x != y) return x > y;
        }
        return false;
    }
}
