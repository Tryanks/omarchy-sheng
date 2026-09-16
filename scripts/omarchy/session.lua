-- Upstream prepends its own bin directory. Keep the device's provisioning and
-- update entrypoints first for autostart, shell menus and launched terminals.
hl.env("PATH", "/usr/local/bin:" .. (os.getenv("PATH") or "/usr/bin"))
