# Kairos — Release e instalación

Cómo generar el instalable (DMG) de Kairos y cómo instalarlo en otro Mac.
Kairos es una app **privada** de uso personal/banda: no se distribuye públicamente ni por la App Store.

## Generar el DMG

Requisitos: **Xcode 16+** y el submódulo de Ableton Link inicializado.

```sh
# Clonado recomendado (incluye el submódulo de Ableton Link):
git clone --recursive https://github.com/diegodezmu/kairos-app.git

# Si ya lo clonaste sin --recursive:
git submodule update --init --recursive

# Generar el DMG (versión 1.0.0 por defecto):
scripts/release-dmg.sh
scripts/release-dmg.sh 1.0.1     # o una versión concreta
```

Salida: `dist/Kairos-<versión>.dmg` (esta carpeta está fuera de git).

### DMG con marca vs. funcional

El script genera un DMG **con marca** (fondo de Figma "Drag to install", con la app a la izquierda
y el atajo a `Applications` a la derecha) usando `dmgbuild`, que escribe el estilo de la ventana
directamente, **sin Finder/AppleScript** — funciona headless y de forma reproducible.

- Instálalo una vez: `python3 -m pip install dmgbuild`.
- Las posiciones de los iconos viven en `scripts/dmg-settings.py` (`icon_locations`), ya alineadas
  con la flecha del fondo; ajústalas ahí si quieres afinar.
- El fondo se compone en HiDPI (1x + 2x) para verse nítido en pantallas retina.

Si `dmgbuild` no está disponible o falla, el script cae automáticamente a un DMG **funcional** vía
`hdiutil` (app + atajo a `Applications`, sin fondo). Es igual de instalable.

## Firma y Gatekeeper

Kairos usa firma **Automatic** (sin Developer ID obligatorio). Notarización: **opcional** para uso
privado.

Al instalar en **otro Mac**, Gatekeeper avisará de "desarrollador no identificado". Para abrirla:

1. Abre el DMG y arrastra `Kairos.app` a `Aplicaciones`.
2. La primera vez: **clic derecho sobre `Kairos.app` → Abrir → Abrir**.
3. A partir de ahí se abre con normalidad.

Si en el futuro quieres evitar esa fricción, el camino es un **Apple Developer ID + notarización**
(~99 $/año), no requerido para uso privado.

## App Sandbox: debe seguir DESACTIVADO

Kairos abre un socket **UDP entrante en el puerto 51515** para recibir la telemetría de `Level`
desde el dispositivo de Max for Live. El target **no** tiene App Sandbox activado (no hay archivo
de entitlements), y así debe seguir: si se activara el sandbox haría falta el entitlement de red
entrante, o la telemetría dejaría de llegar.

## Checklist de release v1.0.0

- [ ] `main` limpio y en verde (`swift test --package-path KairosCore` + tests de la app).
- [ ] Icono presente (visible en Dock/Finder).
- [ ] `scripts/release-dmg.sh` genera el DMG sin errores.
- [ ] DMG instalado y probado en **otro Mac** (clic derecho → Abrir).
- [ ] Tag `v1.0.0` creado y subido.
