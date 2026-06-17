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
3. El patch obtiene `RMS` y `peak` locales de la señal entrante.
4. La instancia integra el `RMS` sobre ~`300 ms` y lo ajusta al estado
   post-fader de la pista.
5. La instancia usa `output_meter_left/right` de Live como referencia de `peak`
   post-fader para que el techo y el clipping coincidan con Ableton.
6. KAIROS detecta las fuentes activas por `sourceSlot`.
7. La sidebar de `Level` muestra el estado del receptor, las fuentes activas y posibles conflictos.
8. Cada lane de `Level` puede seleccionar su `Input source`.
9. Esa asignacion se persiste en presets.

## Identidad de fuente

La asignacion persistente no usa `senderId`, porque ese valor es efimero y puede regenerarse cuando Max vuelve a cargar el dispositivo.

La clave estable es:

- `sourceSlot`: numero logico elegido por el usuario dentro de cada instancia del dispositivo.

Regla operativa:

- Cada dispositivo debe tener un `sourceSlot` unico.
- Si dos dispositivos emiten el mismo `sourceSlot`, KAIROS lo marca como conflicto.

## Compatibilidad con Grid

KAIROS acepta dos formatos:

- Nuevo: `kairos.level.v1`
- Heredado desde `Grid`: `gridlink.rms.v1`

Eso permite usar el experimento previo como referencia y como fallback de validacion.

## Prueba completa

1. Abre KAIROS.
2. Activa uno o varios lanes en la seccion `Level`.
3. En Ableton, inserta `KAIROSLevelSender.amxd` en varias pistas o buses.
4. Asigna `Source 1`, `Source 2`, `Source 3`, etc. sin repetir numeros.
5. Reproduce audio en esas pistas.
6. En KAIROS, confirma en la sidebar:
   - `Receiving N sources on UDP 51515.`
   - lista de fuentes activas detectadas
   - ausencia de conflictos
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
