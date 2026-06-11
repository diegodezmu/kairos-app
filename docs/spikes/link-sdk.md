# Ableton Link SDK integration smoke

## Estado

Integrado el SDK oficial de Ableton Link para macOS como paquete Swift aislado:
`Packages/KairosLinkSDK`.

La integración usa el wrapper C `abl_link` del repo oficial y compila/enlaza desde
Swift sin meter el SDK dentro de `KairosCore`.

## Cómo está integrado

- El repo oficial se incorpora como submódulo git en
  `Packages/KairosLinkSDK/Vendor/link`.
- El paquete local `Packages/KairosLinkSDK` expone:
  - `CAbletonLink`: target C/C++ que compila
    `Vendor/link/extensions/abl_link/src/abl_link.cpp`.
  - `KairosLinkSDK`: target Swift con una llamada smoke al API C.
  - `KairosLinkSmokeCLI`: ejecutable que imprime el resultado del smoke.
- `CAbletonLink` añade los include paths que pide el SDK oficial:
  - `Vendor/link/include`
  - `Vendor/link/modules/asio-standalone/asio/include`
- El target define `LINK_PLATFORM_UNIX=1` y `LINK_PLATFORM_MACOSX=1`, que es la
  configuración mínima documentada por Ableton para builds no-CMake en macOS.

La llamada smoke actual:

1. crea `abl_link` con tempo inicial `120.0`
2. crea un `abl_link_session_state`
3. captura el estado de sesión desde el hilo de app
4. lee `tempo`, `isEnabled` y `peerCount`
5. libera sesión e instancia

## Verificación local

Desde la raíz del repo:

```sh
swift build --package-path Packages/KairosLinkSDK
swift run --package-path Packages/KairosLinkSDK KairosLinkSmokeCLI
```

Salida esperada aproximada:

```text
Ableton Link smoke ok: enabled=false peers=0 tempo=120.0
```

## Cómo se actualiza

Actualizar el submódulo al commit deseado del repo oficial:

```sh
git submodule update --init --recursive Packages/KairosLinkSDK/Vendor/link
git -C Packages/KairosLinkSDK/Vendor/link fetch origin
git -C Packages/KairosLinkSDK/Vendor/link checkout <commit-o-tag>
git add Packages/KairosLinkSDK/Vendor/link
```

Si el upstream cambia el submódulo interno de Asio, volver a sincronizarlo:

```sh
git -C Packages/KairosLinkSDK/Vendor/link submodule update --init --recursive
```

## Licencia

- El SDK de Ableton Link en este repo está bajo GPLv2+ (o licencia propietaria
  alternativa de Ableton).
- Para Kairos, el caso de uso definido en PRD §12.1 es privado y no comercial.
- Para este caso, la obligación práctica es entregar el código fuente del proyecto
  y del SDK a los compañeros junto con el binario.
- No hace falta registro con Ableton mientras no haya distribución comercial ni uso
  del badge oficial.

## DECISION-NEEDED

En F1-TD habrá que decidir dónde vive el adaptador de producción de
`AbletonLinkClock`:

- mantener un target macOS-only separado que consuma `KairosLinkSDK`, o
- introducir una costura específica para que `KairosCore` siga limpio para iOS,
  donde más adelante entrará `LinkKit` en fase 2.
