--- Kernel/MSUF_Require.lua
--- Explicit REQUIRED-versus-OPTIONAL declarations for cross-module dependencies.
---
--- MSUF publishes most of its cross-file API as `_G.MSUF_*` globals that call
--- sites resolve late. A bare `if type(f) == "function" then f() end` cannot
--- tell a genuinely optional collaborator apart from a hard dependency whose
--- export was renamed, dropped from the TOC, or moved behind the consumer in
--- the load order: both simply do nothing, with no error and no clue. These two
--- helpers make the difference explicit, greppable, and - for the required
--- half - loud.
---
--- MSUF.Require(name, context)
---   Resolves `_G[name]` at the load of the calling file and raises when it is
---   not a function or a table. Use it for a symbol that MUST be there; keep
---   the call itself unchanged so correctly wired code behaves identically.
---
--- MSUF.Optional(name)
---   Returns `_G[name]` when it is a function or a table and nil otherwise. It
---   never raises. Use it so a genuinely optional collaborator reads as a
---   decision instead of an unchecked dependency; the caller still nil-checks.
---
--- A dependency is required when the production feature needs its provider.
--- Test fixtures must load that provider; incomplete fixtures never make a
--- production dependency optional. Resolve early dependencies with Require.
--- Resolve forward dependencies at use time, after the owning TOC/LOD module
--- finishes loading, and validate their exports at that readiness boundary.
--- Optional means an intentionally absent collaborator, such as another addon
--- or a load-on-demand UI that has not been opened. It does not mean an export
--- renamed or removed during a refactor.
---
--- No pcall here on purpose (house rule). A missing hard dependency has to
--- unwind with the symbol name in the message instead of being swallowed.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = _G.MSUF or MSUF

local _G = _G
local type = type
local tostring = tostring
local error = error

local ExportPublic = MSUF.ExportPublic

--- Resolve a published global to a usable value. Only functions and tables
--- count: those are the two shapes MSUF exports across files.
local function Resolve(name)
    if type(name) ~= "string" or name == "" then return nil end
    local value = _G[name]
    local kind = type(value)
    if kind == "function" or kind == "table" then return value end
    return nil
end

--- Hard dependency. Raises at the caller's line, naming the symbol and the
--- file that declared the requirement.
local function Require(name, context)
    local value = Resolve(name)
    if value ~= nil then return value end
    local where = context and (" required by " .. tostring(context)) or ""
    error("MSUF: missing required dependency '" .. tostring(name) .. "'" .. where
        .. " - check that its provider still exports it and still loads first in MidnightSimpleUnitFrames.toc.", 2)
end

--- Soft dependency. Returns nil instead of raising; the caller decides.
local function Optional(name)
    return Resolve(name)
end

MSUF.Require = Require
MSUF.Optional = Optional

ExportPublic("MSUF_Require", Require)
ExportPublic("MSUF_Optional", Optional)
