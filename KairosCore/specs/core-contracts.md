# KairosCore Contracts Freeze

> ⚠️ Describe el contrato ORIGINAL de KairosCore. La capa que la app no usa fue **podada**
> (relojes/`ClockSource`/`OriginLatch`, `DynamicsPublisher`/broadcaster, `RMSPeak`, `DynamicsMeter`,
> `AudioEngine`). Vigente y en uso: `CycleEngine`, `ResetDetector`, `Offset`, `ClipDetector`,
> `HistoryBuffer`, `LaneInputStatus`. Ver `docs/decisiones-descartadas.md` y el historial de git.

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

## API pública de construcción

Este contrato añade, de forma aditiva, dos namespaces de factorías públicas:

- `TimeDomainFactory` construye `CycleEngine`, `ResetDetector`, `Offset`, `OriginLatch`, `InternalClock`, `MIDIClock` y `AbletonLinkClock`.
- `DynamicsCoreFactory` construye `HistoryBuffer`, `LaneInputStatusMachine`, `DynamicsPublisher`, `ClipDetector`, `RMSPeakMeasuring` y `DynamicsMeter`.

Reglas del contrato:

- Las factorías devuelven el protocolo o tipo público correspondiente.
- Las implementaciones `Default*` siguen siendo internas y no forman parte del contrato.
- `OriginLatch`, `LaneInputStatusMachine` y `DynamicsMeter` quedan expuestos como componentes públicos porque un consumidor externo necesita instanciarlos y operarlos directamente.
- El cambio es solo aditivo: no altera comportamiento, tablas ni firmas públicas previas.

## DECISION-NEEDED (resueltos en el freeze)

- **Bootstrap de `LaneSignalState` — RESUELTO.** Al activar una lane
  (`disabled → enabled`) el estado inicial es `noSignal`; pasa a `receiving` de
  inmediato con la primera muestra `> −60 dBFS` (entrada sin debounce); vuelve a
  `noSignal` solo tras ≥ 2 s `≤ −60 dBFS`. No hay temporizador de arranque: la
  asimetría de la transición lo cubre. `F1-DC` implementa esto. (PRD §7.7.2.)
- **Histéresis de `LaneSignalState` — RESUELTO: no hay banda extra en dB.** El único
  suavizado es el debounce temporal de 2 s + la cola de clip de 2 s; el umbral −60 dB
  es frontera dura para `receiving`. La histéresis de 1.5 dB de §15.2 es del color del
  **borde** del medidor (target), mecanismo distinto, y no aplica al Input Status.
  El agente acertó al no inventar banda; queda confirmado, sin `CONTRACT-CHANGE`.

## Archivos congelados por este freeze

- `Sources/KairosCore/TimeDomain/*`
- `Sources/KairosCore/DynamicsCore/*`
- `Tests/KairosCoreTests/*ContractTablesTests.swift`
- `specs/time-domain.md`
- `specs/dynamics-core.md`
- `specs/core-contracts.md`
