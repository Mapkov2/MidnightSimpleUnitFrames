local function Read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local theme = Read("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Theme.lua")
assert(not theme:find("ButtonDepthArt", 1, true),
    "hidden button depth textures returned to the Menu2 theme")
assert(theme:find("function T.RefreshMenuFontStrings", 1, true)
    and theme:find("RegisterPageFontString(fs)", 1, true),
    "page-local font registry is missing")

local widgets = Read("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Widgets.lua")
assert(widgets:find("local layoutChanged = false", 1, true)
    and widgets:find("if layoutChanged then QueuePinnedPreviewGeometryRefresh", 1, true),
    "collapsible geometry refresh is not change-gated")
assert(widgets:find("opts.skipStateRefresh", 1, true)
    and widgets:find("refreshUntrackedState", 1, true),
    "collapsible state refresh is not separated from build-time geometry")

local search = Read("MidnightSimpleUnitFrames/Shell/Menu2/Search/MSUF_Menu2_Search_IndexQuery.lua")
assert(search:find('local catalogInteractive = meta.catalog ~= false and (type(command) == "table"', 1, true),
    "construction-time widgets still enter the runtime catalog without semantics")
assert(not search:find('or catalogKind == "button"', 1, true),
    "widget kind still forces provisional runtime-catalog records")

local window = Read("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Window.lua")
local rebuild = assert(window:match(
    "function RebuildActivePageForResize%b()%s*(.-)%s*function M%.RegisterPage"
), "resize rebuild helper missing")
assert(not rebuild:find("InvalidatePage", 1, true),
    "resize still semantically invalidates and abandons the active page")
assert(window:find("M._msuf2PageLayoutVariants", 1, true)
    and window:find("RestorePageEntryRegistrations", 1, true),
    "normal/maximized page variants are not reusable")
assert(window:find("cached.hiddenBuild == true and not hidden", 1, true)
    and window:find("cached.wrapper:SetParent(nil)", 1, true),
    "search-only hidden pages are being promoted despite preview placeholders")

local auraModel = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Menu_Model.lua")
assert(auraModel:find('setmetatable({}, { __mode = "k" })', 1, true)
    and auraModel:find("DefaultsIntoOnce(shared, DEFAULT_SHARED)", 1, true)
    and auraModel:find("Model.InvalidateDefaultSeedCache()", 1, true),
    "Aura menu defaults are not cached behind an explicit invalidation boundary")

print("menu2_perfy_hotpath_contract_smoke: ok")
