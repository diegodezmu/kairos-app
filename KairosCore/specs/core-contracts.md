# KairosCore Contracts Freeze

## Decisiones tomadas

- Forma pública de muestra: `DynamicsSample` usa campos fijos `lane1...lane4`, no colección dinámica.
  Justificación: el PRD fija 4 lanes estéreo con mapeo D5 estable; una forma cerrada evita ambigüedad ABI, reduce superficie en el seam RT y deja claro que fase 2 añade consumidores, no lanes.
- `CycleEngine` recibe `beat` + `frozenOriginBeat`, no un `ClockSource` completo.
  Justificación: mantiene la lógica temporal pura y respeta el contrato exacto de `ClockSource`, que no expone `originBeat`.
- `HistoryBuffer` expone snapshots agregados por lane en amplitud lineal (`min/max/mean` por canal).
  Justificación: conserva el dato crudo medido y deja la conversión a dBFS al render, en línea con `docs/spikes/audio-io.md`.
- `DynamicsPublisher` modela de forma explícita `localConsumer` y `networkBroadcaster`.
  Justificación: el camino audio→dato pasa siempre por la costura y la fase 2 entra como adición, no como cirugía.

## Invariantes transversales

- `KairosCore` no importa SwiftUI/AppKit/UIKit.
- No hay implementación funcional: solo protocolos, tipos, doc y stubs.
- El reloj, el audio real y el networking real quedan fuera de `F1-SPEC`.
- Las tablas de test son el criterio de aceptación de `F1-TD` y `F1-DC`.

## DECISION-NEEDED

- `LaneSignalState` no define el estado bootstrap exacto al pasar de `disabled` a lane activa con menos de 2 s de silencio acumulado.
  Impacto: `F1-DC` necesita una decisión explícita para el primer instante tras activar una lane sin señal sostenida.
- El prompt pide “histéresis” para `LaneSignalState`, pero el PRD §7.7.2 solo fija umbral `-60 dBFS`, debounce de 2 s y cola de clip de 2 s.
  Impacto: no debe inventarse una banda extra de histéresis en dB para el estado de señal sin abrir un `CONTRACT-CHANGE`.

## Archivos congelados por este freeze

- `Sources/KairosCore/TimeDomain/*`
- `Sources/KairosCore/DynamicsCore/*`
- `Tests/KairosCoreTests/*ContractTablesTests.swift`
- `specs/time-domain.md`
- `specs/dynamics-core.md`
- `specs/core-contracts.md`
