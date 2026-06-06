# LuaLS note

Lua language server was flagging a large number of warnings because full-workspace diagnostics scanned this addon as plain Lua and lacked WoW runtime/global context.

This setup keeps Lua 5.1 runtime enabled, disables full-workspace diagnostics, and limits diagnostics to opened files/libraries.
It also ignores build/archive/backup/generated folders and zip artifacts, disables aggressive third-party scanning, and declares shared WoW/MSUF globals so cross-file symbols are treated intentionally shared instead of undefined.
