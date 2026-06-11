# DynamicsCore

## Contrato

`DynamicsCore` congela el camino audio→dato→consumidor, no el audio real.

- `AudioEngine` solo conoce un `DynamicsPublisher`.
- `DynamicsPublisher` publica `DynamicsSample` a un `LocalConsumer` (v1) y deja hueco explícito para `NetworkBroadcaster` (fase 2).
- `DynamicsSample` y `LaneDynamicsSample` viajan en amplitud lineal normalizada, no en dBFS.
- `HistoryBuffer` almacena valores ya medidos y devuelve snapshots agregados por lane.
- `LaneInputStatus` y `LaneSignalState` fijan el output público del estado de señal del sidebar.

## Invariantes

- Hay exactamente 4 lanes estéreo (`lane1...lane4`) con mapeo fijo D5.
- RMS y peak son por canal; no existe suma estéreo cruda en el contrato.
- `clipLeft` y `clipRight` son per-channel; el lane clip agregado se deriva fuera del payload RT.
- `HistoryBuffer` trabaja sobre `DynamicsSample`, nunca sobre audio crudo.
- Los buckets de histórico se expresan en amplitud lineal; la conversión a dBFS queda fuera del hilo RT y fuera de este contrato.
- `LaneSignalState.clipping` prevalece mientras dure su cola.
- El caption visible depende del estado: canal honesto en `receiving`, palabra de estado en `noSignal`/`clipping`.

## Criterios de aceptación

- Tablas de test para §7.2 fijan RMS, peak y clip esperado para señales de entrada conocidas.
- Tablas de test para §7.7.2 fijan transiciones `disabled`/`noSignal`/`receiving`/`clipping`, incluyendo debounce de 2 s y cola de clip de 2 s.
- `AudioEngine` no puede exponer un camino directo audio→render; la costura pública es `DynamicsPublisher`.
- El paquete compila para macOS e iOS sin frameworks de UI.

## Latitud de decisión

- La implementación puede usar ring buffer lock-free, snapshot store o equivalente mientras respete la costura.
- `HistoryBuffer` puede elegir su layout interno y su política de recorte.
- La suscripción/registro concreto de consumidores en `DynamicsPublisher` queda abierto; el contrato congela solo el fan-out visible.

## Fuera de alcance

- `AVAudioEngine` real.
- BlackHole real.
- Networking real para fase 2.
- Conversión de amplitud a dBFS en render/UI.
