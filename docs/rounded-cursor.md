# Pointer bounds on the rounded internal panel

A global `cursor.hotspot_padding=16` prevents the pointer reaching every straight
edge, not just the obscured corners. That workaround was withdrawn. Window and
bar geometry must remain unchanged.

The optional `scripts/omarchy/rounded-cursor.lua` projects only points outside
the four corner arcs onto the nearest point of the arc. Straight edges, valid
points inside corners, and external outputs are unchanged. Coordinates account
for output scale, position and rotation. The current radius of 96 native panel
pixels is an estimate requiring physical calibration, not a panel specification.

This Hyprland Lua API does not expose pointer-motion callbacks. The guard uses
an 8 ms in-process timer and warps only if a coordinate needs correction. It
backs off to 500 ms when the output is powered off. It is not a native compositor
input constraint: a pointer can briefly enter the masked area between samples.
It also respects the user's `cursor.no_warps` setting. Runtime overhead and
physical corner alignment must be checked on the tablet before promoting it
to an image default. It is not included in preview.2.

To enable, install the Lua module under `/usr/local/lib/omarchy-sheng/`, remove
the rectangular hotspot padding, and add this to the user's Hyprland config:

```lua
hl.config({ cursor = { hotspot_padding = 0 } })
dofile("/usr/local/lib/omarchy-sheng/rounded-cursor.lua").start({
  output = "DSI-1",
  radius_px = 96,
})
```

Reloading config enables it without restarting the compositor. Removing the
`dofile` line and reloading disables it. Do not add reserved monitor space or
bar spacers: this adjustment is only for the pointer.

Run `lua tests/rounded-cursor.lua` for straight-edge reachability, all four
arcs, valid-corner points, scaling, rotation, external outputs and screen-off
backoff. Live verification should also move to edge midpoints and corners,
read back the corrected positions, and restore the original pointer position.

The test tablet reconnected on 2026-09-17 while charging at 12%. Live checks
called the exact timer callback synchronously to avoid interference from the
user moving the touchpad: all four edge midpoints remained unchanged, the
valid corner point `(2,40)` remained unchanged, and `(0,0)` projected to
`(14.06,14.06)` on the 48-logical-pixel arc. The other three corners passed too.
The original pointer position was restored. Layout settings were unchanged.
Physical alignment of the estimated arc still requires visual calibration.
