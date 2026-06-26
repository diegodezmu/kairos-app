> ⚠️ PARCIALMENTE DESACTUALIZADO. Describe decisiones ya superadas (BlackHole, iOS/móvil).
> Fuente de verdad = el código y `PLAN-AUDITORIA-V1.md`; ver `docs/decisiones-descartadas.md`.

# Kairos — Roadmap de desarrollo (ejecución por agentes Codex)

> Plan de ejecución operativo. Convierte el PRD (`kairos-prd-tecnico.md`) y el sistema
> de diseño (`kairos-design-system.md`) en **tareas discretas, asignables a agentes
> Codex**, con contrato, dependencias y criterios de aceptación verificables.
>
> - **Fuente de verdad funcional:** `kairos-prd-tecnico.md` (decisiones D1–D14).
> - **Fuente de verdad visual:** Figma + `kairos-design-system.md`.
> - **Este documento manda sobre el *orden y la forma* de construir, no sobre la
>   función** (esa la fija el PRD).

---

## 0. Cómo se ejecuta este roadmap

Todo el desarrollo lo realizan **agentes Codex**, uno por tarea. El roadmap está
diseñado para ese flujo: tareas pequeñas, con entrada/salida explícita, verificables
de forma autónoma por el propio agente, y con un seam de integración de **único dueño**
para lo que no se puede paralelizar.

### 0.1 Plantilla de tarea (todas las tareas siguen este formato)

```
ID:            F<fase>-<código>
Título:        <verbo + objeto>
Depende de:    <IDs que deben estar DONE antes> (o "—")
Paraleliza con:<IDs que pueden correr a la vez>
Entradas:      <secciones del PRD, nodos Figma, archivos del repo>
Entregable:    <archivos/módulos concretos que produce>
Latitud:       <qué puede decidir el agente / qué NO puede tocar>
Aceptación:    <criterios objetivos y testeables — "definition of done">
Verificación:  <comando(s) exactos que el agente ejecuta para autoverificarse>
```

### 0.2 Reglas de ejecución agentic (aplican a TODAS las tareas)

1. **Contract-first.** Ninguna implementación empieza hasta que su **contrato**
   (protocolos, tipos, firmas + tablas de test) esté **congelado** (tarea de freeze).
   Un agente que necesite cambiar un contrato congelado **no lo edita**: abre una tarea
   `CONTRACT-CHANGE` y para.
2. **Test-first donde la lógica es pura.** En `KairosCore` el agente escribe primero las
   **tablas de test** (entrada→salida esperada) derivadas del PRD, luego implementa hasta
   que pasan. Las tablas son el criterio de aceptación, no un extra.
3. **Diff acotado.** Cada tarea toca solo los archivos de su `Entregable`. Si descubre
   trabajo fuera de alcance, lo **anota** (no lo hace) y lo reporta.
4. **`KairosCore` sin UI, multiplataforma.** Cero `import SwiftUI/AppKit/UIKit`. Debe
   compilar para macOS **y** iOS desde el día 1. Verificación incluye build para ambos.
5. **Seams de único dueño.** El hilo de audio RT, el wiring de relojes reales y la
   costura lock-free los toca **una sola tarea/seam owner** (F1-INT). El resto trabaja
   contra **stubs** del contrato.
6. **Fidelidad de diseño = bind por significado.** Las tareas de UI vinculan a tokens y
   text styles reales; si el resultado difiere del original, se **marca como "calibration
   mismatch"** (no se hardcodea, no se recalibra: lo calibra el diseñador). Si falta token,
   se marca "token gap".
7. **Definition of Done común:** compila sin warnings nuevos · tests verdes · diff acotado
   · sin imports prohibidos · `Verificación` reproducible · contratos congelados intactos.

### 0.3 Convenciones de repo (las fija F1-00; las usan todas)

- **Comando de test del core:** `swift test --package-path KairosCore`
- **Build app macOS:** `xcodebuild -scheme Kairos -destination 'platform=macOS' build`
- **Build core para iOS (garantía multiplataforma):**
  `swift build --package-path KairosCore` con plataformas declaradas; CI corre ambos.
- **Una rama por tarea**, nombre = ID. Commits pequeños. PR con el bloque de `Aceptación`
  marcado.

---

## 1. Mapa de fases y dependencias

```
FASE 0 — Seguros y validación (BLOQUEANTE)
  F1-00 Scaffolding ──┐
  F0-1 Spike Link  ───┼──► gate: NO se congela TimeDomain sin F0-1
  F0-2 Spike render ──┤
  F0-3 Spike audio I/O┤
  F0-4 Smoke Link SDK ┘

FASE 1 — macOS v1
  F1-SPEC (contratos + tablas) ──► [FREEZE] ──┬─► F1-TD  TimeDomain      ┐
                                              ├─► F1-DC  DynamicsCore     │ (paralelo)
                                              ├─► F1-RG  Render Grid      │
                                              ├─► F1-RL  Render Level     │
                                              ├─► F1-AS  App services     │
                                              └─► F1-UI  UI shell         ┘
                                                        │
                          F1-INT  Integración (ÚNICO DUEÑO) ◄── todas las anteriores
                                                        │
                                              F1-QA  Aceptación + QA visual

FASE 2 — iOS (iPhone + iPad)
  F2-SPEC telemetría ─► F2-BC Broadcaster(Mac) ─┐
                        F2-IOS-00 scaffold iOS ──┼─► F2-LINK ─► F2-CLIENT ─► F2-UI ─► F2-QA
                                                 └─► F2-PERMS, F2-DEBUG
```

Regla de oro: **la arquitectura completa ya está decidida** (D1–D14 + `DynamicsPublisher`).
Lo que se secuencia es la *implementación del producto*, no la arquitectura.

---

## 2. FASE 0 — Seguros y validación (bloqueante)

Objetivo: eliminar las dos incógnitas que, si se descubren tarde, obligan a rehacer
arquitectura (R1, render), y dejar el esqueleto listo. **No se entra en Fase 1 sin cerrar
F0-1.**

### F1-00 — Scaffolding del proyecto
```
Depende de:    —
Paraleliza con:F0-2, F0-4
Entradas:      PRD §4, §12; §0.3 de este doc
Entregable:    Xcode workspace `Kairos`; app target macOS `Kairos`; Swift Package
               `KairosCore` (plataformas macOS 14 + iOS declaradas); test target
               `KairosCoreTests`; README de build; scripts/comandos de §0.3.
Latitud:       Estructura de carpetas y nombres internos. NO decide arquitectura de
               módulos (ya fijada en PRD §4.1).
Aceptación:    - `swift test --package-path KairosCore` corre (aunque sea 1 test dummy).
               - `xcodebuild -scheme Kairos build` compila app vacía.
               - `KairosCore` compila para macOS y para iOS.
               - `KairosCore` no importa SwiftUI/AppKit/UIKit (test de guardia que falle
                 si aparece el import).
Verificación:  los tres comandos de §0.3 + grep de imports prohibidos.
```

### F0-1 — Spike: determinismo de Ableton Link multi-peer  ⛔ GATE
```
Depende de:    F1-00
Paraleliza con:F0-2, F0-3, F0-4
Entradas:      PRD §5.1, §5.2 (D2/D6), §5.7; mobile-evo.md
Entregable:    spike desechable (no de producción) + `docs/spikes/link-determinism.md`
               con conclusiones.
Objetivo:      validar que dos peers Link calculan la MISMA posición de grid para ciclos
               LARGOS (64/128 steps = varios compases), no solo dentro del quantum.
               Confirmar: (a) anclaje de `originBeat` al start de transporte (D6),
               (b) que un peer que entra a mitad lee un beat absoluto consistente,
               (c) papel de start/stop sync y del quantum.
Latitud:       El agente elige cómo simular dos peers (dos procesos / Link + Ableton).
               NO escribe código de producción de `AbletonLinkClock` aquí.
Aceptación:    - Documento que responde SÍ/NO a "ciclos largos alineados entre peers" con
                 evidencia (logs/medidas).
               - Si NO: propone el ajuste exacto del contrato de `TimeDomain` (cómo se
                 define `originBeat`/`hasOrigin`) ANTES de F1-SPEC.
Verificación:  reproducible siguiendo el README del spike.
GATE:          F1-SPEC no congela el contrato de TimeDomain hasta que esta tarea esté DONE.
```

### F0-2 — Spike: rendimiento de render (Canvas vs Metal)
```
Depende de:    F1-00
Entradas:      PRD §6, §11, §13 (riesgo render 128×4)
Entregable:    micro-benchmark + `docs/spikes/render-perf.md` con decisión.
Objetivo:      decidir la tecnología del renderer (SwiftUI Canvas vs Metal) dibujando
               128 celdas × 4 ciclos a 60 fps de forma estable.
Aceptación:    - Medida de fps/coste con 4 ciclos de 128 steps en modo `line`.
               - Decisión escrita: Canvas o Metal, y la **forma de la API del renderer**
                 que se asume en F1-RG/F1-RL.
Verificación:  benchmark reproducible.
```

### F0-3 — Spike: entrada de audio BlackHole + RMS RT
```
Depende de:    F1-00
Entradas:      PRD §7.1, §7.2, §4.3 (D13)
Entregable:    spike + `docs/spikes/audio-io.md`.
Objetivo:      abrir **BlackHole 16ch directamente** con `AVAudioEngine`, leer 8 canales,
               calcular RMS L/R por lane con vDSP en el callback RT, publicar por ring
               buffer lock-free. Valida D13 y el modelo de hilos (§4.3).
Aceptación:    - Lee canales 1–8 de BlackHole directo (no aggregate).
               - RMS por canal coherente con señal de prueba conocida (tolerancia ±0.5 dB).
               - Callback RT sin allocations/locks (verificado con instrumentación).
Verificación:  spike + comprobación con Thread Sanitizer / instrumento de audio.
```

### F0-4 — Smoke: integración del SDK de Link en Swift
```
Depende de:    F1-00
Entradas:      PRD §4.2, §12.2; referencias Apéndice A
Entregable:    bridging del API C `abl_link` compilando en el proyecto + nota breve.
Objetivo:      confirmar toolchain/bridging (riesgo bajo, pero conviene cerrarlo pronto).
Aceptación:    - Una llamada trivial al SDK compila y enlaza en macOS.
               - Nota sobre licencia: uso privado, GPL satisfecha con fuente a los
                 compañeros (PRD §12.1) — sin registro Ableton.
Verificación:  build del target con el SDK enlazado.
```

---

## 3. FASE 1 — macOS v1

### F1-SPEC — Contratos de `KairosCore` + tablas de test  🧊 FREEZE
```
Depende de:    F0-1 (gate), F0-2, F0-3
Paraleliza con:—  (es el cuello que habilita el fan-out)
Entradas:      PRD §4, §5, §7; conclusiones de F0-1/F0-2/F0-3
Entregable:    En `KairosCore`, SOLO firmas + doc + stubs + tablas de test (sin impl):
               - `specs/time-domain.md`, `specs/dynamics-core.md`, `specs/core-contracts.md`
                 (altitud: contrato + invariantes + tests de aceptación).
               - `ClockSource` (proto, PRD §5.1), `CycleConfig`, `CycleState`,
                 `CycleEngine`, `ResetDetector`, `Offset`.
               - `DynamicsCore`: tipos de muestra (RMS/peak/clip), `HistoryBuffer`,
                 `LaneInputStatus`/`LaneSignalState`, **`DynamicsPublisher` (proto)** con
                 `LocalConsumer` (v1) y hueco para `NetworkBroadcaster` (f2).
               - Tablas de test (XCTest) que codifican §5.3.1, §5.5, §7.2, §7.7 como
                 entrada→salida esperada, marcadas `XCTSkip`/pendientes hasta impl.
Latitud:       Nombres y forma de tipos. NO inventa comportamiento no especificado en PRD;
               si hay hueco, lo marca como `// DECISION-NEEDED` y lo reporta.
Aceptación:    - Compila; tests presentes (rojos/skipped) que cubren §5.3.1, §5.5.1, §5.5.2,
                 §5.6, §7.2, §7.7.2.
               - `DynamicsPublisher` modela explícitamente ≥1 consumidor (LocalConsumer),
                 y el camino audio→dato pasa por la costura (no directo).
               - Revisado y **congelado** (a partir de aquí, cambios solo por CONTRACT-CHANGE).
Verificación:  `swift test --package-path KairosCore` (verde en lo que ya esté, skip resto).
```

> **A partir del FREEZE, las tareas F1-TD/DC/RG/RL/AS/UI pueden lanzarse en paralelo a
> agentes distintos.** TD y DC son independientes entre sí; los renderers trabajan contra
> stubs del contrato.

### F1-TD — TimeDomain (implementación)
```
Depende de:    F1-SPEC (freeze)
Paraleliza con:F1-DC, F1-RG, F1-RL, F1-AS, F1-UI
Entradas:      PRD §5 completo (§5.2 D6, §5.3.1, §5.5, §5.6 D11, §5.7)
Entregable:    Impl de `InternalClock`, `MIDIClock`, `AbletonLinkClock` tras `ClockSource`;
               `CycleEngine` determinista; `ResetDetector` (combinado/general);
               anticipación (§5.5.2); `Offset` (render + hook de metrónomo, D11).
Latitud:       Estructuras internas. NO cambia firmas congeladas. El wiring REAL de Link/MIDI
               a hardware lo hace F1-INT; aquí los relojes externos se prueban con fuentes
               simuladas/inyectadas.
Aceptación:    - 100% de las tablas de §5.3.1 (currentStep, cycleIteration) verdes.
               - Resets combinado (≥2, no todos) y general (todos) detectados en el frame
                 correcto (§5.5.1) con tabla.
               - Anticipación según la tabla de §5.5.2 (8→1, 16/32/64→4, 128→8; 1/2/4→none).
               - Edge cases §5.7: tempo en caliente continuo; `isPlaying==false` congela;
                 `hasOrigin==false` no pinta posición; ciclo activado a mitad entra con fase.
               - `Offset`: `offsetBeats = (offsetMs/1000)×(tempo/60)` y se aplica al beat de
                 render y al instante de click.
Verificación:  `swift test` (suite TimeDomain 100% verde).
```

### F1-DC — DynamicsCore (implementación)
```
Depende de:    F1-SPEC (freeze), F0-3
Paraleliza con:F1-TD, F1-RG, F1-RL, F1-AS, F1-UI
Entradas:      PRD §7.2–§7.7 (D1, D5, D12, D13), §4.3
Entregable:    Captura BlackHole directo (macOS, gated), RMS/peak vDSP por canal,
               `ClipDetector` (cola 2 s), `HistoryBuffer` por lane con agregación por
               columnas (min/max/media), `LaneInputStatus` (estados §7.7.2 con histéresis
               y debounce), `DynamicsPublisher.LocalConsumer`.
Latitud:       Implementación numérica. Separar lo **shared** (tipos, HistoryBuffer,
               LaneSignalState — compila iOS) de la **captura macOS** (AVAudioEngine, gated
               `#if os(macOS)`), porque iOS reusa los tipos para renderizar telemetría.
Aceptación:    - RMS por canal vs señal conocida (±0.5 dB); ventana 300 ms (§15.3).
               - Clip dispara con muestra >0 dBFS y mantiene cola ~2 s; solo el canal que
                 saturó (§7.5.2).
               - HistoryBuffer: agregación por columnas correcta para 10s/30s/1min/2min.
               - `LaneSignalState`: secuencias sintéticas de nivel → línea temporal de
                 estados esperada (noSignal↔receiving con frontera −60 y debounce ≥2 s;
                 clipping prevalece).
               - Parte shared compila para iOS; la captura va bajo `#if os(macOS)`.
Verificación:  `swift test` (suite DynamicsCore verde) + build iOS del package.
```

### F1-RG — Render Grid
```
Depende de:    F1-SPEC (freeze), F0-2 (decisión Canvas/Metal)
Paraleliza con:F1-TD, F1-DC, F1-RL, F1-AS, F1-UI
Entradas:      PRD §6; design-system (Grid: step/cycle/grid/desktop, modos block/border/line,
               mark-reset); nodos Figma de Grid.
Entregable:    `GridRenderer` parametrizado por (mode, cycleCount, stepCount, activeStep,
               resetMarkers, anticipation). Lee `CycleState` del core (stub si hace falta).
Latitud:       Técnica de dibujo según F0-2. NO crea un componente por variante Figma:
               un renderer paramétrico (regla del design-system).
Aceptación:    - Dibuja 1–4 ciclos, mismo ancho visual → densidad por longitud.
               - Estados active/inactive; reset combinado verde, general morado, anticipación
                 roja, todos pintados SOBRE la barra (§6).
               - Mapea a tokens `color/kairos/*` (step-active/inactive, reset-*, anticipation).
               - 128×4 estable a 60 fps (objetivo de F0-2).
               - Calibration mismatches / token gaps marcados, no hardcodeados.
Verificación:  snapshot tests del renderer donde sea viable + QA visual en F1-QA.
```

### F1-RL — Render Level
```
Depende de:    F1-SPEC (freeze), F0-2
Paraleliza con:F1-TD, F1-DC, F1-RG, F1-AS, F1-UI
Entradas:      PRD §7.3–§7.5 (escala fija, zonas, dos masas L/R, histórico, borde semántico,
               clip, marca reset general §7.5.3, §15.2); design-system (window/desktop,
               level-band, bandas −0/−6/−12/−18/−24/−30/−60, −12 acentuado).
Entregable:    `LevelRenderer`: escala fija 0…−60, masas L/R (relleno gris), borde superior
               por canal (verde in-target / rojo out, margen ±6 dB, histéresis 1.5 dB,
               crossfade ~200 ms), clip (relleno rojo, cola 2 s), histórico con columnas,
               marca morada de reset general anclada al tiempo. Soporta layout 4-windows y
               single full-width.
Latitud:       Técnica de dibujo. NO añade peak hold (no existe). NO mete input-status aquí
               (va en sidebar, §7.7.4).
Aceptación:    - Escala lineal en dB sin autoescalado; distancia ∝ diferencia en dB.
               - Borde verde/rojo con margen/histéresis/crossfade de §15.2; dos bordes
                 independientes L/R que se separan al desequilibrar.
               - Clip: solo el relleno del canal que saturó, cola ~2 s, sin tocar el borde.
               - Marca reset general avanza hacia la izquierda con el histórico.
               - Tokens `color/kairos/*` (meter-fill-body, level-in/out-target, clip,
                 meter-scale-line). Mismatches marcados.
Verificación:  snapshot tests + QA visual en F1-QA.
```

### F1-AS — App services
```
Depende de:    F1-SPEC (freeze)
Paraleliza con:F1-TD, F1-DC, F1-RG, F1-RL, F1-UI
Entradas:      PRD §10 (presets), §8 (settings), §15.4 (metrónomo, D7)
Entregable:    `PresetStore` (Codable, Application Support, 5 presets, guarda nombres Rename
               D14, offset, sync, tempo, ciclos, lanes); `SettingsModel` (`@Observable`);
               `MetronomeEngine` (AVAudioEngine de salida dedicado, sample precargado,
               scheduling sample-accurate, ruteo a salida del sistema, offset aplicado D11).
Latitud:       Formato Codable interno. NO elige directorio (local fijo). NO control de
               volumen propio (sigue el del sistema).
Aceptación:    - Round-trip guardar/cargar de los 5 presets preserva todos los campos,
                 incluidos nombres Rename.
               - Click programado sample-accurate contra el mapa de tiempo, desplazado por
                 offset (§15.4 + §5.6); coherente con el grid.
               - Engine de salida separado del de captura.
Verificación:  `swift test` (PresetStore round-trip) + prueba manual de click en F1-INT.
```

### F1-UI — UI shell (chrome + sidebar + workspace)
```
Depende de:    F1-SPEC (freeze), F1-AS (para enlazar settings/presets; puede empezar con stub)
Paraleliza con:F1-TD, F1-DC, F1-RG, F1-RL
Entradas:      design-system completo (tool-bar/desktop, sidebar, button/*, toggle,
               sync-status, data, input-status, icon/rename, icon/dot-status); PRD §8, §9;
               nodos Figma de app-shell-desktop.
Entregable:    Top-bar (preset D9, sidebar toggle, play, reset, metrónomo, estado);
               Sidebar (Global→Sync/Tempo, Grid→4 cycles, Level→4 windows) con:
               - cabecera por ciclo/window: `icon/rename` (D14) + `icon/power`;
               - en Level, `input-status` bajo el nombre (D12, §7.7.4);
               - Offset renombrado (D11);
               workspace modular desktop (combinaciones sidebar+grid+level, etc.).
Latitud:       Composición SwiftUI. NO adopta el sistema de diseño de Apple (render a medida).
               Vincula a tokens/text styles reales; marca mismatches.
Aceptación:    - Estados de sync (Internal/MIDI/Link) y Play/BPM inertes en MIDI/Link (§5.2).
               - Sin modal por "no peers".
               - Rename funcional en Grid y Level; nombres persisten vía F1-AS.
               - `input-status` muestra los 3 estados (verde/blanco/rojo) con su texto.
               - `share data` NO aparece (fase 2).
               - Composiciones modulares del workspace funcionan (design-system §Layout).
Verificación:  build app + QA visual contra `figma-screen-references/` en F1-QA.
```

### F1-INT — Integración  👤 ÚNICO DUEÑO (serial)
```
Depende de:    F1-TD, F1-DC, F1-RG, F1-RL, F1-AS, F1-UI
Paraleliza con:— (un solo agente/seam owner; no paralelizar)
Entradas:      PRD §4.3 (hilos), §5.2, §7.1, §15.4
Entregable:    Wiring real: `AbletonLinkClock`/`MIDIClock` a hardware tras `ClockSource`;
               callback RT de AVAudioEngine → ring buffer lock-free → `DynamicsPublisher`;
               loop de render ~60 fps leyendo clock (con offset) + último dato de dinámica;
               metrónomo disparado contra el mapa de tiempo; degradación por pérdida de
               reloj (§11: congela, sin fallback automático).
Latitud:       Detalle del seam lock-free. NO cambia contratos congelados ni la lógica pura
               (solo conecta).
Aceptación:    - Play en Ableton (Link) arranca la visualización; cambio de tempo en caliente
                 sin saltos.
               - Audio RT sin allocations/locks (Thread Sanitizer / instrumento limpio).
               - Click y grid alineados con offset aplicado.
               - Pérdida de Link/MIDI → grid congela + estado de desconexión (no inventa
                 posición; no fallback auto).
Verificación:  build app + prueba manual guiada (Ableton + BlackHole) documentada en
               `docs/integration-checklist.md`.
```

### F1-QA — Aceptación v1 + QA visual
```
Depende de:    F1-INT
Entregable:    `docs/acceptance-v1.md` con checklist firmada.
Entradas:      PRD §11 (no funcionales), `figma-screen-references/`, criterios de éxito §1.
Aceptación:    - Recorre los criterios de aceptación de todas las tareas F1 en app real.
               - QA visual por breakpoint desktop contra las capturas (jerarquía, densidad).
               - Estabilidad en directo: arranque fiable, sin saltos perceptibles, 128×4 ok.
               - Lista de "calibration mismatch"/"token gap" acumulados → al diseñador.
Verificación:  checklist completa; v1 macOS instalable (firma local, notarización opcional).
```

---

## 4. FASE 2 — iOS (iPhone + iPad)

Principio rector: **Link para el reloj; canal propio para la dinámica** (Apéndice A).
Reusa `KairosCore` (tipos + renderers) sin reescritura. El Mac es **productor**; iPhone/iPad
son **consumidores** + peers Link nativos. La costura `DynamicsPublisher` ya existe desde v1.

### F2-SPEC — Contrato de telemetría
```
Depende de:    F1-INT (productor estable)
Entradas:      Apéndice A; mobile-evo.md (paquete, timestamps, colas, frescura)
Entregable:    `specs/telemetry.md` + tipos Codable del paquete de dinámica (sourceId,
               sequence, measuredAtHostTime, linkBeat, tempo, rmsDb, peakDb, clipping,
               windowMs, sampleRate) + contrato del 2º consumidor de `DynamicsPublisher`.
Aceptación:    - Esquema de paquete fijado y serializable; política de frescura/descarte y
                 snapshot inicial especificadas como invariantes testeables.
Verificación:  `swift test` (round-trip del paquete).
```

### F2-BC — NetworkBroadcaster (Mac)
```
Depende de:    F2-SPEC
Entregable:    Segundo consumidor de `DynamicsPublisher`: anuncio Bonjour/mDNS + servidor
               WebSocket; `Level broadcast on/off` global + nº de dispositivos; snapshot
               inicial al conectar; envío 10–30 Hz, frescura > exhaustividad.
Aceptación:    - Se añade SIN tocar el camino audio→dato (additivo, costura intacta).
               - Cliente de prueba recibe paquetes timestamped a 10–30 Hz; al conectar recibe
                 snapshot; broadcast on/off funciona.
Verificación:  test de integración con cliente WebSocket de prueba + edad del dato medida.
```

### F2-IOS-00 — Scaffold app iOS + reuse de `KairosCore`
```
Depende de:    F1-SPEC (core ya multiplataforma)
Entregable:    Target iOS (iPhone + iPad), enlaza `KairosCore`, deployment target iOS a fijar
               (LinkKit / privacidad de red local iOS 14+).
Aceptación:    - App iOS compila enlazando el core; renderers de grid/level reutilizados.
```

### F2-LINK — Peer Link nativo (iOS)
```
Depende de:    F2-IOS-00, F0-1 (determinismo validado)
Entregable:    LinkKit como `ClockSource` en iOS; tempo/transporte read-only por defecto
               (Ableton maestro); config de grid independiente por dispositivo (D3); offset
               local (solo visual en iOS, D11).
Aceptación:    - Grid del iPhone/iPad alineado con el del Mac vía Link (ciclos iguales →
                 misma fase), conforme a F0-1.
               - Estados Link discretos, sin modal por "no peers".
```

### F2-CLIENT — Cliente de dinámica (iOS)
```
Depende de:    F2-BC, F2-IOS-00
Entregable:    Descubrimiento Bonjour + cliente WebSocket; selector de Dynamics Source;
               cola con descarte por antigüedad; reconstrucción de histórico por timestamp;
               estados de conexión/degradación (Apéndice A).
Aceptación:    - Conexión automática si hay 1 fuente; selector si hay varias.
               - Edad del dato < 200–300 ms en LAN; descarta paquetes viejos.
               - Degradación: cae dinámica → grid sigue por Link; cae Link → medidor sigue.
```

### F2-UI — Pantallas touch (iPhone + iPad)
```
Depende de:    F2-LINK, F2-CLIENT
Entradas:      design-system (touch portrait/landscape, tool-bar/mobile/*, orientación);
               nodos Figma tablet + mobile; D10
Entregable:    Sidebar portrait fullscreen; Grid y Level en pantallas separadas horizontales;
               navegación por gesto **drag** (D10) + reglas de orientación; escalado táctil
               (controles 32→40, tokens de texto mayores).
Latitud:       Constantes del gesto drag NO están especificadas (design-system "Clarifications
               Still Needed"): el agente NO las inventa; abre `DECISION-NEEDED` para spec de
               motion antes de fijarlas.
Aceptación:    - iPhone y iPad nunca muestran Grid y Level a la vez (regla single-primary).
               - Orientación conmuta según contrato; vuelve a horizontal al salir del sidebar.
```

### F2-PERMS / F2-DEBUG / F2-QA
```
F2-PERMS:  permiso de red local iOS (+ multicast entitlement si aplica); mensajes claros
           (permiso denegado / red no disponible / firewall) — "no peers" NO es error.
F2-DEBUG:  vista de diagnóstico: latencia actual/media/máx, edad del dato, paquetes/s,
           pérdidas, cola, peers Link, BPM. Activable por flag.
F2-QA:     aceptación iOS contra Apéndice A + QA visual tablet/mobile; prueba de "palmada"
           (Mac reacciona, iPhone casi a la vez; >1 s = no aceptable).
```

---

## 5. Tablero resumen

| ID | Fase | Tipo | Depende de | Paralelizable |
|---|---|---|---|---|
| F1-00 | 0 | serial | — | con F0-2/4 |
| F0-1 ⛔ | 0 | spike (GATE) | F1-00 | con F0-2/3/4 |
| F0-2 | 0 | spike | F1-00 | sí |
| F0-3 | 0 | spike | F1-00 | sí |
| F0-4 | 0 | smoke | F1-00 | sí |
| F1-SPEC 🧊 | 1 | freeze | F0-1,2,3 | no (cuello) |
| F1-TD | 1 | impl | F1-SPEC | sí (con DC/RG/RL/AS/UI) |
| F1-DC | 1 | impl | F1-SPEC, F0-3 | sí |
| F1-RG | 1 | impl | F1-SPEC, F0-2 | sí |
| F1-RL | 1 | impl | F1-SPEC, F0-2 | sí |
| F1-AS | 1 | impl | F1-SPEC | sí |
| F1-UI | 1 | impl | F1-SPEC, (F1-AS) | sí |
| F1-INT 👤 | 1 | serial | todas F1-* | no (único dueño) |
| F1-QA | 1 | serial | F1-INT | no |
| F2-* | 2 | mixto | F1-INT + cadena propia | parcial |

---

## 6. Gates y riesgos (resumen accionable)

- **GATE F0-1:** no se congela `TimeDomain` (F1-SPEC) sin validar el determinismo Link en
  ciclos largos (riesgo Alta del PRD §13). Es la única incógnita que puede forzar rehacer
  el contrato.
- **Seam de único dueño (F1-INT):** audio RT + relojes reales + lock-free los toca una sola
  tarea. El resto va contra stubs. Evita corrupción de estado en concurrencia.
- **Costura `DynamicsPublisher` desde v1:** el broadcast móvil (F2-BC) entra como segundo
  consumidor, additivo. Si una tarea de v1 cablea audio→render directo, **viola la
  arquitectura** y debe rechazarse en review.
- **Fidelidad de diseño:** las tareas de UI/render marcan "calibration mismatch"/"token gap";
  no hardcodean ni recalibran. La calibración la cierra el diseñador.
- **Uso privado (D8):** sin App Store ni notarización obligatoria; iOS solo necesita firma
  (cuenta de pago para perfiles de 1 año). Ningún gate de Ableton Link.
```
