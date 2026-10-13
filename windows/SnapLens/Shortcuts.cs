using System.Runtime.InteropServices;
using static SnapLens.Loc;

namespace SnapLens;

public sealed record Shortcut(int Key, int Mods)
{
    public const int Alt = 0x1, Ctrl = 0x2, Shift = 0x4, Win = 0x8;

    public string Display
    {
        get
        {
            var parts = new List<string>();
            if ((Mods & Ctrl) != 0) parts.Add("Ctrl");
            if ((Mods & Alt) != 0) parts.Add("Alt");
            if ((Mods & Shift) != 0) parts.Add("Shift");
            if ((Mods & Win) != 0) parts.Add("Win");
            parts.Add(KeyLabel((Keys)Key));
            return string.Join("+", parts);
        }
    }

    public static string KeyLabel(Keys k) => k switch
    {
        >= Keys.D0 and <= Keys.D9 => ((char)('0' + (k - Keys.D0))).ToString(),
        >= Keys.NumPad0 and <= Keys.NumPad9 => "Num" + (k - Keys.NumPad0),
        Keys.Space => "Space",
        Keys.Return => "Enter",
        Keys.Back => "Backspace",
        Keys.Snapshot => "PrtSc",
        Keys.Left => "←", Keys.Right => "→", Keys.Up => "↑", Keys.Down => "↓",
        Keys.OemMinus => "-", Keys.Oemplus => "=", Keys.Oemcomma => ",", Keys.OemPeriod => ".",
        _ => k.ToString(),
    };
}

public enum ShortcutAction { region, full, ocr, describe, record, history }

public static class Shortcuts
{
    public static event Action? Changed;
    /// true enquanto o usuário grava um atalho novo em Ajustes: os atalhos globais ficam suspensos
    /// (senão o Windows entrega a combinação ao atalho antigo em vez de à janela).
    public static event Action<bool>? Suspend;
    public static void SetSuspended(bool on) => Suspend?.Invoke(on);
    public static readonly ShortcutAction[] All = Enum.GetValues<ShortcutAction>();

    public static string Title(this ShortcutAction a) => a switch
    {
        ShortcutAction.region => L("Capturar seleção"),
        ShortcutAction.full => L("Capturar tela inteira"),
        ShortcutAction.ocr => L("OCR de uma seleção"),
        ShortcutAction.describe => L("Descrever seleção com IA"),
        ShortcutAction.record => L("Gravar tela (iniciar/parar)"),
        _ => L("Abrir biblioteca"),
    };

    /// Padrões equivalentes aos do macOS (⌥⌘ / ⌃⌥ → Ctrl+Alt). Nenhuma dessas letras gera
    /// caractere com AltGr no ABNT2; em outros layouts o usuário troca em Ajustes.
    public static Shortcut Default(this ShortcutAction a) => a switch
    {
        ShortcutAction.region => new((int)Keys.P, Shortcut.Ctrl | Shortcut.Alt),
        ShortcutAction.full => new((int)Keys.F, Shortcut.Ctrl | Shortcut.Alt),
        ShortcutAction.ocr => new((int)Keys.T, Shortcut.Ctrl | Shortcut.Alt),
        ShortcutAction.describe => new((int)Keys.D, Shortcut.Ctrl | Shortcut.Alt),
        ShortcutAction.record => new((int)Keys.R, Shortcut.Ctrl | Shortcut.Alt),
        _ => new((int)Keys.H, Shortcut.Ctrl | Shortcut.Alt),
    };

    public static Shortcut Get(this ShortcutAction a) =>
        Settings.Data.Shortcuts.TryGetValue(a.ToString(), out var s) ? s : a.Default();

    public static void Set(this ShortcutAction a, Shortcut s)
    {
        Settings.Data.Shortcuts[a.ToString()] = s;
        Settings.Save();
        Changed?.Invoke();
    }

    public static void Reset(this ShortcutAction a)
    {
        Settings.Data.Shortcuts.Remove(a.ToString());
        Settings.Save();
        Changed?.Invoke();
    }
}

/// Janela invisível que recebe WM_HOTKEY (atalhos globais) e WM_CLIPBOARDUPDATE.
public sealed class MessageWindow : NativeWindow, IDisposable
{
    private const int WM_HOTKEY = 0x0312, WM_CLIPBOARDUPDATE = 0x031D;
    private readonly Dictionary<int, Action> handlers = new();
    public event Action? ClipboardChanged;
    public event Action<int>? Message;

    public MessageWindow()
    {
        CreateHandle(new CreateParams { Caption = "SnapLens.MessageWindow", Parent = new IntPtr(-3) /* HWND_MESSAGE */ });
    }

    /// Registra (ou re-registra) um atalho global. Falso se outro programa já usa a combinação.
    public bool Register(int id, Shortcut sc, Action handler)
    {
        UnregisterHotKey(Handle, id);
        handlers[id] = handler;
        bool ok = RegisterHotKey(Handle, id, (uint)(sc.Mods | 0x4000 /* MOD_NOREPEAT */), (uint)sc.Key);
        if (!ok) Trace.Log($"RegisterHotKey id={id} {sc.Display} FALHOU err={Marshal.GetLastWin32Error()}");
        return ok;
    }

    public void Unregister(int id)
    {
        UnregisterHotKey(Handle, id);
        handlers.Remove(id);
    }

    public void ListenClipboard() => AddClipboardFormatListener(Handle);

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_HOTKEY && handlers.TryGetValue(m.WParam.ToInt32(), out var h))
        {
            Trace.Log($"hotkey id={m.WParam} pressionado");
            h();
            return;
        }
        if (m.Msg == WM_CLIPBOARDUPDATE) { ClipboardChanged?.Invoke(); return; }
        if (m.Msg >= 0x8000) Message?.Invoke(m.Msg);
        base.WndProc(ref m);
    }

    public void Dispose()
    {
        foreach (var id in handlers.Keys.ToList()) UnregisterHotKey(Handle, id);
        RemoveClipboardFormatListener(Handle);
        DestroyHandle();
    }

    [DllImport("user32.dll", SetLastError = true)] private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] private static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    [DllImport("user32.dll")] private static extern bool AddClipboardFormatListener(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool RemoveClipboardFormatListener(IntPtr hwnd);
}
