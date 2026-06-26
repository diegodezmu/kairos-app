# Level via Max for Live

Esta es la arquitectura principal de `Level` en KAIROS.

## Objetivo

- Ableton sigue sonando por la tarjeta o interfaz habitual.
- KAIROS no depende de `BlackHole`, dispositivos agregados ni ruteo virtual del sistema.
- Las instancias de Max for Live envian por UDP local `RMS` integrado + `peak`
  post-fader para que KAIROS siga el canal de Ableton.
- El usuario puede asignar libremente cada fuente emitida a cualquiera de los 4 lanes visuales de `Level`.

## Componentes

- Receptor KAIROS: `Kairos/LevelTelemetryReceiver.swift`
- Runtime de render Level: `Kairos/LevelRuntimeDriver.swift`
- Dispositivo Max for Live: `MaxForLive/KAIROSLevelSender.amxd`
- Patch fuente editable: `MaxForLive/KAIROSLevelSender.maxpat`
- Scripts del dispositivo:
  - `MaxForLive/kairos_level_sender.js`
  - `MaxForLive/kairos_level_node.js`

## Flujo

1. El dispositivo `KAIROSLevelSender.amxd` se inserta en una pista, grupo, return o bus de Ableton.
2. Para correspondencia exacta de `RMS`, el dispositivo debe quedar en la ultima
   posicion de la cadena del canal.
3. El patch obtiene `RMS` (`average~ ... rms`) y `peak` (`peakamp~`) locales de la
   señal entrante, en amplitud lineal verdadera.
4. La instancia integra el `RMS` sobre ~`300 ms` y escala tanto `RMS` como `peak`
   al estado post-fader multiplicando por la ganancia del fader (`display_value`
   del volumen). Todo permanece en amplitud lineal `0..1`, así que el `20*log10`
   de KAIROS produce dBFS coherentes con el canal.
5. **No** se usa `output_meter_left/right` de Live: ese valor es un medidor de GUI
   warpeado (no amplitud lineal) y convertirlo con `20*log10` desalineaba el dB.
   Evitarlo también elimina la carga de GUI de sondear esos medidores.
6. KAIROS detecta las fuentes activas por `sourceSlot`, derivado de la posición
   real de la pista, con el nombre real de la pista como `sourceName`.
7. La sidebar de `Level` muestra el estado del receptor, las fuentes activas y posibles conflictos.
8. Cada lane de `Level` puede seleccionar su `Input source`.
9. Esa asignacion se persiste en presets.

## Identidad de fuente

La asignacion persistente no usa `senderId`, porque ese valor es efimero y puede regenerarse cuando Max vuelve a cargar el dispositivo.

La clave estable es:

- `sourceSlot`: derivado automaticamente de la posicion real del canal en Live
  (audio/grupo → `1, 2, 3…`; return → `1001+`; master → `2001`).
- `sourceName`: el nombre real de la pista, leido en vivo de la Live API.

Asi el **source channel** que muestra KAIROS corresponde 1:1 con el canal de
Ableton sin numerar ni nombrar nada a mano.

Respaldo:

- Si la Live API no esta disponible, el dispositivo usa el numero (`live.numbox`)
  y el nombre (`source …`) manuales como fallback.

Regla operativa:

- Cada canal de Ableton produce un `sourceSlot` unico por construccion.
- Si dos dispositivos viven en la **misma** pista emiten el mismo `sourceSlot`, y
  KAIROS lo marca como conflicto.

## Compatibilidad con Grid

KAIROS acepta dos formatos:

- Nuevo: `kairos.level.v1`
- Heredado desde `Grid`: `gridlink.rms.v1`

Eso permite usar el experimento previo como referencia y como fallback de validacion.

## Prueba completa

1. Abre KAIROS.
2. Activa uno o varios lanes en la seccion `Level`.
3. En Ableton, inserta `KAIROSLevelSender.amxd` (ultimo en la cadena) en varias
   pistas o buses. No numeres ni nombres nada: cada instancia se identifica sola.
4. Reproduce audio en esas pistas.
5. En KAIROS, confirma en la sidebar:
   - `Receiving N sources on UDP 51515.`
   - cada fuente activa aparece con el nombre real de su pista de Ableton
   - ausencia de conflictos (salvo dos instancias en la misma pista)
6. Compara el dB de KAIROS con el medidor del canal de Ableton: el `peak` debe
   seguir al medidor (mismo techo/clip), y el `RMS` quedara por debajo del peak
   por el factor de cresta del material (comportamiento esperado).
7. En cada lane, elige `Input source`.
8. Verifica que el lane responde a la fuente asignada, no al numero del lane.
   - Ejemplo: lane 1 -> source 4
   - Ejemplo: lane 2 -> source 1
9. Guarda un preset.
10. Cambia las asignaciones, carga de nuevo el preset y verifica que se restauran.

## Casos a validar

- Una sola fuente activa asignada a un lane.
- Cuatro fuentes activas asignadas 1:1.
- Asignacion cruzada: source 4 en lane 1, source 1 en lane 2, etc.
- Una fuente desconectada o sin señal: el lane debe pasar a `No signal`.
- Conflicto por numeros repetidos: KAIROS debe avisarlo en la sidebar.

## Partes heredadas de Grid

- Receptor UDP no bloqueante basado en `socket` + `DispatchSourceRead`.
- Formato de amplitud lineal `rms/peak`.
- Deteccion de identidad efimera por `senderId` para conflictos en caliente.

## Partes descartadas de Grid

- Dependencia de IP manual hacia un iPhone.
- Rutas absolutas a los scripts de Max.
- Limite rigido de `slot 1-4` en el dispositivo.
- Paquetes de transporte de Ableton para la vista `Grid`.

## Nota sobre BlackHole

`BlackHole` queda documentado solo como referencia historica / fallback de investigacion.
No es la dependencia principal para `Level` en la arquitectura actual.
