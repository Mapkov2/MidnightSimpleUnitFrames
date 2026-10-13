--- Registers MSUF bundled fonts/textures with LibSharedMedia-3.0 (if available).
--- Kernel/MSUF_Libs.lua owns the registration and the legacy bar-texture key
--- migration, and exports this entry point before the TOC reaches this file.
--- Keep this file lightweight and load-order safe.

local _, MSUF = ...

MSUF.Require("MSUF_RegisterBundledMediaWithLSM", "Media/MSUF_Media.lua")()
