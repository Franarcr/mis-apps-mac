# Oído — contexto

App de barra de menús del Mac (`com.fran.oido`) que detecta llamadas, las graba, las pasa a texto y las resume,
todo en el Mac y sin internet. Lee también `../CLAUDE.md` (reglas generales).

## Cómo funciona

- `Detector.swift`: cada 2 s mira qué app de llamadas (Teams, WhatsApp, Zoom, navegador para Meet…) tiene el micro abierto.
- `Prompt.swift`: aviso flotante «Llamada en X — ¿grabar?» y, mientras graba, una **barrita flotante fija**
  «Teams · 12:34 [Detener]» que se puede mover. Existe porque el icono de la barra se puede esconder con Barra y
  Fran se quedó sin forma de parar una grabación (arreglado en be01e59).
- `Recorder.swift`: dos pistas, micrófono («Yo») y sonido de la app («Ellos»); `OidoAudio` (Obj-C) captura el audio.
- `Transcriber.swift`: voz a texto en el dispositivo, intercalado por tiempo.
- `Summarizer.swift`: resumen y pendientes con Apple Intelligence (FoundationModels). Usa
  `guardrails: .permissiveContentTransformations`; si un trozo lo rechaza el filtro («Detected content likely to be
  unsafe») se salta y se avisa en la nota; si falla el resumen final, se usan las notas por trozo.
- `Store.swift`: llamadas en `~/Library/Application Support/Oido/Llamadas` (fuera de Documentos por iCloud).
- `CallsView.swift`: ventana con el archivo de llamadas y reproductor.
- El título del menú queda vacío mientras graba (la barrita hace de indicador).

## Relación con Barra

`BarraLink.swift` (igual en todas las apps de barra de menús) permite que Barra esconda el icono y abra el menú.
Barra muestra siempre Oído en su lista de escondidas cuando Oído está abierto (ver `../Barra/CLAUDE.md`).

## Compilar

`./build.sh` → `/Applications/Oido.app`. Necesita permisos de micrófono y grabación de pantalla/audio.
