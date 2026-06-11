# BlackHole 16ch + routing desde Ableton

Esta guía deja claro el reparto de responsabilidades:

- Kairos debe abrir `BlackHole 16ch` directamente como entrada CoreAudio.
- El `Aggregate Device` existe solo para la salida de Ableton, para poder enviar a BlackHole sin perder monitorización local.
- BlackHole 16ch debe estar instalado antes de empezar.
- Si prefieres hacerlo desde Terminal, usa los helpers del repo:
  - `bash docs/setup/scripts/blackhole-install-user.sh`
  - `bash docs/setup/scripts/blackhole-verify.sh`
- El mapeo de lanes es fijo (D5):

| Lane Kairos | Par de canales en BlackHole |
| --- | --- |
| Lane 1 | 1-2 |
| Lane 2 | 3-4 |
| Lane 3 | 5-6 |
| Lane 4 | 7-8 |

## Opción A: rápida, para validar F0-3

Usa esta opción si solo quieres demostrar que la señal llega a BlackHole. No oirás el audio por los altavoces mientras Ableton saque audio a BlackHole.

1. Abre `Preferencias > Audio` en Ableton.
2. Deja `Driver Type` en `CoreAudio`.
3. En `Output Device`, elige `BlackHole 16ch`.
4. En `Output Config`, activa al menos estos pares estéreo:
   - `1/2`
   - `3/4`
   - `5/6`
   - `7/8`
5. En cada pista, grupo, return o bus que quieras enviar a Kairos, usa `Audio To > Ext. Out` y selecciona el par correcto:
   - Lane 1 de Kairos <- Ableton `1/2`
   - Lane 2 de Kairos <- Ableton `3/4`
   - Lane 3 de Kairos <- Ableton `5/6`
   - Lane 4 de Kairos <- Ableton `7/8`
6. Para una validación mínima de F0-3, basta con mandar una pista o un bus con señal a `1/2`.
7. Ten en cuenta que aquí el audio sale solo hacia BlackHole. Si no oyes nada por los altavoces, es el comportamiento esperado.

## Opción B: setup real para producto

Usa esta opción cuando quieras oír el proyecto y, a la vez, alimentar Kairos por BlackHole.

### 1. Crear el Aggregate Device en Audio MIDI Setup

1. Abre `Configuración de Audio MIDI`.
2. Si no ves la lista de dispositivos, abre `Ventana > Mostrar dispositivos de audio`.
3. Pulsa `+` y elige `Crear dispositivo agregado`.
4. Renombra el agregado, por ejemplo, a `Kairos Out + BlackHole`.
5. Marca estos dispositivos dentro del agregado:
   - Tu salida real (`Altavoces del MacBook Pro` o tu interfaz)
   - `BlackHole 16ch`
6. Deja todos los dispositivos al mismo `Sample Rate`. Si ya trabajas a `48 kHz`, úsalo también aquí.
7. Elige como `Clock Source` la salida real o la interfaz principal.
8. Activa `Drift Correction` en todos los dispositivos salvo en el que actúe como reloj.

### 2. Entender el offset de canales dentro del agregado

El agregado concatena los canales de los dispositivos incluidos. Como Kairos no abre el agregado, sino `BlackHole 16ch` directamente, lo importante es saber en qué pares del agregado caen los canales de BlackHole para rutar Ableton.

- Si tu salida real aporta `N` canales antes de BlackHole, entonces:
  - BlackHole `1/2` aparece en Ableton como el par `N+1 / N+2`
  - BlackHole `3/4` aparece como `N+3 / N+4`
  - BlackHole `5/6` aparece como `N+5 / N+6`
  - BlackHole `7/8` aparece como `N+7 / N+8`
- Ejemplo típico:
  - Salida real estéreo de 2 canales primero en el agregado -> BlackHole `1/2` = Ableton `3/4`
  - BlackHole `3/4` = Ableton `5/6`
  - BlackHole `5/6` = Ableton `7/8`
  - BlackHole `7/8` = Ableton `9/10`

### 3. Rutear Ableton al agregado

1. En `Preferencias > Audio` de Ableton, elige el `Aggregate Device` como `Output Device`.
2. Abre `Output Config` y activa:
   - El par de monitorización de tu salida real
   - Los pares del agregado que correspondan a BlackHole
3. Mantén el `Master` en la salida real.
4. Para cada bus que deba llegar a Kairos, usa `Audio To > Ext. Out` y selecciona el par del agregado que corresponda al par de BlackHole deseado.
5. Mapeo final que Kairos espera:
   - Lane 1 <- BlackHole `1/2`
   - Lane 2 <- BlackHole `3/4`
   - Lane 3 <- BlackHole `5/6`
   - Lane 4 <- BlackHole `7/8`

## Cómo comprobar que la señal está llegando a BlackHole

### Comprobación de dispositivo

En Terminal:

```bash
system_profiler SPAudioDataType | rg -A6 -B2 "BlackHole 16ch"
```

Debes ver `BlackHole 16ch` y `Input Channels: 16`.

### Comprobación de señal en vivo

1. En Ableton, reproduce una pista con señal y verifica que el medidor de esa pista o bus se mueve.
2. Confirma que la pista está asignada al par externo correcto.
3. Si quieres una comprobación fuera de Ableton, abre cualquier app que pueda monitorizar una entrada CoreAudio, selecciona `BlackHole 16ch` como input y observa actividad en el par esperado.
4. Cuando la Parte B de F0-3 esté cableada, Kairos debería reaccionar en la lane correspondiente a ese mismo par.

## Nota de sincronía

Si además vas a validar el timeline compartido, activa `Link` en Ableton. El routing de audio y Link son cosas separadas: Link sincroniza el tiempo; BlackHole lleva la señal de audio hacia Kairos.

## Problemas habituales

- `BlackHole 16ch` no aparece tras instalarlo:
  - Reinicia el Mac.
  - Si quieres evitar el reinicio completo, prueba `sudo killall coreaudiod`.
- No oyes el proyecto en la opción A:
  - Es normal; la salida va solo a BlackHole.
- El agregado existe, pero Kairos no reacciona:
  - Revisa el offset de canales del agregado.
  - Verifica que el bus de Ableton sale al par correcto.
  - No selecciones el agregado como entrada de Kairos; Kairos debe abrir `BlackHole 16ch` directo.
