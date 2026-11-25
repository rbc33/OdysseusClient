# Odysseus para iPhone

Cliente nativo (SwiftUI + WKWebView) para una instancia de Odysseus self-hosted.

## Qué hace

- Carga tu Odysseus con sesión persistente (no tienes que volver a iniciar sesión)
- Face ID / código para desbloquear y tapa el contenido en el selector de apps
- Pantalla de error con reintento si el servidor o Tailscale no responden
- Enlaces externos → Safari; descargas → hoja de compartir (Archivos, AirDrop…)
- Tira hacia abajo para recargar; desliza desde el borde para ir atrás
- Agita el iPhone para abrir los ajustes (URL del servidor, Face ID, borrar sesión)
- Web Inspector activado: Safari en el Mac > Desarrollo > iPhone

## Compilar

```bash
brew install xcodegen
cd OdysseusClient
xcodegen
open OdysseusClient.xcodeproj
```

En Xcode: target Odysseus → Signing & Capabilities → elige tu Team → Run en el iPhone.
Con Apple ID gratuito la firma dura 7 días (AltStore/AltServer la renueva).

Añade un icono de 1024×1024 en `Sources/Assets.xcassets/AppIcon.appiconset`.

## Servidor (rictow)

Por defecto apunta a `http://rictow:7000` (MagicDNS de Tailscale). En `.env` de Odysseus:

```
AUTH_ENABLED=true
LOCALHOST_BYPASS=false
```

No abras el puerto 7000 en el router: entra solo por Tailscale.

### HTTPS recomendado

El micrófono (dictado) y el portapapeles del navegador solo funcionan en contexto seguro (https).

```bash
sudo tailscale serve --bg 7000
```

Luego pon en los ajustes de la app `https://rictow.<tu-tailnet>.ts.net`.
