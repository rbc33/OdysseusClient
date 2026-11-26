# OdysseusClient

Clientes nativos (SwiftUI + WKWebView) para iPhone/iPad y Mac de una instancia de
[Odysseus](https://github.com/odysseus-dev/odysseus) self-hosted.

## Instalar

**Mac (Homebrew)**

```bash
brew install --cask rbc33/odysseusclient/odysseusclient
```

**iPhone / iPad (SideStore)** — añade la source en Sources → +:

```
https://raw.githubusercontent.com/rbc33/OdysseusClient/main/source.json
```

O instálala dentro de LiveContainer (no gasta hueco de app) con:

```
https://github.com/rbc33/OdysseusClient/releases/latest/download/com.rbc33.odysseus.ipa
```

## Qué hace

- Sesión persistente (no hay que volver a iniciar sesión)
- Bloqueo con Face ID / Touch ID
- Pantalla de error con reintento si el servidor o Tailscale no responden
- Enlaces externos → navegador; descargas → hoja de compartir (iOS) o ~/Descargas (Mac)
- Web Inspector activado para depurar
- **iOS:** tira hacia abajo para recargar, agita el iPhone para abrir los ajustes
- **Mac:** ajustes con ⌘, · recargar ⌘R · atrás/adelante ⌘[ ⌘] · zoom ⌘+ ⌘- ⌘0

## Scripts

| Script | Qué hace |
|---|---|
| `./build-ipa.sh` | `.ipa` sin firmar → `build/com.rbc33.odysseus.ipa` |
| `./build-mac.sh [--open]` | App universal firmada ad-hoc + DMG → `build/Odysseus.dmg` |
| `./release.sh 1.1.0 "Notas"` | Sube versión, compila ambos, publica el release, actualiza `source.json` y el cask de Homebrew |
| `./update.sh [zip] [--delete]` | Aplica un `OdysseusClient.zip` nuevo (por defecto `../OdysseusClient.zip`) |

`release.sh` crea y clona el tap `rbc33/homebrew-odysseusclient` en `../homebrew-odysseusclient`
la primera vez. `update.sh` nunca pisa `source.json` ni la versión de `project.yml`.

Requisitos: `brew install xcodegen gh` (opcional `xcbeautify`), `gh auth login`.

SideStore deduce el bundle ID del nombre del archivo, por eso el `.ipa` se llama
`com.rbc33.odysseus.ipa`.

## Estructura

- `Sources/` — app iOS (`AppSettings.swift` y `LockManager.swift` se comparten con Mac)
- `Mac/` — app macOS
- `icon.png` — icono de la source de SideStore

## Servidor (rictow)

En `.env` de Odysseus:

```
AUTH_ENABLED=true
LOCALHOST_BYPASS=false
```

No abras el puerto 7000 en el router: entra solo por Tailscale.

### HTTPS (necesario en iOS dentro de LiveContainer, micrófono y portapapeles)

```bash
sudo tailscale serve --bg 7000
```

Luego pon en los ajustes `https://rictow.<tu-tailnet>.ts.net` (sin puerto).
En Mac también funciona `http://` a la IP o a MagicDNS.
