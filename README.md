# SnapLens

App de barra de menu para macOS: screenshots, gravação de tela (com áudio do sistema e/ou microfone), OCR local (Vision), descrição de imagens com IA e biblioteca com exportação.

Requer macOS 15+.

## Compilar
```bash
./build.sh          # gera SnapLens.app (ICON=1|2|3 escolhe o ícone)
./make_dmg.sh       # gera SnapLens.dmg
./make_appstore.sh  # gera SnapLens.pkg para a Mac App Store (exige certificados + perfil)
```

## Atalhos padrão
| Ação | Atalho |
|---|---|
| Capturar seleção | ⌘⌥P |
| Capturar tela inteira | ⌃⌥F |
| OCR de seleção | ⌃⌥T |
| Descrever com IA | ⌃⌥D |
| Gravar tela | ⌃⌥R |
| Biblioteca | ⌃⌥H |

## Instalação via DMG
Baixe o `.dmg` em Releases, arraste o SnapLens para Applications. Se o macOS bloquear a abertura (build sem notarização), use clique direito → Abrir. Permita "Gravação de Tela" (e Microfone, se for usar) em Ajustes do Sistema → Privacidade e Segurança.
