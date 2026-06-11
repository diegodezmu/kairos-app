# Kairos - Design System

## Scope

This document is the implementation reference for the final Kairos Figma file.
It replaces the previous design-system writeup and intentionally removes all
legacy structure that no longer exists in the current file.

Use this document together with the final Figma file as the source of truth for:

- visual tokens actually used by the shipped UI
- component contracts and responsive behavior
- screen structure for desktop, tablet, and mobile
- implementation rules for Grid and Level

Do not use `Archive` as a reference. It is a discard area only.

## Figma Source Of Truth

The final file is organized around three pages:

- `Components`
- `Screens`
- `Archive`

Only `Components` and `Screens` are valid for implementation.

The old page taxonomy with numbered prefixes and kebab-case page names is no
longer valid. The current file uses a simpler Title Case page structure at the
document level, while reusable component names inside `Components` still use the
slash-based naming already present in Figma, for example:

- `button/primary`
- `tool-bar/mobile/vertical`
- `window/desktop`

## What Was Removed From The Previous Spec

The previous document described a broader and older system. The following should
be treated as obsolete and are intentionally not part of the final system:

- numbered page families such as `00-*`, `01-*`, `02-*`, `99-*`
- references to `Patterns`, `Docs`, `Prototypes`, or other pages not present now
- placeholder-heavy token architecture that documented categories not used by the
  final UI
- any requirement to mirror every Figma variant as a 1:1 code component
- any suggestion that tablet inherits desktop without dedicated references

## Screen Model

Kairos ships with three active breakpoints in Figma:

- `desktop`
- `tablet`
- `mobile`

There is also a primitive `breakpoint/wide`, but it is not represented by final
screens and should not drive implementation for v1.

### Desktop

The desktop page contains three reference states:

- `app-shell-desktop`
  - full shell with top toolbar, left sidebar, Grid area, four Level windows, and
    the desktop scrollbar between sidebar and display
- `app-shell-desktop (grid)`
  - Grid-focused layout with the sidebar hidden in the active viewport and the
    display occupying the full width
- full-width Level reference inside the same desktop section
  - one expanded `window/desktop` used to validate the full-width meter layout

Key desktop reference dimensions visible in Figma:

- shell width: `1728`
- top toolbar height: `56`
- sidebar content width: `375` inside a `391` wrapper
- main Grid card: `1305 x 692`
- Level row under Grid: `1305 x 337`
- full-width Grid reference: `1696 x 518.5`
- full-width Level reference: `1696 x 518.5`

Desktop is designed as a fullscreen modular workspace. This is not a single fixed
composition. The user can combine modules inside the same viewport, including:

- Sidebar + Grid + Level
- Sidebar + Grid
- Sidebar + Level
- Grid + Level
- Grid only
- Level only

This combinability is part of the intended desktop behavior and should be treated
as a primary layout capability, not as an optional enhancement.

### Tablet

The tablet page has dedicated references and should not be treated as a desktop
inheritance.

It contains:

- `app-shell-tablet`
  - portrait shell that shows the sidebar view, with a top `info` bar and bottom
    `action` bar
- `app-shell-tablet-grid`
  - horizontal Grid view with `tool-bar/mobile/horizontal`
- `app-shell-tablet-level`
  - horizontal Level view with `tool-bar/mobile/horizontal`

Key tablet reference dimensions:

- portrait shell: `834 x 1133`
- sidebar instance width in portrait: `802`
- horizontal split shells: `1113 x 834`
- tablet horizontal Grid canvas: `1081 x 762`
- tablet horizontal Level canvas: `1081 x 762`

Tablet does not reuse the desktop combined-workspace behavior. For accessibility
and legibility, tablet should show one primary screen at a time:

- `Sidebar` in fullscreen portrait
- `Grid` in fullscreen landscape
- `Level` in fullscreen landscape

### Mobile

The mobile page also has dedicated portrait and landscape references.

It contains:

- `app-shell-mobile`
  - portrait shell for the sidebar view, with top `info` and bottom `action`
    bars
- `app-shell-mobile-grid`
  - horizontal Grid view with `tool-bar/mobile/horizontal`
- `app-shell-mobile-level`
  - horizontal full-width Level view
- second `app-shell-mobile-level`
  - horizontal four-window Level view

Key mobile reference dimensions:

- portrait shell: `430 x 956`
- sidebar instance width in portrait: `398`
- horizontal split shells: `956 x 430`
- mobile horizontal Grid canvas: `924 x 358`
- mobile horizontal full-width Level canvas: `924 x 358`
- mobile horizontal four-window Level windows: `225 x 358` each

Mobile follows the same single-primary-screen rule as tablet. It must not try to
show `Grid` and `Level` simultaneously in the active viewport.

## Layout Patterns

The final screens establish three layout patterns:

- Desktop combined workspace
  - toolbar + sidebar + Grid + Level visible together
- Touch portrait sidebar workspace
  - sidebar fills the main area, with top `info` bar and bottom `action` bar
- Touch landscape content workspace
  - horizontal toolbar plus one primary visualization, either Grid or Level

This matters for implementation:

- desktop is the reference for the simultaneous workspace
- touch portrait is the reference for configuration-heavy navigation
- touch landscape is the reference for performance view and quick controls

### Touch Navigation And Orientation Rules

Tablet and mobile share the same navigation rule set:

- the default touch screen is `Sidebar` in fullscreen vertical format
- navigation between `Sidebar`, `Grid`, and `Level` is touch-driven
- `Grid` and `Level` are fullscreen horizontal destinations
- `Grid` and `Level` must not be shown together on small screens

Orientation is part of the layout contract:

- `Sidebar` is a vertical screen
- `Grid` is a horizontal screen
- `Level` is a horizontal screen
- opening the sidebar from `Grid` or `Level` must switch the app from horizontal
  to vertical
- returning from `Sidebar` to `Grid` or `Level` must restore the horizontal
  orientation

This should be documented and implemented as navigation behavior, not as a loose
responsive preference.

## Token Structure

The final file is materially simpler than the previous version.

The current token system is organized around:

- `primitives`
- `semantic-color`
- `semantic-space`
- `semantic-radius`
- domain-specific color tokens under `color/kairos/*`

Component-specific tokens exist where the component needs its own contract, but
the final file also binds many component properties directly to semantic tokens.

### Primitive Token Families

The final primitive inventory includes the following confirmed families:

- color
  - `color/white`
  - `color/black`
  - `color/black-alpha/{40,60,80}`
  - `color/neutral/{0,50,100,150,200,300,400,500,600,700,800,900,1000}`
  - `color/red/{100..900}`
  - `color/amber/{100..900}`
  - `color/blue/{100..900}`
  - `color/green/{100..900}`
  - `color/purple/{100..900}`
- type
  - `type/family/{base,mono}`
  - `type/size/{100..900}`
  - `type/weight/{regular,medium,semibold,bold}`
  - `type/line-height/{100..500}`
  - `type/tracking/{tight,wide}`
  - zero tracking is also used in bound styles even when the variable name is not
    explicit in the inventory response
- space
  - primitive scale under `space/*`
  - confirmed values directly bound in current components: `0`, `2`, `4`, `6`,
    `8`
- radius
  - `radius/{0,2,4,8,12,full}`
- opacity
  - `opacity/{0,10,20,40,60,80,100}`
- breakpoint
  - `breakpoint/{mobile,tablet,desktop,wide}`

### Semantic Space

The current semantic spacing collections in use are:

- `space/component/{xs,sm,md,lg,xl}`
- `space/layout/gap-{xs,sm,md,lg,xl}`

Confirmed runtime bindings from current components:

- `space/component/xs = 4`
- `space/component/sm = 8`
- `space/component/lg = 16`
- `space/component/xl = 24`

The `md` tokens exist and are valid, but the sampled final components above do not
expose a direct fallback value in the MCP output. Read the Figma variable itself
if a specific implementation needs the exact number.

### Semantic Radius

The current semantic radius collections in use are:

- `radius/surface/{sm,md,lg}`
- `radius/control/{sm,md,full}`

Confirmed visible bindings:

- surface buttons and chips resolve to `8px`
- larger surface containers such as sidebar, Grid, and Level cards resolve to
  `12px`
- the toggle pill resolves to `full`

Radius should not be treated as an independent styling system. In Kairos it is
part of the same depth model as semantic background color:

- deeper layers use larger radii
- more elevated nested layers use smaller radii

This prevents rounded children from visually "sticking" to equally rounded parent
surfaces. In practice:

- `canvas` is the structural background layer
- `surface` is the main content layer
- `elevated` is the layer above content surfaces

As elevation increases, radius decreases. Components should therefore derive both
their semantic background color and their radius from the same depth decision.

### Semantic Color

The final UI uses the following semantic color groups:

- text
  - `color/text/primary`
  - `color/text/secondary`
  - `color/text/tertiary`
  - `color/text/inverse`
  - `color/text/disabled`
- border
  - `color/border/subtle`
  - `color/border/strong`
  - `color/border/focus`
- action
  - `color/action/primary`
  - `color/action/primary-pressed`
  - `color/action/secondary`
  - `color/action/secondary-hover`
  - `color/action/accent`
  - `color/action/highlight`
- background
  - consumed directly in the final components even when the search results do not
    list them in one batch
  - `color/background/canvas`
  - `color/background/surface`
  - `color/background/elevated`
  - `color/background/overlay`

Confirmed fallback values from bound components:

- `color/background/canvas = #0A0A0B`
- `color/background/surface = #101012`
- `color/background/elevated = #16171A`
- `color/border/subtle = #24262B`
- `color/text/primary = #F5F7FA`
- `color/text/secondary = #AEB8C4`
- `color/text/tertiary = #8792A0`
- `color/action/accent = #4378B8`
- `color/action/highlight = rgba(67,120,184,0.33)`
- `color/action/secondary-hover = #2F3238`

The three main semantic depth colors are:

- `canvas`
  - deepest structural background
- `surface`
  - primary content surfaces
- `elevated`
  - floating or nested surfaces above `surface`

Depth in Kairos is therefore expressed through two coupled properties:

- semantic background color
- semantic radius

Do not document or implement them as unrelated systems.

## Kairos Domain Color Tokens

Grid and Level use a domain-specific color layer under `color/kairos/*`.
The confirmed token names in the final file are:

- `color/kairos/step-active`
- `color/kairos/step-inactive`
- `color/kairos/reset-combined`
- `color/kairos/reset-general`
- `color/kairos/anticipation`
- `color/kairos/clip`
- `color/kairos/level-in-target`
- `color/kairos/level-out-target`
- `color/kairos/meter-fill-body`
- `color/kairos/meter-scale-line`

These are not generic status colors. They are domain colors and should remain the
only color interface for Grid and Level logic.

Practical meaning in the final system:

- `step-active` / `step-inactive`
  - current and inactive step drawing states
- `reset-combined`
  - combined reset markers
- `reset-general`
  - global reset markers
- `anticipation`
  - end-of-cycle warning state
- `clip`
  - clipped Level state
- `level-in-target` / `level-out-target`
  - target validation feedback for Level
- `meter-fill-body`
  - main meter mass fill
- `meter-scale-line`
  - Level guide lines and scale drawing

## Typography

The final type system is reduced to three families:

- `title`
- `body`
- `label`

The final screens do not rely on a large editorial hierarchy. They repeatedly use
a small set of concrete variants:

- `type/title/sm`
  - semibold
  - `16 / 20`
  - secondary text color
- `type/title/md`
  - semibold
  - `18 / 24`
  - tight tracking
  - secondary text color
- `type/body/lg`
  - regular
  - `15 / 24`
  - tertiary text color
- `type/label/md`
  - medium
  - desktop and horizontal touch bars: `14 / 20`
  - touch portrait action bar: `16 / 20`
- `type/label/xs`
  - semibold
  - desktop and horizontal touch info labels: `12 / 16`
  - touch portrait info bar: `14 / 16`

There is one local functional exception:

- Level dB labels use a dedicated numeric style
  - medium
  - `14px`
  - used only for meter scale annotation
  - do not treat it as a fourth general-purpose text family

The `KAIROS` wordmark in the toolbars is a separate bold `13px` treatment.

The cross-breakpoint size changes in typography are deliberate accessibility
adjustments. They should not be normalized away during implementation.

## Component Inventory

The `Components` page currently documents the following implementation-facing
components and labs.

### Typographic Samples

- `title-sm`
- `title-md`

There is no separate body-style or label-style component gallery. Those families
are validated through real controls and real screens.

### Icons

The icon set shown in `Components` includes:

- `icon/link`
- `icon/double-arrow`
- `icon/add`
- `icon/mode-line`
- `icon/mode-solid`
- `icon/mode-border`
- `icon/remove-s`
- `icon/power`
- `icon/error-wifi`
- `icon/play-disabled`
- `icon/reset`
- `icon/error`
- `icon/danger`
- `icon-network`
- `icon/rename`
- `icon/dot-status`

State-specific icon components also exist for:

- `icon/sidebar`
- `icon/reproduce`
- `icon/selector`
- `icon/metronome`

### Buttons

#### `button/primary`

Desktop binding:

- min height `32`
- padding `8`
- gap `4`
- surface radius `8`
- label style `type/label/md`

States documented in Figma:

- `default`
- `hover`
- `pressed`

It supports:

- label only
- icon-left
- icon-right
- icon + label

#### `button/secondary`

Desktop binding:

- min height `32`
- padding `8`
- gap `4`
- surface radius `8`
- default fill is elevated surface with subtle border

States documented in Figma:

- `default`
- `hover`
- `pressed`

Use it for compact value selectors and icon buttons.

#### `button/tertiary`

Figma shows:

- `default`
- `folded`

Implementation rule:

- `folded` is not a separate code component
- it is the visual representation of the open dropdown state
- code should treat this as one trigger component plus an attached menu/popover

Observed use cases in final screens:

- value pickers such as BPM, pulse, step count, target level, history range

#### `button/ghost`

Figma shows:

- `default`
- `folded`

Implementation rule:

- same as `button/tertiary`
- use one trigger with open/closed behavior
- the open state can render presets and secondary actions inside a popover or menu

Observed use cases in final screens:

- preset selector
- action groups inside the toolbar

#### `sub-button`

This is an internal row pattern used inside tertiary and ghost dropdown states.
It should not become a top-level design-system component unless the codebase
benefits from it.

### Toggle

`toggle` is a pill switch with two states:

- `inactive`
- `active`

Confirmed desktop binding:

- track width `48`
- track height `28`
- inner padding `4`
- thumb size `20`

### Info Atoms

#### `sync-status`

Variants:

- `link-peers`
- `link-disconnected`
- `midi`
- `internal`

Binding:

- label style `type/label/xs`
- optional icon at the left
- text color uses tertiary text

#### `data`

Variants:

- `time`
- `bpm`

Binding:

- label style `type/label/xs`
- tertiary text color

#### `input-status`

Per-window signal-presence caption shown under each Level window name in the sidebar
(setup/pre-flight only; not present in the performance view).

Composition:

- `icon/dot-status` (colored circle) + a text label

States (dot color + label text):

- `receiving` — green dot + the BlackHole channel text (e.g. `BlackHole 1–2`)
- `no-signal` — white dot + `No signal`
- `clipping` — red dot + `Clipping`

Binding:

- dot color uses the Kairos domain tokens: `color/kairos/lane-status-active` (green),
  `color/kairos/lane-status-idle` (white), `color/kairos/clip` (red)
- label style `type/label/xs`, tertiary text color

The dot is only meaningful for an enabled window; a disabled window collapses and shows
no `input-status`. This atom is the only home of signal-presence feedback — it does not
appear in the Grid or in the performance Level meters.

### Toolbars

#### `tool-bar/desktop`

Structure:

- left cluster
  - wordmark
  - preset selector
  - action icons
- right cluster
  - elapsed time
  - BPM
  - sync status

Confirmed binding:

- height `56`
- horizontal padding `16`
- primary horizontal gap `24`

#### `tool-bar/mobile/horizontal`

Used in touch landscape Grid and Level views.

Structure is almost identical to the desktop toolbar, but scaled to the mobile and
tablet landscape canvases.

Confirmed binding:

- height `56`
- horizontal padding `16`
- primary horizontal gap `24`

#### `tool-bar/mobile/vertical`

This is the touch portrait shell pattern and has two variants:

- `info`
- `action`

`info` variant:

- top bar
- wordmark on the left
- sync/status info on the right

`action` variant:

- bottom bar
- full-width preset selector
- three action buttons

Important responsive differences:

- controls increase from `32px` to `40px` min height
- preset row also increases to `40px`
- `type/label/md` resolves to `16px` here
- `type/label/xs` resolves to `14px` here

This is the clearest example in the final file of touch-first responsive scaling.

### Sidebar

`sidebar` is the main configuration surface.

Confirmed desktop container binding:

- width `375`
- min width `375`
- radius `12`
- background `surface`
- inner section padding `16`
- section gap `24`

High-level structure:

- `Global`
  - `Sync`
  - `Tempo`
- `Grid`
  - four cycles
- `Level`
  - four windows

Each cycle (Grid) and window (Level) header carries two trailing controls, left to
right: `icon/rename` (custom-name button) then the on/off `icon/power`. In Level, each
window also shows an `input-status` caption directly under its name. The `share data`
row is phase 2 and is not present in the v1 screens.

Row pattern used throughout the sidebar:

- left label in `type/body/lg`
- right control in `button/secondary` or `button/tertiary`

Headers:

- section headers use `title-md`
- card headers use `title-sm`

Touch portrait references keep the same content structure but widen the container:

- mobile portrait instance width `398`
- tablet portrait instance width `802`

### Grid

Grid is represented in the component page through:

- `step`
- `cycle`
- `grid/desktop`
- `mark-reset`

Documented visual modes:

- `block`
- `border`
- `line`

Documented step-count variants:

- `4`
- `8`
- `16`
- `32`
- `64`
- `128`

Implementation rule:

- do not build one code component per Figma variant
- Figma is showing a test matrix
- code should render Grid parametrically from:
  - mode
  - cycle count
  - step count
  - active step
  - reset markers
  - anticipation state

Confirmed desktop card binding:

- outer card radius `12`
- per-cycle inner padding `16`
- inter-step gap `8`
- inactive mass uses the Kairos inactive-step color

The `step` lab is especially important because it makes the state space explicit:

- `active`
- `inactive`
- `reset-combined`
- `reset-general`
- `anticipation`

Those states exist for `block`, `border`, `line-md`, and `line-sm`, but that does
not mean the code needs four different component trees.

Treat them as one drawing model with different render modes.

### Level

Level is represented in the component page through:

- `level-band/desktop`
- `level-band-row/desktop`
- `window/desktop`

Implementation rule:

- the Figma composition is a visualization aid
- it should not force the same decomposition in code
- if a direct meter renderer is cleaner, prefer that

Confirmed `window/desktop` binding:

- container background `surface`
- radius `12`
- inner padding `16`

Confirmed scale anatomy:

- horizontal reference bands at:
  - `0`
  - `-6`
  - `-12`
  - `-18`
  - `-24`
  - `-30`
  - `-60`
- the `-12` band is highlighted with the accent blue in the reference state
- band lines use `color/kairos/meter-scale-line`

The final screens show two valid Level layouts:

- four-window split
- single expanded full-width meter

Both should be supported by layout logic. The meter drawing language stays the
same; only the viewport changes.

## Responsive Rules That Matter In Code

These are the responsive changes that clearly affect implementation and should not
be ignored:

- desktop is a fullscreen modular workspace and supports mixed module
  compositions in one viewport
- tablet and mobile default to fullscreen `Sidebar`, not to mixed content views
- tablet and mobile must not present `Grid` and `Level` simultaneously
- touch portrait uses split top/bottom bars instead of one horizontal toolbar
- touch portrait action controls grow from `32px` to `40px`
- touch portrait label tokens resolve to larger values
- mobile and tablet landscape use dedicated content shells instead of the desktop
  combined workspace
- icon, button, control, and type sizes vary by breakpoint through token modes and
  these changes are intentional accessibility adjustments
- sidebar width changes by breakpoint
- Grid and Level viewports are not simply scaled desktop canvases; they have their
  own proven reference sizes
- orientation is part of touch navigation
  - `Sidebar` is vertical
  - `Grid` and `Level` are horizontal
  - opening `Sidebar` from a horizontal screen must switch orientation
  - returning to `Grid` or `Level` must restore horizontal orientation

## Clarifications Still Needed

The following behavior is defined conceptually but not numerically in the current
Figma references or the instructions above:

- touch drag behavior between `Sidebar`, `Grid`, and `Level`
  - snap thresholds, gesture direction details, velocity rules, and transition
    timing are not yet specified here

Code agents should not invent those interaction constants without an explicit
product or motion spec.

## Mapping Rules For Code Agents

Use these rules when translating the final Figma to code:

- Ignore `Archive` completely.
- Treat `Components` and `Screens` as the only valid references.
- Use token names that exist now; do not resurrect legacy token categories.
- Read `folded` states in `button/tertiary` and `button/ghost` as interaction
  examples, not as mandatory component splits.
- Read `step`, `cycle`, `level-band`, and `level-band-row` as Figma test rigs for
  Grid and Level. In code, prefer a cleaner parametric renderer.
- Preserve touch-specific control sizing and text scaling.
- Preserve the desktop combined workspace proportions from the `app-shell-desktop`
  reference.
- Use the isolated Grid and Level screen references on tablet/mobile landscape to
  resolve viewport behavior for those modes.
- Treat semantic depth as a joint decision across background color and radius.
- Do not invent touch gesture thresholds or orientation-transition details that
  are not specified in the current materials.

## Final Implementation Summary

The final Kairos system is a compact dark UI with:

- one active visual language
- one real component set
- three real breakpoints
- one explicit depth system coupling color and radius
- one domain-specific color layer for Grid and Level
- a reduced text system centered on `title`, `body`, and `label`

Anything not present in `Components` or `Screens` is out of scope for the current
implementation.
