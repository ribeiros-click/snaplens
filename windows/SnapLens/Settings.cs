using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using Microsoft.Win32;

namespace SnapLens;

/// Preferências do app (equivalente ao UserDefaults do macOS): %APPDATA%\SnapLens\settings.json.
public sealed class AppSettings
{
    public string Language { get; set; } = "system";
    public string ActiveProvider { get; set; } = "";
    public bool RecSystem { get; set; } = true;
    public bool RecMic { get; set; }
    public string ShareServer { get; set; } = "";
    public string ShareChoice { get; set; } = "D1";   // última validade escolhida ao compartilhar
    public int ShareCustomDays { get; set; } = 7;
    public Dictionary<string, string> Models { get; set; } = new();
    public Dictionary<string, string> Bases { get; set; } = new();
    public Dictionary<string, Shortcut> Shortcuts { get; set; } = new();
    public bool WelcomeShown { get; set; }
}

public static class Settings
{
    public static string Dir { get; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "SnapLens");
    private static string FilePath => Path.Combine(Dir, "settings.json");
    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true };

    public static AppSettings Data { get; private set; } = Load();

    private static AppSettings Load()
    {
        try
        {
            Directory.CreateDirectory(Dir);
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath), Json) ?? new AppSettings();
        }
        catch (Exception e) { Trace.Log("settings: falha ao ler: " + e.Message); }
        return new AppSettings();
    }

    public static void Save()
    {
        try
        {
            Directory.CreateDirectory(Dir);
            var tmp = FilePath + ".tmp";
            File.WriteAllText(tmp, JsonSerializer.Serialize(Data, Json));
            File.Move(tmp, FilePath, true);
        }
        catch (Exception e) { Trace.Log("settings: falha ao salvar: " + e.Message); }
    }

    // MARK: Iniciar com o Windows (HKCU\...\Run)

    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    public static bool LaunchAtLogin
    {
        get
        {
            using var k = Registry.CurrentUser.OpenSubKey(RunKey);
            return k?.GetValue("SnapLens") is string;
        }
        set
        {
            using var k = Registry.CurrentUser.CreateSubKey(RunKey);
            if (value) k.SetValue("SnapLens", $"\"{Environment.ProcessPath}\" --background");
            else k.DeleteValue("SnapLens", false);
        }
    }
}

/// Chaves de API no Gerenciador de Credenciais do Windows (equivalente ao Keychain).
public static class CredentialStore
{
    private const string Prefix = "SnapLens:";

    public static string? Get(string account)
    {
        if (!CredRead(Prefix + account, 1 /* GENERIC */, 0, out var ptr)) return null;
        try
        {
            var c = Marshal.PtrToStructure<CREDENTIAL>(ptr);
            if (c.CredentialBlobSize == 0 || c.CredentialBlob == IntPtr.Zero) return "";
            var bytes = new byte[c.CredentialBlobSize];
            Marshal.Copy(c.CredentialBlob, bytes, 0, bytes.Length);
            return Encoding.UTF8.GetString(bytes);
        }
        finally { CredFree(ptr); }
    }

    public static void Set(string account, string value)
    {
        CredDelete(Prefix + account, 1, 0);
        if (string.IsNullOrEmpty(value)) return;
        var bytes = Encoding.UTF8.GetBytes(value);
        var blob = Marshal.AllocHGlobal(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, blob, bytes.Length);
            var c = new CREDENTIAL
            {
                Type = 1,
                TargetName = Prefix + account,
                CredentialBlobSize = (uint)bytes.Length,
                CredentialBlob = blob,
                Persist = 2, // LOCAL_MACHINE: só este usuário, neste computador
                UserName = Environment.UserName,
            };
            if (!CredWrite(ref c, 0)) Trace.Log($"CredWrite falhou: {Marshal.GetLastWin32Error()}");
        }
        finally { Marshal.FreeHGlobal(blob); }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct CREDENTIAL
    {
        public uint Flags;
        public uint Type;
        public string TargetName;
        public string? Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public string? TargetAlias;
        public string? UserName;
    }

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "CredReadW")]
    private static extern bool CredRead(string target, uint type, uint flags, out IntPtr credential);

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "CredWriteW")]
    private static extern bool CredWrite(ref CREDENTIAL credential, uint flags);

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "CredDeleteW")]
    private static extern bool CredDelete(string target, uint type, uint flags);

    [DllImport("advapi32.dll")]
    private static extern void CredFree(IntPtr buffer);
}
