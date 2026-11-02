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
