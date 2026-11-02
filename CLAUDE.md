# SnapLens — notas para o Claude

## Versão
- A versão do app (macOS e Windows) fica só no arquivo `VERSION` na raiz.
- **Toda mudança visível para o usuário sobe a versão no mesmo PR**: recurso novo → `x.Y.0`; correção → `x.y.Z`.
- O número do build é automático (contagem de commits, `git rev-list --count HEAD`); não edite à mão.
- Numa tag `v*`, os workflows usam a versão da tag: crie a tag igual ao conteúdo de `VERSION`.

## Builds
- macOS: `./build.sh` / `./make_dmg.sh`; Windows: `windows/build.ps1`. Os dois leem `VERSION`.
- CI: `.github/workflows/macos.yml` (DMG) e `windows.yml` (instalador) rodam em todo PR e anexam à release em tags `v*`.
- Toda string nova de interface precisa de tradução em `Sources/SnapLens/Resources/{en,es,it,zh-Hans}.lproj/Localizable.strings` (pt-BR é a chave). Textos só do Windows: `windows/SnapLens/WinStrings.cs`.
