# Kairos

Kairos es una herramienta visual de escenario para performance musical en `macOS 14+`, escrita en Swift/SwiftUI. La app muestra dos paneles principales:

- `Grid`: tiempo musical, compases, ciclos y estado de sincronía.
- `Level`: niveles por lane usando telemetría `RMS`/`peak`.

## Arquitectura real

- `Kairos/`: app macOS y capa de integración.
- `KairosCore/`: core lógico testeado, sin UI.
- `Level`: no captura audio dentro de la app. Recibe telemetría por UDP `51515` desde el dispositivo de `Max for Live` en `MaxForLive/`.
- `Sync`: tres fuentes vivas, `Internal`, `USB MIDI` y `Ableton Link`.
- `Packages/KairosLinkSDK/`: wrapper del SDK de Ableton Link, incluido como submódulo.

## Build y tests

Ejecuta desde la raíz del repo:

```sh
git submodule update --init --recursive
swift test --package-path KairosCore
xcodebuild -scheme Kairos -destination 'platform=macOS' build
```

## Configuración de Level con Max for Live

Kairos espera telemetría local enviada por `KAIROSLevelSender.amxd`. La guía operativa está en [docs/setup/level-max-for-live.md](/Users/diegofernandezmunoz/Developer/personal/kairos-app/docs/setup/level-max-for-live.md).

Resumen:

- Inserta el dispositivo en la pista, grupo, return o bus de Ableton.
- Déjalo al final de la cadena del canal para que la lectura coincida con el nivel mostrado.
- Kairos detecta las fuentes activas por `sourceSlot` y `sourceName` y las asigna a los lanes de `Level`.

## Alcance

Kairos es un proyecto `solo macOS`. iPhone, iPad, móvil, tablet y la captura basada en `BlackHole` quedan como referencia histórica, no como estado vivo del proyecto.
