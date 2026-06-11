).

# PRD — 3

## 1. Resumen ejecutivo

Kairos es una aplicación de escritorio nativa para macOS y IOs que actúa como **referencia visual compartida** durante las jam sessions y grabaciones del grupo Slowpatch. Reúne en una sola pantalla cuatro capas: 
1. **Grid**: un **contador de compases** que muestra la posición estructural de varios ciclos temporales en paralelo.
2. **Level**: un **medidor de dinámica** que muestra si la señal se está grabando dentro de un rango sano de volumen.
3. **Sidebar**: menu lateral de configuración de la app
4. **Tool-bar**: una pequeña barra superior de visualización de datos y controles generales

Las cuatro capas beben de un **único clock común"** que puede estar sincronizado con el reloj interno de la app, con una entrada MIDI IN, o con Ableton mediante Ableton Link. Cuando se pulsa Play en Ableton, en dispositivo MIDI externo, o en la app, la herramienta arranca y se limita a visualizarse. Durante la toma nadie la opera: es una superficie de observación, no un panel de control.

El producto se comporta como un instrumento de escenario, no como una aplicación de producción. Su criterio de éxito no es la precisión de medición, sino que cualquiera de los músicos pueda mirarla un segundo, a dos metros de distancia, y entender dónde está el sistema en el tiempo y si el volumen es sano.

---

## 2. Problema y objetivo

El grupo Slowpatch trabaja con secuenciadores, sintetizadores y hardware externo sincronizados a un tempo común, en formato de improvisación organizada y no de canción cerrada. De ahí surgen dos fricciones recurrentes:

**Orientación temporal y estructural.** Durante la jam, cada músico gestiona patrones de duración distinta. Sin una referencia visual común, cada uno cuenta mentalmente o mira la interfaz de su máquina, lo que dificulta coordinar entradas, salidas y transiciones. Hace falta un ancla que diga dónde está cada ciclo y cuándo va a cerrar.

**Gain staging.** Por falta de una referencia de volumen clara, las grabaciones acaban demasiado bajas (obligando a subir ganancia en postproducción y exponiendo ruido) o demasiado altas (saturando). Hace falta una lectura inmediata de si la señal del máster vive en una zona cómoda.

El objetivo es resolver ambas con una sola herramienta, sin que ninguna de las dos capas obligue a leer números ni a pensar mientras se toca.

---

## 3. Principios de producto

- **Instrumento de escenario, no panel de producción.** La pantalla existe para tocar mejor, no para mostrar más datos. Si una función pide atención sostenida o lectura analítica, no pertenece a esta herramienta.
- **Anticipación antes que precisión.** En directo importa más preparar una acción a tiempo que medir con exactitud microscópica.
- **Lectura periférica a dos metros.** Tamaños grandes, alto contraste, fondo oscuro, jerarquía estricta. Todo debe entenderse de reojo.
- **Cero interacción durante la toma.** Play, la app se visualiza, punto. La configuración ocurre antes de tocar.
- **Una sola fuente de tiempo.** Las capas comparten el mismo clock. Nunca dos sistemas temporales en conflicto.

---

## 4. Arquitectura conceptual y fuentes de datos

La herramienta no secuencia nada. Consume dos flujos de entrada y los convierte en una superficie visible.

**Audio (capa de dinámica).** La app puede recibir hasta 4 fuentes de audio estéreo. Aunque a la interfaz lleguen más de veinte canales por distintas tarjetas vía ADAT, todo se organiza en Ableton y solo se envían de 1 a 4 buses seleccionados. El audio se envía a la app a través de **BlackHole** (driver de audio virtual, gratuito y de código abierto), ruteándolo como salida adicional mediante un Aggregate Device en Configuración de Audio MIDI. La app abre BlackHole como dispositivo de entradas estéreo y calcula los niveles de **L y R por separado**. No hay cables físicos ni latencia analógica añadida.

La medición se hace por canal (no sumando L+R en crudo) por una razón de fiabilidad de gain staging: una suma cruda haría que la señal centrada subiera ~3 dB respecto a la lateral, desplazando la referencia según la imagen estéreo. Medir cada canal por separado da una lectura estable y, sobre todo, evita el punto ciego de un promedio: si casi toda la energía vive en un canal, ese canal puede estar pegándose a 0 dB mientras un valor promedio aún indicaría nivel cómodo. El medidor muestra por tanto **dos masas (L y R)** sobre la misma escala, y el indicador de clip vigila el pico real de ambos canales.

**Tiempo.** La fuente puede ser de tres tipos, seleccionables: 

1. **Internal**: reloj generado por la propia app a partir de su BPM, para cuando no hay sincronía externa. 
2. **MIDI Clock**: alternativa que detecta interfaces MIDI conectadas al ordenador.
3. **Link (ableton)**: modo ideal, con Ableton como maestro por defecto. Link comparte el tempo y una línea de beats común; el compás (cuántos beats por compás y dónde cae el "1") se gestiona mediante el _quantum_ de Link y la métrica configurada en la app, y cuando Ableton hace Play la app arranca sincronizada. El comportamiento del transporte cambia según el modo.

**Reloj único.** Ambas capas derivan del mismo reloj, sea cual sea su fuente (Link, MIDI Clock o Internal). La app tiene un Reset propio para realinear la visualización cuando haga falta, pero ese Reset no rompe la sincronía externa: solo reposiciona lo que se muestra.

**Offset visual (delay).** Un control global de offset en milisegundos (rango **±200 ms**) adelanta o retrasa lo que se pinta respecto al beat de Link y al buffer de audio, para compensar la latencia entre Ableton, el hardware externo y la referencia visual.

---

## 6. Estructura de la interfaz

La pantalla se organiza en una composición de **dos zonas** sobre una misma superficie, con una jerarquía visual estricta. El diseño visual concreto (formas, color, tipografía, proporciones exactas) se trabajará en Figma y se replicará a medida; este documento define la función y el comportamiento, no el aspecto final.

### 6.1 Main content (visualizado)

**Cuerpo principal – Grid (contador de compases).** Es la capa que resuelve el problema principal y ocupa la parte superior. Es la información dominante (a no ser que el panel de grid esté desactivado en la configuración).

**Zona perimetral – Level (medidor de dinámica).** Vive como una franja de lectura periférica inferior. No compite con el contador. La única excepción a esa discreción es el **indicador de clip**, que sí puede reclamar atención cuando se supera 0 dB. 

**Modularidad**: ambas capas son opcionales y pueden desplegarse o no mediante un botón.

### 6.2 Sidebar o menu lateral desplegable

**Configuración de elementos comunes.** Estado y fuente de sincronía, delay offset, BPM, y ajustes de metrónomo.

**Configuración del Grid**. Selección y personalización de canales de ciclos.

**Configuración de Level**. Selección y personalización de canales de audio.

### 6.3 Top-bar
Línea superior con controles generales (play, reset y metrónomo) y visualización de datos (estado del sync, bpm, y tiempo)

---

## 7. Capa 1 — Grid (Contador de compases)

### 7.1 Modelo

El sistema se basa en cuatro conceptos: **reloj común**, **canal temporal**, **step** y **reset**. Cada canal interpreta el reloj común con su propia longitud y subdivisión. El avance es **cuantizado**: el canal cae en un step, permanece y salta al siguiente cuando corresponde. No es una animación continua, porque debe sentirse como tiempo musical de secuenciador.

La clave de la referencia temporal es la **relación entre canales de distinta longitud**. Un canal largo de 128 steps combinado con otros de 16, 8 o 4 deja ver de un vistazo proporción, velocidad relativa y proximidad de cierres. Esa relación, no una vista auxiliar, es lo que orienta al grupo.

El panel de grid puede desplegarse en pantalla o no mediante un toggle. Su visualización es opcional

### 7.2 Canales

- Mínimo 1, **máximo 4 canales**. En UI se llaman Cycles
- Todas las filas ocupan el **mismo ancho visual**, de modo que la longitud del ciclo se traduce en densidad: un canal de 4 steps se ve amplio; uno de 128 se ve fino y estructuralmente largo.
- La lectura es horizontal, de izquierda a derecha.

### 7.3 Configuración por canal

Cada canal tiene cuatro parámetros:

1. **on/off**: toggle del canal
2. **Step number**: Rango de 1 a 128. Valores: 1, 2, 4, 8, 16, 32, 64, 128. Más steps no se ven bien en pantalla, por ello 128 es lo máximo. 
3. **Pulse**: Define cuánto dura cada step respecto al beat general. Es la velocidad a la que avanza cada canal en el grid. Escala de 1/16 a 64.
4. **Mode (visualization)**: block (masa sólida, mejor para ciclos cortos/medios), border(stroke interior del bloque. visibilidad media) o line (más ligera, mejor para alta densidad; la línea coincide con el borde inicial del step).

El grid muestra sólo la parte visual del progreso de steps en los canales activos. La info de cada canal y sus controles se ven únicamente en el sidebar de configuración.

### 7.4 Estados

Los steps tienen dos estados durante la reproducción:
- **Active**: step presente. Usa un color claro para hacer referencia a la actividad.
- **Inactive**: steps futuros o pasados. Su color es más oscuro para referenciar la inactividad.

### 7.5 Resets y lectura de horizonte

Un reset ocurre cuando un canal completa su ciclo y vuelve al primer step. Es un cierre estructural y un punto natural para entrar, salir, mutear o transicionar. La herramienta distingue dos niveles, pintados **sobre la propia barra**, nunca como icono o capa externa:

- **Reset combinado.** Dos o más canales reinician a la vez, pero no todos. Realce verde del primer step: coincidencia parcial.
- **Reset general.** Todos los canales activos reinician a la vez. Realce morado del primer step: alineación total, punto de mayor peso estructural.

### 7.6 Anticipación

Para reforzar la anticipación sin una vista auxiliar, **el último tramo de steps de cada ciclo se ilumina de forma diferenciada** en rojo, para señalar que el reinicio es inminente. Este realce rojo ocurre sólo en los ciclos de 8 o más steps, en 1, 2 y 4 se evita para no saturar con rojo.

Tramos finales señalados de cada ciclo:
- 1 - realce rojo desactivado
- 2 - realce rojo desactivado
- 4 - realce rojo desactivado
- 8 - realce rojo en el último step
- 16 - realce rojo en los últimos 4 steps
- 32 - realce rojo en los últimos 4 steps
- 64 - realce rojo en los últimos 4 steps
- 128 - realce rojo en los últimos 8 steps

---

## 8. Capa 2 — Level (medidor de dinámica)

### 8.1 Métrica

La métrica núcleo y única es **RMS**, integrado de forma estable (ventana cercana a 1 segundo, tipo VU) para responder a la energía media sin reaccionar de forma nerviosa a cada transitorio. Es la lectura relevante para gain staging. 

### 8.2 Escala vertical

- Eje **lineal en dB**, de **0 a -60 dB**. No se aplica curva adicional sobre los dB y no hay autoescalado: la escala se comporta como una regla fija para que -18, -12 o -24 sean lugares reconocibles en pantalla.
- La distancia entre dos valores en pantalla es proporcional a su diferencia en dB.

### 8.3 Target level 

- **Threshold móvil** (por defecto -12 dB), ajustable en preparación. No es una frontera de bien/mal: es una línea de referencia que revela cuánto está la señal por encima o por debajo del objetivo.
### 8.4 Zonas de referencia

Además hay bandas de referencia en las áreas de mayor importancia:

| Zona                | Rango aprox. | Lectura                         |
| ------------------- | -----------: | ------------------------------- |
| Crítica superior    |    0 a -6 dB | Señal muy alta, margen reducido |
| Fuerte controlada   |  -6 a -12 dB | Intensa pero utilizable         |
| Cómoda de grabación | -12 a -24 dB | Área principal de trabajo       |
| Baja utilizable     | -24 a -30 dB | Aprovechable según contexto     |
| Residual            | -30 a -60 dB | Colas, ruido, silencio práctico |


### 8.5 Visualización

La lectura se basa en **masa visual**, no en una línea fina que exija seguimiento ocular. El nivel se representa como **dos masas, L y R**, contra la escala fija, con comportamiento cromático distinto según estén por un rango superior o inferior al target level. El objetivo no es leer "-19,4 dB", sino reconocer de un vistazo que se está en zona cómoda y si los dos canales están equilibrados.

La visualización combina dos lecturas sobre la misma escala fija:

- **Nivel actual:** las dos masas (L y R) que muestran dónde está la señal ahora.
- **Histórico reciente:** la silueta del pasado próximo, que muestra hacia dónde viene moviéndose la energía. Es una pieza central, no secundaria: el nivel actual dice _dónde estás_, pero la trayectoria dice si llevas demasiado tiempo en un punto bajo (momento de crecer) o demasiado tiempo intenso (momento de reducir o cambiar). Esta lectura de tendencia es parte de la primera fase.

El histórico ofrece cuatro ventanas temporales seleccionables (en UI estos cuatro canales se denominan "windows"): **10 s, 30 s, 1 min y 2 min**. En ventanas cortas se dibuja con detalle; en las largas se aplica agregación por columnas (cada columna resume su tramo con mínimo, máximo y media), de modo que se lee como una banda de recorrido con su tendencia media por dentro, en lugar de una línea nerviosa ilegible. Esto es a la vez más claro y más barato de renderizar.

### 8.6 Relleno, borde y color

Cada onda (L y R) tiene dos elementos visuales con funciones separadas. El **relleno** de la masa es **siempre gris**: aporta cuerpo y forma, no estado. El **borde superior** es el que lleva el **color semántico** — verde  dentro de la zona objetivo, rojo cuando se aleja del threshold más del margen definido, por arriba o por abajo. Es decir, la línea superior de cada masa es la que dice dónde está el nivel y si está bien.

Hay dos bordes, uno por canal, cada uno con su color independiente. Cuando L y R están equilibrados, los dos bordes se solapan y se leen como uno; cuando se desequilibran, se separan y ver **uno verde y otro rojo** delata por sí mismo que un canal se ha salido. La histéresis y el crossfade se aplican al color del borde, para que no titile en el límite.

La forma sigue contando la tendencia (la silueta del pasado en el eje del histórico) y el color del borde cuenta el estado actual; son dos lecturas en dos dimensiones distintas que no compiten. Las tres ventanas temporales (visualización, trazo y color) operan sobre este borde: el trazo es la línea que se dibuja, el color es el del borde.

### 8.7 Saturación (clip)

Cuando alguna muestra supera 0 dB en una onda, su **relleno** —normalmente gris— se vuelve **rojo**. No cambia el borde: el relleno es un canal aparte, reservado para esta alerta, así que el rojo de clip y el color de estado del borde conviven sin ambigüedad. Toda la masa enrojeciéndose es imposible de ignorar de reojo, que es lo que pide la señal más urgente del medidor.

El rojo **permanece con una cola de unos 2 segundos**: tras el pico, el relleno mantiene el rojo y se desvanece progresivamente, de modo que un clip fugaz se vea aunque haya durado un instante. Cuando la cola termina, el relleno vuelve a gris y el medidor sigue su lectura normal. Con L y R separados, solo se enrojece el relleno de la onda que ha saturado, señalando cuál es. No hay peak hold.

### 8.8 Marca de reset general

El histórico incorpora una referencia a los **resets generales** del contador: en el instante en que todos los canales reinician a la vez, se dibuja una **marca morada** sobre el eje temporal del medidor. La marca se **ancla a ese instante y avanza hacia la izquierda con el histórico**, conservando su correspondencia con la silueta a medida que el tiempo pasa. El morado es el color semántico del reset general en toda la herramienta, de modo que la marca enlaza la capa temporal con la dinámica y deja leer cómo se mueve la energía alrededor de cada gran reinicio.

Se mantiene a baja prominencia, para acompañar sin competir con la lectura de nivel. Solo se referencia el reset general; los combinados no aparecen en el medidor, para no recargar la franja.


## 9. Capa 3 — Sidebar de configuración

### GLOBAL
Área de configuración de parámetros globales. Dentro hay dos secciones:

#### Sección Sync
- **Modos**: Internal, MIDI (con desplegable de canales), y Link con indicador de estado (link active/inactive + peer nº)
- **Visual offset** (selector +-200ms)

La fuente de reloj es un selector de tres posiciones: **Link**, **MIDI Clock** e **Internal**. El comportamiento del transporte depende del modo:

- **Internal.** El reloj lo genera la propia app a partir de su BPM. Aquí la app es el maestro, así que el **botón de play/reset está activo**: con él se inicia y reinicia el transporte.
- **Link / MIDI Clock.** El transporte lo manda la fuente externa (con Link, Play en Ableton arranca la app). El **botón de play y BPM quedan desactivados** (visibles pero inertes, para comunicar que el control está delegado, no roto).

En los tres modos, el **Reset propio de visualización** sigue disponible, porque no toca el transporte: solo realinea lo que se pinta.
#### Sección Tempo
- **BPM**: selector con rango de 1 a 999 BPM
- **Metronome pulse**: selector con rango 1/16-1

### GRID 
Área de configuración del Grid. Incluye un toggle on/off que quita y pone el panel de grid en el área de visualización.
Por defecto los 4 canales llamados "Cycles" están apagados. Al activarlos el canal despliega sus parámetros ocultos: 
- Steps
- Pulse
- Mode

### LEVEL 
Área de configuración del Level. Incluye un toggle on/off que quita y pone el panel de level en el área de visualización.
Por defecto los 4 canales llamados "windows" están apagados. Al activarlos el canal despliega sus parámetros ocultos: 
- Target level
- History range
- Share data (*envía datos de nivel con telemetría a la red wifi conectada. Este parámetro se usará en la actualización con la app de mobile*)

## 10. Capa 4 — tool-bar 

Se trata de la barra superior omnipresente y tiene triple función: 
#### Sección de presets
**La persistencia**: Dado que nadie configura durante la toma y que el setup se reutiliza entre sesiones, la herramienta debe **guardar y cargar la configuración** (canales con sus parámetros, threshold, offset, métrica, fuente de sincronía) como presets de sesión locales. Es una pieza pequeña pero decisiva para la adopción: sin ella, rearmar el setup a mano antes de cada ensayo es fricción que desincentiva su uso.
Un botón con el nombre del preset activo permite cambiar entre presets o guardar hasta 4 nuevos. Total 5, default + 4 personalizables. Los presets se guardan de serie dentro de la app, no se puede elegir directorio.

#### Control general (action-buttons)
plegar/desplegar sidebar, play, reset y metronome on/off. 

#### Mostrar el estado de la app (data)
Sync source y su estado, bpm y tiempo transcurrido desde el play en horas, minutos y segundos (xh xm xs). 

---

## 12. Requisitos no funcionales

- **Legibilidad**: alto contraste, fondo oscuro, jerarquía clara, poca densidad textual.
- **Estabilidad en directo** por encima de la riqueza de funciones. La app debe arrancar fiable y sostenerse sin saltos perceptibles.
- **Fluidez de render** suficiente para que el avance por steps se perciba estable, incluso con canales largos (64 y 128 steps).
- **Separación entre lógica temporal y capa visual.** El cálculo de posición, reset, coincidencias y distancia al próximo evento debe poder testearse sin depender de la capa de UI.
- **Abstracción de la fuente de reloj** desde el inicio, de modo que el resto del sistema no dependa de si el tiempo viene de Link, MIDI Clock o Internal.
- **Diseño libre.** La capa visual se dibuja a medida; no se adopta el sistema de diseño estándar de Apple.

---

## 13. Arquitectura técnica

App **nativa en Swift**, con la capa visual **dibujada a medida** (SwiftUI Canvas o Metal según exigencia de render), no con componentes estándar del sistema. Como la herramienta es casi por completo una superficie de visualización sin interacción durante el uso, dibujar a mano da libertad total para replicar el diseño de Figma y mantiene todo en una sola tecnología.

Módulos sugeridos:

- **Motor de audio.** AVAudioEngine abre BlackHole como entrada estéreo y calcula RMS de L y R por separado y detección de clip por canal. El cálculo se apoya en vDSP/Accelerate. Carga sencilla.
- **Motor de sincronía.** Tres fuentes tras una interfaz común: Ableton Link mediante su SDK oficial (LinkKit / API C `abl_link`, que aporta tempo, línea de beats y quantum para la fase de compás), MIDI Clock vía CoreMIDI, y un reloj Internal generado a partir del BPM de la app. El resto del sistema no distingue de cuál viene el tiempo.
- **Dominio temporal.** Estado de canales, avance cuantizado, detección de resets y coincidencias, distancia al próximo cierre. Lógica pura, testeable, independiente de la UI.
- **Histórico de dinámica.** Buffer de valores de RMS ya calculados (no de audio crudo) con agregación por columnas para las ventanas largas. Memoria despreciable.
- **Capa de render.** Dibujo de barras, resets, realces, rejilla, medidor de dos masas con histórico, clip y pulso. Aplicación del offset visual.
- **Persistencia.** Serialización local de presets de sesión.

---

## 14. Viabilidad y riesgos técnicos

- **Captura de audio y RMS:** triviales una vez el máster entra por BlackHole como dispositivo de entrada. Medir L y R por separado cuesta prácticamente lo mismo que un único cálculo. El indicador de clip es detección directa sobre el buffer. Sin riesgo relevante.
- **Histórico del medidor:** de bajo coste. Lo que se almacena son los valores de RMS ya calculados (del orden de unos miles para 2 minutos), no el audio. El único punto de cuidado es el dibujo en ventanas largas, resuelto con agregación por columnas (mínimo/máximo/media por píxel), que además es más legible que pintar la curva cruda.
- **Configuración de BlackHole:** requiere un Aggregate Device para que Ableton envíe el máster a BlackHole sin perder su salida principal. Es un paso de setup del usuario que conviene documentar en una guía breve; no afecta a la arquitectura de la app.
- **Ableton Link en Swift:** el SDK oficial es maduro y está pensado para apps Apple. Es la pieza con más peso de integración, pero de bajo riesgo. La gestión del compás y del "1" se resuelve con el quantum de Link más la métrica configurada.
- **Render con canales largos:** dibujar 128 celdas al mismo ancho da celdas muy pequeñas; el modo línea, la rejilla sutil y un dibujo eficiente (Canvas bien optimizado o Metal) lo resuelven. Es el punto de rendimiento a vigilar.
- **Offset visual:** simple desplazamiento temporal aplicado al render; sin complejidad.
- **Click sonoro del metrónomo:** Idealmente cargar un click sample propio y evitar sintetizar sonido 
