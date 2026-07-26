-- Menu2 development consistency checks.
--
-- The nav list, aliases, icon grid, theme colors, and ApplyService global
-- lists are all built from compact string DSLs. A typo there fails silently:
-- the nav entry just doesn't appear, the color becomes nil, the refresh
-- global is never called. This module makes those failures loud on demand.
--
-- Usage: /msufmenucheck
-- Read-only; safe to run on live characters. Zero cost unless invoked.
local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

local function Report(issues, severity, text)
    issues[#issues + 1] = { severity = severity, text = text }
end

local function CheckNavigation(issues)
    local navItems = M.navItems
    if type(navItems) ~= "table" or #navItems == 0 then
        Report(issues, "error", "navItems missing or empty (Navigation DSL failed to parse)")
        return
    end
    local T = M.Theme or {}
    local iconGrid = T.navIconGrid or {}
    local iconColors = T.navIconColors or {}
    local pages = M.pages or {}
    local navKeys = {}
    for i = 1, #navItems do
        local item = navItems[i]
        if item.key then
            navKeys[item.key] = true
            if not pages[item.key] then
                Report(issues, "error", ("nav item '%s' (%s) has no registered page"):format(item.key, tostring(item.label)))
            end
            if not iconGrid[item.key] then
                Report(issues, "warn", ("nav item '%s' has no icon in T.navIconGrid"):format(item.key))
            end
            if not iconColors[item.key] then
                Report(issues, "warn", ("nav item '%s' has no color in T.navIconColors"):format(item.key))
            end
            if type(item.label) ~= "string" or item.label == "" then
                Report(issues, "error", ("nav item '%s' has no label"):format(item.key))
            end
        elseif item.header then
            if type(item.id) ~= "string" or item.id == "" then
                Report(issues, "warn", ("nav header '%s' has no group id"):format(tostring(item.header)))
            end
        elseif item.title then
            if type(item.id) ~= "string" or item.id == "" then
                Report(issues, "warn", ("nav title '%s' has no group id"):format(tostring(item.title)))
            end
        else
            Report(issues, "error", ("nav row %d is neither page nor header/title (DSL parse defect)"):format(i))
        end
    end
    for key in pairs(iconGrid) do
        if not navKeys[key] and not pages[key] then
            Report(issues, "info", ("icon grid entry '%s' matches no nav item or page (stale?)"):format(key))
        end
    end
    local aliases = M.ALIASES
    if type(aliases) == "table" then
        for alias, target in pairs(aliases) do
            if target ~= "search" and not navKeys[target] and not pages[target] then
                Report(issues, "error", ("alias '%s' points to unknown page '%s'"):format(alias == "" and "<empty>" or alias, tostring(target)))
            end
        end
    else
        Report(issues, "error", "M.ALIASES missing (alias DSL failed to parse)")
    end
end

local function CheckThemeColors(issues)
    local T = M.Theme or {}
    local colors = T.colors
    if type(colors) ~= "table" then
        Report(issues, "error", "T.colors missing (color DSL failed to parse)")
        return
    end
    for key, c in pairs(colors) do
        if type(c) ~= "table" or #c < 3 or #c > 4 then
            Report(issues, "error", ("color '%s' has %s components (expected 3-4)"):format(key, type(c) == "table" and #c or type(c)))
        else
            for i = 1, #c do
                if type(c[i]) ~= "number" then
                    Report(issues, "error", ("color '%s' component %d is not a number"):format(key, i))
                    break
                end
            end
        end
    end
end

local function CheckApplyService(issues)
    local Apply = M.ApplyService
    if type(Apply) ~= "table" then
        Report(issues, "error", "M.ApplyService missing")
        return
    end
    local required = { "Flush", "RequestUnit", "RequestGeneral", "RequestGroup", "RequestAuras", "RequestClassPower" }
    for i = 1, #required do
        local name = required[i]
        if type(Apply[name]) ~= "function" then
            Report(issues, "error", "ApplyService." .. name .. " is missing")
        end
    end
end

local function CheckMotionTokens(issues)
    local T = M.Theme or {}
    local motion = T.motion or {}
    local policy = T.motionPolicy or {}
    local minD, maxD = tonumber(policy.min), tonumber(policy.max)
    if minD and maxD then
        for key, duration in pairs(motion) do
            duration = tonumber(duration)
            if not duration then
                Report(issues, "error", ("motion '%s' is not a number"):format(key))
            elseif duration < minD or duration > maxD then
                Report(issues, "warn", ("motion '%s' (%.3f) outside policy [%.3f, %.3f]"):format(key, duration, minD, maxD))
            end
        end
    end
end

local SEVERITY_COLOR = { error = "|cffff5040", warn = "|cffffb020", info = "|cff80a0ff" }

local function RunChecks()
    local issues = {}
    CheckNavigation(issues)
    CheckThemeColors(issues)
    CheckApplyService(issues)
    CheckMotionTokens(issues)
    local errors, warns = 0, 0
    for i = 1, #issues do
        if issues[i].severity == "error" then errors = errors + 1
        elseif issues[i].severity == "warn" then warns = warns + 1 end
    end
    if #issues == 0 then
        print("|cff40d060MSUF Menu Check:|r no issues found (nav, aliases, icons, colors, motion, apply globals)")
        return
    end
    print(("|cffffd700MSUF Menu Check:|r %d error(s), %d warning(s), %d note(s)"):format(errors, warns, #issues - errors - warns))
    for i = 1, #issues do
        local issue = issues[i]
        print("  " .. (SEVERITY_COLOR[issue.severity] or "") .. issue.severity .. "|r " .. issue.text)
    end
end

_G.SLASH_MSUFMENUCHECK1 = "/msufmenucheck"
-- Blizzard owns this table; reassigning the global taints protected commands such as /tm.
_G.SlashCmdList.MSUFMENUCHECK = RunChecks
--- Listed in /msuf help only while this file is actually loaded.
if MSUF and MSUF.SlashCommands and MSUF.SlashCommands.RegisterExternal then
    MSUF.SlashCommands.RegisterExternal({
        usage = "/msufmenucheck",
        help = "Check the options menu for structural problems.",
        dev = true,
    })
end
