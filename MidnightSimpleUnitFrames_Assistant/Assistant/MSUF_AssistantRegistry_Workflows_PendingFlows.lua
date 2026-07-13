-- Assistant pending workflow handlers.
-- Loaded before MSUF_AssistantRegistry_Workflows.lua; the main workflow module passes shared helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.Workflow = A.Workflow or {}

function A.Workflow.RegisterPendingFlowHandlers(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local Trim = ctx.Trim or function(text)
        text = tostring(text or "")
        return (text:gsub("^%s+", ""):gsub("%s+$", ""))
    end
    local Normalize = ctx.Normalize or function(text)
        text = tostring(text or ""):lower():gsub("[,;:!?%(%)]", " "):gsub("%s+", " ")
        return Trim(text)
    end

    if not (Registry and type(Registry.GetAction) == "function") then return end

    local function IsCancel(text)
        text = Normalize(text)
        if text == "cancel" or text == "no" or text == "nein" or text == "abort" or text == "stop" or text == "close" then return true end
        local phrases = {
            "never mind", "nevermind", "forget it", "cancel that", "abort that", "stop that", "not now",
            "no thanks", "no thank you", "dont", "do not",
            "abbrechen", "abbruch", "nein danke", "vergiss es", "lass es", "doch nicht",
        }
        for i = 1, #phrases do
            if (" " .. text .. " "):find(" " .. phrases[i] .. " ", 1, true) then return true end
        end
        return false
    end

    local function StripPrefixCI(raw, prefix)
        raw = Trim(raw)
        prefix = tostring(prefix or "")
        if raw == "" or prefix == "" then return nil end
        if raw:sub(1, #prefix):lower() == prefix:lower() then
            local value = Trim(raw:sub(#prefix + 1))
            value = Trim(value:gsub("^[:=%-%s]+", ""))
            return value
        end
        return nil
    end

    local function StripSuffixCI(raw, suffix)
        raw = Trim(raw)
        suffix = tostring(suffix or "")
        if raw == "" or suffix == "" or #raw < #suffix then return raw end
        if raw:sub(#raw - #suffix + 1):lower() == suffix:lower() then
            return Trim(raw:sub(1, #raw - #suffix))
        end
        return raw
    end

    local function CleanPendingProfileDestination(text, kind)
        local raw = Trim(text)
        if raw == "" then return "" end
        raw = Trim(raw:gsub("[%.!]+$", ""))
        raw = StripSuffixCI(raw, " please")
        raw = StripSuffixCI(raw, " bitte")
        local politePrefix = StripPrefixCI(raw, "please ") or StripPrefixCI(raw, "bitte ")
        if politePrefix and politePrefix ~= "" then raw = politePrefix end
        local prefixes = {
            "call it ", "name it ", "use name ", "use profile name ", "profile name ",
            "new profile name ", "new profile ", "destination profile ", "destination ",
            "to profile ", "to ",
            "nenn es ", "nenne es ", "name ist ", "profilname ", "zu profil ", "zu ",
            "nach profil ", "nach ", "als ",
        }
        if kind == "profileCopyDestination" then
            local copyPrefixes = { "copy it to ", "copy to ", "copy profile to ", "kopiere es nach ", "kopiere nach " }
            for i = 1, #copyPrefixes do
                local value = StripPrefixCI(raw, copyPrefixes[i])
                if value and value ~= "" then raw = value; break end
            end
        elseif kind == "profileRenameDestination" then
            local renamePrefixes = { "rename it to ", "rename to ", "rename profile to ", "benenne es um in ", "benenne es um zu ", "benenne es in ", "umbenennen in ", "umbenennen zu ", "in profile ", "in " }
            for i = 1, #renamePrefixes do
                local value = StripPrefixCI(raw, renamePrefixes[i])
                if value and value ~= "" then raw = value; break end
            end
        end
        for i = 1, #prefixes do
            local value = StripPrefixCI(raw, prefixes[i])
            if value and value ~= "" then raw = value; break end
        end
        raw = Trim(raw:gsub("^['\"`]+", ""):gsub("['\"`]+$", ""))
        return raw
    end

    local function OriginalDestination(text, kind)
        local cleaned = CleanPendingProfileDestination(text, kind)
        local normalized = Normalize(text)
        local history = type(A.GetHistory) == "function" and A.GetHistory() or nil
        if type(history) ~= "table" then return cleaned end
        for i = #history, 1, -1 do
            local item = history[i]
            if type(item) == "table" and item.role == "user" then
                local original = CleanPendingProfileDestination(item.text, kind)
                -- RouteInput normalizes punctuation before a blocking flow reaches
                -- this handler. Recover the just-recorded raw reply so quoted empty
                -- names stay empty and user-facing capitalization is preserved.
                if Normalize(item.text) == normalized then return original end
                if original:lower() == cleaned:lower() then return original end
                break
            end
        end
        return cleaned
    end

    local function DisplayProfileName(name)
        local display = A.DisplayProfileName
        return type(display) == "function" and display(name) or Trim(name)
    end

    local function PendingSetting(settingKey)
        if type(settingKey) ~= "string" or settingKey == "" then return nil end
        return Registry and type(Registry.GetSetting) == "function" and Registry:GetSetting(settingKey) or nil
    end

    local function OpenPendingSetting(flow, settingKey, label)
        local action = Registry and type(Registry.GetAction) == "function" and Registry:GetAction("open_setting_control") or nil
        if not action then
            return { text = "I found the exact option, but the menu navigation bridge is not ready yet. Reopen the MSUF menu and try again.", status = "failed" }
        end
        return A.ExecutePlan({
            kind = "action",
            action = action,
            args = {
                settingKey = settingKey,
                page = flow and flow.page,
                label = label or (flow and flow.label),
            },
            label = "Open " .. tostring(label or (flow and flow.label) or "exact MSUF option"),
            summary = "Opens the exact control from the current Assistant conversation.",
        })
    end

    local function WantsPendingSettingOpen(text)
        local norm = Normalize(text)
        return norm == "open" or norm == "open it" or norm == "open this" or norm == "open that"
            or norm == "open horizontal" or norm == "open vertical"
            or norm == "open x offset" or norm == "open y offset"
            or norm == "show me where" or norm == "show me where it is" or norm == "show me where that is"
            or norm == "where do i change it" or norm == "where do i change that" or norm == "where do i change this"
            or norm == "where can i change it" or norm == "where can i change that" or norm == "where can i change this"
            or norm == "take me to it" or norm == "take me to that" or norm == "take me there"
            or norm == "go to it" or norm == "go to that" or norm == "go there"
    end

    local function LooksLikeFreshPendingTopic(text)
        local parser = A.Parser or {}
        local norm = type(parser.ActionableText) == "function" and Normalize(parser.ActionableText(text)) or Normalize(text)
        if norm == "" then return false end
        return norm:match("^set%s+") ~= nil or norm:match("^change%s+") ~= nil
            or norm:match("^make%s+") ~= nil or norm:match("^turn%s+") ~= nil
            or norm:match("^enable%s+") ~= nil or norm:match("^disable%s+") ~= nil
            or norm:match("^show%s+") ~= nil or norm:match("^hide%s+") ~= nil
            or norm:match("^move%s+") ~= nil or norm:match("^nudge%s+") ~= nil
            or norm:match("^shift%s+") ~= nil or norm:match("^position%s+") ~= nil
            or norm:match("^reposition%s+") ~= nil or norm:match("^raise%s+") ~= nil
            or norm:match("^lower%s+") ~= nil or norm:match("^increase%s+") ~= nil
            or norm:match("^decrease%s+") ~= nil or norm:match("^add%s+") ~= nil
            or norm:match("^remove%s+") ~= nil or norm:match("^reset%s+") ~= nil
            or norm:match("^toggle%s+") ~= nil or norm:match("^open%s+") ~= nil
            or norm:match("^search%s+") ~= nil or norm:match("^find%s+") ~= nil
            or norm:match("^where%s+") ~= nil or norm:match("^how%s+") ~= nil
    end

    local function IsReferentialPendingValueReply(text)
        local parser = A.Parser or {}
        local norm = type(parser.ActionableText) == "function" and Normalize(parser.ActionableText(text)) or Normalize(text)
        return norm:match("^set%s+it%s+to%s+") ~= nil
            or norm:match("^set%s+that%s+to%s+") ~= nil
            or norm:match("^set%s+this%s+to%s+") ~= nil
            or norm:match("^set%s+to%s+") ~= nil
            or norm:match("^make%s+it%s+") ~= nil
            or norm:match("^make%s+that%s+") ~= nil
            or norm:match("^make%s+this%s+") ~= nil
            or norm:match("^use%s+") ~= nil
            or norm:match("^value%s+") ~= nil
            or norm:match("^to%s+") ~= nil
            or norm:match("^at%s+") ~= nil
    end

    local function IsReferentialPendingMovementReply(text)
        local parser = A.Parser or {}
        local norm = type(parser.ActionableText) == "function" and Normalize(parser.ActionableText(text)) or Normalize(text)
        local allowed = {
            a = true, bit = true, by = true, further = true, it = true, just = true,
            move = true, nudge = true, shift = true, position = true, reposition = true,
            please = true, pixel = true, pixels = true, px = true, slightly = true,
            that = true, the = true, this = true,
            up = true, down = true, left = true, right = true, higher = true, lower = true, raise = true,
        }
        local directionWords = { up = true, down = true, left = true, right = true, higher = true, lower = true, raise = true }
        local movementVerbs = { move = true, nudge = true, shift = true, position = true, reposition = true }
        local sawDirection, sawPronoun, sawMovementVerb = false, false, false
        for word in norm:gmatch("%a+") do
            if not allowed[word] then return false end
            if directionWords[word] then sawDirection = true end
            if word == "it" or word == "that" or word == "this" then sawPronoun = true end
            if movementVerbs[word] then sawMovementVerb = true end
        end
        return sawDirection or (sawMovementVerb and sawPronoun)
    end

    local function PendingValueText(text, expectedType)
        local raw = Trim(text)
        local norm = Normalize(raw)
        if norm:match("^result%s+%d+$") or norm:match("^option%s+%d+$") then return nil end
        raw = raw:gsub("^[Pp]lease%s+", "")
        local prefixes = {
            "set it to ", "set that to ", "set this to ", "set to ", "use ",
            "make it ", "make that ", "make this ",
            "value ", "to ", "at ",
        }
        local lowered = raw:lower()
        for i = 1, #prefixes do
            local prefix = prefixes[i]
            if lowered:sub(1, #prefix) == prefix then
                raw = Trim(raw:sub(#prefix + 1))
                break
            end
        end
        if raw == "" then return nil end
        if expectedType == "number" then
            if not raw:match("^[%+%-]?%d+%.?%d*%%?$") and not raw:match("^[%+%-]?%.%d+%%?$") then return nil end
        elseif expectedType == "color" then
            local colorNorm = Normalize(raw)
            local named = {
                red = true, green = true, blue = true, yellow = true, orange = true, purple = true,
                pink = true, white = true, black = true, gray = true, grey = true, cyan = true,
                magenta = true, gold = true, brown = true, turquoise = true,
            }
            local isHex = raw:match("^#?%x%x%x%x%x%x%x?%x?$") ~= nil
            local isRGB = raw:match("^%d+%s*[, ]%s*%d+%s*[, ]%s*%d+$") ~= nil
            if not named[colorNorm] and not isHex and not isRGB then return nil end
        end
        return raw
    end

    local function HandleSettingValueFlow(text, flow)
        if WantsPendingSettingOpen(text) then
            return OpenPendingSetting(flow, flow.settingKey, flow.label)
        end
        local setting = PendingSetting(flow.settingKey)
        if not setting then
            A.ClearPendingFlow()
            return { text = "That option is no longer available in the active MSUF profile. Ask me to find it again.", status = "failed" }
        end
        -- A strong new command changes the subject instead of becoming the
        -- literal value of a free-form string setting. Referential forms such
        -- as "set it to ..." remain attached to the selected control.
        if LooksLikeFreshPendingTopic(text) and not IsReferentialPendingValueReply(text) then
            A.ClearPendingFlow()
            return nil
        end
        local rawValue = PendingValueText(text, flow.expectedType or setting.type)
        if rawValue == nil then
            local norm = Normalize(text)
            if norm:match("^result%s+%d+$") or norm:match("^option%s+%d+$") then return nil end
            if LooksLikeFreshPendingTopic(text) then
                A.ClearPendingFlow()
                return nil
            end
            return {
                text = "I am still waiting for the value for " .. tostring(flow.label or setting.label or "that option")
                    .. ". Give me the value, ask me to open it, or say cancel.",
                status = "ambiguous",
            }
        end
        local parser = A.Parser or {}
        -- Use the human registry label in the synthetic command and preserve
        -- the original reply as raw text. String parsing intentionally keys
        -- off labels/aliases (not internal dotted keys) so values such as
        -- "Shadow Word: Pain" retain their case and punctuation.
        local synthetic = "set " .. tostring(setting.label or setting.key) .. " to " .. tostring(rawValue)
        local value = type(parser.ValueForRegistrySetting) == "function"
            and parser.ValueForRegistrySetting(setting, Normalize(synthetic), synthetic) or nil
        if value == nil then
            return {
                text = "I could not use '" .. tostring(rawValue) .. "' for " .. tostring(flow.label or setting.label or "that option")
                    .. ". Try another value, ask me to open it, or say cancel.",
                status = "ambiguous",
            }
        end
        A.ClearPendingFlow()
        return A.ExecutePlan({
            kind = "changes",
            changes = { { setting = setting, value = value } },
            label = "Set " .. tostring(flow.label or setting.label or setting.key),
            summary = "Changes the exact option selected in the previous Assistant message.",
            sourceText = synthetic,
        })
    end

    local function MovementDirection(text)
        local norm = Normalize(text)
        if norm == "1" or norm:find(" up", 1, true) or norm:match("^up%s*")
            or norm:find("higher", 1, true) or norm:find("raise", 1, true) then return "up" end
        if norm == "2" or norm:find(" down", 1, true) or norm:match("^down%s*")
            or norm:find("lower", 1, true) then return "down" end
        if norm == "3" or norm:find(" left", 1, true) or norm:match("^left%s*") then return "left" end
        if norm == "4" or norm:find(" right", 1, true) or norm:match("^right%s*") then return "right" end
        return nil
    end

    local function HandleSettingMovementFlow(text, flow)
        local norm = Normalize(text)
        if WantsPendingSettingOpen(text) then
            local axisKey
            local axisLabel
            if norm:find("horizontal", 1, true) or norm:find("x offset", 1, true) then
                axisKey, axisLabel = flow.xKey, tostring(flow.label or "Text") .. " X Offset"
            elseif norm:find("vertical", 1, true) or norm:find("y offset", 1, true) then
                axisKey, axisLabel = flow.yKey, tostring(flow.label or "Text") .. " Y Offset"
            end
            if axisKey then return OpenPendingSetting(flow, axisKey, axisLabel) end
            return {
                text = "I found both position controls for " .. tostring(flow.label or "that text")
                    .. ". Say 'open horizontal' for X Offset or 'open vertical' for Y Offset.",
                status = "ambiguous",
            }
        end

        -- A complete command naming another component starts a fresh turn.
        -- Direction words alone are not enough: "lower player frame width"
        -- must never mutate the old text offset merely because it says lower.
        local isContinuation = IsReferentialPendingMovementReply(text)
        local requestedDirection = MovementDirection(text)
        if (requestedDirection and not isContinuation)
            or (LooksLikeFreshPendingTopic(text) and not isContinuation)
        then
            A.ClearPendingFlow()
            return nil
        end

        local direction = requestedDirection
        if not direction then
            if LooksLikeFreshPendingTopic(text)
                and not norm:find("move it", 1, true)
                and not norm:find("move that", 1, true)
                and not norm:find("move this", 1, true)
            then
                A.ClearPendingFlow()
                return nil
            end
            return {
                text = "Sure — which way should I move " .. tostring(flow.label or "that text")
                    .. "?\n1. Up\n2. Down\n3. Left\n4. Right\nYou can include an amount, for example 'down 5', or say 'open horizontal' / 'open vertical'.",
                status = "ambiguous",
            }
        end

        local settingKey = (direction == "left" or direction == "right") and flow.xKey or flow.yKey
        local setting = PendingSetting(settingKey)
        if not setting then
            A.ClearPendingFlow()
            return { text = "I could not reopen that exact position option. Ask me to find the text position again.", status = "failed" }
        end
        local amount = tonumber(tostring(text or ""):match("[%+%-]?%d+%.?%d*")) or tonumber(flow.step) or 10
        amount = math.abs(amount)
        if amount == 0 then
            return { text = "Zero keeps " .. tostring(flow.label or "that text") .. " where it is. Give me another amount or say cancel.", status = "info" }
        end
        local delta = (direction == "left" or direction == "down") and -amount or amount
        A.ClearPendingFlow()
        return A.ExecutePlan({
            kind = "changes",
            changes = { { setting = setting, relativeDelta = delta, direction = direction } },
            label = "Move " .. tostring(flow.label or setting.label or "MSUF text") .. " " .. direction,
            summary = "Moves the exact text position selected in the previous Assistant message.",
            sourceText = "move " .. tostring(flow.noun or flow.label or setting.label or setting.key) .. " " .. direction .. " " .. tostring(amount),
        })
    end

    function A.HandlePendingFlow(text)
        local flow = A.Workflow.PendingFlow()
        if type(flow) ~= "table" then return nil end
        if IsCancel(text) or Normalize(text) == "cancel workflow" then
            local ok, message = A.Workflow.CancelActiveWorkflow()
            return { text = message, status = ok and "applied" or "failed" }
        end
        if flow.kind == "profileCopyDestination" then
            local source = DisplayProfileName(flow.source)
            local dest = OriginalDestination(text, flow.kind)
            if dest == "" then return { text = "What should the destination profile be called? Example: 'call it Raid Backup'. Say 'cancel' or 'never mind' to stop.", status = "confirmation_needed" } end
            A.ClearPendingFlow()
            local action = Registry:GetAction("copy_profile_from_to")
            if not action then return { text = "Open Profiles first so I can copy that profile.", status = "failed" } end
            return A.ExecutePlan({
                kind = "action",
                action = action,
                args = { source = source, name = dest },
                confirmRequired = true,
                label = "Copy profile " .. tostring(source) .. " to " .. tostring(dest),
                summary = "Copies one named profile to a new destination profile.",
            })
        end
        if flow.kind == "profileRenameDestination" then
            local dest = OriginalDestination(text, flow.kind)
            if dest == "" then return { text = "What should the new profile be called? Examples: 'to Raid Renamed' or 'named Raid Renamed'. Say 'cancel' or 'never mind' to stop.", status = "confirmation_needed" } end
            A.ClearPendingFlow()
            local action = Registry:GetAction("rename_profile")
            if not action then return { text = "Open Profiles first so I can rename that profile.", status = "failed" } end
            return A.ExecutePlan({
                kind = "action",
                action = action,
                args = { source = flow.source, name = dest },
                confirmRequired = true,
                label = "Rename profile " .. tostring(flow.source) .. " to " .. tostring(dest),
                summary = "Renames the selected profile.",
            })
        end
        if flow.kind == "settingValue" then return HandleSettingValueFlow(text, flow) end
        if flow.kind == "settingMovement" then return HandleSettingMovementFlow(text, flow) end
        return nil
    end
end
