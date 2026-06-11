# Figma Screen References

Estas imágenes son una referencia visual rápida del Figma final de Kairos.

## Cómo deben usarse

Para un agente de código, el orden correcto de fuentes es:

1. `Figma MCP` sobre los nodos reales del archivo
2. [kairos-design-system.md](/Users/diegofernandezmunoz/Developer/personal/kairos-app/kairos-design-system.md)
3. estas capturas JPG como validación visual

Estas imágenes sirven para:

- validar intención visual general
- entender jerarquía, densidad y composición por breakpoint
- comprobar la relación entre módulos
- verificar el comportamiento esperado entre orientación vertical y horizontal
- hacer QA visual al final de la implementación

Estas imágenes no deben usarse para inferir:

- spacing exacto
- tamaños exactos
- colores exactos
- radios exactos
- contratos de componentes

Para esas decisiones, la fuente de verdad sigue siendo Figma vía MCP, los tokens
reales y la documentación del sistema.

## Selección incluida

Esta carpeta recoge la selección principal de pantallas y un estado adicional de
Level en mobile porque ayuda a validar composiciones sensibles:

| Archivo | Nodo Figma | Uso |
|---|---:|---|
| `01-desktop-workspace-full.jpg` | `83:8522` | Workspace desktop completo en fullscreen |
| `02-desktop-grid-focused.jpg` | `88:27257` | Desktop con foco en Grid |
| `03-desktop-level-expanded.jpg` | `91:38783` | Referencia de Level expandido en desktop |
| `04-tablet-sidebar-portrait.jpg` | `168:15266` | Sidebar fullscreen vertical en tablet |
| `05-tablet-grid-landscape.jpg` | `168:17022` | Grid horizontal en tablet |
| `06-tablet-level-landscape.jpg` | `168:17036` | Level horizontal en tablet |
| `07-mobile-sidebar-portrait.jpg` | `84:16402` | Sidebar fullscreen vertical en mobile |
| `08-mobile-grid-landscape.jpg` | `84:20657` | Grid horizontal en mobile |
| `09-mobile-level-landscape-full.jpg` | `84:22174` | Level horizontal full-width en mobile |
| `10-mobile-level-landscape-four-windows.jpg` | `88:28722` | Level horizontal con cuatro ventanas en mobile |

## Qué debe mirar un agente aquí

Al usar estas referencias, un agente debería fijarse sobre todo en:

- qué módulo ocupa la pantalla en cada breakpoint
- qué composiciones son válidas en desktop
- que tablet y mobile no mezclan `Grid` y `Level` simultáneamente
- que `Sidebar` pertenece al modo vertical
- que `Grid` y `Level` pertenecen al modo horizontal
- la sensación de profundidad, densidad y jerarquía visual

## Qué no debe resolver aquí

Si hay una diferencia entre una impresión visual de la imagen y un valor real de
Figma, deben ganar los datos estructurados de Figma.

Eso incluye:

- variables
- estilos tipográficos
- tamaños de controles
- breakpoints
- nombres y estados de componentes

## Nota

Estas capturas complementan el sistema de diseño. No lo sustituyen.
