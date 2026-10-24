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
--- MSUF.Require(name, context[, namespace])
---   Resolves a nonnil `_G[name]` first, otherwise a namespace-only owned
---   PublicGlobals entry. Raises unless the result is a function or table.
---   Keep the call itself unchanged so correctly wired code behaves identically.
---
--- MSUF.Optional(name[, context[, namespace]])
---   Uses the same global-first, then namespace-only owned-registry lookup.
---   Returns a function or table and nil otherwise; it never raises. Use it so
---   an optional collaborator is explicit; the caller still nil-checks.
---
--- An explicit third argument resolves only that table, with no global or
--- registry fallback (even for nil/false/wrong-type input). Its keys are exact.
--- Without it both legacy lookup contracts above remain unchanged; Optional
--- continues to ignore its second context argument.
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
local select = select

local ExportPublic = MSUF.ExportPublic

--- Resolve a compatible global or a namespace-only owned export. A nonnil
--- global, including false/zero/wrong type, keeps its original precedence.
--- A cleared public alias stays absent even if its registry snapshot remains.
--- Only functions and tables count as cross-file dependencies.
local function Resolve(name, namespace, explicit)
    if type(name) ~= "string" or name == "" then return nil end
    local value, kind
    if explicit then
        if type(namespace) ~= "table" then return nil end
        value = namespace[name]
        kind = type(value)
    else
        value = _G[name]
        kind = type(value)
        if kind == "nil" then
            local compat = MSUF.Compat
            local legacy = compat and compat.LegacyGlobals
            if not (legacy and legacy[name]) then
                local owned = MSUF.PublicGlobals
                value = owned and owned[name]
                kind = type(value)
            end
        end
    end
    if kind == "function" or kind == "table" then return value end
    return nil
end

--- Hard dependency. Raises at the caller's line, naming the symbol and the
--- file that declared the requirement.
local function Require(name, context, ...)
    local value = Resolve(name, (...), select("#", ...) > 0)
    if value ~= nil then return value end
    local where = context and (" required by " .. tostring(context)) or ""
    error("MSUF: missing required dependency '" .. tostring(name) .. "'" .. where
        .. " - check that its provider still exports it and still loads first in MidnightSimpleUnitFrames.toc.", 2)
end

--- Soft dependency. Returns nil instead of raising; the caller decides.
local function Optional(name, context, ...)
    return Resolve(name, (...), select("#", ...) > 0)
end

MSUF.Require = Require
MSUF.Optional = Optional

ExportPublic("MSUF_Require", Require)
ExportPublic("MSUF_Optional", Optional)
