# F0-3 — Spike de entrada de audio BlackHole + RMS RT

## Respuesta corta

**Sí, el camino queda validado para F1-DC.**

- La Parte A pasó de forma autónoma con una señal sintética de referencia: el RMS por
  canal quedó dentro de `±0.5 dB` y el clip saltó solo cuando se inyectó una muestra
  `> 0 dBFS`.
- La Parte B también corrió en este entorno: `BlackHole 16ch` estaba presente, se abrió
  **directamente** con `AVAudioEngine`, el tap leyó `16` canales, el spike midió los
  `8` primeros (D5) y publicó snapshots por ring buffer lock-free.
- No se tocó `KairosCore`; el spike vive aislado en un paquete desechable.

## Spike

Implementación desechable:

- `Packages/AudioIOSpike/Package.swift`
- `Packages/AudioIOSpike/Sources/AudioIOSpikeSupport`
- `Packages/AudioIOSpike/Sources/AudioIOSpikeCLI/main.swift`

Artefacto de ejecución:

- [docs/spikes/artifacts/audio-io-run.log](/Users/diegofernandezmunoz/Developer/personal/kairos-app/docs/spikes/artifacts/audio-io-run.log)

Comandos reproducibles desde la raíz del repo:

```sh
swift test --package-path Packages/AudioIOSpike
swift test --package-path Packages/AudioIOSpike --sanitize=thread
swift run --package-path Packages/AudioIOSpike AudioIOSpikeCLI \
  --output docs/spikes/artifacts/audio-io-run.log
```

El ejecutable hace dos cosas:

1. Parte A: genera PCM sintético no interleaved de `8` canales a `48 kHz`, con una
   ventana de `300 ms` (`14400` frames), y pasa ese buffer por la misma ruta de
   medición usada luego en vivo.
2. Parte B: detecta `BlackHole 16ch`, lo fija como dispositivo del `inputNode`
   subyacente (`kAudioOutputUnitProperty_CurrentDevice`), instala un tap en float32 y
   publica snapshots por ring buffer SPSC lock-free.

## Parte A — validación matemática

Configuración:

- Sample rate: `48_000 Hz`
- Ventana RMS: `300 ms`
- Frames por buffer: `14_400`
- Mapeo validado:
  - Lane 1 = canales `1-2`
  - Lane 2 = `3-4`
  - Lane 3 = `5-6`
  - Lane 4 = `7-8`

Resultados RMS:

| Lane | RMS L objetivo | RMS L medido | Δ L | RMS R objetivo | RMS R medido | Δ R |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | `-12.000 dBFS` | `-11.997 dBFS` | `+0.003 dB` | `-7.000 dBFS` | `-7.001 dBFS` | `-0.001 dB` |
| 2 | `-18.000 dBFS` | `-17.998 dBFS` | `+0.002 dB` | `-9.000 dBFS` | `-9.000 dBFS` | `-0.000 dB` |
| 3 | `-24.000 dBFS` | `-24.001 dBFS` | `-0.001 dB` | `-4.500 dBFS` | `-4.502 dBFS` | `-0.002 dB` |
| 4 | `-30.000 dBFS` | `-30.002 dBFS` | `-0.002 dB` | `-15.000 dBFS` | `-15.002 dBFS` | `-0.002 dB` |

Lectura:

- Todas las diferencias quedaron entre `0.000` y `0.003 dB`.
- La tolerancia pedida (`±0.5 dB`) queda ampliamente cubierta.

Clip test:

- Se inyectó una muestra aislada de `1.010` en la **lane 3, canal R**.
- Resultado:
  - `clipRight == true`
  - `clipLeft == false`

Conclusión de la Parte A:

- La medición RMS por canal con `vDSP_rmsqv` es correcta para la ruta propuesta.
- La detección de clip con `vDSP_maxmgv` + umbral `peak > 1.0` dispara donde debe y no
  contamina el canal vecino.

## Parte B — I/O en vivo con BlackHole

Estado: **corrió en este entorno**.

Hallazgos del run:

- Dispositivo detectado: `BlackHole 16ch`
- UID: `BlackHole16ch_UID`
- Canales de entrada del dispositivo: `16`
- Canales del tap de `AVAudioEngine`: `16`
- Canales medidos por el spike: `8`
- Tamaño pedido al tap: `14400` frames (`300 ms` a `48 kHz`)
- Tamaño observado por callback: `14400` frames
- Callbacks observados: `3`
- Snapshots publicados en ring buffer: `3`
- Drops en ring buffer: `0`

Evidencia funcional:

- La app abrió **BlackHole directo**, no el Aggregate Device.
- `sampleTime` avanzó `0 -> 28800`, consistente con `2` saltos de `14400` frames.
- En esta corrida hubo actividad real en la lane 1:
  - primer snapshot: `rmsLeft=0.043373`, `rmsRight=0.044032`
  - último snapshot: `rmsLeft=0.046219`, `rmsRight=0.047074`
- Las lanes `2-4` llegaron en silencio en esta ejecución, lo cual es válido para el
  spike: el objetivo aquí era demostrar apertura directa, lectura de `8` canales y
  publicación RT-safe, no calibrar una señal concreta en vivo.

Conclusión de la Parte B:

- D13 queda validada en esta máquina: `AVAudioEngine` puede fijarse a `BlackHole 16ch`
  y leer los canales `1-8` con numeración estable.

## Argumento de RT-safety

El callback del tap hace solo trabajo acotado y preasignado:

1. Lee `floatChannelData` ya entregado por `AVAudioEngine`.
2. Ejecuta `vDSP_rmsqv` y `vDSP_maxmgv` sobre punteros existentes.
3. Construye un `DynamicsSample` de tamaño fijo en stack.
4. Lo escribe en un ring buffer SPSC con memoria ya reservada.
5. Actualiza contadores con atómicos C11 (`stdatomic`), sin mutexes.

Lo que **no** hace el callback:

- no crea arrays Swift,
- no crea strings,
- no imprime logs,
- no toca `DispatchQueue`,
- no usa `Lock`, `NSLock`, `os_unfair_lock` ni similares,
- no hace conversión a dB para UI.

Detalles relevantes:

- El ring buffer usa una sola escritura RT y un solo lector no-RT.
- La señalización entre ambos lados se limita a índices atómicos `read/write`.
- La conversión a texto y la interpretación del snapshot se hacen fuera del callback.
- La pasada `swift test --package-path Packages/AudioIOSpike --sanitize=thread` quedó
  verde para la ruta automatizable del spike. No se ejecutó Instruments de audio en
  esta tarea.

## Forma de dato propuesta para F1-SPEC

Propuesta: congelar el payload RT en **amplitud lineal normalizada** y dejar la
conversión a dB para el hilo de render/UI.

```swift
struct LaneDynamicsSample {
    var rmsLeft: Float
    var rmsRight: Float
    var peakLeft: Float
    var peakRight: Float
    var clipLeft: Bool
    var clipRight: Bool
}

struct DynamicsSample {
    var hostTime: UInt64
    var sampleTime: Int64
    var frameCount: UInt32
    var sampleRate: Double
    var lane1: LaneDynamicsSample
    var lane2: LaneDynamicsSample
    var lane3: LaneDynamicsSample
    var lane4: LaneDynamicsSample
}
```

Razón:

- `rms*` y `peak*` salen directos del callback y conservan máxima precisión.
- El render puede convertir a dBFS fuera de RT y clampear a `[-60, 0]` según §7.3.
- `clipLeft` y `clipRight` permiten no ocultar un solo canal pegado.
- `laneClip` puede derivarse como `clipLeft || clipRight`, así que no hace falta
  duplicarlo en el payload RT.
- `hostTime` y `sampleTime` dejan alineable el histórico futuro con render y offset.

## Verificación adicional

Además del spike:

```sh
swift test --package-path KairosCore
swift build --package-path KairosCore
```

Ambos pasaron sin cambios en `KairosCore`.
