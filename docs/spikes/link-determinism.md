# Ableton Link multi-peer determinism spike

## Respuesta corta

**NO, no de forma incondicional.**

La propiedad "dos peers calculan el mismo `currentStep` y la misma
`cycleIteration` para ciclos largos" **sí se cumple** si ambos:

1. estuvieron presentes en el **mismo start de transporte compartido**,
2. usan ese mismo start como ancla,
3. y **congelan** su `originBeat` local una sola vez.

Pero **no se cumple** si el contrato se apoya solo en Link "tal cual", porque:

- un peer que entra a mitad de sesión **no hereda** el start original por sí solo;
- y tras un cambio de tempo, **recalcular** `originBeat` desde `beatAtTime(originHostTime)`
  rompe la continuidad.

Conclusión para `F1-SPEC`: hay que congelar el contrato con una definición más
estricta de `originBeat`/`hasOrigin` en modo Link.

## Spike

Implementación desechable en:

- `Packages/KairosLinkSDK/Sources/KairosLinkDeterminismSpikeCLI/main.swift`

Artefacto de ejecución:

- `docs/spikes/artifacts/link-determinism-run.log`

Comando reproducible desde la raíz del repo:

```sh
swift run --package-path Packages/KairosLinkSDK KairosLinkDeterminismSpikeCLI \
  --output docs/spikes/artifacts/link-determinism-run.log
```

El spike lanza peers reales de Link en este mismo Mac, los une a la misma sesión
por loopback, alinea muestras por `hostMicros` y compara:

- beat raw por peer
- `elapsedBeats`
- `currentStep`
- `cycleIteration`

Configuración de prueba:

- ciclo largo: `128 steps`
- pulse: `1/4`
- longitud de ciclo: `32 beats`
- quantums observados: `4` y `32`

## Evidencia

### 1) Start/stop sync OFF no da origen compartido

Del log:

- `A-off playing=true`
- `B-off playing=false`

Con Link activo pero `start/stop sync` desactivado, el segundo peer no entra en
play y no hay un origen de transporte común utilizable para D6.

### 2) Dos peers presentes en el mismo start sí alinean ciclos largos

Start compartido observado:

- `Shared transport start observed at hostMicros≈43698108218 (spread=6us)`

Muestra a `+8.5 beats`:

- `A q4`: `elapsed=8.500000 step=34 iter=0`
- `B q4`: `elapsed=8.500000 step=34 iter=0`
- `q4 rawBeatSpread=3.999988`
- `q32 rawBeatSpread=0.000012`

Interpretación:

- los **beats raw no son iguales** entre peers;
- pero con el mismo origen compartido, ambos calculan el mismo step/iteración.

Cruce de ciclo largo a `+33.5 beats`:

- `A q4`: `elapsed=33.500000 step=6 iter=1`
- `B q4`: `elapsed=33.500000 step=6 iter=1`
- `C q4` con origen original compartido: `elapsed=33.500000 step=6 iter=1`

Esto valida el punto central del gate: con ancla correcta, dos peers sí
mantienen la misma `cycleIteration` en un ciclo de 32 beats, no solo la fase
dentro del compás.

### 3) Late join: Link no backfillea el origen original

Snapshot del peer tardío `C` al entrar en una sesión ya corriendo:

- `playing=false`
- `startSync=true`
- `startMicros=43702386557`

Eso demuestra que **Link no le entrega automáticamente el start original** a un
peer que entra tarde, aunque el resto ya esté corriendo con `start/stop sync`.

Si `C` arranca localmente y usa **su propio origen local**:

- `C local origin`: `elapsed=11.730248 step=46 iter=0`

En ese mismo instante, `A` y `B` iban por:

- `step=82 iter=0`

Luego, **con origen local tardío hay desfase inmediato de grid**.

Si al mismo peer tardío se le da el **origen original compartido**:

- `A`: `elapsed=20.500000 step=82 iter=0`
- `B`: `elapsed=20.500000 step=82 iter=0`
- `C`: `elapsed=20.500000 step=82 iter=0`

Así que el late join **sí puede alinearse**, pero solo cuando conoce el origen
de transporte original.

### 4) Cambio de tempo en caliente: recalcular `originBeat` rompe continuidad

Antes del cambio de tempo, todos estaban en:

- `elapsed=33.500000 step=6 iter=1`

Después de cambiar de `120` a `90 BPM`, si se recalcula `originBeat`
dinámicamente desde el `originHostTime` original, el log da:

- `A`: `elapsed=31.289596 step=125 iter=0`
- `B`: `elapsed=31.289596 step=125 iter=0`
- `C`: `elapsed=31.289596 step=125 iter=0`

Es decir:

- los peers siguen coincidiendo **entre sí**,
- pero la posición **retrocede** respecto al estado previo (`iter=1 -> iter=0`).

Además `timeForIsPlaying` dejó de apuntar al origen inicial:

- `Post-tempo startTimeMicros snapshot: A=43692523948, B=43692523954, C=43702493094`
- `originalSharedOrigin=43698108218`

Luego **no es válido** definir el origen en modo Link como "releer
`beatAtTime(originHostTime)` cuando haga falta".

### 5) Cambio de tempo en caliente: con `originBeat` congelado sí hay continuidad

El spike recalculó la misma muestra post-tempo usando un `originBeat` **congelado
por peer** antes del cambio:

- `A q4`: `elapsed=39.665991 step=30 iter=1`
- `B q4`: `elapsed=39.665994 step=30 iter=1`
- `C q4`: `elapsed=39.666000 step=30 iter=1`

También con `q32`:

- `A q32`: `elapsed=39.665991 step=30 iter=1`
- `B q32`: `elapsed=39.665994 step=30 iter=1`
- `C q32`: `elapsed=39.666000 step=30 iter=1`

Esto sí preserva continuidad y determinismo multi-peer tras el cambio de tempo.

## Papel de start/stop sync y del quantum

### Start/stop sync

`start/stop sync` es **necesario** para que los peers ya presentes compartan el
mismo evento de arranque de transporte.

Pero **no basta** para un late join:

- el peer tardío no recibió `playing=true`;
- tampoco recibió el `startMicros` original.

Por tanto, `start/stop sync` resuelve el arranque compartido de los peers ya
presentes, pero **no garantiza por sí solo** el determinismo de iteración para
quien entra a mitad de sesión.

### Quantum

El quantum sí afecta a Link, pero su papel aquí es concreto:

- define la **fase compartida** y la cuantización del arranque;
- cambia la clase de equivalencia del beat raw entre peers;
- **no** transporta por sí mismo la iteración de un ciclo largo.

En esta corrida:

- con `q=4`, el `rawBeatSpread` entre peers llegó a `~4` beats (A/B) y `~12`
  beats (A/B/C);
- con `q=32`, el `rawBeatSpread` cayó a `~0.00003`.

Pero en ambos casos, el late join **seguía fallando** si usaba su origen local
en vez del origen original compartido. Eso descarta usar el quantum como sustituto
de un origen bien definido.

## Ajuste exacto del contrato para `F1-SPEC`

### Propuesta

En modo Link, el contrato de `TimeDomain` debe congelarse así:

1. `quantum`

   - `ClockSource.quantum` sigue siendo el **quantum musical de Link** usado para
     fase/transporte.
   - **No** debe reinterpretarse como `cycleLengthBeats`.

2. `originHostTime`

   - Añadir un ancla explícita de transporte compartido:
     `originHostTime: UInt64?`
   - Este valor representa **el host time del start compartido**.

3. `originBeat`

   - **No** debe ser "el resultado de llamar otra vez a
     `beat(atHostTime: originHostTime)`".
   - Debe definirse como:

     `originBeat = beat(atHostTime: originHostTime)` **capturado una sola vez y congelado por peer** cuando el origen se vuelve conocido.

4. `hasOrigin`

   - `hasOrigin == true` solo cuando el peer conoce `originHostTime` **y** ya ha
     congelado su `originBeat` local.
   - Si el peer entra en una sesión Link ya corriendo y no recibe el origen
     original, `hasOrigin` debe seguir en `false` hasta:
     - el siguiente start compartido, o
     - una inyección externa del `originHostTime` original.

5. Late join determinista

   - Si producto exige que un peer que entra tarde caiga en la iteración correcta
     **sin esperar al próximo start**, `F1-SPEC` debe introducir una vía de
     adopción explícita del origen original, por ejemplo:

     `adoptSharedOrigin(hostTime: UInt64)`

   - Ese `hostTime` puede venir de un canal de sesión/control propio; **Link solo**
     no lo backfilleó en este spike.

### Consecuencia práctica

La fórmula de §5.3.1 sigue siendo válida, pero en Link pasa a depender de un
`originBeat` **latched**:

```text
elapsedBeats   = beat - frozenOriginBeat
stepFloat      = elapsedBeats / pulse
currentStep    = floor(stepFloat) mod stepNumber
cycleIteration = floor(stepFloat / stepNumber)
```

No debe depender de recomputar `originBeat` desde el host time tras cambios de
tempo.

## Decisión

`F1-SPEC` puede avanzar solo si se congela este matiz:

- **SÍ** hay determinismo multi-peer en ciclos largos para peers presentes en el
  mismo start y con `originBeat` congelado.
- **NO** basta con Link puro + start/stop sync + recalcular el origen sobre la
  marcha.
- Para late join determinista mid-session hace falta **adoptar el origen original**
  o esperar al siguiente start compartido.
