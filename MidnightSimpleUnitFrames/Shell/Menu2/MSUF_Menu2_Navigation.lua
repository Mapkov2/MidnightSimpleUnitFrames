--- Menu2 navigation data and slash/page aliases.
---
--- This module is intentionally data-only. The window shell consumes
--- `M.navItems` and `M.ALIASES`; search indexing also reads `M.navItems`.
--- Keeping it separate makes page/navigation changes visible without digging
--- through frame construction code.
local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local Lines = M.Lines or function(rows) return tostring(rows or ""):gmatch("[^\r\n]+") end
local PipeRows = M.PipeRows
if type(PipeRows) ~= "function" then
    PipeRows = function(rows)
        local out = {}
        for line in Lines(rows) do
            local cols, n = {}, 0
            for col in (line .. "|"):gmatch("(.-)|") do n = n + 1; cols[n] = col end
            out[#out + 1] = cols
        end
        return out
    end
end

local function NavRows(rows)
    local nav = {}
    for _, cols in ipairs(PipeRows(rows)) do
        if cols[1] == "T" then
            nav[#nav + 1] = { title = cols[2], id = cols[3] }
        elseif cols[1] == "H" then
            nav[#nav + 1] = { header = cols[2], id = cols[3], defaultOpen = cols[4] ~= "0" }
        elseif cols[1] == "P" then
            local item = { key = cols[2], label = cols[3] }
            if cols[4] and cols[4] ~= "" then item.group = cols[4] end
            nav[#nav + 1] = item
        end
    end
    return nav
end
M.navItems = NavRows [[
P|home|Dashboard
T|Frames|frames
P|uf_player|Unitframes|frames
P|gf_layout|Party/Raid Frames|frames
T|Appearance|appearance
P|opt_bars|Bars|appearance
P|opt_castbar|Cast Bars|appearance
P|opt_colors|Colors|appearance
P|opt_fonts|Fonts|appearance
P|auras3_styling|Auras|appearance
P|opt_misc|Miscellaneous|appearance
T|Features|features
P|classpower|Class Resources|features
P|gameplay|Gameplay|features
P|profiles|Profiles
]]
M.navPrimaryForKey = {
    home = "home",
    uf_player = "uf_player",
    uf_target = "uf_player",
    uf_boss = "uf_player",
    uf_focus = "uf_player",
    uf_pet = "uf_player",
    uf_targettarget = "uf_player",
    uf_focustarget = "uf_player",
    gf_layout = "gf_layout",
    gf_bars = "gf_layout",
    gf_indicators = "gf_layout",
    gf_auras = "gf_layout",
    auras3_styling = "auras3_styling",
    auras3_filters = "auras3_styling",
    auras3_buffs = "auras3_styling",
    auras3_debuffs = "auras3_styling",
    auras3_custom = "auras3_styling",
    opt_bars = "opt_bars",
    opt_castbar = "opt_castbar",
    opt_colors = "opt_colors",
    opt_fonts = "opt_fonts",
    opt_misc = "opt_misc",
    classpower = "classpower",
    gameplay = "gameplay",
    profiles = "profiles",
}
local function AliasRows(rows)
    local aliases = {}
    for line in Lines(rows) do
        local target, keys = line:match("^([^=]+)=(.+)$")
        if target and keys then
            for key in keys:gmatch("[^|]+") do
                aliases[key == "<empty>" and "" or key] = target
            end
        end
    end
    return aliases
end
M.ALIASES = AliasRows [[
home=<empty>|home|menu|main|options|opt
uf_player=player|frames|frame|unitframes|unit_frames|unitframe|unit_frame
uf_target=target
uf_targettarget=tot|targettarget
uf_focustarget=focustarget|focus_target|focustargettarget|ft
uf_focus=focus
uf_boss=boss
uf_pet=pet
opt_bars=bars|appearance|appearances|look|looks|style|globalstyle|global_style
opt_fonts=fonts
auras3_styling=aura|auras|aura_style|aurastyle|aura_styling|aurastyling|aura_appearance|auraappearance
opt_castbar=castbar
opt_colors=colors|colours
opt_misc=misc
classpower=classpower|class
gameplay=gameplay
profiles=profiles
gf_layout=layout|group|groupframes|partyraid|party_raid|party/raid|partyframes|party_frames|raidframes|raid_frames|party|raid
gf_bars=health
gf_indicators=status|statuses|indicator|indicators|status_indicators|statusindicator|group_status|group_indicators|groupindicators
modules=modules
search=search
]]
