# Kairos App — Plan de auditoría técnica y refactorización para versión 1

> Documento de auditoría y roadmap de saneamiento. **No es código todavía**: es el mapa de trabajo
> para cerrar Kairos v1 con calidad de proyecto revisado por un desarrollador senior.
> Redactado tras una auditoría directa del repositorio (HEAD `7d11bfe`, rama `main`).
> **Regla rectora: el estado funcional actual del código es la fuente de verdad. La documentación
> antigua NO lo es.**

---

## 1. Resumen ejecutivo

Kairos es una **app nativa de escritorio para macOS escrita en Swift 6 / SwiftUI** (deployment target
macOS 14). No es un proyecto web: gran parte del briefing original habla en términos de “stores, hooks,
renders, props” pero la implementación real es Swift/AppKit/SwiftUI. Esta auditoría toma el código Swift
como verdad.

**El proyecto está funcionalmente sano y es estable, pero arrastra una capa importante de residuo
documental y de código muerto** procedente de decisiones que ya se descartaron durante el desarrollo
iterativo con agentes. Las tres conclusiones de mayor impacto:

1. **La arquitectura de audio pivotó y la documentación no lo refleja.** `Level` ya **no** captura audio
   con BlackHole: recibe telemetría `RMS`/`peak` ya calculada desde un dispositivo **Max for Live** por
   **UDP (puerto 51515)**. BlackHole quedó degradado a “referencia histórica”. Sin embargo el PRD, el
   roadmap y parte de los `docs/` siguen describiendo el flujo BlackHole (20 menciones en el PRD), y hay
   un paquete entero muerto (`Packages/AudioIOSpike`) y etiquetas hardcodeadas “BlackHole 1-2” en la UI.

2. **El alcance se redujo a macOS y la documentación sigue llena de móvil/tablet/iOS.** iPhone/iPad
   (fase 2) **se cancela en v1**. Pero `mobile-evo.md`, 41 menciones móvil/tablet en
   `kairos-design-system.md`, las capturas `figma-screen-references/*mobile*`/`*tablet*`, el target iOS de
   `KairosCore` y toda una capa de “seguros de fase 2” en el core siguen presentes y pueden hacer que un
   agente reintroduzca decisiones muertas.

3. **Existe un “God file”: `Kairos/DesktopShell.swift` (4 622 líneas, ~55 tipos).** Concentra el modelo de
   integración, ~50 vistas SwiftUI, tokens, tipografía, formatters, iconos y estilos de botón. Es el
   principal foco de deuda de mantenibilidad y el único refactor grande verdaderamente secuencial.

Además, hay **bloqueadores concretos de distribución**: no existe `AppIcon.appiconset` (la app sale con
icono en blanco), no hay script de DMG, no hay remoto de GitHub configurado y **el árbol de trabajo está
sucio** (13 archivos sin commitear, +2360/−556 líneas, `DesktopShell.swift` con +1770 líneas pendientes).

Lo positivo, que conviene **no romper**: el core lógico (`KairosCore`) está bien aislado y testado (26
tests), la app tiene cobertura real de su lógica crítica (Grid, Level/telemetría, USB MIDI, presets,
metrónomo), no hay marcadores `TODO/HACK` sueltos, y la separación de dominios Time/Dynamics es correcta.

**Tesis del plan:** Kairos no necesita un rescate arquitectónico, necesita **alinear la verdad
(código ↔ docs ↔ alcance), eliminar residuo, descomponer el God file y cerrar build/DMG/release**. Por eso
se reordena la prioridad respecto al briefing (justificado en §6): primero baseline limpia y reconciliación
documental, porque son la red de seguridad que evita que los agentes reintroduzcan lo descartado.

---

## 2. Estado actual detectado del repositorio

### 2.1 Stack y topología real

| Módulo | Qué es | Estado | LOC aprox. |
|---|---|---|---|
| `Kairos/` (app target) | App SwiftUI macOS 14, `@main KairosApp` → `DesktopShellRootView` | **Vivo** | ~10 200 |
| `KairosCore/` (SPM) | Core lógico puro sin UI: `TimeDomain` + `DynamicsCore`, 26 tests | **Vivo (parcialmente sin cablear)** | ~1 900 |
| `Packages/KairosLinkSDK/` (SPM) | Wrapper de Ableton Link (C++ vendado como **submódulo git** `Vendor/link`) | **Vivo** (lo usa `AbletonLinkBridge`) | — |
| `Packages/AudioIOSpike/` (SPM) | Spike F0-3 de captura BlackHole + RMS en tiempo real | **MUERTO** (0 referencias, fuera del workspace) | — |
| `MaxForLive/` | Dispositivo M4L (`.amxd` + `.maxpat` + 2 `.js`) que emite telemetría de Level | **Vivo (núcleo del flujo Level actual)** | — |
| `KairosTests/` | Tests del app target (telemetría, grid, presets, USB MIDI, metrónomo) | **Vivo** | — |
| `docs/`, `*.md` raíz, `figma-screen-references/` | Documentación y referencias | **Mezcla de vigente y obsoleto** | — |

**El workspace (`Kairos.xcworkspace`) solo referencia `Kairos.xcodeproj` + `KairosLinkSDK`.** `KairosCore` se
enlaza como paquete local del proyecto. `AudioIOSpike` **no está en el workspace**: es un huérfano.

### 2.2 Flujo de datos real (verificado en código)

- **Grid (tiempo musical):** `DesktopShellModel` resuelve el transporte a nivel de app combinando
  `AbletonLinkBridge` (Link, vía `LiveLinkSession`), `USBMIDISyncBridge` (CoreMIDI, con su propio tracker de
  MIDI clock `USBMIDISyncTracker` que parsea `0xF8`/SPP) y un reloj interno; `TransportBeatResolver`
  convierte `elapsed → beat (+ offset)` y alimenta `CycleEngine`/`ResetDetector` de `KairosCore`. El render
  lo hace `GridRenderer` (SwiftUI `Canvas`).
- **Level (señal):** `LevelTelemetryReceiver` escucha UDP 51515 (JSON `kairos.level.v1`, con compat legacy
  `gridlink.rms.v1`), `LevelRuntimeDriver` mapea cada *source* M4L a un *lane* visual y agrega vía
  `HistoryBuffer`/`ClipDetector`/`LaneInputStatusMachine` de `KairosCore`; `LevelRenderer` (Canvas) pinta.
- **Estado/persistencia:** `SettingsModel` (`@Observable @MainActor`) + `DesktopShellModel`
  (`@Observable`, hub de integración) + `PresetStore` (`actor` → `Application Support/Kairos/presets.json`)
  + `PresetStoreDTOs` (DTOs Codable con migraciones de presets legacy).

### 2.3 Sincronía: tres fuentes reales

`SyncSource` (`Kairos/AppSettings.swift:4`) = **`internalClock` · `usb` · `link`**. La antigua fuente
genérica **“MIDI Clock” fue descartada**: los presets legacy con `"midi"` migran a `internalClock`
(test `testLegacyMidiSyncSourceDecodesAsInternalClock`). El MIDI **vivo** hoy es **USB MIDI sync**
(`USBMIDISyncBridge`, CoreMIDI). → confirma la intuición del briefing: “MIDI Clock descartado” es correcto.

### 2.4 Git / baseline

- Rama única `main`, **sin remoto** configurado, **sin tags**.
- **Árbol sucio**: 13 archivos modificados sin commitear (incl. `DesktopShell.swift` +1770, `kairos_level_sender.js` +257). Trabajo en curso no guardado.
- `.gitignore` correcto (nada indebido trackeado: `git ls-files` no devuelve `.DS_Store`/`xcuserstate`/`.build`).
- Submódulo Ableton Link → **los clones necesitan `--recursive`** (riesgo al instalar en el Mac de un amigo).
- Último commit (`7d11bfe`) es un **commit gigante mezclado** (sync bridges + telemetría + M4L + tests + docs) — exactamente el antipatrón que el briefing pide evitar.

---

## 3. Riesgos principales

| # | Riesgo | Severidad | Evidencia |
|---|---|---|---|
| R1 | **Árbol de trabajo sucio**: un agente puede pisar/derribar +2 300 líneas no commiteadas | 🔴 Bloqueante | `git diff --stat` |
| R2 | **Docs contradicen el código** (BlackHole, iOS/móvil): un agente reintroduce lo descartado | 🔴 Alta | PRD 20×BlackHole/13×iPhone; design-system 41×móvil |
| R3 | **God file `DesktopShell.swift`** (4 622 líneas): cualquier cambio de UI toca un archivo enorme y serializa el trabajo | 🟠 Media-alta | conteo de líneas + ~55 tipos |
| R4 | **Código muerto que confunde**: `AudioIOSpike`, capa de relojes de `KairosCore`, stubs de fase 2, etiquetas “BlackHole 1-2” | 🟠 Media | 0 refs entrantes; grep de símbolos |
| R5 | **Sin app icon ni DMG ni firma documentada**: no se puede cerrar la distribución | 🟠 Media | no hay `AppIcon.appiconset` ni script |
| R6 | **Bugs funcionales conocidos posiblemente abiertos** (reset fiable 1/5, clip→masa roja, target line, paneles responsivos) — memoria de hace 13 días, hubo commits después | 🟠 Media | historial + memoria de decisiones |
| R7 | **Estado de Figma divergente**: el MCP en vivo muestra una sola página “Portada” frente a la estructura multipágina documentada | 🟡 Baja | `get_metadata` en vivo |
| R8 | **Submódulo Link**: clone sin `--recursive` deja la app sin compilar en otro Mac | 🟡 Baja | `.gitmodules` |

---

## 4. Principios de auditoría

1. **El código funcional manda.** Ante conflicto código↔doc, gana el código; la doc se actualiza, no al revés.
2. **macOS-only en v1.** iPhone/iPad/tablet/móvil están **fuera de alcance**. No se implementa, no se documenta como vivo, no se “deja preparado”.
3. **No reintroducir lo descartado:** BlackHole como dependencia principal, MIDI Clock genérico, captura de audio en la app, broadcast a iOS, peak vía `output_meter` de Live.
4. **Eliminar con evidencia.** Antes de borrar una pieza, comprobar referencias en runtime, tests, build (pbxproj/workspace), docs y Figma. Documentar cada eliminación.
5. **Separar por dominio.** Commits y PRs atómicos por dominio; nunca mezclar UI + lógica + build + docs.
6. **No romper lo que funciona.** Core aislado y testado, app runnable, 26+ tests verdes: mantener verde tras cada fase.
7. **Audio/Sync/Grid/Level requieren prueba manual.** Ningún cambio en esos dominios se da por bueno sin validación en vivo (Ableton + M4L + Link/USB MIDI).
8. **Cierre de cada fase con resumen**: qué se tocó, qué se eliminó, qué queda pendiente, qué hay que testar.

---

## 5. Dominios auditables

> Formato por dominio: **Qué revisar · Preguntas · Criterios de problema · Output esperado · Prioridad · Dependencias · Paralelización.**

### 5.1 Arquitectura general

- **Qué revisar:** topología de módulos (§2.1), límites `KairosCore` ↔ app, paquetes locales (`AudioIOSpike` huérfano, `KairosLinkSDK`), submódulo Link, ubicación del hub de integración (`DesktopShellModel`), y el solapamiento entre la capa de relojes de `KairosCore` y los *bridges* de la app.
- **Preguntas:** ¿La separación core/app es real y útil sin fase 2? ¿Qué de `KairosCore` está **sin cablear** y por qué? ¿Hay dos implementaciones del mismo concepto (reloj en core vs `TransportBeatResolver`/`USBMIDISyncTracker` en app)? ¿`AudioIOSpike` aporta algo?
- **Criterios de problema:** código compilado pero sin consumidores de runtime; dos caminos para una misma responsabilidad; paquete fuera del workspace; target iOS sin destino real.
- **Output esperado:** documento `docs/arquitectura.md` con el diagrama real (Grid/Level/Sync/Estado), decisión explícita sobre `KairosCore` (mantener como core testado de macOS, **podar** la capa de relojes y los stubs de fase 2 no usados, **quitar** target iOS o marcarlo inerte), y eliminación de `AudioIOSpike`.
- **Prioridad:** Alta (condiciona el resto). **Dependencias:** baseline limpia (BASE-1). **Paralelización:** el *documento* sí; la *poda de core* NO (toca core + tests, secuencial — ver DEAD-2).

#### Código muerto / sin cablear detectado en `KairosCore` (verificado por grep de símbolos usados por la app)

La app solo construye de `KairosCore`: `CycleEngine`, `ResetDetector`, `Offset`, `CycleState/Configuration`
(TimeDomain) y `HistoryBuffer`, `ClipDetector`, `LaneInputStatus(Machine)`, `DynamicsSample` + factories
(DynamicsCore). **No usa**:

- `TimeDomain/InternalClock.swift` (70), `AbletonLinkClock.swift` (52), `MIDIClock.swift` (52), `ClockSource.swift` (33), `ClockTimeline.swift` (206), `OriginLatch.swift` → la app reimplementó el transporte a nivel de app. **Vivos en tests, muertos en la app.**
- `DynamicsCore/DynamicsPublisher*`, `NetworkBroadcaster.swift` (stub de 4 líneas), `AudioEngine.swift` (stub de 6 líneas), `LocalConsumer`, `RMSPeak*`, `DynamicsMeter` → “seguros de fase 2” (broadcast a iOS) hoy sin sentido (la telemetría va al revés: M4L→app).

> Decisión a tomar (no asumir): **podar** estos subsistemas (camino recomendado para un v1 limpio, dado que fase 2 se cancela) **o** conservarlos marcados explícitamente como “no cableado / futuro”. Cualquiera de las dos exige actualizar los tests que los referencian. **No** dejarlos sin etiquetar.

### 5.2 Componentes de interfaz

- **Qué revisar:** los ~50 `struct ... : View` dentro de `DesktopShell.swift` (toolbar, sidebar, workspace modular, tarjetas de cycle/lane, botones —`ToolbarIconButton`, `PowerIconButton`, `ModeIconButton`, `TertiaryIconButton`, `ToggleButton`, `SegmentButton`, etc.—, dropdowns flotantes, `PresetSelectorButton`, `RenameableTitle`, estilos `SurfaceButtonStyle`), más `GridRenderer.swift` (1 113) y `LevelRenderer.swift` (1 394).
- **Preguntas:** ¿qué componentes son necesarios para v1? ¿cuáles duplican variantes? ¿qué botón tiene render roto (memoria menciona *tertiary*/*ghost*)? ¿los iconos son los reales de Figma o glifos SF aproximados? ¿`GridPreviewDriver`/`LevelPreviewDriver`/`LevelPreviewSnapshot` deberían renombrarse (ya no son “preview”: son el driver vivo alimentado por telemetría)?
- **Criterios de problema:** un único archivo con modelo+vistas+tokens+estilos; nombres “Preview” para lógica de producción; iconos placeholder (SF Symbols) en vez de assets de Figma; estados de botón inconsistentes.
- **Output esperado:** **descomposición de `DesktopShell.swift`** en archivos por responsabilidad (Model / Toolbar / Sidebar / Workspace / Controls+Buttons / Dropdown / Tokens+Typography / Icons), **sin cambiar comportamiento**; inventario de componentes v1; importación de los iconos reales de Figma; renombrado de los “Preview*” a nombres de runtime.
- **Prioridad:** Media-alta (mantenibilidad). **Dependencias:** §5.3 (estado) estable; iconos dependen de Figma/Branding. **Paralelización:** la descomposición es **un solo dueño** (SHELL-1, secuencial); inventario y mapeo de iconos sí pueden ir en paralelo.

### 5.3 Gestión de estado y flujo de datos

- **Qué revisar:** `SettingsModel` (139), `DesktopShellModel` (~1 250 líneas de modelo dentro del God file, ~15 campos `@ObservationIgnored`, varias `Task` de monitorización, drivers, receiver), `PresetStore` (actor, 75) + `PresetStoreDTOs` (669, migraciones), y los puntos de verdad de tempo/transport/offset/reset.
- **Preguntas:** ¿hay estado duplicado entre `SettingsModel` y `DesktopShellModel`? ¿el ciclo de vida de tasks/receiver/bridges se limpia siempre (`stopRuntime`/`deinit`)? ¿el transporte tiene una única fuente de verdad o se recalcula en varios sitios? ¿las migraciones de presets cubren todos los formatos legacy?
- **Criterios de problema:** el mismo dato vivo en dos modelos; efectos secundarios difíciles de rastrear; listeners/tasks sin cancelar; lógica de dominio mezclada con presentación en el modelo.
- **Output esperado:** `docs/estado-y-datos.md` con el mapa de propiedad del estado (quién posee tempo, transport, offset, lanes, presets), confirmación de limpieza de recursos, y aislamiento más claro de la lógica de transporte (idealmente extraída del God file a un tipo propio testeable).
- **Prioridad:** Alta (flujos críticos). **Dependencias:** baseline limpia. **Paralelización:** NO con §5.2/§5.4 (toca el núcleo del que dependen); secuencial y coordinado.

### 5.4 Audio, señal y sincronía musical (núcleo funcional)

- **Qué revisar:** `LevelTelemetryReceiver`, `LevelRuntimeDriver`, el contrato JSON (`kairos.level.v1`/legacy `gridlink.rms.v1`), `MaxForLive/*` (`.amxd`, `.maxpat`, `kairos_level_sender.js`, `kairos_level_node.js`), `AbletonLinkBridge`, `USBMIDISyncBridge` + `USBMIDISyncTracker`, `MetronomeClickEngine`, y la coherencia dB (linear `0..1` → `20·log10`).
- **Preguntas:** ¿el flujo M4L→UDP→lane es coherente y está libre de residuo BlackHole? ¿las etiquetas mostradas reflejan el *source* real de Ableton (nombre de pista / `sourceSlot`) o aún dicen “BlackHole 1-2”? ¿el `gridlink.rms.v1` legacy se mantiene a propósito (compat) y está documentado? ¿Grid (transporte) y Level (señal) están bien separados? ¿reset/offset/tempo están centralizados?
- **Criterios de problema:** referencias a BlackHole como dependencia, nombres de canal que inducen a error, peak warpeado, lógica de señal acoplada a la de tiempo, recálculos dispersos de beat.
- **Output esperado:** **eliminar el residuo BlackHole** del path de Level (incl. etiquetas hardcodeadas `LevelRenderer.swift:1163-1169` “BlackHole 1-2/3-4/5-6/7-8” → deben derivar del `sourceName`/`sourceSlot` reales); documento técnico `docs/level-telemetria.md` (ya existe base en `docs/setup/level-max-for-live.md`, consolidarlo); documento `docs/sync.md` (Internal/USB/Link, MIDI clock genérico descartado); **plan de pruebas manuales** de niveles y sincronía (ver §14).
- **Prioridad:** **Muy alta** (es el núcleo; además concentra el residuo más peligroso). **Dependencias:** baseline limpia. **Paralelización:** la limpieza de etiquetas es localizada pero toca `LevelRenderer` (coordinar con §5.2); el doc va en paralelo; cambios de comportamiento → secuenciales + prueba manual obligatoria.

### 5.5 Performance y estabilidad

- **Qué revisar:** loops de render (`Canvas` Grid/Level a ~60 fps vía `TimelineView`/tasks), el `HistoryBuffer` (recorte a 120 s — confirmado), el receiver UDP no bloqueante (`DispatchSourceRead`, drenado en cola dedicada, salto a `@MainActor`), las `Task` de monitorización (link/level/metronome) y su cancelación, y `DesktopShellModel.startRuntimeIfNeeded/stopRuntime`.
- **Preguntas:** ¿hay renders innecesarios por `@Observable` mal acotado? ¿el histórico está acotado en memoria (sí: 120 s) y en columnas (sí: 56/240)? ¿se cancelan todas las tasks/sockets en `stopRuntime`/`deinit`? ¿el spike F0-2 confirmó Canvas con ~100× de margen (sí) — se mantiene? ¿estabilidad en sesión larga (>2 h de directo)?
- **Criterios de problema:** timers/listeners sin limpiar, buffers sin límite, recálculo en el ciclo visual, retención de `self` en closures.
- **Output esperado:** checklist de limpieza de efectos verificada, confirmación de límites de buffers, y una **prueba de estabilidad de sesión larga** documentada. (Riesgo bajo: la evidencia actual es buena —límites presentes, cancelaciones presentes—; es verificación, no reescritura.)
- **Prioridad:** Media. **Dependencias:** §5.3/§5.4 estables. **Paralelización:** verificación independiente; correcciones puntuales coordinadas con el dominio afectado.

### 5.6 Estilos, tokens y sistema de diseño

- **Qué revisar:** `DesktopShellTokens`, `DesktopShellTypography`, `KairosIcon`/`KairosIconView` (en el God file), los `Assets.xcassets/*.imageset` (21 glifos), y la relación con los tokens reales de Figma (`color/kairos/*`, etc., documentados en la memoria de extracción `docs/design/figma-extraction-probe.md`).
- **Preguntas:** ¿hay valores hardcodeados que contradicen Figma? ¿`kairos-design-system.md` (26 KB, 41 menciones móvil/tablet) coincide con la implementación macOS-only actual? ¿los iconos en uso son los reales de Figma o aproximaciones SF? ¿nomenclatura coherente token↔código↔Figma?
- **Criterios de problema:** colores/tamaños/radios hardcodeados, reglas responsive de tablet/móvil en el doc, iconos placeholder, tokens huérfanos.
- **Output esperado:** `kairos-design-system.md` **reescrito a macOS-only** (quitar responsive móvil/tablet, conservar tokens válidos), inventario de tokens reales vs implementados, importación de iconos reales, y un par de “calibration items” pendientes ya señalados (p. ej. `meter-fill-body`).
- **Prioridad:** Media. **Dependencias:** Figma (§5.10 / sección 12). **Paralelización:** SÍ (aislado por dominio), salvo el momento en que toque `DesktopShell` (coordinar con SHELL-1).

### 5.7 Accesibilidad y usabilidad básica

- **Qué revisar:** distinción visual de estados (active/hover/folded/disabled/error), contraste en tema oscuro, tamaños clicables de los iconos de toolbar/sidebar, foco y navegación por teclado mínima, legibilidad a distancia de escenario.
- **Preguntas:** ¿se distinguen bien los estados de botón (memoria reporta *ghost*/*tertiary* con render dudoso)? ¿contraste suficiente sobre `#101012`? ¿hay controles demasiado pequeños para uso en directo? ¿qué accesibilidad **no** aporta valor aquí y solo añade complejidad?
- **Criterios de problema:** estados indistinguibles, contraste insuficiente, *hit targets* pequeños.
- **Output esperado:** criterios mínimos documentados (`docs/usabilidad.md`), ajustes visuales puntuales y lista de validación manual. **Sin sobre-ingeniería**: es herramienta personal de directo.
- **Prioridad:** Baja-media. **Dependencias:** §5.2/§5.6. **Paralelización:** SÍ (revisión); cambios coordinados con UI.

### 5.8 Documentación del repositorio

- **Qué revisar:** raíz (`kairos-origen.md`, `kairos-prd-tecnico.md` 48 KB, `kairos-roadmap.md`, `kairos-design-system.md`, `mobile-evo.md`, `BUILD.md`) y `docs/` (`setup/level-max-for-live.md` ✅ vigente, `setup/blackhole-*` ⚠️ histórico, `design/figma-extraction-probe.md`, `spikes/*`).
- **Preguntas:** ¿qué doc está vigente y cuál contradice el código? ¿qué necesita alguien que abra el repo en 6 meses? ¿qué necesita un agente para no reintroducir lo descartado? ¿dónde se declara que móvil/tablet quedan fuera?
- **Criterios de problema:** docs que describen BlackHole/iOS como vivos, ausencia de README de entrada, `BUILD.md` con comandos de validación iOS ya inútiles, primer renglón corrupto en `kairos-origen.md` (`).`).
- **Output esperado:** **crear `README.md`** (qué es, stack, cómo correr, cómo está estructurado, alcance v1 = macOS); **carpeta `docs/historico/`** para archivar `mobile-evo.md`, los `blackhole-*` y el PRD/roadmap antiguos con cabecera “ARCHIVADO — no es estado vivo”; **`docs/decisiones-descartadas.md`** (móvil/tablet, BlackHole como principal, MIDI clock genérico, broadcast iOS); actualizar `BUILD.md`. (Detalle en §10.)
- **Prioridad:** **Alta** (red de seguridad para los agentes). **Dependencias:** ninguna (puede empezar ya). **Paralelización:** SÍ, totalmente.

### 5.9 Build, empaquetado, DMG y distribución

- **Qué revisar:** `Kairos.xcodeproj/project.pbxproj` (versión 1.0.0 ✅, bundle `com.diegofernandezmunoz.Kairos` ✅, macOS 14 ✅, `CODE_SIGN_STYLE=Automatic`, **sin** `DEVELOPMENT_TEAM`, **sin** entitlements, **sin** `ASSETCATALOG_COMPILER_APPICON_NAME`), `Assets.xcassets` (**sin `AppIcon.appiconset`**), submódulo Link, y la ausencia total de script de release/DMG.
- **Preguntas:** ¿compila de forma reproducible (incl. `--recursive` del submódulo)? ¿hay flujo de DMG? ¿dónde está el icono de app (Figma → Branding)? ¿qué pasos faltan para instalar en otro Mac? ¿qué fricción de Gatekeeper habrá sin notarizar? ¿el sandbox está apagado (necesario para el UDP receiver)?
- **Criterios de problema:** icono ausente, sin script, firma/entitlements sin documentar, riesgo de romper UDP si alguien activa sandbox.
- **Output esperado:** crear `AppIcon.appiconset` desde la página **Branding** de Figma; **script `scripts/release-dmg.sh`** (build Release + `create-dmg`/`hdiutil`); `docs/release.md` (firma ad-hoc vs Developer ID, notarización opcional, instrucciones “abrir con clic derecho” para el usuario final, recordatorio `git clone --recursive`); confirmar/documentar sandbox OFF.
- **Prioridad:** Alta para el cierre, pero **después** de limpieza (no tiene sentido empaquetar residuo). **Dependencias:** icono de Figma; baseline limpia. **Paralelización:** script e icono en paralelo; documentación de release en paralelo.

### 5.10 GitHub, versionado y limpieza final

- **Qué revisar:** estado git (§2.4), `.gitignore`, `.gitmodules`, archivos generados, `.claude/settings.local.json` (solo permisos de Figma MCP, sin secretos — aceptable), rutas absolutas en docs (`figma-screen-references/README.md` usa rutas `/Users/...`).
- **Preguntas:** ¿el repo está listo para publicar? ¿hay binarios/artefactos que no deban versionarse? ¿hay rutas locales? ¿procede `v1.0.0`? ¿qué estructura de commits cierra el proyecto?
- **Criterios de problema:** árbol sucio, sin remoto, sin tag, rutas absolutas, commits gigantes.
- **Output esperado:** **commitear el árbol sucio dividido por dominio**, crear repo en GitHub y `git push`, sustituir rutas absolutas por relativas, checklist de publicación, y **tag `v1.0.0`** al final.
- **Prioridad:** **Última** (cierre). **Dependencias:** todo lo anterior cerrado. **Paralelización:** NO (es el sello final).

---

## 6. Priorización recomendada (y por qué difiere del briefing)

El briefing propone empezar por *arquitectura → estado → audio → performance → UI → estilos → docs → build → git*.
**Lo ajusto** porque la auditoría muestra que **la arquitectura ya es estable** (core aislado, tests verdes,
app runnable) y que el riesgo real para un trabajo dirigido por agentes no es la arquitectura, sino
**(a) una baseline sucia, (b) documentación que miente y reintroduce lo descartado, y (c) residuo**. Por eso
la documentación y la limpieza suben de prioridad: son la **red de seguridad** del resto.

Orden recomendado:

0. **Baseline limpia** (commitear/dividir el árbol sucio, build+tests verdes, remoto GitHub). — *Bloqueante.*
1. **Reconciliación documental y de alcance** (README, archivar móvil/BlackHole, decisiones descartadas). — *Protege todo lo demás.*
2. **Eliminación de residuo / código muerto** (`AudioIOSpike`, poda core, etiquetas BlackHole). — *Aclara el modelo mental.*
3. **Descomposición de `DesktopShell.swift`** (un solo dueño, sin cambiar comportamiento). — *Desbloquea trabajo paralelo de UI.*
4. **Audio/Sync/Grid/Level: verificación + bugs funcionales abiertos** (con prueba manual). — *Núcleo.*
5. **Performance/estabilidad** (verificación de límites y limpieza de efectos; sesión larga).
6. **Componentes/UI** (iconos reales, estados de botón, responsive de paneles).
7. **Estilos / design system** (reescribir `kairos-design-system.md` macOS-only).
8. **Accesibilidad/usabilidad** mínima.
9. **Build, DMG, icono, release**.
10. **Limpieza final de GitHub + tag `v1.0.0`**.

---

## 7. Plan de trabajo por fases

> IDs por dominio para que varios agentes los referencien sin colisión.

### Fase 0 — Baseline y verdad (secuencial primero, luego paralelo)
- **BASE-1** *(secuencial, primero)*: revisar el `git diff` actual y **commitearlo dividido por dominio** (audio/telemetría · UI/render · settings/DTO · docs · M4L). Confirmar `swift test --package-path KairosCore` + tests del app verdes y `xcodebuild -scheme Kairos -destination 'platform=macOS' build` OK. Dejar `main` limpio.
- **BASE-2** *(secuencial, tras BASE-1)*: crear repo GitHub privado + remoto + primer `push`. Sustituir rutas absolutas (`figma-screen-references/README.md`).
- **DOC-1 … DOC-5** *(paralelo, tras BASE-1)*: README, archivado de obsoletos, decisiones descartadas, `BUILD.md`, consolidación de docs de Level/Sync (ver §10).

### Fase 1 — Residuo y core (coordinado)
- **DEAD-1** *(paralelo-safe)*: eliminar `Packages/AudioIOSpike/` (huérfano, 0 refs) + sus artefactos; quitarlo de cualquier doc.
- **DEAD-2** *(secuencial, único dueño core)*: decidir y aplicar la poda/etiquetado de la capa de relojes y stubs de fase 2 de `KairosCore`; actualizar tests; mantener 100% verde.
- **DEAD-3** *(coordinar con UI)*: quitar etiquetas hardcodeadas “BlackHole 1-2…” de `LevelRenderer.swift:1163-1169` → derivar de `sourceName`/`sourceSlot`.
- **ARCH-1** *(paralelo)*: `docs/arquitectura.md` con diagrama real + decisión de `KairosCore`.

### Fase 2 — Descomposición del God file (secuencial, un dueño)
- **SHELL-1**: dividir `DesktopShell.swift` por responsabilidad **sin cambiar comportamiento** (verificar con los tests existentes de `DesktopShellModel`/metrics). Renombrar `*Preview*` de runtime.

### Fase 3 — Núcleo funcional (secuencial + prueba manual)
- **AUDIO-1/SYNC-1**: verificar coherencia del flujo Level (telemetría) y Sync (Internal/USB/Link); fijar bugs abiertos confirmados (R6) con validación en vivo.
- **STATE-1**: mapa de propiedad del estado + extracción testeable del transporte.

### Fase 4 — UI, estilos, performance, a11y (mayormente paralelo)
- **UI-1** iconos reales de Figma · **UI-2** estados de botón · **UI-3** paneles responsivos + scroll sidebar · **DS-1** design-system macOS-only · **PERF-1** verificación límites/efectos + sesión larga · **A11Y-1** mínimos.

### Fase 5 — Build, DMG, release
- **BUILD-1** `AppIcon.appiconset` (Branding Figma) · **BUILD-2** `scripts/release-dmg.sh` · **BUILD-3** `docs/release.md` (firma/notarización/sandbox/`--recursive`) · **FIGMA-1** limpieza del archivo Figma.

### Fase 6 — Cierre
- **GIT-1** checklist de publicación + **tag `v1.0.0`** + release notes.

---

## 8. Tareas paralelizables por agentes

Pueden avanzar **a la vez** porque están aisladas por dominio y no tocan el estado global ni el God file:

- **DOC-1…5** (README, archivado, decisiones descartadas, BUILD, consolidación docs).
- **ARCH-1** (documento de arquitectura).
- **DEAD-1** (borrar `AudioIOSpike`).
- **DS-1** (reescribir `kairos-design-system.md` a macOS-only) — siempre que no edite `DesktopShell.swift`.
- **BUILD-2 / BUILD-3** (script DMG y doc de release).
- **FIGMA-1** (limpieza de Figma) — trabajo fuera del repo de código.
- **A11Y-1** y **PERF-1** en su fase de *revisión/diagnóstico* (sin tocar código compartido todavía).

---

## 9. Tareas que NO deben hacerse en paralelo

Tocan arquitectura, estado global o archivos compartidos grandes → **secuenciales y con coordinación**:

- **BASE-1** (commitear el árbol sucio) **antes que cualquier otra cosa**. Nada empieza con el tree dirty.
- **SHELL-1** (descomponer `DesktopShell.swift`): **un solo agente**, sin que nadie más toque ese archivo hasta cerrarlo. Es el cuello de botella físico (todo el UI vive ahí).
- **DEAD-2** (poda de `KairosCore` + tests): único dueño del core; cambia API y tests.
- **STATE-1 / AUDIO-1 / SYNC-1**: tocan transporte/telemetría/estado del que dependen Grid, Level y UI. Coordinar y **validar en vivo** antes de soltar dependientes.
- **DEAD-3 / UI-2 / UI-3 / DS-1** comparten `LevelRenderer.swift`/`GridRenderer.swift`/`DesktopShell.swift`: **serializar** los que toquen el mismo archivo o esperar a que SHELL-1 cierre.
- **GIT-1 / tag** al final, cuando todo lo demás esté verde.

---

## 10. Documentación que debe crearse o actualizarse

| Acción | Archivo | Detalle |
|---|---|---|
| **Crear** | `README.md` (raíz) | Qué es Kairos, stack (Swift/SwiftUI macOS 14), alcance v1 = **solo macOS**, cómo correr, estructura de módulos, dónde está el flujo Level (M4L), cómo instalar (DMG). Punto de entrada inexistente hoy. |
| **Crear** | `docs/arquitectura.md` | Diagrama real Grid/Level/Sync/Estado; qué de `KairosCore` está cableado y qué no. |
| **Crear** | `docs/decisiones-descartadas.md` | móvil/tablet/iPhone/iPad fuera; BlackHole degradado a histórico; MIDI Clock genérico descartado; broadcast a iOS descartado; captura de audio en la app descartada. |
| **Crear** | `docs/release.md` | build Release, DMG, firma ad-hoc vs Developer ID, notarización **opcional**, Gatekeeper (“abrir con clic derecho”), `git clone --recursive`, sandbox OFF (necesario para UDP). |
| **Crear** | `docs/usabilidad.md` (mínimo) | criterios mínimos de estados/contraste/hit-targets para directo. |
| **Actualizar** | `kairos-design-system.md` | quitar responsive móvil/tablet (41 menciones); conservar tokens válidos; alinear con la implementación macOS. |
| **Actualizar** | `BUILD.md` | quitar la validación iOS ya inútil; reflejar workspace real y submódulo. |
| **Consolidar** | `docs/setup/level-max-for-live.md` (+ `MaxForLive/README.md`) | ya vigentes; promover a doc técnico de referencia de Level; documentar el legacy `gridlink.rms.v1` como compat intencional. |
| **Archivar** | `docs/historico/` ← `mobile-evo.md`, `docs/setup/blackhole-aggregate.md` + scripts/artefactos BlackHole, y copia anotada de PRD/roadmap | Cabecera “ARCHIVADO — referencia histórica, NO es estado vivo”. |
| **Reparar** | `kairos-origen.md` | primer renglón corrupto (`).`). Decidir si se archiva. |

---

## 11. Limpieza del repositorio

- **Commitear el árbol sucio** (`BASE-1`) dividido por dominio. Es el prerrequisito de todo.
- **Eliminar** `Packages/AudioIOSpike/` (huérfano, fuera del workspace, 0 referencias) y sus `.build`/`dSYM`.
- **Podar** (o etiquetar como “no cableado”) la capa de relojes y los stubs de fase 2 de `KairosCore` (`NetworkBroadcaster.swift` y `AudioEngine.swift` son stubs de 4–6 líneas; `Internal/AbletonLink/MIDIClock`, `ClockSource`, `ClockTimeline`, `OriginLatch`, `DynamicsPublisher`, `RMSPeak`, `DynamicsMeter`, `LocalConsumer` están sin consumir por la app).
- **Quitar** las etiquetas “BlackHole 1-2…” de `LevelRenderer.swift`.
- **Decidir el target iOS** de `KairosCore/Package.swift` (`.iOS(.v17)`): quitarlo (fase 2 cancelada) o dejarlo documentado como inerte.
- **Eliminar** rutas absolutas `/Users/...` de la documentación.
- **Verificar** `.gitignore` (ya correcto) y evaluar si `.claude/settings.local.json` debe versionarse (inocuo, pero opcional).
- **Configurar remoto GitHub** + primer push.
- Cada eliminación se **documenta** en el resumen de fase (qué, por qué, referencias comprobadas).

---

## 12. Limpieza del proyecto de Figma

> ⚠️ El MCP de Figma en vivo (a fecha de auditoría) devuelve **una sola página de nivel superior: “Portada”
> (`380:3033`)** en el archivo `kairos-design-system` (`GFhOPG6jAQdos0l8nkHytA`). Esto **diverge** de la
> estructura multipágina (00-docs … 05-screens) documentada en el histórico del proyecto. **Antes de actuar,
> confirmar el estado real con el archivo abierto** (puede haber sido reorganizado, o ser otro archivo/branch).

Una vez confirmado el estado, los objetivos de limpieza son:

- **Eliminar/archivar las pantallas y reglas de móvil/tablet** (evidencia de que existen: `figma-screen-references/*mobile*`, `*tablet*` y 41 menciones en el design-system). Fuera de alcance v1.
- **Confirmar la página `Branding`** con los **iconos de la app y del DMG**; exportar el set para `AppIcon.appiconset` (BUILD-1). El briefing la menciona explícitamente.
- **Dejar una sola fuente de verdad** de tokens/variables alineada con la implementación macOS y con `kairos-design-system.md` ya saneado.
- **Renombrar/ordenar páginas** para que un humano o agente futuro navegue sin tropezar con estados descartados.
- Anotar en el archivo (o en `docs/`) qué es histórico y qué es vivo.

---

## 13. Build, DMG y preparación de release

**Estado actual:** `MARKETING_VERSION=1.0.0`, bundle `com.diegofernandezmunoz.Kairos`, macOS 14, firma
`Automatic` sin team, **sin entitlements**, **sin app icon**, **sin script de DMG**, submódulo Link.

Checklist de release:

- [ ] **App icon**: crear `AppIcon.appiconset` desde Branding (Figma) + `ASSETCATALOG_COMPILER_APPICON_NAME`.
- [ ] **Reproducibilidad**: documentar `git clone --recursive` (o `submodule update --init --recursive`); verificar build Release limpio en un Mac sin caché.
- [ ] **Sandbox**: confirmar **OFF** (la app abre un socket UDP entrante 51515; con sandbox haría falta entitlement de red). Documentarlo para que nadie lo active sin querer.
- [ ] **Firma**: decidir ad-hoc/local vs Developer ID. Notarización **opcional** (uso privado, no App Store).
- [ ] **DMG**: `scripts/release-dmg.sh` (build Release → `.app` → `create-dmg`/`hdiutil` con fondo/branding).
- [ ] **Instalación en Mac de un amigo**: instrucciones de Gatekeeper (“clic derecho → Abrir”) si va sin notarizar.
- [ ] **`docs/release.md`** con todo lo anterior, para regenerar el instalador en el futuro.

---

## 14. Checklist de definición de “terminado” para la versión 1

**Repositorio**
- [ ] `main` limpio (sin cambios sin commitear), build macOS + `swift test` (KairosCore y app) en verde.
- [ ] Repo en GitHub, sin rutas absolutas ni secretos, `.gitignore` correcto.
- [ ] `tag v1.0.0` + release notes.

**Código**
- [ ] `Packages/AudioIOSpike` eliminado; capa muerta de `KairosCore` podada o etiquetada.
- [ ] Sin residuo BlackHole en el path de Level (incl. etiquetas de UI).
- [ ] `DesktopShell.swift` descompuesto por responsabilidad; nombres de runtime ya no dicen “Preview”.
- [ ] Sin marcadores `TODO/HACK` nuevos sin justificar.

**Funcional (validado en vivo con Ableton + M4L + Link/USB MIDI)**
- [ ] Level: cada *source* M4L se asigna a su lane; `No signal`/`receiving`/`clipping` correctos; clip pinta masa roja; target line sigue el valor configurado; conflictos detectados.
- [ ] Grid: pulso musical correcto (1/4 = negra = 1 beat), anticipación = solo el step activo, reset combinado/general visibles y **reset fiable** (no 1/5 clics).
- [ ] Sync: Internal / USB MIDI / Link conmutan y arrastran tempo/transport; offset afecta render y click coherentemente.
- [ ] Metrónomo: click a tempo, alternancia visual, respeta offset.
- [ ] Estabilidad: sesión de directo larga sin fugas ni degradación.

**Diseño / docs**
- [ ] `kairos-design-system.md` macOS-only y alineado con Figma; iconos reales importados.
- [ ] README + arquitectura + decisiones-descartadas + release + nivel/sync documentados; obsoletos archivados.

**Distribución**
- [ ] App icon presente; DMG generado e instalado con éxito en otro Mac.

---

## 15. Instrucciones directas para agentes de código

> Copia este bloque como guía de trabajo. Aplica a **todos** los agentes que toquen Kairos en v1.

1. **No empieces a refactorizar sin entender el dominio.** Lee el código real del dominio afectado **antes** de tocarlo. El código funcional es la fuente de verdad; la documentación antigua **no**.
2. **Primero, baseline limpia.** Si el árbol de trabajo está sucio, **no trabajes encima**: párate y avisa. Nada se construye sobre cambios sin commitear.
3. **No reintroduzcas funcionalidades descartadas:** nada de móvil/tablet/iPhone/iPad, captura de audio con BlackHole como dependencia principal, “MIDI Clock” genérico, ni broadcast a iOS. Si lo ves en docs antiguos, es residuo, no requisito.
4. **macOS-only.** El único target de producto es la app macOS. `KairosCore` puede seguir siendo el core lógico testado de macOS; no “dejes preparado” iOS.
5. **No hagas cambios visuales que contradigan Figma.** Si un valor del código difiere de Figma, **marca el desajuste** (“calibration mismatch”); no lo hardcodees ni recalibres por tu cuenta.
6. **No toques audio, sync, Grid o Level sin prueba manual posterior** (Ableton + dispositivo M4L + Link/USB MIDI). Esos dominios no se dan por buenos solo con que compile.
7. **Antes de eliminar una pieza, comprueba referencias** en runtime, tests, build (`pbxproj`/workspace), documentación y Figma. **Documenta toda eliminación** de código muerto (qué, por qué, qué referencias verificaste).
8. **`DesktopShell.swift` tiene un solo dueño a la vez.** Si te asignan SHELL-1, nadie más edita ese archivo hasta cerrarlo. Si NO es tu tarea, no lo toques: coordina.
9. **Separa commits por dominio.** Nada de commits gigantes que mezclen UI + lógica + build + docs (como `7d11bfe`). Un PR = un dominio.
10. **Mantén el verde.** Tras cada cambio: `swift test --package-path KairosCore` y los tests del app target deben pasar; la app macOS debe compilar. Si rompes un test, arréglalo o justifica el cambio de contrato.
11. **No cambies contratos de `KairosCore` a la ligera.** Si necesitas API nueva, hazlo aditivo y con tests; documenta el cambio.
12. **Al cerrar cada fase, deja un resumen**: qué se tocó, qué se eliminó, qué queda pendiente y qué hay que testar manualmente.

---

### Apéndice — Evidencia clave de la auditoría (anclas)

- Pivot de audio: `Kairos/LevelTelemetryReceiver.swift` (UDP 51515), `Kairos/LevelRuntimeDriver.swift`, `docs/setup/level-max-for-live.md` (“BlackHole… solo referencia histórica”), `MaxForLive/README.md`.
- Residuo BlackHole en UI: `Kairos/LevelRenderer.swift:1163-1169`.
- Sync real: `Kairos/AppSettings.swift:4` (`SyncSource`), `Kairos/USBMIDISyncBridge.swift`, `Kairos/AbletonLinkBridge.swift`; legacy migrado: test `testLegacyMidiSyncSourceDecodesAsInternalClock`.
- God file: `Kairos/DesktopShell.swift` (4 622 líneas, ~55 tipos).
- Core sin cablear: `KairosCore/Sources/KairosCore/TimeDomain/{InternalClock,AbletonLinkClock,MIDIClock,ClockSource,ClockTimeline,OriginLatch}.swift`, `.../DynamicsCore/{NetworkBroadcaster,AudioEngine,DynamicsPublisher*,RMSPeak*,DynamicsMeter,LocalConsumer}.swift`.
- Paquete muerto: `Packages/AudioIOSpike/` (0 refs, fuera del workspace).
- Build/distribución: `Kairos.xcodeproj/project.pbxproj` (sin app icon/entitlements/team), `Assets.xcassets` (sin `AppIcon.appiconset`), `.gitmodules` (submódulo Link).
- Baseline sucia: `git diff --stat` = 13 archivos, +2360/−556.
