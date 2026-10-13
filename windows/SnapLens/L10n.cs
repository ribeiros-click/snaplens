using System.Globalization;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;

namespace SnapLens;

/// Localização: as chaves são o texto em português (idioma-base). As traduções vêm dos mesmos
/// Localizable.strings do app macOS (embutidos no .exe) e de WinStrings (textos só do Windows).
/// `L("texto")` devolve a tradução; `L("… %@ …", arg)` formata.
public static class Loc
{
    public static string L(string key) => L10n.Get(key);

    public static string L(string key, params object[] args)
    {
        var s = L10n.Get(key);
        var sb = new StringBuilder();
        int i = 0, pos = 0;
        while (true)
        {
            int at = s.IndexOf("%@", pos, StringComparison.Ordinal);
            if (at < 0) { sb.Append(s, pos, s.Length - pos); break; }
            sb.Append(s, pos, at - pos);
            sb.Append(i < args.Length ? Convert.ToString(args[i], L10n.Culture) : "");
            i++;
            pos = at + 2;
        }
        return sb.ToString();
    }
}

public static class L10n
{
    public static event Action? Changed;

    /// Idiomas suportados pelo app (código do .lproj → nome nativo).
    public static readonly (string Code, string Name)[] Languages =
    {
        ("pt-BR", "Português (Brasil)"), ("en", "English"), ("es", "Español"), ("it", "Italiano"), ("zh-Hans", "中文（简体）"),
    };

    /// "system" = seguir o idioma do Windows.
    public static string Selection
    {
        get => Settings.Data.Language;
        set
        {
            Settings.Data.Language = value;
            Settings.Save();
            cached = null;
            Changed?.Invoke();
        }
    }

    /// Código efetivo em uso.
    public static string Code
    {
        get
        {
            if (Selection != "system" && Languages.Any(l => l.Code == Selection)) return Selection;
            var c = CultureInfo.CurrentUICulture;
            return c.TwoLetterISOLanguageName switch
            {
                "pt" => "pt-BR",
                "es" => "es",
                "it" => "it",
                "zh" => "zh-Hans",
                "en" => "en",
                _ => "en",
            };
        }
    }

    /// Cultura para datas/números coerente com o idioma do app.
    public static CultureInfo Culture => CultureInfo.GetCultureInfo(Code == "zh-Hans" ? "zh-Hans" : Code);

    private static Dictionary<string, string>? cached;
    private static Dictionary<string, Dictionary<string, string>>? all;

    public static string Get(string key)
    {
        cached ??= Load(Code);
        return cached.TryGetValue(key, out var v) ? v : key;
    }

    private static Dictionary<string, string> Load(string code)
    {
        all ??= LoadAll();
        var d = new Dictionary<string, string>(StringComparer.Ordinal);
        if (all.TryGetValue(code, out var mac)) foreach (var kv in mac) d[kv.Key] = kv.Value;
        foreach (var kv in WinStrings.For(code)) d[kv.Key] = kv.Value;
        return d;
    }

    private static readonly Regex Line = new(@"^\s*""((?:[^""\\]|\\.)*)""\s*=\s*""((?:[^""\\]|\\.)*)""\s*;", RegexOptions.Compiled);

    private static Dictionary<string, Dictionary<string, string>> LoadAll()
    {
        var result = new Dictionary<string, Dictionary<string, string>>();
        var asm = Assembly.GetExecutingAssembly();
        foreach (var name in asm.GetManifestResourceNames())
        {
            var m = Regex.Match(name, @"^l10n\.([A-Za-z-]+)\.lproj");
            if (!m.Success) continue;
            using var stream = asm.GetManifestResourceStream(name)!;
            using var reader = new StreamReader(stream, Encoding.UTF8);
            var dict = new Dictionary<string, string>(StringComparer.Ordinal);
            string? line;
            while ((line = reader.ReadLine()) != null)
            {
                var lm = Line.Match(line);
                if (lm.Success) dict[Unescape(lm.Groups[1].Value)] = Unescape(lm.Groups[2].Value);
            }
            result[m.Groups[1].Value] = dict;
        }
        return result;
    }

    private static string Unescape(string s)
    {
        if (!s.Contains('\\')) return s;
        var sb = new StringBuilder(s.Length);
        for (int i = 0; i < s.Length; i++)
        {
            if (s[i] == '\\' && i + 1 < s.Length)
            {
                i++;
                sb.Append(s[i] switch { 'n' => '\n', 't' => '\t', _ => s[i] });
            }
            else sb.Append(s[i]);
        }
        return sb.ToString();
    }
}
