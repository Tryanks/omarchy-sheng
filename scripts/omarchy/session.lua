-- Upstream prepends its own bin directory. Keep the device's provisioning and
-- update entrypoints first for autostart, shell menus and launched terminals.
hl.env("PATH", "/usr/local/bin:" .. (os.getenv("PATH") or "/usr/bin"))

-- The SM8550/DSI cursor plane can be invisible while input remains functional.
-- Composite the cursor in the desktop until the device DRM path is qualified.
hl.config({ cursor = { no_hardware_cursors = true } })
