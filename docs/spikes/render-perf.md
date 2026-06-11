# F0-2 — Spike de rendimiento de render (Canvas vs Metal)

## Alcance

Spike desechable para responder una sola pregunta: si el Grid de Kairos, en su peor
caso de v1, necesita Metal o si SwiftUI `Canvas` llega con margen suficiente.

- Caso medido: `mode = line`, `4` ciclos visibles, `128` steps por ciclo.
- Objetivo: `60 fps` estables.
- Restricción respetada: no se toca `KairosCore` ni la arquitectura del PRD §4.1.

## Benchmark implementado

Se añadió un spike autocontenido al target macOS `Kairos`, activado con el argumento:

```text
--render-perf-spike
```

Qué hace el spike:

- Abre una ventana real de macOS con un `Canvas` SwiftUI de `1728 × 540 pt`.
- En la máquina medida eso equivale a `3456 × 1080 px` (`backingScale = 2.0`).
- Usa `TimelineView(.animation(minimumInterval: 1/60))` para forzar un ritmo de
  actualización de 60 Hz.
- Fuerza redraw completo en cada frame.
- Recorre el step activo continuamente (`frame % 128`) para que el highlight cambie
  en todos los frames.
- Incluye los estados visuales relevantes del peor caso `line`:
  - step activo claro
  - anticipación roja en los últimos `8` steps
  - reset general morado al volver a `step 0`
- Mide dos cosas:
  - `fps_avg`: frames dibujados por segundo en una ventana real
  - `draw_cpu_*`: tiempo de CPU invertido dentro del closure de dibujo del `Canvas`

Parámetros de la medida:

- Warmup: `120` frames
- Muestra: `600` frames
- Build: `Release`

## Reproducción

```bash
xcodebuild -scheme Kairos -configuration Release -destination 'platform=macOS' -derivedDataPath .derivedData/render-perf build
./.derivedData/render-perf/Build/Products/Release/Kairos.app/Contents/MacOS/Kairos --render-perf-spike | tee docs/spikes/artifacts/render-perf-run.log
```

Artefacto generado:

- [docs/spikes/artifacts/render-perf-run.log](/Users/diegofernandezmunoz/Developer/personal/kairos-app/docs/spikes/artifacts/render-perf-run.log)

## Entorno de medida

- Hardware: MacBook Pro `Mac15,11`
- Chip: Apple `M3 Max`
- GPU: Apple `M3 Max`, `30` cores, Metal 3
- RAM: `36 GB`
- SO: macOS `15.7.4`

## Resultado obtenido

Salida del benchmark:

```text
renderer=Canvas
window_points=1728x540
backing_scale=2.000
window_pixels=3456x1080
cycles=4
steps_per_cycle=128
mode=line
warmup_frames=120
measured_frames=600
elapsed_seconds=9.983
fps_avg=60.100
frame_interval_avg_ms=16.667
frame_interval_p95_ms=16.667
frame_interval_max_ms=16.667
draw_cpu_avg_ms=0.158
draw_cpu_p95_ms=0.200
draw_cpu_max_ms=0.541
stable_60fps_ratio_percent=100.000
target_60fps_met=yes
```

Lectura:

- El caso `4 × 128` en `line` sostuvo `60.1 fps` en ventana real.
- El `p95` del frame interval se mantuvo exactamente en `16.667 ms`.
- El coste de CPU del dibujo del `Canvas` fue muy bajo:
  - media `0.158 ms`
  - p95 `0.200 ms`
  - máximo `0.541 ms`

## Decisión

**Decisión: usar SwiftUI `Canvas` en F1-RG. No usar Metal en v1 para el Grid.**

Justificación:

1. El peor caso objetivo (`4 × 128`, `line`) ya cumple `60 fps` estables en una
   ventana real, no en un render offscreen.
2. El closure de dibujo consume una fracción mínima del presupuesto de `16.667 ms`
   por frame. Con la medida actual, el cuello de botella no está en el dibujo del Grid.
3. Metal aumentaría complejidad de implementación, mantenimiento y depuración sin una
   necesidad demostrada por datos en este caso.
4. La decisión no bloquea una migración futura: si F1-RG añade más carga visual real
   y deja de cumplir, la entrada al renderer puede mantenerse y cambiar solo el backend.

Condición de revisión futura:

- Reabrir Canvas vs Metal solo si el renderer final añade coste material no cubierto por
  este spike: composición adicional, efectos, blending pesado, o más geometría por frame.

## Forma de API asumida para F1-RG/F1-RL

El renderer no debe calcular tiempo ni estado musical. Debe recibir un snapshot de dibujo
ya resuelto por capas superiores, alineado con PRD §4.2.

Forma mínima asumida para el Grid renderer:

```swift
enum GridVisualMode {
    case block
    case border
    case line
}

enum GridResetMark {
    case none
    case combined
    case general
}

struct GridRenderFrame {
    let mode: GridVisualMode
    let cycles: [GridCycleRenderInput]   // solo ciclos visibles
}

struct GridCycleRenderInput {
    let stepCount: Int                   // 1, 2, 4, 8, 16, 32, 64, 128
    let activeStepIndex: Int?            // nil cuando no hay origen/posición válida
    let resetMark: GridResetMark         // marca a pintar en step 0 de ese frame
    let anticipationRange: Range<Int>?   // tramo final que va en rojo
}
```

Interpretación práctica de entradas:

- `mode`: `block`, `border` o `line`.
- `cycles.count`: número de ciclos activos que hay que pintar.
- `stepCount`: número de steps de cada ciclo.
- `activeStepIndex`: step activo del ciclo en ese frame.
- `resetMark`: si el ciclo participa en reset `combined` o `general`.
- `anticipationRange`: steps finales que deben ir en rojo.

Implicación para F1-RL:

- Mantener el mismo patrón: el renderer consume snapshots inmutables ya resueltos.
- No meter lógica temporal, de RMS o de detección de estados dentro del dibujo.

## Conclusión

Con los datos de este spike, **Canvas es suficiente y es la opción recomendada para v1**.
El riesgo de PRD §13 queda cubierto para el caso extremo `128 × 4` en `line` con margen
holgado, así que F1-RG puede implementarse sobre `Canvas` sin introducir Metal por
precaución prematura.
