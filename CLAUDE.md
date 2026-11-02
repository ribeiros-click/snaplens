# SnapLens — notas para o Claude

## Versão
- A versão do app (macOS e Windows) fica só no arquivo `VERSION` na raiz.
- Formato `X.Y` (como as releases já publicadas: v1.7, v1.8, v1.9, v1.10…); correção pequena pode usar `X.Y.Z`.
- **Toda mudança visível para o usuário sobe a versão no mesmo PR** (recurso → `X.Y+1`; correção → `X.Y.Z+1`).
- **Cada merge no `main` publica a release `v<VERSION>`** sozinho (DMG + instalador do Windows). Se a versão não subiu, os arquivos da release existente são substituídos.
- O número do build é automático (contagem de commits, `git rev-list --count HEAD`); não edite à mão.

## Notas de versão
- **Todo PR com mudança visível adiciona uma linha em `CHANGELOG.md`** na seção `## <VERSION>` (em português: “**Novo:**”, “**Correção:**”…). Essa seção vira a nota da release.

## Site (lens.ribeiros.click)
- As páginas `server/public_html/{,en/,es/,it/,zh/}index.html` são **geradas** por `Tools/build_site.py` (textos nos 5 idiomas ficam lá). Não edite os `index.html` à mão: rode `python3 Tools/build_site.py`.
- Prints: `SnapLens --render-shots <pasta>` (interface real). O workflow `site.yml` gera os prints e publica o site a cada merge no `main` (precisa do secret `HOSTINGER_API_TOKEN`); em PRs só gera os prints como artefato.
- Recurso novo que muda o que o app faz com dados → atualizar `server/public_html/politicas/privacidade.html`.

## Testes
- macOS: `swift test` (alvo `Tests/SnapLensTests`); Windows: `dotnet test windows/SnapLens.Tests`. Os dois rodam no CI antes do build.
- Lógica nova que não depende de tela (cálculos, comparação, montagem de URL, seleção de itens) ganha teste nos dois.

## Builds
- macOS: `./build.sh` / `./make_dmg.sh`; Windows: `windows/build.ps1`. Os dois leem `VERSION`.
- CI: `.github/workflows/macos.yml` (DMG) e `windows.yml` (instalador) rodam em todo PR (artefato para teste) e em push no `main` / tag `v*` (release).
- Toda string nova de interface precisa de tradução em `Sources/SnapLens/Resources/{en,es,it,zh-Hans}.lproj/Localizable.strings` (pt-BR é a chave). Textos só do Windows: `windows/SnapLens/WinStrings.cs`.
