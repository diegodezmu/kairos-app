# Evolución de la app a móvil 


## Propósito del documento

Este documento recoge las decisiones, criterios técnicos y contexto funcional definidos para evolucionar la aplicación actual de escritorio en Mac hacia un sistema distribuido con soporte para iPhone. La aplicación existente funciona como herramienta visual de directo: muestra grids de tempo, ciclos/pulsos y un analizador de nivel en RMS para ayudar a los músicos a orientarse temporal y dinámicamente durante una jam o actuación.

El objetivo de esta evolución es permitir que la aplicación de escritorio siga siendo el nodo principal de análisis y control, mientras que dispositivos móviles, concretamente iPhones, puedan conectarse al mismo entorno musical para visualizar tempo, fase, start/stop y dinámica de nivel. La arquitectura debe separar claramente la sincronía musical de los datos propios de la aplicación.

  
## Contexto del producto

La aplicación está pensada para uso musical en directo. Su función principal no es producir sonido, sino ofrecer una referencia visual estable y periférica para músicos que trabajan con Ableton Live, hardware externo y sesiones sincronizadas por tempo. El sistema debe ayudar a leer la estructura temporal, anticipar resets o alineaciones de ciclos y controlar la dinámica de nivel de la mezcla o señal entrante.

Actualmente la aplicación de escritorio contempla varias fuentes de sincronía: modo interno, MIDI Clock y Ableton Link. El modo interno permite que la aplicación genere su propio reloj. MIDI Clock depende de seleccionar una interfaz o puerto MIDI concreto. Ableton Link, en cambio, funciona de forma distinta: no se selecciona un dispositivo o puerto, sino que la aplicación entra en una sesión Link compartida con otras aplicaciones compatibles en la misma red local.

  
## Principio central de arquitectura

La evolución móvil debe basarse en dos capas independientes. La primera capa es la sincronía musical, resuelta mediante Ableton Link. Esta capa sincroniza tempo, beat, fase y, opcionalmente, start/stop entre Ableton Live, la aplicación de escritorio y las aplicaciones móviles. La segunda capa es la telemetría propia de la aplicación, necesaria para enviar al móvil datos que Link no transporta, como RMS, picos, histórico de dinámica o estado del medidor.

La separación es importante porque Ableton Link no es un bus genérico de datos. Link permite que varias aplicaciones compartan una referencia musical común, pero no sirve para enviar datos arbitrarios de la aplicación. Por tanto, la app de iPhone debe participar directamente en Link para la sincronía temporal, y además conectarse a la app de escritorio para recibir los datos de dinámica medidos por esta.

La formulación recomendada es: ****Link para el reloj; canal propio para la dinámica****.

## Funcionamiento esperado de Ableton Link

Ableton Link debe implementarse como una fuente de sincronía activable, no como un selector de dispositivo. A diferencia de MIDI Clock, no debe aparecer un dropdown con puertos ni una lista de instancias de Ableton. Cuando el usuario activa Link, la aplicación se une a la sesión Link disponible en la red local. Si no hay ningún otro participante, la aplicación sigue estando en modo Link, pero aparece como único peer.

No debe mostrarse un modal de error cuando Link está activo y no hay otros peers. La ausencia de peers no es un fallo. Es un estado normal del sistema. La app simplemente está disponible dentro de Link y podrá sincronizarse automáticamente cuando Ableton Live u otra aplicación compatible active Link en la misma red. Sólo aparecerá un modal cuando el móvil no esté conectado a ninguna red wifi. 

La interfaz debe mostrar estados discretos como:

```text

Link off

Link active · no peers

Link active · 1 peer · 124 BPM

Link active · 2 peers · 124 BPM

```

  

Un modal o alerta solo tendría sentido si existe un problema real: permisos de red local denegados, firewall bloqueando descubrimiento, fallo al iniciar Link, red no disponible o error técnico explícito. No debe utilizarse un modal para informar de que no hay peers.

  

## Relación entre Ableton Live y la aplicación

  

Ableton Live no debe entenderse como un maestro central al que la aplicación se conecta. Link es peer-to-peer en términos conceptuales: todos los participantes entran en una sesión común. Ableton Live, la app de escritorio y la app de iPhone son peers dentro de esa sesión.

  

Para que la aplicación se sincronice con Live, Live debe tener Link activado. No basta con que Ableton esté abierto o reproduciendo audio. Si Live reproduce pero Link está apagado, la aplicación no debería recibir tempo/fase desde Live vía Link.

  

Cuando Live tenga Link activado y la aplicación active Link, ambos deberían detectarse automáticamente si están en la misma red local o en el mismo equipo, según la plataforma. No debe existir una acción de “conectar a Ableton Live”. La lógica debe ser “activar Link” y mostrar el estado de la sesión.

  

## Control de tempo dentro de Link

  

A pesar de que Link no funciona como un modelo maestro/esclavo tradicional, y que  cualquier peer puede modificar el tempo de la sesión, para evitar errores de grabación, ableton link se establece como master tempo por defecto, dejando incapacitada la opción de modificar tempo y pulsar play al resto de peers de la red. Todos los peers, app de escritorio, y apps de iphone se limitan a ser esclavos de tempo y transporte (play/stop). En modo internal si que podrán hacer uso del selector de bpm y del botón play.
  


## Grid Offset / Visual Offset

  

La aplicación contempla un offset para ajustar la sincronía visual respecto al sonido real. Esta opción sigue teniendo sentido aunque la aplicación esté sincronizada por Ableton Link.

  

Link proporciona una referencia común de tempo, beat y fase, pero no debe asumirse que exporta toda la compensación de latencia del setup de Ableton Live. La señal puede pasar por hardware externo, interfaz de audio, buffers, compensaciones internas, monitorización, latencia de pantalla y renderizado visual. Aunque Live esté bien compensado internamente, la percepción visual de la app puede necesitar ajuste local.




Este offset no debe modificar la sesión Link ni la fase compartida con otros peers. Debe aplicarse únicamente antes de renderizar la interfaz local. La lógica sería:

  

```text

recibir tempo/phase desde Link

aplicar Offset local

renderizar barras, grids o indicadores visuales

```

  

El offset debe entenderse como calibración escénica. No corrige Link; corrige la forma en que la referencia Link se representa visualmente en un dispositivo concreto.

  

## Evolución a iPhone: app móvil como peer Link

  

La evolución móvil debe asumir que cada iPhone puede ser un peer Link nativo. Esto significa que la app iOS debe integrar LinkKit o el SDK/plataforma equivalente para participar directamente en la sesión Ableton Link.

  

La app móvil no debería depender del Mac para recibir tempo si el objetivo es una sincronía musical robusta. El Mac no debe actuar como “servidor de tempo” para el iPhone si el iPhone puede participar directamente en Link. La arquitectura recomendada es que Ableton Live, la app de Mac y la app de iPhone estén todos en la misma sesión Link.

  

El iPhone renderiza localmente sus propios grids a partir de la referencia Link. No recibe frames ni capturas de pantalla desde el Mac. Recibe la base temporal común y calcula su visualización en local.

  

El flujo esperado sería:

  

```text

Ableton Live: Link activado

App Mac: Sync Source = Ableton Link

App iPhone: Link activado

Todos los dispositivos en la misma red local

Cada app muestra estado de peers y BPM compartido

```

  

La app móvil debe mostrar estado de Link de forma parecida a la app de escritorio:

  

```text

Link active · no peers

Link active · 2 peers · 124 BPM

Tempo and play control: read-only by design

```

  

## Red local y condiciones de conectividad

  

Los dispositivos deben estar en la misma red local. Link no debe depender de internet, pero sí necesita que los dispositivos puedan descubrirse y comunicarse en la LAN/Wi‑Fi. En un contexto de directo o ensayo, la recomendación es usar un router dedicado, aunque no tenga conexión a internet. Es preferible evitar redes públicas, redes saturadas, redes de invitados con aislamiento entre clientes o Wi‑Fi inestable.

  

En iOS hay que contemplar permisos de red local. Desde iOS 14, las apps que descubren o interactúan con dispositivos en la red local deben pedir permiso al usuario. Si este permiso se deniega, la app puede parecer incapaz de encontrar otros peers o fuentes de datos aunque la red sea correcta.

  

Además, según la implementación concreta, puede ser necesario contemplar el entitlement de multicast de Apple si se usan mecanismos de descubrimiento basados en multicast. Esto debe verificarse durante la implementación de LinkKit y de Bonjour/mDNS.

  

La app debe tener mensajes de error claros para estos casos, diferenciando entre:

  

```text

Link active · no peers

Local network permission denied

Network unavailable

Firewall or discovery issue

Level source not found

```

  

“No peers” no es un error. Permiso denegado o fallo de red sí lo es.

  

## Dinámica RMS: por qué hace falta una segunda conexión

  

La aplicación de escritorio no solo muestra grids; también mide dinámica de nivel en RMS. Esta medición proviene de una entrada de audio o de una señal monitorizada en el Mac. Si los iPhones deben visualizar esa misma dinámica, la información debe enviarse desde la app de escritorio a las apps móviles mediante un canal propio.

  

Ableton Link no transporta RMS, clipping, histórico de dinámica ni ningún dato arbitrario de la aplicación. Por tanto, para dinámica hace falta una conexión directa o semidirecta entre la app desktop y los móviles.

  

La app de escritorio debe actuar como fuente de dinámica. La app móvil debe actuar como cliente/receptor de dinámica.

  

La arquitectura recomendada es:

  

```text

Ableton Link: tempo, beat, phase, start/stop opcional

Canal propio Mac → iPhone: RMS, peak, histórico, clipping, estado del medidor

```

  

## Transporte recomendado para dinámica

  

Para el primer diseño serio, la opción recomendada es:

  

```text

Bonjour/mDNS para descubrimiento

WebSocket para streaming de datos

```

  

Bonjour/mDNS permite que los iPhones encuentren automáticamente la app de escritorio en la red local. WebSocket permite mantener una conexión persistente y enviar valores numéricos de dinámica varias veces por segundo. Es fácil de depurar, suficiente para la cantidad de datos necesaria y más cómodo que diseñar una capa UDP desde cero.

  

OSC por UDP podría ser una alternativa en contextos musicales, pero no se recomienda como base inicial porque añade más complejidad en conexión, estado, reconexión, entrega de datos y depuración. Para un sistema visual de RMS, WebSocket es más práctico.

  

El flujo recomendado es:

  

```text

App Mac calcula RMS

App Mac anuncia servicio de dinámica en red local

App iPhone descubre fuentes disponibles

Si hay una fuente, se conecta automáticamente

Si hay varias fuentes, muestra selector de Dynamics Source

App iPhone recibe muestras y renderiza localmente el medidor

```

  

## Selector de fuente de dinámica

  

Aunque Link no necesita selector de dispositivo, la dinámica sí puede necesitarlo. Si solo hay una app de escritorio en la red, el iPhone puede conectarse automáticamente. Si hay varias, la app móvil debe mostrar un selector de fuente:

  

```text

Level Source

- MacBook Pro de Diego

- Mac mini escenario

- Studio Mac

```

  

Este selector no debe confundirse con Link. Link es una sesión musical común; Level Source es la fuente concreta de datos RMS.

  

La app móvil debe poder estar en uno de estos estados:

  

```text

Link active · no dynamics source

Link active · receiving dynamics from MacBook Pro

Link active · dynamics source lost

Link off · receiving dynamics from MacBook Pro

```

  

Es importante que Link y dinámica sean independientes. Si se cae la fuente de dinámica, el grid puede seguir sincronizado por Link. Si Link se desactiva, el medidor de dinámica podría seguir recibiendo datos, aunque sin referencia musical común.

  

## Qué datos enviar al iPhone

  

No se deben enviar imágenes, frames o capturas de la visualización del Mac. El Mac debe enviar datos estructurados y el iPhone debe reconstruir su propia visualización localmente.

  

Un paquete de dinámica podría contener:

  

```json

{

  "type": "level_sample",

  "sourceId": "macbook-pro-diego",

  "sequence": 18420,

  "measuredAtHostTime": 123456789.123,

  "linkBeat": 512.375,

  "tempo": 124.0,

  "rmsDb": -18.4,

  "peakDb": -8.1,

  "clipping": false,

  "windowMs": 100,

  "sampleRate": 48000

}

```

  

Campos recomendados:

  

```text

sourceId: identificador estable de la fuente desktop

sequence: número incremental para detectar pérdidas o saltos

measuredAtHostTime: timestamp del momento de medición

linkBeat: posición musical estimada en Link cuando se midió el valor

tempo: BPM de referencia en ese instante

rmsDb: valor RMS en dB

peakDb: valor de pico, si está disponible

clipping: estado de clipping, si está disponible

windowMs: ventana temporal usada para el cálculo RMS

sampleRate: sample rate de entrada, si es relevante

```


El objetivo es que el iPhone pueda saber no solo qué valor llegó, sino cuándo ocurrió y cómo debe colocarlo en su visualización.

  

## Timestamp y alineación temporal

  

Cada muestra de dinámica debe llevar marca temporal. Sin timestamp, el iPhone solo sabe cuándo recibió el dato, no cuándo fue medido. Esto puede producir visualizaciones retrasadas o incorrectamente alineadas con el grid.

  

Hay dos niveles de timestamp útiles:

  

```text

Timestamp de sistema/host: permite medir edad del dato y latencia aproximada

Referencia musical Link: permite colocar el valor dentro del histórico musical

```

  

Lo ideal es que cada muestra incluya una referencia temporal vinculada a Link, por ejemplo `linkBeat`, además de un timestamp técnico. Así el iPhone puede renderizar el dato sobre la misma rejilla musical que usa para pintar los grids.

  

La lógica conceptual es:

  

```text

Mac mide RMS en un instante

Mac calcula qué beat/fase Link corresponde a ese instante

Mac envía RMS + timestamp + linkBeat

IPhone recibe el paquete

IPhone coloca el dato en la línea temporal visual correcta

```

  

Esto evita que la visualización dependa únicamente del momento de llegada del paquete.

  

## Frecuencia de envío

  

No es necesario enviar datos a frecuencia de audio. El RMS ya es una medida integrada en una ventana temporal. Para visualización musical en directo, una frecuencia de entre 10 y 30 actualizaciones por segundo debería ser suficiente como punto de partida.

  

Valores orientativos:

  

```text

10 Hz: suficiente para tendencia general, muy ligero

20 Hz: buen equilibrio para medidor visual vivo

30 Hz: más fluido, aún razonable para LAN

>60 Hz: probablemente innecesario para RMS y puede complicar colas/renderizado

```

  

La app debe priorizar frescura sobre exhaustividad. En tiempo real, no tiene sentido reproducir todos los paquetes viejos si el iPhone se retrasa. Para la lectura actual, debe usarse el dato más reciente. Para el histórico, sí pueden insertarse muestras previas siempre que vengan timestamped.

  

## Snapshot inicial de histórico

Si el iPhone se conecta a mitad de una toma, no debería empezar con un gráfico vacío si la app de Mac ya tiene histórico reciente. La app desktop puede enviar un snapshot inicial con los últimos segundos o minutos de dinámica, y luego continuar con muestras incrementales.

  

Ejemplo:

  

```text

IPhone conecta

Mac envía snapshot de últimos 60 segundos

IPhone reconstruye histórico inicial

Mac empieza streaming en vivo de nuevas muestras

```

  

Esto es especialmente útil si la app tiene modos de histórico de 10 s, 30 s, 1 min o 2 min.

  

## Latencia: riesgo y criterio de aceptación

  

La latencia de dinámica remota es un riesgo real, pero no debería superar un segundo si la arquitectura está bien diseñada. Si ocurre una latencia de más de un segundo, normalmente indica un problema de ventana de análisis, buffering, cola de mensajes, red o renderizado, no una limitación inevitable del envío de RMS por red local.

  

La latencia total puede venir de varios puntos:

  

```text

entrada de audio en la app desktop

buffer de audio

ventana de cálculo RMS

frecuencia de publicación

transmisión por red local

cola de recepción en iPhone

renderizado visual

suavizado/interpolación visual

```

  

El componente más peligroso no suele ser la red, sino el diseño del medidor. Si el RMS se calcula sobre una ventana de 1 segundo, el dato ya nace lento. Además, si después se suaviza en desktop y se vuelve a suavizar en iPhone, la visualización puede sentirse gelatinosa y retrasada.

  

Criterios orientativos:

  

```text

< 150 ms: muy bien para directo

150–300 ms: aceptable para feedback visual vivo

300–500 ms: usable para dinámica general, menos útil para reacción inmediata

> 1000 ms: problemático para directo

```

  

El objetivo debe ser mantener la edad del dato percibida por debajo de 200–300 ms cuando el sistema se use como referencia viva.

  

## Edad del dato

  

La métrica más importante no es solo la latencia de red, sino la edad del dato:

  

```text

edad del dato = momento actual en iPhone - momento real de medición en Mac

```

  

Esta métrica responde a la pregunta musical relevante: “lo que veo ahora en el iPhone, ¿cuánto tiempo hace que ocurrió?”. Si la edad del dato supera un segundo, el móvil ya no muestra el presente, sino una sombra retrasada del presente.

  

La app debe diseñarse para mostrar datos frescos primero y reconstruir histórico después.

  

## Política de colas y descarte

  

Para datos de dinámica en vivo, no debe adoptarse una mentalidad de “no perder ningún paquete”. Si el iPhone se retrasa y acumula mensajes, reproducirlos todos en orden puede provocar que el medidor vaya estable pero tarde. Ese comportamiento es peor que descartar paquetes antiguos.

  

La política recomendada es:

  

```text

Para valor actual: usar siempre el paquete más reciente válido

Para histórico: insertar muestras según timestamp si aún son relevantes

Para colas acumuladas: descartar datos demasiado antiguos

Para reconexión: solicitar snapshot reciente al desktop

```

  

La app debe evitar que la cola de mensajes cree una visualización del pasado.

  

## Modo debug

  

El modo debug es una vista interna de diagnóstico, no una función musical para el usuario final. Sirve para verificar si el sistema está enviando y renderizando los datos de dinámica a tiempo.

  

El modo debug debe permitir comparar lo que mide la app de escritorio con lo que recibe el iPhone. Puede activarse desde ajustes avanzados o mediante una bandera de desarrollo.

  

Métricas útiles:

  

```text

latencia actual estimada

latencia media

latencia máxima reciente

edad del último dato

paquetes por segundo recibidos

paquetes perdidos o saltos de sequence

paquetes descartados por antigüedad

tamaño de cola

fuente de dinámica conectada

último paquete recibido hace X ms

estado de Link

número de peers Link

BPM Link actual

```

  

El modo debug debe ayudar a separar problemas:

  

```text

Si el dato sale tarde del Mac: problema de análisis, buffer o ventana RMS

Si el dato llega tarde al iPhone: problema de red, WebSocket o cola

Si el dato llega rápido pero se ve tarde: problema de renderizado o suavizado visual

Si el iPhone reproduce una curva antigua: problema de cola acumulada

```

  

Una prueba práctica sería generar un evento dinámico claro, como una palmada, un golpe de bombo o un cambio brusco de nivel. El medidor local del Mac debe reaccionar primero y el iPhone debe reaccionar casi a la vez. Si el iPhone reacciona un segundo tarde, el sistema no es aceptable para uso en directo.

  

## Lectura rápida y lectura histórica

  

Conviene separar dos tipos de medición visual:

  

```text

RMS rápido: feedback casi inmediato del nivel actual

Histórico/tendencia: lectura suave de la evolución dinámica reciente

```

  

El RMS rápido debe tener una ventana suficientemente corta para sentirse vivo. El histórico puede ser más suave porque su función es mostrar dirección musical, no reaccionar a cada golpe. Esta separación evita que toda la interfaz se vuelva lenta por intentar hacer que una única lectura sirva para todo.

  

## Diseño recomendado de interfaz desktop

  

La app de escritorio debe mantener una separación clara entre fuentes de sincronía y emisión de dinámica.

  

Zona de sync:

  

```text

Sync Source

- Internal

- MIDI Clock

- Ableton Link

```

  

Cuando Sync Source = MIDI Clock:

  

```text

MIDI input dropdown

MIDI clock status

```

  

Cuando Sync Source = Ableton Link:

  

```text

Link active/off

Peers count

BPM actual

Grid Offset

```

  

Zona de dinámica:

  

```text

RMS local

Clipping 

Histórico reciente

Level broadcast on/off

Connected mobile devices count

Debug metrics opcionales

```

  

El desktop debe poder mostrar algo como:

  

```text

Link active · 2 peers · 124 BPM

Level broadcast · 2 devices connected

RMS -18.4 dB

Remote latency avg 52 ms

```

  

## Diseño recomendado de interfaz iPhone

  

La app móvil debe tratarse como una extensión visual de la app de escritorio, pero no como una pantalla tonta. Debe renderizar localmente sus grids y su medidor.

  

Elementos recomendados:

  

```text

Link status

Peers count

BPM actual

Follow Start/Stop on/off

Tempo control read-only por defecto

Dynamics Source

RMS remoto

Histórico de dinámica

Estado de conexión de level

Debug opcional

```

  

Estados posibles:

  

```text

Link off · no dynamics source

Link active · no peers · no dynamics source

Link active · 2 peers · receiving dynamics from MacBook Pro

Link active · 2 peers · dynamics source lost

Link active · receiving snapshot

Link active · reconnecting dynamics source

```

  

La app móvil debe evitar permisos confusos. Si iOS solicita acceso a red local, la interfaz debe explicar que es necesario para encontrar Ableton Link y la fuente de dinámica en la red local.

  

## Comportamiento ante desconexiones

  

El sistema debe degradar con claridad, no fallar de forma opaca.

  

Si se pierde Link pero sigue la dinámica:

  

```text

El medidor puede seguir funcionando

El grid pierde sincronía externa o vuelve a modo interno según decisión de producto

Mostrar estado Link off/disconnected

```

  

Si se pierde la fuente de dinámica pero sigue Link:

  

```text

El grid sigue sincronizado

El medidor se congela, se vacía o muestra “Dynamics source lost”

Intentar reconexión automática

```

  

Si se pierde todo:

  

```text

Mostrar estado claro

No bloquear la UI

Permitir volver a Internal si procede

```

  

Si no hay peers Link:

  

```text

No mostrar error

Mostrar “Link active · no peers”

Mantener app lista para sincronizarse cuando aparezcan peers

```

  

## Seguridad y control

  

Aunque el sistema esté pensado para un entorno de confianza, conviene que el desktop tenga una opción clara para permitir o no que móviles reciban dinámica:

  

```text

Allow mobile devices to receive dynamics

Level broadcast on/off

```

  

No se plantea como una medida de seguridad compleja, sino como claridad de control. En una red compartida, el usuario debe saber cuándo su app está emitiendo datos para otros dispositivos.

  

Para una primera versión local, no hace falta diseñar autenticación compleja. Si el producto evoluciona a contextos con múltiples usuarios, se podría añadir pairing por código, QR o confirmación desde desktop.

  

## Decisiones recomendadas

  

La evolución móvil debe seguir estas decisiones:

  

```text

Ableton Link debe ser un toggle/estado, no un selector de dispositivo.

Los iPhones deben integrarse como peers Link nativos.

Tempo control y transport debe ser read-only por defecto en iPhone.

Grid Offset debe mantenerse como offset visual local compatible con Link.

Link no debe usarse para transportar RMS.

La dinámica debe enviarse por un canal propio Mac → iPhone.

Bonjour/mDNS + WebSocket es la arquitectura recomendada para dinámica.

Los paquetes de RMS deben incluir timestamp, sequence y referencia musical Link si es posible.

La app debe priorizar frescura sobre entrega exhaustiva de paquetes.

Debe existir modo debug para medir edad del dato, latencia y colas.

```

  

## Riesgos principales

  

Los riesgos principales son:

  

```text

Confundir Link con una conexión a Ableton Live en lugar de una sesión peer-to-peer.

Mostrar errores falsos cuando Link está activo pero no hay peers.

Permitir que el iPhone cambie el tempo Link accidentalmente.

Usar un offset que altere la sesión Link en vez de ser local.

Intentar transportar datos RMS por Link.

Enviar visuales en lugar de datos estructurados.

No timestamped data, provocando histórico mal alineado.

Acumular paquetes antiguos y mostrar dinámica retrasada.

Aplicar demasiado suavizado y generar sensación de latencia.

No contemplar permisos de red local en iOS.

Depender de redes Wi‑Fi públicas o saturadas en directo.

```

  

## Referencias técnicas a consultar por el agente de código

  

Documentación de Ableton Link:

  

```text

https://ableton.github.io/link/

```

  

Repositorio Ableton Link:

  

```text

https://github.com/ableton/link

```

  

Ableton LinkKit para iOS:

  

```text

https://ableton.github.io/linkkit/

```

  

Manual de Ableton Live sobre Link, tempo follower y MIDI:

  

```text

https://www.ableton.com/en/manual/synchronizing-with-link-tempo-follower-and-midi/

```

  

FAQ de Ableton Link:

  

```text

https://help.ableton.com/hc/en-us/articles/209776125-Link-features-and-functions-FAQ

```

  

Apple Local Network Privacy:

  

```text

https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy

```

  

Apple Bonjour / Network framework / local network discovery:

  

```text

https://developer.apple.com/bonjour/

```

  

## Resumen ejecutivo para implementación futura

  

La app de escritorio debe seguir siendo el nodo principal de análisis de audio y puede actuar como fuente de dinámica para móviles. Ableton Link debe encargarse exclusivamente de la sincronía musical entre Ableton Live, desktop e iPhone. Los iPhones deben ser peers Link nativos, no simples receptores de tempo desde el Mac. Para recibir RMS y otros datos de nivel, los iPhones deben conectarse a la app desktop mediante una capa propia de red local, preferiblemente Bonjour/mDNS para descubrimiento y WebSocket para streaming.

  

El sistema debe diseñarse para directo: estados claros, sin modales innecesarios, permisos de red bien explicados, control de tempo bloqueado por defecto, start/stop opcional, offset visual local y medición de latencia mediante modo debug. La prioridad no es transportar todos los datos, sino transportar los datos correctos, con timestamp, suficientemente rápido y sin que la interfaz muestre información vieja como si fuera presente.