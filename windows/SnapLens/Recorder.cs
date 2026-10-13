using ScreenRecorderLib;
using static SnapLens.Loc;

namespace SnapLens;

/// Gravação de tela com Media Foundation (ScreenRecorderLib): vídeo H.264 em .mp4,
/// com áudio do sistema e/ou microfone opcionais.
public sealed class ScreenRecorder
{
    public static ScreenRecorder Shared { get; } = new();
    public event Action? StateChanged;

    public bool IsRecording { get; private set; }
    public DateTime? StartDate { get; private set; }

    private Recorder? recorder;
    private string fileName = "";
    private string sourceLabel = "";
    private SynchronizationContext? ui;
    private DateTime? stoppedAt;

    public void Start(Screen screen)
    {
        if (IsRecording) return;
        ui = SynchronizationContext.Current;
        bool wantSystem = Settings.Data.RecSystem, wantMic = Settings.Data.RecMic;

        var options = new RecorderOptions
        {
            SourceOptions = new SourceOptions
            {
                RecordingSources = { new DisplayRecordingSource(screen.DeviceName) },
            },
            OutputOptions = new OutputOptions { RecorderMode = RecorderMode.Video },
            AudioOptions = new AudioOptions
            {
                IsAudioEnabled = wantSystem || wantMic,
                IsOutputDeviceEnabled = wantSystem,
                IsInputDeviceEnabled = wantMic,
                Bitrate = AudioBitrate.bitrate_128kbps,
                Channels = AudioChannels.Stereo,
            },
            VideoEncoderOptions = new VideoEncoderOptions
            {
                Encoder = new H264VideoEncoder { BitrateMode = H264BitrateControlMode.Quality, EncoderProfile = H264Profile.High },
                Quality = 70,
                Framerate = 60,
                IsFixedFramerate = false,
                IsHardwareEncodingEnabled = true,
            },
            MouseOptions = new MouseOptions { IsMousePointerEnabled = true },
        };

        var name = Guid.NewGuid().ToString().ToUpperInvariant() + ".mp4";
        var path = Path.Combine(Store.Shared.VideosDir, name);
        var rec = Recorder.CreateRecorder(options);
        rec.OnRecordingComplete += (_, e) => Post(() => Finalize(true, null));
        rec.OnRecordingFailed += (_, e) => Post(() => Finalize(false, e.Error));
        rec.OnStatusChanged += (_, e) => Trace.Log("recorder status: " + e.Status);

        recorder = rec;
        fileName = name;
        sourceLabel = string.Join(" + ", new[] { wantSystem ? L("áudio do sistema") : null, wantMic ? L("microfone") : null }.Where(x => x != null));
        if (sourceLabel.Length == 0) sourceLabel = L("sem áudio");
        Trace.Log($"gravação: iniciando {screen.DeviceName} → {path} ({sourceLabel})");
        rec.Record(path);
        StartDate = DateTime.Now;
        stoppedAt = null;
        IsRecording = true;
        StateChanged?.Invoke();
    }

    /// Para a gravação; o item entra na biblioteca quando o arquivo termina de ser escrito.
    public void Stop()
    {
        if (!IsRecording || recorder == null) return;
        IsRecording = false;
        stoppedAt = DateTime.Now;
        StateChanged?.Invoke();
        recorder.Stop();
    }

    private void Post(Action a)
    {
        if (ui != null) ui.Post(_ => a(), null); else a();
    }

    private void Finalize(bool ok, string? error)
    {
        if (recorder == null) return;
        var rec = recorder;
        recorder = null;
        IsRecording = false;
        try { rec.Dispose(); } catch { }
        var path = Path.Combine(Store.Shared.VideosDir, fileName);
        if (!ok)
        {
            Trace.Log("gravação falhou: " + error);
            Toast.Show(L("Erro na gravação: %@", error ?? "?"), Icons.Warning);
            try { if (File.Exists(path) && new FileInfo(path).Length == 0) File.Delete(path); } catch { }
        }
        else if (!File.Exists(path))
        {
            Toast.Show(L("A gravação falhou: arquivo não foi criado"), Icons.Warning);
        }
        else
        {
            var seconds = ((stoppedAt ?? DateTime.Now) - (StartDate ?? DateTime.Now)).TotalSeconds;
            Store.Shared.AddVideo(fileName, seconds, sourceLabel);
            Toast.Show(L("Gravação salva na biblioteca (%@)", Format.Duration(seconds)), Icons.Video);
        }
        StateChanged?.Invoke();
    }
}
