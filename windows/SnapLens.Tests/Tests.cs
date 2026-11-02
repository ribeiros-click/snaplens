using SnapLens;
using Xunit;

/// Comparação de versões usada pelo aviso de atualização: "1.10" é mais nova que "1.9".
public class UpdateCheckerTests
{
    [Theory]
    [InlineData("1.10", "1.9", true)]
    [InlineData("1.9", "1.10", false)]
    [InlineData("1.10", "1.10", false)]
    [InlineData("1.10", "1.10.0", false)]
    [InlineData("1.10.1", "1.10", true)]
    [InlineData("2.0", "1.99", true)]
    [InlineData("1.11-beta", "1.10", true)]
    [InlineData("garbage", "1.0", false)]
    public void IsNewer(string a, string b, bool expected) => Assert.Equal(expected, UpdateChecker.IsNewer(a, b));
}

/// Validades da caixa de compartilhar.
public class ShareChoiceTests
{
    [Fact]
    public void Resolve()
    {
        Assert.Equal((30 * 86400, true), ShareChoice.Once.Resolve(7));
        Assert.Equal((86400, false), ShareChoice.D1.Resolve(7));
        Assert.Equal((5 * 86400, false), ShareChoice.D5.Resolve(7));
        Assert.Equal((0, false), ShareChoice.Never.Resolve(7));
    }

    [Theory]
    [InlineData(3, 3)]
    [InlineData(0, 1)]
    [InlineData(9999, 365)]
    public void CustomDaysAreClamped(int days, int expected) =>
        Assert.Equal(expected * 86400, ShareChoice.Custom.Resolve(days).Seconds);
}

/// Link do Google Lens: a URL da imagem vai codificada no parâmetro `url`.
public class LensUrlTests
{
    [Fact]
    public void BuildsUploadByUrl()
    {
        var url = new Uri(ShareClient.LensUrl("https://lens.ribeiros.click/i/abc123XYZ0?x=1&y=2"));
        Assert.Equal("lens.google.com", url.Host);
        Assert.Equal("/uploadbyurl", url.AbsolutePath);
        var query = System.Web.HttpUtility.ParseQueryString(url.Query);
        Assert.Equal("https://lens.ribeiros.click/i/abc123XYZ0?x=1&y=2", query["url"]);
        Assert.False(string.IsNullOrEmpty(query["hl"]));
    }
}

/// Regras da sincronização entre dispositivos.
public class SyncPlanTests
{
    private static readonly DateTime Now = DateTime.Now;
    private static readonly DateTime Cutoff = Now.AddDays(-7);

    private static Item Make(ItemKind kind, double daysAgo, string? text = null, string? file = "x.png") =>
        new() { Kind = kind, Date = Now.AddDays(-daysAgo), Text = text, File = kind.IsText() ? null : file };

    [Fact]
    public void UploadsOnlyRecentLocalUnsentItemsOfEnabledKinds()
    {
        var synced = Make(ItemKind.screenshot, 1); synced.SyncId = "abc";
        var fromOther = Make(ItemKind.screenshot, 1); fromOther.Device = "Mac";
        var recent = Make(ItemKind.screenshot, 1);
        var old = Make(ItemKind.screenshot, 10);
        var text = Make(ItemKind.ocr, 2, "olá");
        var emptyText = Make(ItemKind.clipboardText, 2, "");
        var video = Make(ItemKind.video, 1, file: "v.mp4");
        var up = SyncPlan.ToUpload(new[] { synced, fromOther, recent, old, text, emptyText, video }, Cutoff, new SyncPlan.Options());
        Assert.Equal(new[] { text.Id, recent.Id }, up.Select(i => i.Id)); // mais antigo primeiro; vídeos desligados
        Assert.Single(SyncPlan.ToUpload(new[] { video }, Cutoff, new SyncPlan.Options(Videos: true)));
    }

    [Fact]
    public void PropsRoundTripIntoIncomingItem()
    {
        var original = Make(ItemKind.screenshot, 1);
        original.Source = "Claude";
        var props = SyncPlan.Props(original, "PC-1", "DESKTOP-01");
        var incoming = SyncPlan.Incoming(props, "drive-file", new HashSet<Guid>(), "MAC-2", Cutoff);
        Assert.NotNull(incoming);
        Assert.Equal(original.Id, incoming!.Id);
        Assert.Equal(ItemKind.screenshot, incoming.Kind);
        Assert.True(Math.Abs((incoming.Date - original.Date).TotalSeconds) < 1);
        Assert.Equal("DESKTOP-01", incoming.Device);
        Assert.Equal("drive-file", incoming.SyncId);
        Assert.Equal("Claude", incoming.Source);
        Assert.Equal(original.Id.ToString().ToUpperInvariant() + ".png", incoming.File);
    }

    [Fact]
    public void IgnoresOwnKnownOldOrInvalidFiles()
    {
        var i = Make(ItemKind.screenshot, 1);
        var props = SyncPlan.Props(i, "PC-1", "DESKTOP-01");
        Assert.Null(SyncPlan.Incoming(props, "f", new HashSet<Guid>(), "PC-1", Cutoff));
        Assert.Null(SyncPlan.Incoming(props, "f", new HashSet<Guid> { i.Id }, "MAC", Cutoff));
        var old = SyncPlan.Props(Make(ItemKind.screenshot, 30), "PC-1", "DESKTOP-01");
        Assert.Null(SyncPlan.Incoming(old, "f", new HashSet<Guid>(), "MAC", Cutoff));
        Assert.Null(SyncPlan.Incoming(new Dictionary<string, string> { ["id"] = "x" }, "f", new HashSet<Guid>(), "MAC", Cutoff));
    }

    /// Itens criados no Mac chegam com o tipo pelo rawValue do enum Swift (mesmos nomes).
    [Fact]
    public void AcceptsMacProps()
    {
        var props = new Dictionary<string, string>
        {
            ["id"] = "0f8fad5b-d9cb-469f-a165-70867728950e", ["kind"] = "ocr",
            ["date"] = SyncPlan.Iso(Now), ["device"] = "MAC-1", ["deviceName"] = "MacBook",
        };
        var i = SyncPlan.Incoming(props, "f", new HashSet<Guid>(), "PC-2", Cutoff);
        Assert.NotNull(i);
        Assert.Equal(ItemKind.ocr, i!.Kind);
        Assert.Null(i.File);
    }
}
