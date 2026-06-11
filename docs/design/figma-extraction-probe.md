# F1-DESIGN-PROBE - Figma MCP extraction pattern (Grid)

## Scope

This note documents what the Figma MCP actually returned for the Grid components
in `kairos-design-system`, using Dev Mode data from the real file instead of
guessing from screenshots or from `kairos-design-system.md`.

Local sources read before extraction:

- `kairos-design-system.md`
- `figma-screen-references/README.md`

Figma file used:

- File: [kairos-design-system](https://www.figma.com/design/GFhOPG6jAQdos0l8nkHytA/kairos-design-system)
- Page returned by MCP: [Components](https://www.figma.com/design/GFhOPG6jAQdos0l8nkHytA/kairos-design-system?node-id=4-4)
- Section that contains the component lab: [components](https://www.figma.com/design/GFhOPG6jAQdos0l8nkHytA/kairos-design-system?node-id=156-15262)

## Nodes anchored for Grid

These are the exact node anchors used during extraction:

| Node | Figma node id | Link | What MCP returned |
|---|---:|---|---|
| Components page | `4:4` | [open](https://www.figma.com/design/GFhOPG6jAQdos0l8nkHytA/kairos-design-system?node-id=4-4) | Page tree root |
| Components section | `156:15262` | [open](https://www.figma.com/design/GFhOPG6jAQdos0l8nkHytA/kairos-design-system?node-id=156-15262) | Full component inventory on the page |
| `step` frame | `81:1771` | [open](https://www.figma.com/design/GFhOPG6jAQdos0l8nkHytA/kairos-design-system?node-id=81-1771) | All Grid step variants, generated code, screenshot, variables |
| `cycle` frame | `81:1780` | [open](https://www.figma.com/design/GFhOPG6jAQdos0l8nkHytA/kairos-design-system?node-id=81-1780) | Variant matrix metadata; code required drilling into child variants |
| `grid/desktop` | `91:30449` | [open](https://www.figma.com/design/GFhOPG6jAQdos0l8nkHytA/kairos-design-system?node-id=91-30449) | Container-level structure, variables, sampled generated code |

Useful child anchors:

| Node | Figma node id | Link |
|---|---:|---|
| `step` `state=block/active` | `81:1772` | [open](https://www.figma.com/design/GFhOPG6jAQdos0l8nkHytA/kairos-design-system?node-id=81-1772) |
| `cycle` `variant=block/16-steps` | `81:1823` | [open](https://www.figma.com/design/GFhOPG6jAQdos0l8nkHytA/kairos-design-system?node-id=81-1823) |
| `cycle` `variant=line/16-steps` | `81:1840` | [open](https://www.figma.com/design/GFhOPG6jAQdos0l8nkHytA/kairos-design-system?node-id=81-1840) |
| `cycle` `variant=border/16-steps` | `81:1857` | [open](https://www.figma.com/design/GFhOPG6jAQdos0l8nkHytA/kairos-design-system?node-id=81-1857) |

## MCP methods used

| Method | Why it was used | What it returned here |
|---|---|---|
| `whoami` | Confirm access before relying on MCP data | Authenticated user and plan list. MCP access worked. |
| `get_metadata` | Find the page id, section id, component ids, variant ids, and exact node sizes | Top-level page `4:4`, section `156:15262`, `step` `81:1771`, `cycle` `81:1780`, `grid/desktop` `91:30449`, and all child state nodes with sizes. |
| `get_design_context` | Primary extraction method for implementation-facing structure | For `step`, it returned the full variant union, CSS-variable-backed color bindings, exact widths/heights/radii, node ids, and a screenshot. For large nodes like `cycle`, the parent call degraded to sparse metadata, so child calls were required. |
| `get_variable_defs` | Resolve the variables actually bound to the selected node to concrete values | For `step`, it returned exact Grid color tokens and values, `radius/surface = 8`, `component/grid-step/min-height = 32`, `border-width-4 = 4`, `border-radius-12 = 12`. For `cycle` and `grid/desktop`, it returned spacing, container, and layout values. |
| `search_design_system` | Check the canonical variable names in the design library | Confirmed the real library token names are `color/kairos/grid-*` and `color/kairos/level-*`, not the shorter names used in the repo markdown. |
| `get_code_connect_map` | Check whether Dev Mode exposes code mappings for these nodes | Returned a plan gate error: Code Connect requires a Developer seat in an Organization or Enterprise plan. Not usable in this workspace. |

## Exact MCP extraction for `step`

### Variants exposed by `get_design_context`

The `step` node returned one component contract with these exact `state`
variants:

- `block/active`
- `block/reset-combined`
- `block/reset-general`
- `block/anticipation`
- `block/inactive`
- `border/active`
- `border/reset-combined`
- `border/reset-general`
- `border/anticipation`
- `border/inactive`
- `line-md/active`
- `line-md/reset-combined`
- `line-md/reset/general`
- `line-md/anticipation`
- `line-md/inactive`
- `line-sm/active`
- `line-sm/reset-combined`
- `line-sm/reset/general`
- `line-sm/anticipation`
- `line-sm/inactive`

Important detail: the line variants are named `reset/general` in Figma, not
`reset-general`.

### Geometry and drawing model

`get_metadata` and `get_design_context` agree on the outer node size:

- `step` frame size: `200 x 32`
- outer min-height token: `component/grid-step/min-height = 32`

Per mode, the MCP returned:

| Mode | Outer box | Inner drawing | Radius | Stroke/line width | Notes |
|---|---|---|---:|---:|---|
| `block` | `200 x 32` | Filled rectangle | `radius/surface = 8` | n/a | Background color switches by state |
| `border` | `200 x 32` | Transparent fill + stroke | `radius/surface = 8` | `border-width-4 = 4` | Stroke color switches by state |
| `line-md` | `200 x 32` | Left-aligned vertical line that fills height | `border-radius-12 = 12` | `8` px line width | Outer wrapper stays transparent |
| `line-sm` | `200 x 32` | Left-aligned vertical line that fills height | `border-radius-12 = 12` | `4` px line width | Outer wrapper stays transparent |

### State-to-token mapping

`get_variable_defs` on `81:1771` returned these exact bound variables and
resolved values:

| Semantic state | Actual Figma token name | Resolved value |
|---|---|---|
| active | `color/kairos/grid-step-active` | `#f5f7fa` |
| inactive | `color/kairos/grid-step-inactive` | `#24262b` |
| reset-combined | `color/kairos/grid-reset-combined` | `#74d79a` |
| reset-general | `color/kairos/grid-reset-general` | `#aa82db` |
| anticipation | `color/kairos/grid-anticipation` | `#e98284` |

### What changes and what stays invariant

Across all `step` variants:

- Width stays `200`
- Height stays `32`
- State changes only the color token
- Mode changes only the drawing strategy

Mode-specific invariants:

- `block`: same `8px` radius in all states
- `border`: same `4px` stroke and `8px` radius in all states
- `line-md`: same `8px` line width and `12px` line radius in all states
- `line-sm`: same `4px` line width and `12px` line radius in all states

## Exact data from `cycle` and `grid/desktop`

### `cycle`

`get_metadata` on `81:1780` returned the full variant matrix:

- `block/4-steps`, `line/4-steps`, `border/4-steps`
- `block/8-steps`, `line/8-steps`, `border/8-steps`
- `block/16-steps`, `line/16-steps`, `border/16-steps`
- `block/32-steps`, `line/32-steps`, `border/32-steps`
- `block/64-steps`, `line/64-steps`, `border/64-steps`
- `128-steps`

`get_variable_defs` on `81:1780` returned the exact layout bindings:

- `space/component/sm = 8`
- `space/component/lg = 16`
- `component/grid-cycle/min-height = 64`
- `component/grid-step/min-height = 32`
- `radius/surface = 8`
- `color/kairos/grid-step-inactive = #24262b`

`get_design_context` on the parent `cycle` node was too large and fell back to
sparse metadata. Drilling into child variants showed:

- Block and border cycles use `16px` inner padding
- Inter-step gap is `8px`
- Block and border steps are repeated parametrically, not drawn as unique shapes
- `variant=block/16-steps` and `variant=border/16-steps` both returned `1728 x 96`
- The generated code for some line variants reported obviously distorted heights
  on larger nodes, so exact layout on composite nodes must be cross-checked with
  metadata and variable defs, not trusted blindly from the sampled code string

### `grid/desktop`

`get_metadata` on `91:30449` returned a container size of `1305 x 560`.

`get_variable_defs` on `91:30449` returned:

- `color/background/surface = #101012`
- `radius/canvas = 12`
- `space/layout/gap-lg = 16`
- `space/component/sm = 8`
- `space/component/lg = 16`
- `component/grid-cycle/min-height = 64`
- `component/grid-step/min-height = 32`
- `component/panel/grid-min-height = 560`
- `viewport-fullheight = 1117`

This is the exact Grid desktop container contract exposed by MCP:

- background surface color: `#101012`
- outer radius: `12`
- vertical gap between cycle rows: `16`
- each cycle row keeps `16` inner padding
- each cycle row keeps `8` inter-step gap
- panel min-height is explicitly tokenized at `560`

## Reusable extraction pattern

Use this pattern for future UI/render tasks that need Figma-exact data without
modifying the design file:

1. Start with `get_metadata` without a `nodeId`.
   This returns the top-level page ids available to MCP.
2. Call `get_metadata` again on the page id.
   This gives the tree of node ids, names, positions, and sizes.
3. Anchor the node explicitly.
   Save both the raw node id (`81:1771`) and a direct Figma link using
   `node-id=81-1771`. That link is the stable handoff artifact for future work.
4. Call `get_design_context` on the exact component node.
   This is where MCP exposes:
   - variant names and prop unions
   - generated reference code
   - CSS-variable-backed token usage with fallback real values
   - node ids embedded into the generated structure
   - a screenshot when the response fits
5. Call `get_variable_defs` on the same node.
   This is the reliable way to resolve the actual token names and their current
   values for that node.
6. If the node is large and `get_design_context` degrades to sparse metadata,
   split the extraction into child nodes and re-run `get_design_context` on those
   smaller anchors.
7. If the token names in repo docs and bound variables do not match, run
   `search_design_system`.
   This exposes the canonical library path, collection name, and official token
   name in the design system.
8. Only after steps 4 to 7 should the design be translated to code.
   Translation should preserve:
   - node-anchored geometry
   - exact token names
   - resolved fallback values
   - variant names
   - drawing-mode differences

## What Dev Mode exposed here

In this file, Dev Mode exposed:

- exact node ids and sizes via `get_metadata`
- actual bound variables and resolved values via `get_variable_defs`
- generated implementation reference code via `get_design_context`
- a screenshot bundled inside `get_design_context` when the node was small enough
- canonical library variable names via `search_design_system`

It did not expose a usable Code Connect map in this workspace because the plan is
not eligible for that feature.

## Gaps between Figma and `kairos-design-system.md`

These are the important places where the repo markdown is not enough and the
MCP-backed Figma data must win:

1. Domain token names are more specific in Figma.
   The markdown names `color/kairos/step-active`, `step-inactive`,
   `reset-combined`, `reset-general`, `anticipation`, and `clip`.
   The real library variables returned by MCP are `color/kairos/grid-step-active`,
   `grid-step-inactive`, `grid-reset-combined`, `grid-reset-general`,
   `grid-anticipation`, and `color/kairos/level-clip`.
2. The markdown does not include exact `step` geometry.
   Figma gives the real `200 x 32` contract, the `8px` surface radius, `4px`
   border stroke, `8px` and `4px` line widths, and `12px` line radius.
3. The markdown does not include the exact node anchors needed for repeatable
   extraction.
   Future work should not rely on names alone when a stable `node-id` exists.
4. The markdown does not document Grid container tokens.
   Figma adds `color/background/surface = #101012`, `radius/canvas = 12`,
   `space/layout/gap-lg = 16`, `component/panel/grid-min-height = 560`, and
   `viewport-fullheight = 1117`.
5. The markdown does not mention the variant naming inconsistency in Figma.
   Line variants use `reset/general`, while block and border variants use
   `reset-general`.
6. The markdown does not document an MCP limitation that matters operationally.
   Large composite nodes may return sparse metadata or sampled code that is less
   trustworthy for geometry than the raw metadata plus variable definitions.

## Practical translation rule for code work

If a renderer task later consumes this probe, the safe translation rule is:

- use `get_design_context` to recover the component shape and variant model
- use `get_variable_defs` to resolve the real tokens and values
- use `get_metadata` to verify dimensions on large composite nodes
- treat the generated code as a reference, not as authoritative layout output for
  large frames
- never backfill missing geometry from screenshots or from
  `kairos-design-system.md` when the Figma node already exposes a real value
