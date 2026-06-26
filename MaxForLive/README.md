# KAIROS Level Sender

Este directorio contiene el dispositivo de Max for Live que sustituye el flujo basado en `BlackHole` para la seccion `Level` de KAIROS.

## Archivos

- `KAIROSLevelSender.amxd`: dispositivo listo para arrastrar a Ableton Live.
- `KAIROSLevelSender.maxpat`: patch fuente editable en Max.
- `kairos_level_sender.js`: formatea la telemetria post-fader en el formato JSON de KAIROS.
- `kairos_level_node.js`: envia los paquetes UDP al receptor local de KAIROS.
- `build_amxd.py`: reconstruye el `.amxd` a partir del `.maxpat` si se edita el patch.

## Comportamiento

- El audio sigue saliendo de Ableton por la interfaz de audio habitual.
- Cada instancia calcula un `RMS` integrado de ~`300 ms` y un `peak` a partir del
  audio real del patch (amplitud lineal verdadera) y los escala al estado
  **post-fader** de la pista multiplicando por la ganancia del fader.
- **Todo viaja en una única unidad: amplitud lineal `0..1`.** KAIROS la convierte
  a dBFS con `20*log10`, de forma que `RMS` y `peak` son coherentes entre sí y con
  el canal de Ableton (post-fader). Ya **no** se usa `output_meter_left/right` de
  Live para el `peak`: ese valor es una lectura de medidor warpeada (no amplitud
  lineal) y al convertirla con `20*log10` introducía un error sistemático de dB y
  mezclaba unidades con el `RMS`.
- La `identidad` (nombre y número de fuente) se deriva automáticamente de la pista
  vía Live API, para que el **source channel** que muestra KAIROS coincida con el
  canal real de Ableton sin numerar cada dispositivo a mano. Ver «Identidad de
  fuente».
- Solo se leen propiedades baratas de la Live API (`name`, `display_value` del
  volumen, ruta de la pista); ya no se sondean los medidores L/R caros de GUI.
- Para que el `RMS` sea un espejo exacto del canal, el dispositivo debe ir en la
  **ultima posicion de la cadena** del track / bus / return. Si quedan efectos
  despues, el patch medira audio anterior a esos efectos y el `RMS` ya no podra
  coincidir exactamente con la salida final del canal.
- Si la pista no puede resolverse por la Live API, el dispositivo recurre al nivel
  pre-fader medido con `peakamp~` para no quedarse en silencio.
- Editar solo los `.js` no requiere reconstruir el `.amxd` (se cargan por referencia);
  basta recargar el dispositivo en Live.
- Cada instancia emite telemetria ligera a `127.0.0.1:51515`.
- El identificador para KAIROS es `sourceSlot`, derivado de la posición real de
  la pista (audio/grupo → `1, 2, 3…`; return → `1001+`; master → `2001`). Así
  cada canal de Ableton obtiene un `sourceSlot` único y estable sin intervención
  manual, y `sourceName` refleja el nombre real de la pista en vivo.
- Si la pista no puede resolverse por la Live API, se usa como respaldo el número
  y nombre manuales del propio dispositivo.
- `senderId` sigue existiendo, pero solo para detectar conflictos temporales cuando dos dispositivos anuncian el mismo `sourceSlot` (p. ej. dos instancias en la misma pista).

## Uso

1. Arrastra `KAIROSLevelSender.amxd` a una pista, grupo, return o bus de Ableton Live.
2. Colocalo en la **ultima posicion** de la cadena de dispositivos si quieres
   correspondencia exacta con el `RMS` post-fader del canal.
3. Deja juntos el `.amxd` y los dos scripts `.js` de este directorio.
4. Si editas `KAIROSLevelSender.maxpat`, regenera el dispositivo con `build_amxd.py`.
5. Guarda el dispositivo si quieres reutilizarlo en varios proyectos.
6. Pon una instancia en cada pista, bus, grupo o return que quieras visualizar.
7. No hace falta numerar ni nombrar nada a mano: cada instancia toma el número y
   el nombre de su propia pista. El `live.numbox` y `source Track` solo actúan
   como respaldo si la Live API no está disponible.
8. Abre KAIROS. En la sidebar de `Level` deberias ver el receptor en escucha y las fuentes activas detectadas con el nombre real de cada pista.
9. Asigna libremente esas fuentes a los lanes visuales desde `Input source`.

## Paquete emitido

```json
{
  "type": "kairos.level.v1",
  "sourceSlot": 4,
  "senderId": "kairos-abc123",
  "sourceName": "Drums",
  "rmsL": 0.18,
  "rmsR": 0.16,
  "peakL": 0.74,
  "peakR": 0.68,
  "timestampMs": 178234123
}
```

## Compatibilidad heredada

KAIROS sigue aceptando tambien el formato antiguo de `Grid`:

```json
{
  "type": "gridlink.rms.v1",
  "slot": 1,
  "senderId": "gridlink-abc123",
  "sourceName": "Track",
  "rmsL": 0.12,
  "rmsR": 0.11,
  "peakL": 0.42,
  "peakR": 0.39
}
```

Eso permite validar la migracion con el experimento previo sin tocar su repo.
