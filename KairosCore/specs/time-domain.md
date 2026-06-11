# TimeDomain

## Contrato

`TimeDomain` congela la superficie pública mínima para resolver posición musical, resets y offset sin acoplarse a UI ni al SDK real del reloj.

- `ClockSource` es la única fuente de beat/tempo/transporte.
- `CycleEngine` resuelve estado de ciclos a partir de un `beat` ya desplazado por `Offset` y de un `frozenOriginBeat` ya latcheado.
- `ResetDetector` decide marcas `combined`/`general` comparando estados consecutivos.
- `Offset` convierte milisegundos locales a beats locales; nunca muta la sesión compartida.

## Invariantes

- `ClockSource.quantum` es el quantum de transporte/fase, nunca `cycleLengthBeats`.
- `ClockSource.originHostTime` es el host time del start compartido.
- El `originBeat` usado por `CycleEngine` se captura una sola vez y queda congelado por peer; no forma parte del contrato público de `ClockSource`.
- `CycleEngine` es puro respecto a su entrada: no calcula tiempo de reloj ni hace latching interno.
- `currentStep` es zero-based y `cycleIteration` también.
- `currentStep` y `cycleIteration` son `nil` cuando no existe `frozenOriginBeat`.
- La tabla de anticipación es cerrada: `8→1`, `16/32/64→4`, `128→8`, `1/2/4→none`.
- `Offset` es local por dispositivo y afecta a render/click local; no modifica Link/MIDI/internal transport state.

## Criterios de aceptación

- Tablas de test para §5.3.1 fijan `currentStep` y `cycleIteration` desde `beat`, `pulse`, `stepNumber` y `frozenOriginBeat`.
- Tablas de test para §5.5.1 fijan cuándo un wrap simultáneo se pinta `combined`, `general` o `none`.
- Tablas de test para §5.5.2 fijan exactamente el `anticipationRange`.
- Tablas de test para §5.6 fijan la conversión `offsetMs / 1000 * tempo / 60`.
- El paquete compila sin importar SwiftUI/AppKit/UIKit.

## Latitud de decisión

- La tarea de implementación puede escoger structs, classes o actors concretos para `InternalClock`, `MIDIClock` y `AbletonLinkClock`.
- La captura del `frozenOriginBeat` puede vivir en un coordinador o seam owner, pero no puede alterar el contrato público de `ClockSource`.
- La estrategia de freeze cuando `isPlaying == false` pertenece a la capa que consulta el reloj; el contrato aquí solo exige conservar la última posición válida.

## Fuera de alcance

- Integración real con Ableton Link.
- Wiring de CoreMIDI.
- Programación real del metrónomo.
- Cualquier cálculo de render.
