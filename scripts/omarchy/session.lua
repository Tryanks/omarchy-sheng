-- Upstream prepends its own bin directory. Keep the device's provisioning and
-- update entrypoints first for autostart, shell menus and launched terminals.
hl.env("PATH", "/usr/local/bin:" .. (os.getenv("PATH") or "/usr/bin"))

-- The SM8550/DSI cursor plane can be invisible while input remains functional.
-- Composite the cursor in the desktop until the device DRM path is qualified.
hl.config({ cursor = { no_hardware_cursors = true } })

-- The tablet's Hall switch is gpio-keys, not the PC's "Lid Switch".
-- logind suspend is disabled; closing only locks/blanks, opening only wakes.
o.bind("switch:on:gpio-keys", nil, "/usr/local/lib/omarchy-sheng/lid.sh close", { locked = true })
o.bind("switch:off:gpio-keys", nil, "/usr/local/lib/omarchy-sheng/lid.sh open", { locked = true })
o.window("org.omarchy.sheng.Fingerprint", { float = true, center = true })
o.window("org.omarchy.sheng.Fingerprint", { size = { 560, 500 } })
