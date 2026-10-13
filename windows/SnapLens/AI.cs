using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using static SnapLens.Loc;

namespace SnapLens;

public enum Provider { anthropic, openai, deepseek, custom }

public static class Providers
{
    public static readonly Provider[] All = Enum.GetValues<Provider>();

    public static string Name(this Provider p) => p switch
    {
        Provider.anthropic => "Anthropic (Claude)",
        Provider.openai => "OpenAI",
        Provider.deepseek => "DeepSeek",
        _ => L("Personalizado (compatível com OpenAI)"),
    };

    public static string ShortName(this Provider p) => p switch
    {
        Provider.anthropic => "Claude",
        Provider.openai => "OpenAI",
        Provider.deepseek => "DeepSeek",
        _ => L("Personalizado"),
    };

    public static string DefaultModel(this Provider p) => p switch
    {
        Provider.anthropic => "claude-sonnet-5-5",
        Provider.openai => "gpt-4o-mini",
        Provider.deepseek => "deepseek-chat",
        _ => "",
    };

    public static string DefaultBase(this Provider p) => p switch
    {
        Provider.anthropic => "https://api.anthropic.com",
        Provider.openai => "https://api.openai.com/v1",
        Provider.deepseek => "https://api.deepseek.com",
        _ => "http://localhost:11434/v1",
    };

    public static string Hint(this Provider p) => p switch
    {
        Provider.anthropic => L("Suporta imagens."),
        Provider.openai => L("Suporta imagens (use um modelo com visão, ex.: gpt-4o)."),
        Provider.deepseek => L("Atenção: os modelos da API oficial do DeepSeek podem não aceitar imagens. Se der erro, use outro provedor ou um modelo com visão."),
        _ => L("Ollama (http://localhost:11434/v1), OpenRouter, Groq, Gemini (…/v1beta/openai) etc. A chave é opcional."),
    };

    public static bool NeedsKey(this Provider p) => p != Provider.custom;

    public static string ApiKey(this Provider p) => CredentialStore.Get("key." + p) ?? "";
    public static void SetApiKey(this Provider p, string key) => CredentialStore.Set("key." + p, key.Trim());

    public static string Model(this Provider p)
    {
        var m = Settings.Data.Models.GetValueOrDefault(p.ToString(), "");
        return string.IsNullOrWhiteSpace(m) ? p.DefaultModel() : m.Trim();
    }

    public static string BaseURL(this Provider p)
    {
        var b = Settings.Data.Bases.GetValueOrDefault(p.ToString(), "");
        return (string.IsNullOrWhiteSpace(b) ? p.DefaultBase() : b).Trim().TrimEnd('/');
    }

    public static bool IsConfigured(this Provider p) => (!p.NeedsKey() || p.ApiKey().Length > 0) && p.Model().Length > 0;

    /// Provedor ativo; null = nativo (Windows OCR).
    public static Provider? Active =>
        Enum.TryParse<Provider>(Settings.Data.ActiveProvider, out var p) && p.IsConfigured() ? p : null;
}

public static class AIClient
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(90) };

    public static string Prompt =>
        L("Descreva esta imagem de forma clara e objetiva, em português do Brasil. Se houver texto visível, transcreva-o fielmente em uma seção final chamada \"Texto na imagem\".");

    public static async Task<string> Describe(string imagePath, Provider provider)
    {
        var png = ScaledPng(imagePath, 1568) ?? throw new AppError(L("Não consegui ler a imagem."));
        var b64 = Convert.ToBase64String(png);
        JsonObject body;
        if (provider == Provider.anthropic)
        {
            body = new JsonObject
            {
                ["model"] = provider.Model(), ["max_tokens"] = 1500,
                ["messages"] = new JsonArray(new JsonObject
                {
                    ["role"] = "user",
                    ["content"] = new JsonArray(
                        new JsonObject { ["type"] = "image", ["source"] = new JsonObject { ["type"] = "base64", ["media_type"] = "image/png", ["data"] = b64 } },
                        new JsonObject { ["type"] = "text", ["text"] = Prompt }),
                }),
            };
        }
        else
        {
            body = new JsonObject
            {
                ["model"] = provider.Model(), ["max_tokens"] = 1500,
                ["messages"] = new JsonArray(new JsonObject
                {
                    ["role"] = "user",
                    ["content"] = new JsonArray(
                        new JsonObject { ["type"] = "text", ["text"] = Prompt },
                        new JsonObject { ["type"] = "image_url", ["image_url"] = new JsonObject { ["url"] = "data:image/png;base64," + b64 } }),
                }),
            };
        }
        return await Send(provider, body);
    }

    public static async Task<string> Translate(string text, string language, Provider provider)
    {
        var instruction = L("Traduza o texto a seguir para %@. Responda apenas com a tradução, sem comentários.", language) + "\n\n" + text;
        var body = new JsonObject
        {
            ["model"] = provider.Model(), ["max_tokens"] = 4000,
            ["messages"] = new JsonArray(new JsonObject { ["role"] = "user", ["content"] = instruction }),
        };
        return await Send(provider, body);
    }

    private static async Task<string> Send(Provider provider, JsonObject body)
    {
        var url = provider == Provider.anthropic ? provider.BaseURL() + "/v1/messages" : provider.BaseURL() + "/chat/completions";
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)) throw new AppError("URL inválida: " + url);
        using var req = new HttpRequestMessage(HttpMethod.Post, uri)
        {
            Content = new StringContent(body.ToJsonString(), Encoding.UTF8, "application/json"),
        };
        var key = provider.ApiKey();
        if (provider == Provider.anthropic)
        {
            req.Headers.Add("x-api-key", key);
            req.Headers.Add("anthropic-version", "2023-06-01");
        }
        else if (key.Length > 0) req.Headers.Add("Authorization", "Bearer " + key);

        using var resp = await Http.SendAsync(req);
        var text = await resp.Content.ReadAsStringAsync();
        JsonNode? json = null;
        try { json = JsonNode.Parse(text); } catch { }
        if (!resp.IsSuccessStatusCode)
        {
            var msg = json?["error"]?["message"]?.GetValue<string>() ?? (text.Length > 200 ? text[..200] : text);
            throw new AppError(L("%@ respondeu %@: %@", provider.ShortName(), (int)resp.StatusCode, msg));
        }
        string? result;
        if (provider == Provider.anthropic)
            result = string.Join("\n", (json?["content"] as JsonArray ?? new JsonArray())
                .Select(c => c?["text"]?.GetValue<string>()).Where(t => t != null));
        else
            result = json?["choices"]?[0]?["message"]?["content"]?.GetValue<string>();
        result = result?.Trim();
        if (string.IsNullOrEmpty(result)) throw new AppError(L("Resposta vazia do provedor."));
        return result;
    }

    private static byte[]? ScaledPng(string path, int maxSize)
    {
        using var thumb = Images.LoadThumbnail(path, maxSize);
        return thumb == null ? null : Images.ToPng(thumb);
    }
}
