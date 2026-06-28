# Kairos — Design System (índice)

> Índice fino que une el archivo de Figma de Kairos con el código macOS. **Figma es la
> fuente de verdad** para los valores exactos; este documento solo mapea nombres/semántica
> y deja por escrito las decisiones con carga. Resuelve los nombres/valores de token reales
> por el MCP de Figma (`search_design_system` / `get_variable_defs`); ver
> [docs/design/figma-extraction-probe.md](docs/design/figma-extraction-probe.md).

## Alcance

Kairos v1 es **solo macOS**. La UI publicada es el workspace de escritorio (Grid + Level +
Sidebar + Toolbar). No hay build móvil ni tablet, ni está planificada.

**Sobre las pantallas de tablet/móvil en Figma:** la página `Screens` del archivo de Figma
contiene además layouts de tablet y móvil. Se hicieron **durante el proceso de diseño para
validar que la interfaz es escalable** a otros formatos — son una exploración de diseño que se
conserva como posibilidad futura, **no** un requisito de v1 y **no** está implementada. Trátalas
como referencia; no construyas a partir de ellas. (Ver también
[docs/decisiones-descartadas.md](docs/decisiones-descartadas.md).)

## Figma como fuente de verdad

El archivo tiene tres páginas a nivel de documento:

- `Components` — el set real de componentes (válido para implementar)
- `Screens` — pantallas compuestas (válidas para implementar; tablet/móvil son solo referencia, ver Alcance)
- `Archive` — zona de descarte, **ignórala por completo**

Los componentes reutilizables conservan nombres con barra en Figma (`button/primary`,
`window/desktop`, …). Lee siempre los valores reales desde Figma por el MCP en vez de fiarte de
números copiados aquí.

## Sistema de profundidad (color + radio, acoplados)

Tres profundidades estructurales de fondo, cada una con un radio semántico — son **un** sistema, no dos:

- `color/background/canvas` (`#0A0A0B`) — fondo estructural más profundo
- `color/background/surface` (`#101012`) — superficies de contenido principales
- `color/background/elevated` (`#16171A`) — superficies flotantes/anidadas

Otros valores de chrome confirmados (resuelve el resto en Figma):
`text/primary #F5F7FA`, `text/secondary #AEB8C4`, `text/tertiary #8792A0`,
`border/subtle #24262B`, `action/accent #4378B8`, `action/highlight rgba(67,120,184,0.33)`,
`action/secondary-hover #2F3238`.

## Mapa de color de dominio Kairos (con carga)

Grid y Level usan una capa de color de dominio bajo `color/kairos/*`. **No** son colores de
estado genéricos: son la única interfaz de color para la lógica de Grid/Level. Los nombres en
Figma van prefijados (`grid-*`, `level-*`); las variantes de línea nombran el reset general como
`reset/general`.

Grid (confirmados):
- `grid-step-active` `#f5f7fa` — paso actual
- `grid-step-inactive` `#24262b` — paso inactivo
- `grid-reset-combined` `#74d79a` — marca de reset combinado (verde)
- `grid-reset-general` `#aa82db` — marca de reset global (púrpura)
- `grid-anticipation` `#e98284` — aviso de fin de ciclo (rojo)

Level (resuelve nombres/valores exactos en Figma):
- `level-clip` (confirmado) — estado de clip (rojo)
- `level-in-target` / `level-out-target` — feedback de validación de target
- `meter-fill-body` — relleno de la masa del medidor
- `meter-scale-line` — líneas guía / escala

## Tipografía

Sistema reducido en torno a estilos `title`, `body` y `label` (familia Inter). Tamaños/pesos viven
en los text styles de Figma y en `DesktopShellTypography` en código.

## Inventario de componentes

Set de componentes de escritorio (detalle en la página `Components` de Figma): Icons, Buttons
(primary/secondary/tertiary/ghost + estados folded), Toggle/Switch, Info atoms (input-status =
punto + caption, status dot, badge, divider), Toolbar, Sidebar, Grid (step/cycle), Level (meter
band/row).

En código no son espejos 1:1 de Figma: Grid y Level son renderers paramétricos (los nodos
`step`/`cycle`/`level-band` de Figma son bancos de prueba, no contratos de componente).

## Reglas para agentes de código

- Ignora `Archive`. Usa `Components` + `Screens` (escritorio) como referencia.
- Lee tokens/valores exactos desde Figma por el MCP; no resucites nombres de token antiguos.
- Trata la profundidad semántica como una decisión conjunta de color de fondo + radio.
- Grid/Level: prefiere un renderer paramétrico limpio antes que replicar los nodos de prueba de Figma.
- No construyas tablet/móvil ni inventes comportamiento táctil/orientación (fuera de alcance — ver Alcance).
- Si un valor difiere entre código y Figma, marca el desajuste; no lo hardcodees ni recalibres por tu cuenta.
