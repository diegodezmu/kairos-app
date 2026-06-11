# Kairos — PRD técnico

> Documento de requisitos de producto orientado a implementación. Su objetivo es
> que agentes de código puedan desarrollar la aplicación sin ambigüedad. No cubre
> la dirección estética (resuelta en Figma); define **función, comportamiento y
> arquitectura**.

---

## 0. Control del documento

- **Estado:** v1.1 en especificación. Listo para desarrollo del target macOS.
  Incorpora las decisiones D11–D14 (offset, Input Status, entrada de audio, Rename)
  y el contexto de uso privado.
- **Fuentes:** `kairos-origen.md` (spec original desktop), `mobile-evo.md`
  (evolución móvil), `figma-screen-references/` (capturas de referencia),
  `kairos-design-system.md` (sistema de diseño, fuente de verdad visual).
- **Relación con las fuentes:** este PRD las supersede donde haya conflicto. Las
  decisiones de las secciones siguientes prevalecen sobre el texto original.

### 0.1 Decisiones bloqueadas

Estas decisiones están cerradas y son la base del diseño. No reabrir sin motivo.

| #   | Decisión                 | Valor                                                                                                                 |
| --- | ------------------------ | --------------------------------------------------------------------------------------------------------------------- |
| D1  | Modelo de audio          | Hasta **4 buses estéreo independientes**, un medidor (lane) por bus                                                   |
| D2  | Posición del Grid        | **Determinista desde el timeline del reloj** (común a todos los dispositivos)                                         |
| D3  | Config del Grid en móvil | **Independiente por dispositivo** (fase 2)                                                                            |
| D4  | Alcance v1               | **macOS primero**; **iOS (iPhone + iPad)** en fase 2                                                                   |
| D5  | Routing de buses         | **Mapeo fijo**: Lane 1 = ch 1‑2, 2 = 3‑4, 3 = 5‑6, 4 = 7‑8                                                            |
| D6  | Origen del grid sin Link | **Anclado al transporte** (Play / MIDI Start / Link start‑stop)                                                       |
| D7  | Metrónomo                | **Mínimo**: click interno fijo, pulse configurable, sin upload de sample                                              |
| D8  | Distribución             | **Uso privado, no comercial** (tú + el grupo); sin App Store ni revisión. macOS: firma local/ad‑hoc basta, notarización **opcional** (comodidad). iOS: cuenta de desarrollador de pago recomendada solo para perfiles de 1 año. Sin sandbox |
| D9  | Acceso a presets         | El selector de presets vive en la **top‑bar** (primer botón), no en el sidebar                                        |
| D10 | Layout iPhone (fase 2)   | Grid y Level en **pantallas separadas**; gesto de **drag** para alternar (excepción a "cero interacción" por espacio) |
| D11 | Offset                   | Renombrado de "visual offset" a **Offset**. Ajuste temporal **local** que desplaza **render Y clic del metrónomo** (cuando está activo) por la misma cantidad. Nunca toca la sesión/fase Link. Por dispositivo (§5.6)                  |
| D12 | Input Status (Level)     | Componente `input-status` bajo el nombre de cada window: **dot** (blanco=sin señal · verde=señal · rojo=clip) + texto según estado (canal `BlackHole 1–2` / `No signal` / `Clipping`). **Solo en sidebar**, no en performance (§7.7)        |
| D13 | Entrada de audio         | Kairos abre **BlackHole 16ch directamente** (no el Aggregate Device) → numeración de canal estable. Etiqueta fiable `BlackHole 1–2`. Ruteo fijo de D5 intacto                                                                           |
| D14 | Rename (Grid + Level)    | El usuario puede renombrar **cada ciclo de Grid y cada window de Level** vía botón **Rename** (icono tag) a la **izquierda** del on/off. Nombre cosmético, persiste en presets; no altera el ruteo                                       |

---

## 1. Resumen y visión

Kairos es una **superficie de visualización pasiva** para directo y grabación del
grupo Slowpatch. En una sola pantalla reúne dos lecturas:

1. **Grid** — contador de compases multi‑ciclo: dónde está el sistema en el tiempo
   y cuándo cierran los ciclos.
2. **Level** — medidor de dinámica RMS (L/R) de hasta 4 buses: si la señal vive en
   una zona de volumen sana.

Ambas capas derivan de un **reloj único** (Internal, MIDI Clock o Ableton Link).
Cuando arranca el transporte, la app **se limita a visualizarse**: durante la toma
nadie la opera.

**Criterio de éxito:** que cualquier músico, a dos metros y de reojo, entienda en
un segundo dónde está el tiempo y si el nivel es sano.

---

## 2. Principios de producto (filtro de decisiones)

Toda feature debe pasar estos filtros; si los incumple, no entra.

- **Instrumento de escena, no panel de producción.** Si pide atención sostenida o
  lectura analítica, no pertenece aquí.
- **Anticipación antes que precisión.** Importa preparar la acción a tiempo, no
  medir al microsegundo.
- **Lectura periférica a dos metros.** Tamaños grandes, alto contraste, fondo
  oscuro, jerarquía estricta.
- **Cero interacción durante la toma.** Toda la configuración ocurre antes. (salvo en versión de iphone dónde se permite hacer drag entre vistas grid y level durante la performance por limitación de espacio en pantalla).
- **Un solo reloj.** Nunca dos sistemas temporales en conflicto.

---

## 3. Alcance

### 3.1 Dentro de v1 (macOS)

- App nativa macOS con render a medida.
- Reloj único con tres fuentes: Internal, MIDI Clock, Ableton Link.
- Grid: 1–4 ciclos configurables, estados, resets, anticipación, offset visual.
- Level: 1–4 lanes (buses) con RMS L/R, histórico, zonas, clip, marca de reset.
- Sidebar de configuración, top‑bar, presets locales.
- Metrónomo mínimo (D7).

### 3.2 Fase 2 (iOS: iPhone + iPad) — fuera de v1, ver Apéndice A

- App iOS como peer Link nativo. **iPhone y iPad** son ambos targets de pleno
  derecho (mismo rol: peer Link + consumidor de telemetría). El iPad tiene
  pantallas dedicadas en Figma (ver sistema de diseño).
- Canal propio Mac→iOS (Bonjour/mDNS + WebSocket) para telemetría de dinámica.
- Selector de fuente de dinámica, snapshot de histórico, modo debug, broadcast.

> **Requisito de v1 que habilita la fase 2:** el dominio temporal y el de dinámica
> se construyen desde el día 1 en un **Swift Package compartido** (`KairosCore`),
> sin dependencias de UI ni de plataforma, para que iOS lo reaproveche sin
> reescritura. Ver §4.

### 3.3 No‑objetivos

- No secuencia ni genera música (más allá del click del metrónomo).
- No es herramienta de producción ni de medición certificada.
- No adopta el sistema de diseño estándar de Apple.
- No persiste en la nube ni requiere internet.

---

## 4. Arquitectura de software

### 4.1 Mapa de módulos

```
┌─────────────────────────────────────────────────────────────┐
│ App target: Kairos (macOS)                                   │
│  ┌────────────────────────┐  ┌────────────────────────────┐  │
│  │ UI / Render layer       │  │ App services               │  │
│  │ - GridRenderer          │  │ - PresetStore (persistence)│  │
│  │ - LevelRenderer         │  │ - SettingsModel            │  │
│  │ - Sidebar / TopBar      │  │ - MetronomeEngine          │  │
│  │ (SwiftUI + Canvas/Metal)│  │                            │  │
│  └───────────┬────────────┘  └─────────────┬──────────────┘  │
│              │ observa estado               │                  │
└──────────────┼──────────────────────────────┼──────────────────┘
               │                               │
┌──────────────▼───────────────────────────────▼──────────────┐
│ Swift Package: KairosCore  (sin UI, testeable, multiplataforma)│
│  ┌──────────────────────┐    ┌────────────────────────────┐   │
│  │ TimeDomain            │    │ DynamicsCore               │   │
│  │ - ClockSource (proto) │    │ - AudioEngine (BlackHole)  │   │
│  │   · InternalClock     │    │ - RMS/Peak (vDSP)          │   │
│  │   · MIDIClock         │    │ - HistoryBuffer (per lane) │   │
│  │   · AbletonLinkClock  │    │ - ClipDetector             │   │
│  │ - CycleEngine         │    │ - LaneInputStatus          │   │
│  │ - ResetDetector       │    │ - DynamicsPublisher (proto)│   │
│  │ - Offset              │    │   · LocalConsumer (v1)     │   │
│  └──────────────────────┘    │   · NetworkBroadcaster(f2) │   │
│                              └────────────────────────────┘   │
└───────────────────────────────────────────────────────────────┘
```

### 4.2 Reglas de arquitectura

- **`KairosCore` no importa SwiftUI/AppKit/UIKit.** Solo Foundation, Accelerate,
  CoreMIDI, AVFAudio y el SDK de Link.
- **La lógica temporal es pura y testeable:** dado un `beat` (o `hostTime`), el
  `CycleEngine` produce el estado de cada ciclo de forma determinista, sin tocar
  render ni reloj de pared. Esto es testeable con tablas de entrada/salida.
- **El render no calcula posición temporal.** Pide al core el estado para el
  instante a pintar (ya con offset visual aplicado) y solo dibuja.
- **Aislamiento de la fuente de reloj:** el resto del sistema consume
  `ClockSource` sin saber si es Internal, MIDI o Link.
- **Costura de dinámica abstracta (seguro de fase 2 instalado en v1):** los valores
  de dinámica ya calculados (RMS/peak/clip/estado por lane) se publican a través de
  un interfaz `DynamicsPublisher`. En v1 el **único** consumidor es el render local
  (`LocalConsumer`); en fase 2 se añade un **segundo** consumidor, el
  `NetworkBroadcaster` (Bonjour/mDNS + WebSocket), **sin tocar** la ruta audio→dato.
  Esto convierte el broadcast móvil en una **adición**, no en cirugía. El camino
  audio→render **no** se cablea directo: pasa siempre por la costura.

### 4.3 Modelo de hilos

- **Hilo de audio (RT):** callback de `AVAudioEngine`. Cálculo de RMS/peak por
  bloque. **Cero allocations, cero locks.** Publica resultados a la UI por ring
  buffer lock‑free.
- **Hilo de render:** ~60 fps. Lee estado temporal (del clock) y el último valor
  de dinámica publicado. Dibuja.
- **Main:** UI de configuración, persistencia, gestión de dispositivos.
- **Reloj:** Link/MIDI corren en sus propios contextos; exponen estado consultable
  de forma thread‑safe (snapshot inmutable por frame).

---

## 5. Dominio temporal (reloj + grid)

### 5.1 Reloj único

Interfaz común consumida por las dos capas:

```
protocol ClockSource {
    /// Tempo actual en BPM.
    var tempo: Double { get }
    /// Posición musical continua en beats desde el origen de transporte.
    func beat(atHostTime: UInt64) -> Double
    /// ¿El transporte está corriendo?
    var isPlaying: Bool { get }
    /// Quantum/longitud de barra de referencia (beats). Link lo aporta; en
    /// Internal/MIDI se deriva de la métrica configurada.
    var quantum: Double { get }
    /// El origen (beat 0) está definido (transporte arrancado al menos una vez).
    var hasOrigin: Bool { get }
}
```

`beat(atHostTime:)` es la pieza central: todo el grid es función de este valor
(D2). Dos dispositivos con el mismo timeline producen la misma posición sin
comunicarse.

### 5.2 Las tres fuentes y el transporte

| Fuente | Origen del beat 0 (D6) | Tempo / Play | Reset |
|---|---|---|---|
| **Internal** | El **Play** de la app fija el origen | App es maestro: **BPM y Play activos** | Reinicia la cuenta (origen = ahora) |
| **MIDI Clock** | **MIDI Start / Song Position Pointer** entrante | Externo: **BPM y Play inertes** (visibles, deshabilitados) | Realineado visual local |
| **Ableton Link** | **Link start/stop** del maestro (Ableton por defecto) | Externo: **BPM y Play inertes** | Realineado visual local |

**Nota de diseño sobre el Reset en Link/MIDI:** el ancla compartida la define el
maestro de transporte (Ableton vía Link start/stop, o el secuenciador MIDI). El
botón **Reset** de la app, en estos modos, es un **realineado visual local** y no
emite transporte (no desincroniza a otros peers). Esto respeta "el Reset no rompe
la sincronía externa". En **Internal**, donde la app es maestro, el Reset sí
reinicia la cuenta porque el transporte es suyo.

**Ableton Link como maestro por defecto:** cuando hay Link, el tempo y el
transporte los manda Ableton. La app y (en fase 2) los iPhones son esclavos de
tempo y transporte. La opción de modificar tempo/play queda deshabilitada en estos
modos. Esto evita errores de grabación.

**Ausencia de peers no es error:** Link activo sin peers es un estado normal
(`Link active · no peers`). Nunca un modal por esto. (Relevante sobre todo en
fase 2; en v1 macOS el estado se muestra igualmente en la top‑bar/sidebar.)

### 5.3 Modelo de ciclos (Grid)

Conceptos: **reloj común**, **ciclo (cycle)**, **step**, **reset**.

- **Ciclos:** mínimo 1, **máximo 4**. En UI se llaman **Cycles**.
- **Step number:** valores discretos **1, 2, 4, 8, 16, 32, 64, 128**. (Máximo 128)
- **Pulse:** duración de cada step **en beats**. Valores: **1/16, 1/8, 1/4, 1/2,
  1, 2, 4, 8, 16, 32, 64**. Ejemplo: 16 steps × pulse 1/4 = 4 beats = 1 compás en
  4/4. Es decir, `stepDurationBeats = pulse`.
- **Longitud del ciclo en beats:** `cycleLengthBeats = stepNumber × pulse`.
- **Visual mode:** `block` (masa sólida, ciclos cortos/medios), `border` (stroke
  interior, visibilidad media), `line` (ligero, alta densidad; la línea coincide
  con el borde inicial del step).

#### 5.3.1 Cálculo de posición (determinista)

Para un `beat` dado (ya con offset visual aplicado, ver §5.6):

```
elapsedBeats   = beat - originBeat        // origin según D6/§5.2
stepFloat      = elapsedBeats / pulse
currentStep    = floor(stepFloat) mod stepNumber     // 0-based
cycleIteration = floor(stepFloat / stepNumber)
```

El avance es **cuantizado**: el step activo salta de uno a otro, no interpola. Se
debe percibir como tiempo de secuenciador.

- Todas las filas ocupan el **mismo ancho visual**: la longitud se traduce en
  densidad (4 steps se ven anchos; 128, finos).
- Lectura horizontal, izquierda → derecha.

### 5.4 Estados de step

- **Active:** step presente. Color claro.
- **Inactive:** steps pasados/futuros. Color oscuro.

### 5.5 Resets, coincidencias y anticipación

#### 5.5.1 Detección de reset

Un ciclo "resetea" en el frame en que `currentStep` vuelve a 0 (cambia de
iteración). Sobre los ciclos **activos**:

- **Reset combinado** (≥2 ciclos resetean a la vez, pero **no todos**): realce
  **verde** del primer step de los implicados. Coincidencia parcial.
- **Reset general** (**todos** los ciclos activos resetean a la vez): realce
  **morado** del primer step. Alineación total, máximo peso estructural.

Se pintan **sobre la propia barra**, nunca como icono o capa externa.

> Con D3 (config de grid independiente por dispositivo), el reset general se
> calcula **localmente** según los ciclos configurados en ese dispositivo. Como la
> fase de cada ciclo es función del reloj común, sigue siendo reproducible.

#### 5.5.2 Anticipación (realce rojo del tramo final)

El último tramo de cada ciclo se ilumina en **rojo** para señalar reinicio
inminente. Solo en ciclos de 8+ steps (en 1/2/4 se evita para no saturar):

| Step number | Steps finales en rojo |
| ----------- | --------------------- |
| 1           | —                     |
| 2           | —                     |
| 4           | —                     |
| 8           | último 1              |
| 16          | últimos 4             |
| 32          | últimos 4             |
| 64          | últimos 4             |
| 128         | últimos 8             |

### 5.6 Offset (calibración escénica) — D11

> Renombrado: antes "visual offset". Ya **no** es solo visual.

- Control global en **milisegundos, rango ±200 ms**.
- Es un **ajuste temporal local** que desplaza **dos salidas locales por la misma
  cantidad**:
  1. **Render** — el `beat` que se pasa al `CycleEngine` y el alineado del histórico
     de Level.
  2. **Clic del metrónomo** — el instante en que se programa cada click, **cuando el
     metrónomo está activo**.
  Al desplazarse ambos lo mismo, render y clic permanecen **mutuamente coherentes**.
- **Invariante:** el offset **nunca** modifica el reloj ni la sesión/fase Link. Solo
  afecta a lo que **este dispositivo** emite localmente. Es **por dispositivo** (en
  fase 2 cada iPhone/iPad tiene el suyo).
- En un dispositivo **sin clic** (p. ej. iPhone en fase 2) el offset es de facto
  solo‑visual; la definición no cambia: desplaza las salidas locales que existan.
- Compensa la latencia percibida entre Ableton, hardware externo, buffers y la
  pantalla.
- Conversión: `offsetBeats = (offsetMs / 1000) × (tempo / 60)`.

### 5.7 Casos límite a cubrir en tests

- Cambio de tempo en caliente (Link): la posición debe seguir siendo continua.
- Transporte detenido (`isPlaying == false`): el grid se congela en su última
  posición, no se resetea solo.
- `hasOrigin == false` (Link activo sin start aún): estado neutro, sin pintar
  posición arbitraria.
- Ciclo recién activado a mitad de toma: se incorpora con su fase correcta
  (determinista), no desde 0.
- Pérdida de reloj externo: ver §11.

---

## 6. Capa Grid — render y comportamiento

- Ocupa la **parte superior** (zona dominante salvo que el panel esté desactivado).
- Panel **opcional**: toggle on/off lo añade/quita del área de visualización.
- Solo se ven los ciclos **activos**. La info y controles de cada ciclo viven en
  el sidebar.
- Render eficiente para 128 celdas (Canvas optimizado o Metal). El **modo línea**
  y una rejilla sutil resuelven la alta densidad. Punto de rendimiento a vigilar
  (§11).
- Mapa de color semántico (consistente en toda la app):
  - Claro = activo · oscuro = inactivo
  - **Verde** = reset combinado · **Morado** = reset general · **Rojo** = anticipación

---

## 7. Capa Level — audio y render

### 7.1 Motor de audio

- Entrada vía **BlackHole (16 ch)**. El **Aggregate Device** se usa solo del lado de
  la **salida de Ableton** (para que envíe a BlackHole sin perder su monitorización),
  documentado en guía de setup (§12.3).
- **La app abre el dispositivo BlackHole 16ch DIRECTAMENTE** con `AVAudioEngine`, **no
  el Aggregate Device** (D13). Razón: la numeración de canal del agregado depende del
  orden de los dispositivos que lo componen; leyendo BlackHole directo, los índices de
  canal son **estables y deterministas** y el mapeo de D5 (ch 1‑8) es fiable pase lo
  que pase con el agregado. Esto además elimina una de las fuentes del fallo silencioso
  de ruteo (ver §7.7).
- **Mapeo fijo de lanes (D5):**

| Lane   | Canales BlackHole |
| ------ | ----------------- |
| Lane 1 | 1 – 2 (L/R)       |
| Lane 2 | 3 – 4 (L/R)       |
| Lane 3 | 5 – 6 (L/R)       |
| Lane 4 | 7 – 8 (L/R)       |

- Cada lane se alimenta de un bus estéreo enviado desde Ableton. El **par de canales
  es fijo** (D5). El nombre del window es **personalizable** vía Rename (D14, §8.2/§8.3);
  por defecto es genérico (p. ej. "Source 1"). La app **no** puede derivar ni la app de
  origen ("Ableton") ni la numeración interna de Ableton — solo conoce su propio
  dispositivo y sus índices de canal, que muestra como caption de Input Status (§7.7).

### 7.2 Medición

- **Métrica núcleo: RMS** por canal (L y R **por separado**, nunca suma cruda).
  Justificación: la suma cruda desplaza la referencia ~3 dB según la imagen
  estéreo y oculta un canal pegado a 0 dB. El cálculo se apoya en **vDSP/Accelerate**
  (`vDSP_rmsqv`).
- **Ventana de integración:** estilo VU, **300 ms** (confirmado, §15.3; tunable
  250–400 ms). Se acorta respecto al ~1 s del documento original porque 1 s se
  percibe lento como lectura "viva". El histórico (§7.5) aporta la tendencia lenta.
- **Clip:** detección directa de **pico real** por canal (`vDSP_maxmgv`); una
  muestra > 0 dBFS dispara la alerta.

### 7.3 Escala (regla fija)

- Eje **lineal en dB, de 0 a −60 dB**. Sin autoescalado, sin curva: −18, −12, −24
  son lugares reconocibles fijos.
- Distancia en pantalla proporcional a diferencia en dB.

### 7.4 Target y zonas

- **Target level:** threshold móvil, default **−12 dB**, **por lane** (cada
  medidor el suyo). No es frontera bien/mal: es referencia de cuánto se está por
  encima/debajo del objetivo.
- **Zonas de referencia** (bandas pintadas en las áreas importantes):

| Zona | Rango | Lectura |
|---|---|---|
| Crítica superior | 0 a −6 dB | Muy alta, margen reducido |
| Fuerte controlada | −6 a −12 dB | Intensa pero utilizable |
| Cómoda de grabación | −12 a −24 dB | Área principal |
| Baja utilizable | −24 a −30 dB | Aprovechable según contexto |
| Residual | −30 a −60 dB | Colas, ruido, silencio |

### 7.5 Visualización

Lectura por **masa visual**, no línea fina. Dos masas, **L y R**, sobre la escala
fija. Dos lecturas en dos dimensiones que no compiten:

- **Nivel actual:** dónde está la señal ahora (las dos masas).
- **Histórico reciente:** silueta del pasado próximo = hacia dónde se mueve la
  energía. Es pieza central. **History range por lane**, seleccionable entre
  **10 s, 30 s, 1 min, 2 min**. En ventanas cortas se dibuja con detalle; en
  largas se aplica **agregación por columnas** (cada columna: mínimo, máximo,
  media), lo que es más legible y más barato.

> **Nomenclatura:** lo que el documento original llamaba "windows" eran en
> realidad **lanes/medidores** (uno por bus, D1). El valor temporal 10 s/30 s/…
> es el parámetro **history range** de cada lane, no su identidad. En UI se
> denominan **Sources** (Source 1–4).

#### 7.5.1 Relleno, borde y color

- **Relleno** de cada masa: **siempre gris**. Aporta cuerpo/forma, no estado.
- **Borde superior:** lleva el **color semántico** — **verde** dentro de la banda
  de comodidad (±6 dB del target), **rojo** al salirse por arriba o por abajo.
  Margen, histéresis (1.5 dB) y crossfade (~200 ms) están especificados en §15.2.
- Hay **dos bordes** (uno por canal), color independiente. Cuando L y R están
  equilibrados se solapan y se leen como uno; al desequilibrarse, uno verde y otro
  rojo delata qué canal se salió.

#### 7.5.2 Saturación (clip)

- Al superar 0 dBFS en una onda, su **relleno** (normalmente gris) se vuelve
  **rojo**. No cambia el borde: relleno y borde son canales separados, conviven
  sin ambigüedad.
- El rojo **permanece con cola de ~2 s** y se desvanece, para que un clip fugaz se
  vea. Solo se enrojece el relleno del canal que saturó. **Sin peak hold.**

#### 7.5.3 Marca de reset general

- En el instante en que **todos los ciclos** resetean a la vez, se dibuja una
  **marca morada** sobre el eje temporal del histórico.
- La marca se **ancla a ese instante y avanza hacia la izquierda** con el
  histórico, conservando correspondencia con la silueta.
- Baja prominencia (acompaña, no compite). **Solo** el reset general; los
  combinados no aparecen en el medidor.

### 7.6 Coste y riesgo

- Se almacenan **valores de RMS ya calculados** (no audio crudo): unos miles para
  2 min. Memoria despreciable. El único cuidado es el dibujo en ventanas largas,
  resuelto con agregación por columnas.

### 7.7 Input Status (estado de señal por lane) — D12/D13

Cada lane informa de **qué entrada tiene y en qué estado está**, para cazar ruteos
erróneos **antes** de tocar. El mapeo es fijo (D5) y la app pinta fielmente lo que
llega; sin esta capa, una lane puede mostrar **silencio** (bus no ruteado) o **el bus
equivocado** sin avisar, y se toman decisiones de gain staging sobre datos malos.

#### 7.7.1 Qué puede mostrar la app (feasibility)

- **Sí, fiable:** el **dispositivo** de entrada (nombre vía CoreAudio, p. ej.
  `BlackHole 16ch`), el **par de canales** que lee la lane (constante por D5/D13) y el
  **estado de señal** (derivado del RMS ya calculado).
- **No derivable (no afirmar):** que la señal "viene de Ableton" (cualquier cliente
  puede escribir en BlackHole) ni los **números internos de Ableton** ("14‑15"), que
  viven en otro espacio de numeración (el del Aggregate Device). Esa semántica de
  usuario se cubre con el **nombre del window** (Rename, D14), no con el caption.
- El **caption** muestra solo el canal honesto: `BlackHole 1–2`. El **nombre** del
  window (arriba) es el que el usuario personaliza (p. ej. "Drums", "FX").

#### 7.7.2 Modelo de estados (`LaneSignalState`)

| Estado | Condición | Significado | Dot | Texto |
|---|---|---|---|---|
| `disabled` | Lane apagada (toggle off) | No se pinta; en sidebar, fila colapsada | — (lo dice el toggle) | — |
| `noSignal` | Activa; `max(RMS_L, RMS_R) ≤ −60 dB` ≥ **2 s** | Cableada pero no llega nada: ruteo ausente/erróneo o bus en silencio | Blanco | `No signal` |
| `receiving` | Activa; nivel `> −60 dB`, sin clip | Recibiendo señal sana | Verde | canal BlackHole (`BlackHole 1–2`) |
| `clipping` | Activa; pico `> 0 dBFS` en los últimos **2 s** (cola de §7.5.2) | Saturación/problema | Rojo | `Clipping` |

> El texto del caption es **dependiente del estado**: el canal solo se muestra en
> `receiving`; en `noSignal`/`clipping` se sustituye por la palabra de estado. Componente
> Figma: `input-status` (= `icon/dot-status` + label).

- **Frontera en el suelo de la escala (−60 dB)**, coherente con la zona "Residual"
  (§7.4). **Debounce** (≥ 2 s por debajo) para volver a `noSignal`, de modo que un bus
  genuinamente bajo (un pad a −50) lea `receiving`. `clipping` **prevalece** sobre el
  color mientras dure su cola de 2 s.
- Estado interno barato en `DynamicsCore` (`LaneInputStatus`), umbral sobre datos ya
  calculados; no es audio nuevo.

#### 7.7.3 Tokens de color (calibrar en Figma)

- `color/kairos/lane-status-idle` → **blanco** (`noSignal`)
- `color/kairos/lane-status-active` → verde (`receiving`)
- reutilizar `color/kairos/clip` → rojo (`clipping`)

Tres estados de dot (sin ámbar: lo "caliente" ya lo cuenta el borde del medidor, §15.2).

#### 7.7.4 Dónde y cómo se muestra — **solo sidebar**

- **Sidebar (LEVEL), bajo el nombre de cada window — único hogar:** el componente
  **`input-status`** (= `icon/dot-status` + label) justo debajo del título.
  Actualización a baja frecuencia (2–4 Hz basta). Es la confirmación de ruteo
  **pre‑vuelo**, antes de la toma.
- **Panel Level (performance): NO se muestra.** Se descarta el caption bajo los
  medidores para no añadir información innecesaria durante la actuación. La ausencia de
  señal ya se percibe por el medidor plano y el `clipping` por su relleno rojo (§7.5.2).

---

## 8. Sidebar de configuración

Panel lateral desplegable. Toda la configuración ocurre **antes** de tocar.

### 8.1 GLOBAL

> El selector de **Preset** ya **no vive aquí**: se ha movido a la top‑bar (D9, ver §9).
> El sidebar GLOBAL contiene Sync y Tempo.

**Sync**
- Selector de fuente de tres posiciones: **Internal · MIDI Clock · Link**.
- MIDI: desplegable de puertos/interfaces detectadas + estado de MIDI clock.
- Link: indicador de estado (`Link off` / `Link active · no peers` /
  `Link active · N peers · BPM`). **No** es un selector de dispositivo: es un
  toggle de estado. Sin modal por ausencia de peers.
- **Offset:** selector ±200 ms (D11; afecta a render **y** clic del metrónomo).

**Tempo**
- **BPM:** rango **1–999**. Activo solo en Internal; inerte (visible) en
  MIDI/Link.
- **Metronome pulse:** rango **1/16 – 1**.
- *(El upload de sample del original queda fuera por D7: click interno fijo.)*

### 8.2 GRID

- Toggle on/off del panel de grid.
- 4 ciclos (**Cycles**), apagados por defecto. Cada ciclo tiene en su cabecera, de
  izquierda a derecha: **botón Rename** (`icon/rename`, D14) · **toggle on/off** (power).
  El nombre por defecto es genérico ("Cycle 1"…) y se personaliza con Rename.
- Al activar un ciclo, despliega sus parámetros: **Step number**, **Cycle Pulse**,
  **Visual mode**.

### 8.3 LEVEL

- Toggle on/off del panel de level.
- 4 windows (**Sources**), apagados por defecto. Cada window tiene en su cabecera, de
  izquierda a derecha: **botón Rename** (`icon/rename`, D14) · **toggle on/off** (power).
  Bajo el nombre, el **caption de Input Status**: **dot** (blanco/verde/rojo) + texto
  del canal `BlackHole 1–2` (§7.7).
- Al activar un window, despliega:
  - **Target level** — threshold de la lane.
  - **History range** — 10 s / 30 s / 1 min / 2 min.
  - *(`share data` → fase 2. **Retirada de las pantallas v1**: oculta, no se muestra
    hasta fase 2.)*

---

## 9. Top‑bar

Barra superior omnipresente. Doble función:

- **Control general (de izquierda a derecha):**
  1. **Preset** — **primer botón** (D9). Muestra el nombre del preset activo; al
     pulsarlo despliega la selección de presets (cambiar / guardar, ver §10).
  2. Plegar/desplegar sidebar.
  3. **Play** (inerte en MIDI/Link).
  4. **Reset** (siempre disponible, semántica de §5.2).
  5. Metrónomo on/off.
- **Estado:** fuente de sync y su estado · BPM · tiempo transcurrido desde Play
  (`Xh Xm Xs`, la "h" no aparece hasta que se pasa del minuto 59).

---

## 10. Persistencia (presets)

- Guarda/carga: ciclos y sus parámetros, lanes (target, history range), **nombres
  personalizados** de ciclos y windows (Rename, D14), offset, fuente de sync, ajustes
  de tempo/metrónomo.
- **5 presets**: 1 default + 4 personalizables. El **botón de preset de la top‑bar**
  (D9) muestra el nombre del preset activo y, al pulsarlo, despliega cambiar y guardar.
- Almacenamiento **local dentro de la app** (Application Support), serialización
  Codable. No se elige directorio. Sin nube.

---

## 11. Requisitos no funcionales

- **Legibilidad:** alto contraste, fondo oscuro, jerarquía clara, poca densidad
  textual.
- **Estabilidad en directo > riqueza de funciones.** Arranque fiable, sin saltos
  perceptibles.
- **Fluidez de render** estable incluso con ciclos de 64/128 steps.
- **Separación lógica temporal / UI** (§4): el cálculo de posición, resets,
  coincidencias y distancia al próximo evento se testea sin UI.
- **Abstracción del reloj** desde el inicio.
- **Render a medida**: no se adopta el sistema de diseño de Apple.
- **Degradación ante pérdida de reloj:**
  - Internal: la app es maestro, no aplica pérdida externa.
  - MIDI/Link perdido: el grid se **congela** y se muestra el estado de
    desconexión; no se inventa posición. Decisión de producto sobre fallback a
    Internal: **no automático** en v1 (evita sorpresas en directo); el usuario
    cambia de fuente manualmente.

---

## 12. Distribución y empaquetado

### 12.1 Vía (D8) — uso privado, no comercial

Kairos es una herramienta **privada** (el autor + el grupo), no se distribuye al
público ni va a App Store. Esto relaja casi todos los *gates* administrativos:

- **App Store / revisión:** fuera por completo (macOS y iOS). Sin App Review.
- **macOS:** **firma local/ad‑hoc** basta para correr en los Macs propios. La
  **notarización es opcional** (solo comodidad para instalar en los Macs de los
  compañeros sin fricción de Gatekeeper). No bloqueante.
- **iOS/iPad (fase 2):** único *gate* residual. Firmar es obligatorio para instalar en
  dispositivos físicos; lo práctico es una **cuenta de desarrollador de pago
  (~99 €/año)** por los perfiles de provisión de **1 año** + instalación ad‑hoc (el
  Apple ID gratuito caduca a los 7 días, inviable en directo). **Sin revisión.**
- **Ableton Link (licencia):** sin restricción para este caso. No hay *gate* técnico
  (el SDK compila/corre sin registrar nada) ni necesidad de aprobación/registro de
  Ableton. El código es **GPLv2+**; la obligación de copyleft se satisface dando el
  **código fuente a los compañeros** junto al binario. Registrar la app con Ableton
  solo haría falta si fuera comercial o usara el badge oficial.
- **Sin sandbox**: acceso libre a BlackHole y, en fase 2, a la red local sin las
  fricciones del entorno sandboxed.

### 12.2 Targets y dependencias

- macOS nativo (Swift + SwiftUI; Canvas/Metal para el render a medida).
- Dependencias: **Accelerate** (vDSP), **AVFAudio**, **CoreMIDI**, **Ableton Link
  SDK** (LinkKit / API C `abl_link`).
- **Deployment target: macOS 14.0 Sonoma** (ver §15.1).

### 12.3 Setup del usuario (documentar como guía breve)

- Instalar BlackHole 16ch.
- Crear Aggregate Device que combine la salida real + BlackHole.
- En Ableton, enviar de 1 a 4 buses a los pares de canales de BlackHole según el
  mapeo de §7.1.
- Activar Link en Ableton para sincronía.

---

## 13. Riesgos y mitigaciones

| Riesgo | Severidad | Mitigación |
|---|---|---|
| Render de 128 celdas / 4 ciclos a 60 fps | Media | Canvas optimizado o Metal; modo línea; dibujo por dirty‑region |
| Integración Ableton Link en Swift | Baja‑media | SDK maduro y orientado a Apple; aislar tras `ClockSource` |
| **Determinismo cross‑device (D2) en ciclos largos** | **Alta** | Link garantiza fase dentro del quantum (~1 compás); los ciclos de 64/128 steps abarcan muchos compases y requieren origen+iteración compartidos. **Spike bloqueante de Link multi‑peer** que valide la alineación antes de **congelar el contrato de `TimeDomain`** (fase 0 del roadmap) |
| Mapeo de canales BlackHole mal configurado por el usuario | Media | Leer **BlackHole directo** (D13, numeración estable) + **Input Status** por lane (§7.7): dot + etiqueta en sidebar (pre‑vuelo) y caption en el panel |
| Ventana RMS que se siente lenta | Baja | 300 ms por defecto, tunable; histórico para la tendencia |
| Origen/"1" incoherente entre arranques | Media | Anclaje al transporte (D6), determinista y testeable |
| Acoplar UI y lógica temporal | Media | `KairosCore` sin UI desde el día 1 (habilita además fase 2) |
| Retrofit del broadcast móvil (fase 2) | Media | Costura `DynamicsPublisher` desde el día 1 (§4.2): el render local es un consumidor, el broadcaster otro; adición, no cirugía |

---

## 14. Glosario y nomenclatura

| Término             | Significado                                                               |
| ------------------- | ------------------------------------------------------------------------- |
| **Cycle**           | Canal temporal del Grid. 1–4.                                             |
| **Steps**           | Unidad discreta de un ciclo. 1–128 por ciclo.                             |
| **Pulse**           | Duración de un step en beats (1/16…64).                                   |
| **Mode**            | block / border / line.                                                    |
| **Source (lane)**   | Medidor de Level asociado a un bus estéreo. 1–4. (Antes "window".)        |
| **History range**   | Ventana temporal del histórico de una Source (10 s…2 min).                |
| **Target level**    | Threshold de referencia de una Source (default −12 dB).                   |
| **Offset**          | Ajuste temporal local ±200 ms, por dispositivo; desplaza render **y** clic. Antes "visual offset". (Sin. "Grid offset", "delay".) |
| **Reset combinado** | ≥2 ciclos resetean a la vez (no todos). Verde.                            |
| **Reset general**   | Todos los ciclos resetean a la vez. Morado.                               |
| **Clip**            | Pico > 0 dBFS. Relleno rojo, cola 2 s.                                    |
| **Input Status**    | Estado de señal por window: dot blanco/verde/rojo + canal BlackHole. Solo sidebar (§7.7). |
| **Rename**          | Nombre personalizable de un ciclo de Grid o un window de Level (D14). Cosmético, no toca el ruteo. |

Convención de marca: en UI escribir **"Link"** (los diseños muestran "Linc", es
una errata a corregir).

---

## 15. Constantes y parámetros cerrados

Antes "decisiones abiertas". Resueltas; quedan como constantes del proyecto
(tunables salvo indicación). Valores por defecto a usar en implementación.

### 15.1 Versión mínima de macOS — **macOS 14 Sonoma**

Razonamiento: nada en la app exige macOS 15. macOS 14 ya aporta el toolchain
moderno completo (framework **Observation** / `@Observable`, macros de Swift 5.9,
SwiftUI Canvas maduro), que es justo lo que conviene para el modelo de estado y el
render. Fijar 14 es "moderno sin restricción arbitraria": no condiciona el
desarrollo y deja un pequeño margen de compatibilidad. Subirlo a 15 (Sequoia, la
versión del autor) es trivial y no rompe nada, pero no aporta ventaja técnica para
este producto. **Decisión: deployment target macOS 14.0.**

### 15.2 Borde rojo: margen, histéresis y crossfade

El borde de cada canal es **verde** dentro de la banda de comodidad y **rojo** al
salirse, por arriba o por abajo del target.

- **Margen: ±6 dB simétrico** respecto al target. Con target −12 dB → verde en
  −18…−6 dB, que coincide casi exacto con las zonas "cómoda" + "fuerte controlada"
  (§7.4). Coherente visual y musicalmente.
- **Histéresis: 1.5 dB.** Pasa a rojo cuando `|nivel − target| > 6.0`; vuelve a
  verde cuando `|nivel − target| < 4.5`. Evita parpadeo en el límite.
- **Crossfade de color: ~200 ms** entre verde y rojo (transición suave, no salto).
- *Nota:* el peligro real de "demasiado alto" lo cubre el **clip** (relleno rojo,
  §7.5.2), que es un canal aparte; por eso el margen del borde puede ser simétrico
  sin infra‑avisar lo caliente. Si en uso se viera necesario, se puede pasar a
  asimétrico (p. ej. +4 / −6) sin cambios estructurales.

### 15.3 Ventana de integración RMS — **300 ms** (confirmado)

300 ms es el equilibrio correcto: lo bastante corto para sentirse "vivo" como
lectura actual, lo bastante largo para no reaccionar nervioso a cada transitorio.
La tendencia lenta ya la da el histórico (§7.5). Rango aceptable 250–400 ms; se
deja como constante tunable, default **300 ms**.

### 15.4 Click del metrónomo

- **Sample empaquetado con la app** (no upload de usuario, coherente con D7):
  **mono, 44.1 kHz, 16 bit**, muy corto (**< 100 ms**), normalizado. Ligero y
  estable.
- **Reproducción:** `AVAudioEngine` de **salida dedicado** (separado del engine de
  entrada de BlackHole) con un `AVAudioPlayerNode`. El buffer del click se
  **precarga una vez** en un `AVAudioPCMBuffer`; los disparos se **programan de
  forma sample‑accurate** contra el mapeo de tiempo del reloj (no con un timer de
  UI), para que el click caiga rítmicamente firme.
- **Volumen:** el engine se rutea a la **salida del sistema por defecto**, de modo
  que el volumen del click **sigue directamente al volumen del dispositivo** (subir
  o bajar el volumen del sistema lo afecta de inmediato). Sin control de volumen
  propio en v1.
- **Subdivisión:** la determina el selector **Metronome pulse** (1/16 – 1, §8.1).
- **Offset:** el disparo del click se programa contra el mapa de tiempo **ya
  desplazado por el Offset** (D11/§5.6), de modo que click y grid caen alineados.

### 15.5 Valores del selector de Pulse — **confirmado**

Set expuesto en UI, de 1/16 a 64: **1/16, 1/8, 1/4, 1/2, 1, 2, 4, 8, 16, 32, 64**
(ya fijado en §5.3).

---

## Apéndice A — Fase 2: evolución a iOS (iPhone + iPad) (resumen accionable)

> Fuera de v1. Se documenta para que la arquitectura de v1 no cierre puertas.
> Detalle completo en `mobile-evo.md`.

**Principio rector:** *Link para el reloj; canal propio para la dinámica.*

- **Sincronía:** cada **iPhone/iPad** es **peer Link nativo** (LinkKit). No depende
  del Mac para el tempo. Tempo y transporte **read‑only por defecto** (Ableton maestro).
- **Config de grid:** **independiente por dispositivo** (D3). Link no transporta la
  definición de ciclos; cada móvil configura los suyos. El timeline común garantiza
  que ciclos iguales salgan alineados.
- **Layout y excepción de interacción (D10):** por limitación de espacio —sobre
  todo en **horizontal**— Grid y Level **no caben cómodamente a la vez**. En iPhone
  cada vista ocupa una **pantalla independiente** y el usuario alterna con un gesto
  de **drag**. Es la única interacción permitida durante la performance, y solo en
  móvil; no altera el principio de "cero interacción" en desktop. La sincronía no
  se ve afectada: ambas vistas siguen derivando del mismo reloj y se renderizan
  localmente.
- **Dinámica:** canal propio **Bonjour/mDNS** (descubrimiento) + **WebSocket**
  (streaming) desde el Mac. Telemetría **por lane**.
- **Paquete de dinámica:** incluye `sourceId`, `sequence`, timestamp de host,
  `linkBeat`, `tempo`, `rmsDb`, `peakDb`, `clipping`, `windowMs`, `sampleRate`.
- **Frescura > exhaustividad:** valor actual = paquete más reciente; descartar
  paquetes viejos; histórico se inserta por timestamp. Snapshot inicial al
  conectar. Frecuencia 10–30 Hz.
- **Objetivo de latencia:** edad del dato < 200–300 ms. Modo debug para medir
  latencia, edad, colas, peers.
- **Estados claros, sin modales falsos:** "no peers" no es error; sí lo son
  permiso de red local denegado, red no disponible, firewall, fuente de dinámica
  perdida.
- **Control en el Mac:** `Level broadcast on/off` global + nº de dispositivos
  conectados. (Reemplaza el `share data` per‑lane del original como master switch;
  la selección de qué lanes emitir se decide en el diseño de fase 2.)
- **Permisos iOS:** red local (iOS 14+), posible multicast entitlement (verificar
  con Bonjour/mDNS).
- **Degradación:** Link y dinámica son independientes; si cae una, la otra sigue.

**Referencias:** Ableton Link (https://ableton.github.io/link/), LinkKit iOS
(https://ableton.github.io/linkkit/), Apple Local Network Privacy
(TN3179), Apple Bonjour (https://developer.apple.com/bonjour/).
