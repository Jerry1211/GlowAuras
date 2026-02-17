-- GlowAuras.lua
-- GlowAuras (Retail 12.0+)
-- Learns SPELL_ACTIVATION_OVERLAY_GLOW_* spellIDs and lets you configure per-glow alerts.
-- UI rules:
--   - New Glow Aura… popup opens ABOVE main (no overlap)
--   - Choose Sound opens LEFT of main (no overlap) + toggles on 2nd click
--   - Edit Alert opens RIGHT of main (no overlap) + toggles on 2nd click
-- No SetMinResize/SetMaxResize (compat)
-- /ga to open

local ADDON = ...
GlowAurasDB = GlowAurasDB or {}

------------------------------------------------------------
-- LibSharedMedia (optional)
------------------------------------------------------------
local LSM = (LibStub and LibStub("LibSharedMedia-3.0", true)) or nil

------------------------------------------------------------
-- DB
------------------------------------------------------------
local function AuraDefaults()
    return {
        enabled = true,
        spellID = nil, -- learned glow spellID

        message = "PROC!",
        sound   = "Default: Raid Warning",

        showText  = true,
        showIcon  = false,
        playSound = true,

        -- Legacy: older versions used displayMode = "TEXT"/"ICON". Kept for backward compat.
        displayMode = "TEXT",

        -- Icon selection
        iconKind  = "SPELL",    -- "SPELL" | "SPELLNAME" | "FILE" | "PATH"
        iconValue = nil,        -- spellID / spell name / fileID / texture path
        iconSize  = 64,
        iconX     = 0,
        iconY     = 0,

        -- Visuals
        showBackground = true,

        overlayLocked = false,
        overlayPoint  = nil, -- { point, relativePoint, x, y }
        overlayW       = 500,
        overlayH       = 80,

        alertDuration  = 0,       -- seconds (0 = no auto-hide)
        textX          = 0,
        textY          = 0,
        fontSize       = 32,
        textJustify    = "CENTER", -- LEFT / CENTER / RIGHT

        -- When enabled, anchor the text to the icon instead of the overlay.
        textAnchorToIcon = false,
        textPos          = "CENTER", -- CENTER / TOP / BOTTOM / LEFT / RIGHT
        textGap          = 8,
    }
end

local defaults = {
    enabled = true,
    activeAuraKey = nil,

    -- main UI placement
    uiPoint = nil, -- {point, relPoint, x, y}

    auras = {
        ["Black Ox"] = (function()
            local a = AuraDefaults()
            a.spellID = 124682
            a.message = "BLACK OX PROC"
            return a
        end)(),
    }
}

local function DeepCopyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            DeepCopyDefaults(dst[k], v)
        else
            if dst[k] == nil then dst[k] = v end
        end
    end
end

local function InitDB()
    DeepCopyDefaults(GlowAurasDB, defaults)

    if not GlowAurasDB.auras or next(GlowAurasDB.auras) == nil then
        GlowAurasDB.auras = {}
        GlowAurasDB.auras["Black Ox"] = defaults.auras["Black Ox"]
    end

    GlowAurasDB.recentIcons = GlowAurasDB.recentIcons or {}

    if not GlowAurasDB.activeAuraKey or not GlowAurasDB.auras[GlowAurasDB.activeAuraKey] then
        for k in pairs(GlowAurasDB.auras) do
            GlowAurasDB.activeAuraKey = k
            break
        end
    end
end

------------------------------------------------------------
-- Small helpers
------------------------------------------------------------
local function Clamp(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function Trim(s)
    s = tostring(s or "")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Spell icon helper (Retail 12.0+ safe)
local function GetSpellTextureCompat(spellIDOrName)
    if spellIDOrName == nil then return nil end

    local sid = tonumber(spellIDOrName)
    if sid then
        if _G.C_Spell and type(_G.C_Spell.GetSpellTexture) == "function" then
            local ok, tex = pcall(_G.C_Spell.GetSpellTexture, sid)
            if ok and tex then return tex end
        end
        if type(_G.GetSpellInfo) == "function" then
            local ok, name, _, icon = pcall(_G.GetSpellInfo, sid)
            if ok and icon then return icon end
        end
        if type(_G.GetSpellTexture) == "function" then
            local ok, tex = pcall(_G.GetSpellTexture, sid)
            if ok and tex then return tex end
        end
        return nil
    end

    if type(_G.GetSpellInfo) == "function" then
        local ok, name, _, icon = pcall(_G.GetSpellInfo, tostring(spellIDOrName))
        if ok and icon then return icon end
    end

    return nil
end

------------------------------------------------------------
-- Placement helpers (NO OVERLAP)
------------------------------------------------------------
local function PlaceRightOf(mainFrame, childFrame, gap, yOffset)
    if not (mainFrame and childFrame) then return end
    gap = gap or 20
    yOffset = yOffset or 0
    childFrame:ClearAllPoints()
    childFrame:SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", gap, yOffset)
end

local function PlaceLeftOf(mainFrame, childFrame, gap, yOffset)
    if not (mainFrame and childFrame) then return end
    gap = gap or 20
    yOffset = yOffset or 0
    childFrame:ClearAllPoints()
    childFrame:SetPoint("TOPRIGHT", mainFrame, "TOPLEFT", -gap, yOffset)
end

local function PlaceAbove(mainFrame, childFrame, gap, xOffset)
    if not (mainFrame and childFrame) then return end
    gap = gap or 20
    xOffset = xOffset or 0
    childFrame:ClearAllPoints()
    childFrame:SetPoint("BOTTOM", mainFrame, "TOP", xOffset, gap)
end

------------------------------------------------------------
-- Aura access / selection
------------------------------------------------------------
local function EnsureAuraExists(key)
    if not GlowAurasDB.auras[key] then
        GlowAurasDB.auras[key] = AuraDefaults()
        GlowAurasDB.auras[key].message = ("PROC: %s"):format(key)
    end
end

local function ActiveAuraKey()
    return GlowAurasDB.activeAuraKey
end

local function GetAura(key)
    key = key or ActiveAuraKey()
    if not key then return nil end
    EnsureAuraExists(key)
    return GlowAurasDB.auras[key]
end

local function NormalizeAuraDisplay(aura)
    if not aura then return end

    -- Migrate legacy displayMode into showText/showIcon once.
    if aura.showIcon == nil then
        aura.showIcon = (tostring(aura.displayMode or "TEXT"):upper() == "ICON")
    end
    if aura.showText == nil then
        aura.showText = not (tostring(aura.displayMode or "TEXT"):upper() == "ICON")
    end

    -- Keep displayMode in a sane state for older code paths/UI.
    if aura.showIcon and not aura.showText then
        aura.displayMode = "ICON"
    else
        aura.displayMode = "TEXT"
    end

    local p = tostring(aura.textPos or "CENTER"):upper()
    if p ~= "CENTER" and p ~= "TOP" and p ~= "BOTTOM" and p ~= "LEFT" and p ~= "RIGHT" then
        aura.textPos = "CENTER"
    else
        aura.textPos = p
    end
end

local function SortedAuraKeys()
    local t = {}
    for k in pairs(GlowAurasDB.auras or {}) do t[#t+1] = k end
    table.sort(t, function(a,b) return tostring(a):lower() < tostring(b):lower() end)
    return t
end

------------------------------------------------------------
-- spellID -> auraKey mapping
------------------------------------------------------------
local spellToAura = {}

local function RebuildSpellMap()
    wipe(spellToAura)
    for k, aura in pairs(GlowAurasDB.auras or {}) do
        local id = tonumber(aura.spellID)
        if id then
            spellToAura[id] = k
        end
    end
end

------------------------------------------------------------
-- Overlay (shared; settings are per aura)
------------------------------------------------------------
local overlay
local overlayResizeGrip
local hideToken = 0
local currentShownAuraKey = nil

local OVERLAY_MIN_W, OVERLAY_MIN_H = 200, 40
local OVERLAY_MAX_W, OVERLAY_MAX_H = 900, 300

local function ResolveAuraIconTexture(aura)
    if not aura then return "Interface\\Icons\\INV_Misc_QuestionMark" end

    -- Prefer explicit pick
    if aura.iconKind == "SPELL" and aura.iconValue then
        return GetSpellTextureCompat(aura.iconValue) or "Interface\\Icons\\INV_Misc_QuestionMark"
    elseif aura.iconKind == "SPELLNAME" and aura.iconValue then
        return GetSpellTextureCompat(aura.iconValue) or "Interface\\Icons\\INV_Misc_QuestionMark"
    elseif (aura.iconKind == "FILE" or aura.iconKind == "PATH") and aura.iconValue then
        return aura.iconValue
    end

    -- Otherwise use aura spellID icon
    if tonumber(aura.spellID) then
        return GetSpellTextureCompat(aura.spellID) or "Interface\\Icons\\INV_Misc_QuestionMark"
    end

    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function ApplyOverlaySettings(auraKey)
    if not overlay then return end
    local aura = GetAura(auraKey)
    if not aura then return end
    NormalizeAuraDisplay(aura)

    aura.overlayW = Clamp(aura.overlayW, OVERLAY_MIN_W, OVERLAY_MAX_W)
    aura.overlayH = Clamp(aura.overlayH, OVERLAY_MIN_H, OVERLAY_MAX_H)
    overlay:SetSize(aura.overlayW, aura.overlayH)

    if overlay.bg then
        if aura.showBackground then overlay.bg:Show() else overlay.bg:Hide() end
    end

    -- Text placement/settings
    overlay.text:ClearAllPoints()
    local tx = Clamp(aura.textX, -2000, 2000)
    local ty = Clamp(aura.textY, -2000, 2000)

    local anchorToIcon = (aura.textAnchorToIcon and aura.showIcon and overlay.icon)
    if anchorToIcon then
        local gap = Clamp(aura.textGap, 0, 200)
        local pos = tostring(aura.textPos or "CENTER"):upper()
        if pos == "TOP" then
            overlay.text:SetPoint("BOTTOM", overlay.icon, "TOP", tx, ty + gap)
        elseif pos == "BOTTOM" then
            overlay.text:SetPoint("TOP", overlay.icon, "BOTTOM", tx, ty - gap)
        elseif pos == "LEFT" then
            overlay.text:SetPoint("RIGHT", overlay.icon, "LEFT", tx - gap, ty)
        elseif pos == "RIGHT" then
            overlay.text:SetPoint("LEFT", overlay.icon, "RIGHT", tx + gap, ty)
        else
            overlay.text:SetPoint("CENTER", overlay.icon, "CENTER", tx, ty)
        end
    else
        overlay.text:SetPoint("CENTER", overlay, "CENTER", tx, ty)
    end

    local j = tostring(aura.textJustify or "CENTER"):upper()
    if j ~= "LEFT" and j ~= "CENTER" and j ~= "RIGHT" then j = "CENTER" end
    overlay.text:SetJustifyH(j)

    local fontPath = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local size = Clamp(aura.fontSize, 8, 96)
    overlay.text:SetFont(fontPath, size, "OUTLINE")

    -- Icon placement/settings
    if overlay.icon then
        overlay.icon:ClearAllPoints()
        overlay.icon:SetPoint("CENTER", overlay, "CENTER",
            Clamp(aura.iconX, -2000, 2000),
            Clamp(aura.iconY, -2000, 2000)
        )
        local isz = Clamp(aura.iconSize, 12, 200)
        overlay.icon:SetSize(isz, isz)
    end

    if overlayResizeGrip then
        overlayResizeGrip:SetShown(not aura.overlayLocked)
    end
end

local function AnchorOverlayForAura(auraKey)
    local aura = GetAura(auraKey)
    if not aura or not overlay then return end

    overlay:ClearAllPoints()
    if type(aura.overlayPoint) == "table" and aura.overlayPoint[1] then
        overlay:SetPoint(
            aura.overlayPoint[1],
            UIParent,
            aura.overlayPoint[2] or "CENTER",
            aura.overlayPoint[3] or 0,
            aura.overlayPoint[4] or 180
        )
    else
        overlay:SetPoint("CENTER", 0, 180)
    end
end

local function EnsureOverlay(auraKey)
    if overlay then return end

    overlay = CreateFrame("Frame", "GlowAuras_Overlay", UIParent, "BackdropTemplate")
    overlay:SetFrameStrata("DIALOG")
    overlay:SetClampedToScreen(true)

    overlay.bg = overlay:CreateTexture(nil, "BACKGROUND")
    overlay.bg:SetAllPoints()
    overlay.bg:SetColorTexture(0, 0, 0, 0.35)

    overlay.text = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    overlay.text:SetPoint("CENTER")

    overlay.icon = overlay:CreateTexture(nil, "OVERLAY")
    overlay.icon:SetPoint("CENTER")
    overlay.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    overlay.icon:Hide()

    -- Move (only when unlocked for current aura)
    overlay:SetMovable(true)
    overlay:EnableMouse(true)
    overlay:RegisterForDrag("LeftButton")
    overlay:SetScript("OnDragStart", function(self)
        local aura = GetAura(auraKey)
        if not aura or aura.overlayLocked then return end
        self:StartMoving()
    end)
    overlay:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local aura = GetAura(auraKey)
        if not aura or aura.overlayLocked then return end

        local p, _, rp, x, y = self:GetPoint(1)
        aura.overlayPoint = { p or "CENTER", rp or "CENTER", x or 0, y or 0 }
    end)

    -- Resize (only when unlocked)
    overlay:SetResizable(true)
    overlay:SetScript("OnSizeChanged", function(self, w, h)
        if not self._resizing then return end
        local aura = GetAura(auraKey)
        if not aura then return end

        aura.overlayW = Clamp(w, OVERLAY_MIN_W, OVERLAY_MAX_W)
        aura.overlayH = Clamp(h, OVERLAY_MIN_H, OVERLAY_MAX_H)
        ApplyOverlaySettings(auraKey)

        if _G.GA_EditorFrame and _G.GA_EditorFrame:IsShown() and _G.GA_EditorFrame.SyncSliders then
            _G.GA_EditorFrame:SyncSliders()
        end
    end)

    overlayResizeGrip = CreateFrame("Button", nil, overlay)
    overlayResizeGrip:SetSize(16, 16)
    overlayResizeGrip:SetPoint("BOTTOMRIGHT", -2, 2)
    overlayResizeGrip:EnableMouse(true)

    local gripTex = overlayResizeGrip:CreateTexture(nil, "ARTWORK")
    gripTex:SetAllPoints()
    gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    overlayResizeGrip:SetNormalTexture(gripTex)

    overlayResizeGrip:SetScript("OnMouseDown", function()
        local aura = GetAura(auraKey)
        if not aura or aura.overlayLocked then return end
        overlay._resizing = true
        overlay:StartSizing("BOTTOMRIGHT")
    end)
    overlayResizeGrip:SetScript("OnMouseUp", function()
        overlay:StopMovingOrSizing()
        overlay._resizing = false
        local aura = GetAura(auraKey)
        if not aura or aura.overlayLocked then return end
        local w, h = overlay:GetSize()
        aura.overlayW = Clamp(w, OVERLAY_MIN_W, OVERLAY_MAX_W)
        aura.overlayH = Clamp(h, OVERLAY_MIN_H, OVERLAY_MAX_H)
        ApplyOverlaySettings(auraKey)
    end)

    overlay:Hide()
end

------------------------------------------------------------
-- Sound playback (LSM only + built-in defaults)
------------------------------------------------------------
local function PlayConfiguredSound(auraKey)
    local aura = GetAura(auraKey)
    if not aura or not aura.playSound then return end

    local choice = tostring(aura.sound or "")

    -- Built-in defaults (no LSM required)
    if choice == "Default: Raid Warning" then
        PlaySound(SOUNDKIT.RAID_WARNING, "Master"); return
    elseif choice == "Default: Ready Check" then
        PlaySound(SOUNDKIT.READY_CHECK, "Master"); return
    elseif choice == "Default: Alarm Clock Warning 2" then
        PlaySound(SOUNDKIT.ALARM_CLOCK_WARNING_2, "Master"); return
    elseif choice == "Default: Tell Message" then
        PlaySound(SOUNDKIT.TELL_MESSAGE, "Master"); return
    elseif choice == "Default: UI Error" then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON, "Master"); return
    elseif choice == "Default: Map Ping" then
        PlaySound(SOUNDKIT.MAP_PING, "Master"); return
    end

    -- LibSharedMedia selection
    if LSM then
        local path = LSM:Fetch("sound", choice, true)
        if path then
            PlaySoundFile(path, "Master")
            return
        end
    end

    -- Fallback
    PlaySound(SOUNDKIT.RAID_WARNING, "Master")
end

local function HideAlert()
    if overlay then overlay:Hide() end
    currentShownAuraKey = nil
end

local function ShowAlert(auraKey, forcePreview)
    local aura = GetAura(auraKey)
    if not aura then return end
    NormalizeAuraDisplay(aura)

    EnsureOverlay(auraKey)
    AnchorOverlayForAura(auraKey)
    ApplyOverlaySettings(auraKey)

    local doSound = aura.playSound

    if not forcePreview and not doSound and (not aura.showText) and (not aura.showIcon) then return end

    currentShownAuraKey = auraKey

    local wantIcon = aura.showIcon or false
    local wantText = aura.showText or false
    if forcePreview then
        wantIcon = wantIcon or (not wantText)
        wantText = wantText or (not wantIcon)
    end

    if wantIcon then
        local tex = ResolveAuraIconTexture(aura)
        overlay.icon:SetTexture(tex)
        overlay.icon:Show()
    else
        overlay.icon:Hide()
    end

    if wantText then
        overlay.text:SetText(tostring(aura.message or "PROC!"))
        overlay.text:Show()
    else
        overlay.text:Hide()
    end

    if wantIcon or wantText then
        overlay:Show()
    else
        overlay:Hide()
    end

    if doSound and not forcePreview then
        PlayConfiguredSound(auraKey)
    end

    local dur = tonumber(aura.alertDuration) or 0
    if dur > 0 then
        hideToken = hideToken + 1
        local myToken = hideToken
        C_Timer.After(dur, function()
            if myToken ~= hideToken then return end
            if overlay and overlay:IsShown() and currentShownAuraKey == auraKey then
                HideAlert()
            end
        end)
    end
end

------------------------------------------------------------
-- Learn mode (captures next glow show)
------------------------------------------------------------
local learning = { active = false, auraKey = nil }

local function StartLearning(auraKey)
    learning.active = true
    learning.auraKey = auraKey
end

local function StopLearning()
    learning.active = false
    learning.auraKey = nil
end

------------------------------------------------------------
-- UI helpers
------------------------------------------------------------
local UI = {}
_G.GA_UI = UI

local PAD = 14

local function MakeLabel(parent, text, x, y, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function MakeButton(parent, text, w, h, x, y)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    return b
end

local function MakeEditBox(parent, w, x, y)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(w, 30)
    eb:SetPoint("TOPLEFT", x, y)
    eb:SetAutoFocus(false)
    eb:SetTextInsets(10, 10, 0, 0)
    return eb
end

local function MakeSlider(parent, name, label, minV, maxV, step, x, y, w)
    local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", x, y)
    s:SetWidth(w or 260)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    _G[s:GetName() .. "Text"]:SetText(label)
    _G[s:GetName() .. "Low"]:SetText(tostring(minV))
    _G[s:GetName() .. "High"]:SetText(tostring(maxV))
    return s
end

------------------------------------------------------------
-- Sound Picker (LEFT)
------------------------------------------------------------
local function BuildSoundList()
    local list = {}
    local seen = {}

    local function add(name)
        if not name or name == "" then return end
        if not seen[name] then
            seen[name] = true
            list[#list+1] = name
        end
    end

    add("Default: Raid Warning")
    add("Default: Ready Check")
    add("Default: Alarm Clock Warning 2")
    add("Default: Tell Message")
    add("Default: UI Error")
    add("Default: Map Ping")

    if LSM then
        local l = LSM:List("sound")
        for _, s in ipairs(l) do
            add(s)
        end
    else
        add("(LibSharedMedia-3.0 not found)")
    end

    table.sort(list, function(a, b) return tostring(a) < tostring(b) end)
    return list
end

local function RefreshSelectedSoundLabels()
    local aura = GetAura()
    if not aura then return end

    if UI.mainSoundLabel then
        UI.mainSoundLabel:SetText("Selected: " .. tostring(aura.sound))
    end
    if UI.soundValueLabel then
        UI.soundValueLabel:SetText("Selected: " .. tostring(aura.sound))
    end
end

local function EnsureSoundPicker()
    if UI.soundPicker then return end
    if not UI.frame then return end

    local sp = CreateFrame("Frame", "GA_SoundPicker", UIParent, "BackdropTemplate")
    sp:SetSize(430, 350)
    sp:SetFrameStrata("DIALOG")
    sp:SetClampedToScreen(true)

    sp:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    sp:SetBackdropColor(0.04, 0.05, 0.08, 1.0)
    sp:SetBackdropBorderColor(0.25, 0.3, 0.4, 1.0)

    sp.bgSolid = sp:CreateTexture(nil, "BACKGROUND", nil, -1)
    sp.bgSolid:SetAllPoints()
    sp.bgSolid:SetColorTexture(0.04, 0.05, 0.08, 1.0)

    sp:SetMovable(true)
    sp:EnableMouse(true)

    local drag = CreateFrame("Frame", nil, sp)
    drag:SetPoint("TOPLEFT", 6, -6)
    drag:SetPoint("TOPRIGHT", -40, -6)
    drag:SetHeight(26)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() sp:StartMoving() end)
    drag:SetScript("OnDragStop",  function() sp:StopMovingOrSizing() end)

    sp:Hide()
    UI.soundPicker = sp

    MakeLabel(sp, "Select Sound", 12, -12, "GameFontNormalLarge")

    local close = MakeButton(sp, "X", 26, 22, 430 - 12 - 26, -10)
    close:SetFrameLevel(sp:GetFrameLevel() + 10)
    close:SetScript("OnClick", function() sp:Hide() end)

    MakeLabel(sp, "Search", 12, -48, "GameFontNormal")
    local search = MakeEditBox(sp, 260, 80, -40)
    search:SetText("")
    UI.soundSearch = search

    local preview = MakeButton(sp, "Preview", 90, 24, 430 - 12 - 90, -42)
    preview:SetScript("OnClick", function()
        local k = ActiveAuraKey()
        if not k then return end
        local aura = GetAura(k)
        if not aura then return end
        local was = aura.playSound
        aura.playSound = true
        PlayConfiguredSound(k)
        aura.playSound = was
    end)

    local listFrame = CreateFrame("Frame", nil, sp, "BackdropTemplate")
    listFrame:SetSize(360, 245)
    listFrame:SetPoint("TOPLEFT", 12, -82)
    listFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    listFrame:SetBackdropColor(0, 0, 0, 0.25)
    listFrame:SetBackdropBorderColor(0.2, 0.25, 0.35, 1.0)

    local scroll = CreateFrame("ScrollFrame", "GA_SoundScrollFrame", sp, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -26, 2)

    local ROW_H = 20
    local NUM_ROWS = 11
    UI.soundRows = {}

    for i = 1, NUM_ROWS do
        local row = CreateFrame("Button", nil, listFrame)
        row:SetSize(330, ROW_H)
        row:SetPoint("TOPLEFT", 8, -(i - 1) * ROW_H - 6)
        row:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight")

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 4, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWidth(320)

        UI.soundRows[i] = row
    end

    UI.allSounds = BuildSoundList()
    UI.filteredSounds = UI.allSounds

    local function ApplyFilter()
        local q = (search:GetText() or ""):lower()
        if q == "" then
            UI.filteredSounds = UI.allSounds
        else
            local out = {}
            for _, name in ipairs(UI.allSounds) do
                if tostring(name):lower():find(q, 1, true) then
                    out[#out + 1] = name
                end
            end
            UI.filteredSounds = out
        end
        FauxScrollFrame_SetOffset(scroll, 0)
    end

    local function UpdateList()
        local aura = GetAura()
        if not aura then return end

        local items = UI.filteredSounds
        local offset = FauxScrollFrame_GetOffset(scroll) or 0
        local total = #items

        FauxScrollFrame_Update(scroll, total, NUM_ROWS, ROW_H)

        for i = 1, NUM_ROWS do
            local idx = offset + i
            local row = UI.soundRows[i]
            local name = items[idx]

            if name then
                row:Show()
                row.soundName = name
                row.text:SetText(name)

                if name == aura.sound then
                    row.text:SetTextColor(0.2, 1.0, 0.2)
                else
                    row.text:SetTextColor(0.85, 0.85, 0.85)
                end

                row:SetScript("OnClick", function()
                    local a = GetAura()
                    if not a then return end
                    a.sound = row.soundName
                    RefreshSelectedSoundLabels()
                    UpdateList()
                end)
            else
                row:Hide()
                row.soundName = nil
            end
        end
    end

    scroll:SetScript("OnVerticalScroll", function(_, delta)
        FauxScrollFrame_OnVerticalScroll(scroll, delta, ROW_H, UpdateList)
    end)

    search:SetScript("OnTextChanged", function()
        ApplyFilter()
        UpdateList()
    end)

    local ok = MakeButton(sp, "OK", 90, 24, 12, -335)
    ok:SetScript("OnClick", function() sp:Hide() end)

    local selectedLabel = sp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    selectedLabel:SetPoint("LEFT", ok, "RIGHT", 12, 0)
    selectedLabel:SetWidth(300)
    selectedLabel:SetJustifyH("LEFT")
    UI.soundValueLabel = selectedLabel

    UI.SoundPicker_UpdateList = UpdateList
    UI.SoundPicker_ApplyFilter = ApplyFilter
end

------------------------------------------------------------
-- Alert Editor (RIGHT)
------------------------------------------------------------
local EDIT_MIN_W, EDIT_MIN_H = 460, 320
local EDIT_MAX_W, EDIT_MAX_H = 900, 600

local function EnsureAlertEditor()
    if UI.alertEditor then return end

    local ed = CreateFrame("Frame", "GA_EditorFrame", UIParent, "BackdropTemplate")
    ed:SetSize(520, 360)
    ed:SetFrameStrata("DIALOG")
    ed:SetMovable(true)
    ed:SetClampedToScreen(true)
    ed:EnableMouse(true)
    ed:RegisterForDrag("LeftButton")
    ed:SetScript("OnDragStart", ed.StartMoving)
    ed:SetScript("OnDragStop", ed.StopMovingOrSizing)

    ed:SetResizable(true)
    ed:SetScript("OnSizeChanged", function(self, w, h)
        if not self._resizing then return end
        w = Clamp(w, EDIT_MIN_W, EDIT_MAX_W)
        h = Clamp(h, EDIT_MIN_H, EDIT_MAX_H)
        if w ~= self:GetWidth() or h ~= self:GetHeight() then
            self:SetSize(w, h)
        end
    end)

    ed:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    ed:SetBackdropColor(0.06, 0.08, 0.12, 1.0)
    ed:SetBackdropBorderColor(0.25, 0.3, 0.4, 1.0)
    ed:Hide()
    UI.alertEditor = ed

    MakeLabel(ed, "Edit Alert", PAD, -PAD, "GameFontNormalLarge")

    local close = MakeButton(ed, "X", 26, 22, 520 - PAD - 26, -PAD)
    close:SetScript("OnClick", function()
        ed:Hide()
        if overlayResizeGrip then overlayResizeGrip:Hide() end
        HideAlert()
    end)

    MakeLabel(ed, "Alert Text", PAD, -50)
    local msg = MakeEditBox(ed, 330, PAD, -78)
    ed.msgBox = msg
    msg:SetScript("OnEnterPressed", function(box)
        local aura = GetAura()
        if not aura then return end
        aura.message = box:GetText()
        box:ClearFocus()
        if overlay and overlay:IsShown() and (aura.showText or false) then
            overlay.text:SetText(tostring(aura.message or "PROC!"))
        end
        if UI.msgBox and UI.frame and UI.frame:IsShown() then
            UI.msgBox:SetText(tostring(aura.message or "PROC!"))
        end
    end)

    MakeLabel(ed, "Text Align", PAD + 350, -50)
    local dd = CreateFrame("Frame", "GA_TextAlignDropDown", ed, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", PAD + 330, -66)
    UIDropDownMenu_SetWidth(dd, 120)
    ed.alignDD = dd

    local function AlignLabel(j)
        if j == "LEFT" then return "Left" end
        if j == "RIGHT" then return "Right" end
        return "Center"
    end

    local function SetAlign(j)
        local aura = GetAura()
        if not aura then return end
        aura.textJustify = j
        UIDropDownMenu_SetText(dd, AlignLabel(j))
        ApplyOverlaySettings(ActiveAuraKey())
    end

    UIDropDownMenu_Initialize(dd, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        local aura = GetAura()
        local cur = aura and tostring(aura.textJustify or "CENTER"):upper() or "CENTER"
        for _, j in ipairs({ "LEFT", "CENTER", "RIGHT" }) do
            info.text = AlignLabel(j)
            info.checked = (cur == j)
            info.func = function() SetAlign(j) end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local cbAnchor = CreateFrame("CheckButton", nil, ed, "UICheckButtonTemplate")
    cbAnchor:SetPoint("TOPLEFT", PAD, -110)
    cbAnchor.text:SetText("Anchor text to icon")
    cbAnchor:SetScript("OnClick", function(btn)
        local aura = GetAura(); if not aura then return end
        aura.textAnchorToIcon = btn:GetChecked() and true or false
        ApplyOverlaySettings(ActiveAuraKey())
        ShowAlert(ActiveAuraKey(), true)
    end)
    ed.cbAnchor = cbAnchor

    MakeLabel(ed, "Text Position", PAD + 210, -110)
    local posDD = CreateFrame("Frame", "GA_TextPosDropDown", ed, "UIDropDownMenuTemplate")
    posDD:SetPoint("TOPLEFT", PAD + 190, -126)
    UIDropDownMenu_SetWidth(posDD, 120)
    ed.posDD = posDD

    local function PosLabel(p)
        if p == "TOP" then return "Above" end
        if p == "BOTTOM" then return "Below" end
        if p == "LEFT" then return "Left" end
        if p == "RIGHT" then return "Right" end
        return "Center"
    end

    local function SetPos(p)
        local aura = GetAura(); if not aura then return end
        aura.textPos = p
        UIDropDownMenu_SetText(posDD, PosLabel(p))
        ApplyOverlaySettings(ActiveAuraKey())
        ShowAlert(ActiveAuraKey(), true)
    end

    UIDropDownMenu_Initialize(posDD, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        local aura = GetAura()
        local cur = aura and tostring(aura.textPos or "CENTER"):upper() or "CENTER"
        for _, p in ipairs({ "CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            info.text = PosLabel(p)
            info.checked = (cur == p)
            info.func = function() SetPos(p) end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local x0, y0 = PAD, -165
    local col2 = PAD + 270

    ed.wSlider        = MakeSlider(ed, "GA_AlertWidthSlider",   "Width",        OVERLAY_MIN_W, OVERLAY_MAX_W, 5,   x0,   y0,       240)
    ed.hSlider        = MakeSlider(ed, "GA_AlertHeightSlider",  "Height",       OVERLAY_MIN_H, OVERLAY_MAX_H, 2,   x0,   y0 - 55,  240)
    ed.dSlider        = MakeSlider(ed, "GA_AlertLenSlider",     "Length (sec)", 0,             10,            0.5, x0,   y0 - 110, 240)
    ed.iconSizeSlider = MakeSlider(ed, "GA_IconSizeSlider",     "Icon Size",    12,            200,           1,   x0,   y0 - 165, 240)

    ed.txSlider = MakeSlider(ed, "GA_TextXSlider",        "Text X",       -200,          200,           1,   col2, y0,       240)
    ed.tySlider = MakeSlider(ed, "GA_TextYSlider",        "Text Y",       -100,          100,           1,   col2, y0 - 55,  240)
    ed.fsSlider = MakeSlider(ed, "GA_FontSizeSlider",     "Font Size",    12,            64,            1,   col2, y0 - 110, 240)
    ed.gapSlider = MakeSlider(ed, "GA_TextGapSlider",     "Text Gap",     0,             50,            1,   col2, y0 - 165, 240)

    local function HookSlider(slider, getter, setter)
        slider:SetScript("OnValueChanged", function(_, value)
            setter(value)
            ApplyOverlaySettings(ActiveAuraKey())
            local aura = GetAura()
            if overlay and overlay:IsShown() and aura and (aura.showText or false) then
                overlay.text:SetText(tostring(aura.message or "PROC!"))
            end
        end)
        slider:SetScript("OnShow", function(self)
            self:SetValue(getter())
        end)
    end

    HookSlider(ed.wSlider,
        function()
            local aura = GetAura()
            return aura and Clamp(aura.overlayW, OVERLAY_MIN_W, OVERLAY_MAX_W) or OVERLAY_MIN_W
        end,
        function(v)
            local aura = GetAura(); if not aura then return end
            aura.overlayW = math.floor(v + 0.5)
        end
    )

    HookSlider(ed.hSlider,
        function()
            local aura = GetAura()
            return aura and Clamp(aura.overlayH, OVERLAY_MIN_H, OVERLAY_MAX_H) or OVERLAY_MIN_H
        end,
        function(v)
            local aura = GetAura(); if not aura then return end
            aura.overlayH = math.floor(v + 0.5)
        end
    )

    HookSlider(ed.dSlider,
        function()
            local aura = GetAura()
            return aura and (tonumber(aura.alertDuration) or 0) or 0
        end,
        function(v)
            local aura = GetAura(); if not aura then return end
            aura.alertDuration = v
        end
    )

    HookSlider(ed.iconSizeSlider,
        function()
            local aura = GetAura()
            return aura and Clamp(aura.iconSize, 12, 200) or 64
        end,
        function(v)
            local aura = GetAura(); if not aura then return end
            aura.iconSize = math.floor(v + 0.5)
        end
    )

    HookSlider(ed.txSlider,
        function()
            local aura = GetAura()
            return aura and (tonumber(aura.textX) or 0) or 0
        end,
        function(v)
            local aura = GetAura(); if not aura then return end
            aura.textX = math.floor(v + 0.5)
        end
    )

    HookSlider(ed.tySlider,
        function()
            local aura = GetAura()
            return aura and (tonumber(aura.textY) or 0) or 0
        end,
        function(v)
            local aura = GetAura(); if not aura then return end
            aura.textY = math.floor(v + 0.5)
        end
    )

    HookSlider(ed.fsSlider,
        function()
            local aura = GetAura()
            return aura and Clamp(aura.fontSize, 12, 64) or 32
        end,
        function(v)
            local aura = GetAura(); if not aura then return end
            aura.fontSize = math.floor(v + 0.5)
        end
    )

    HookSlider(ed.gapSlider,
        function()
            local aura = GetAura()
            return aura and Clamp(aura.textGap, 0, 50) or 8
        end,
        function(v)
            local aura = GetAura(); if not aura then return end
            aura.textGap = math.floor(v + 0.5)
        end
    )

    function ed:SyncSliders()
        local aura = GetAura()
        if not aura then return end
        NormalizeAuraDisplay(aura)
        self.wSlider:SetValue(Clamp(aura.overlayW, OVERLAY_MIN_W, OVERLAY_MAX_W))
        self.hSlider:SetValue(Clamp(aura.overlayH, OVERLAY_MIN_H, OVERLAY_MAX_H))
        self.dSlider:SetValue(tonumber(aura.alertDuration) or 0)
        self.iconSizeSlider:SetValue(Clamp(aura.iconSize, 12, 200))
        self.txSlider:SetValue(tonumber(aura.textX) or 0)
        self.tySlider:SetValue(tonumber(aura.textY) or 0)
        self.fsSlider:SetValue(Clamp(aura.fontSize, 12, 64))
        UIDropDownMenu_SetText(self.alignDD, AlignLabel(tostring(aura.textJustify or "CENTER"):upper()))
        UIDropDownMenu_SetText(self.posDD, PosLabel(tostring(aura.textPos or "CENTER"):upper()))
        self.cbAnchor:SetChecked(aura.textAnchorToIcon and true or false)
        self.gapSlider:SetValue(Clamp(aura.textGap, 0, 50))
        self.msgBox:SetText(tostring(aura.message or "PROC!"))
    end

    local grip = CreateFrame("Button", nil, ed)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:EnableMouse(true)
    local gtex = grip:CreateTexture(nil, "ARTWORK")
    gtex:SetAllPoints()
    gtex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetNormalTexture(gtex)
    grip:SetScript("OnMouseDown", function()
        ed._resizing = true
        ed:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        ed:StopMovingOrSizing()
        ed._resizing = false
    end)

    ed:SetScript("OnShow", function(self)
        local k = ActiveAuraKey()
        if not k then return end
        EnsureOverlay(k)
        AnchorOverlayForAura(k)
        ApplyOverlaySettings(k)
        self:SyncSliders()
        ShowAlert(k, true) -- preview
        local aura = GetAura(k)
        if overlayResizeGrip then
            overlayResizeGrip:SetShown(aura and (not aura.overlayLocked) or false)
        end
    end)

    ed:SetScript("OnHide", function()
        if overlayResizeGrip then overlayResizeGrip:Hide() end
        HideAlert()
    end)
end

------------------------------------------------------------
-- New Aura Popup (ABOVE)
------------------------------------------------------------
local function EnsureNewAuraPopup()
    if UI.newAuraPopup then return end

    local p = CreateFrame("Frame", "GA_NewAuraPopup", UIParent, "BackdropTemplate")
    p:SetSize(360, 170)
    p:SetFrameStrata("DIALOG")
    p:SetClampedToScreen(true)
    p:SetPoint("CENTER", 0, 120)
    p:SetMovable(true)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop",  p.StopMovingOrSizing)

    p:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    p:SetBackdropColor(0.06, 0.08, 0.12, 1.0)
    p:SetBackdropBorderColor(0.25, 0.3, 0.4, 1.0)
    p:Hide()
    UI.newAuraPopup = p

    MakeLabel(p, "New Glow Aura", PAD, -PAD, "GameFontNormalLarge")

    local close = MakeButton(p, "X", 26, 22, 360 - PAD - 26, -PAD)
    close:SetScript("OnClick", function()
        StopLearning()
        p:Hide()
    end)

    MakeLabel(p, "Name", PAD, -48)
    local nameBox = MakeEditBox(p, 220, PAD, -74)
    nameBox:SetText("")
    p.nameBox = nameBox

    local spellLabel = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spellLabel:SetPoint("TOPLEFT", PAD, -112)
    spellLabel:SetText("GlowID: (not learned)")
    p.spellLabel = spellLabel

    local learnBtn = MakeButton(p, "Learn", 90, 26, PAD + 240, -74)
    learnBtn:SetScript("OnClick", function()
        local n = Trim(nameBox:GetText())
        if n == "" then
            print("|cffffcc00[GlowAuras]|r Enter a name first.")
            return
        end

        EnsureAuraExists(n)
        StartLearning(n)
        p.spellLabel:SetText("GlowID: learning... trigger the proc now")
    end)

    local saveBtn = MakeButton(p, "Save", 90, 26, PAD, -138)
    saveBtn:SetScript("OnClick", function()
        local n = Trim(nameBox:GetText())
        if n == "" then
            print("|cffffcc00[GlowAuras]|r Name cannot be blank.")
            return
        end

        EnsureAuraExists(n)
        local aura = GlowAurasDB.auras[n]
        if not tonumber(aura.spellID) then
            print("|cffffcc00[GlowAuras]|r You must Learn a GlowID before saving.")
            return
        end

        GlowAurasDB.activeAuraKey = n
        RebuildSpellMap()
        StopLearning()
        p:Hide()

        if UI.Dropdown_Refresh then UI:Dropdown_Refresh() end
        if UI.Refresh then UI:Refresh() end
    end)

    local cancelBtn = MakeButton(p, "Cancel", 90, 26, PAD + 100, -138)
    cancelBtn:SetScript("OnClick", function()
        StopLearning()
        p:Hide()
    end)

    p:SetScript("OnShow", function()
        StopLearning()
        nameBox:SetText("")
        p.spellLabel:SetText("GlowID: (not learned)")
    end)
end

local function ToggleNewAuraPopup(show)
    EnsureNewAuraPopup()
    local p = UI.newAuraPopup
    if show == nil then show = not p:IsShown() end

    if show then
        p:Show()
        if UI.frame and UI.frame:IsShown() then
            PlaceAbove(UI.frame, p, 20, 0)
        end
    else
        StopLearning()
        p:Hide()
    end
end

------------------------------------------------------------
-- Icon Picker (ABOVE) - provided by GlowAuras_IconPicker.lua
------------------------------------------------------------
local function EnsureIconPicker()
    if UI.iconPickerEnsured then return end
    UI.iconPickerEnsured = true

    if not GA_IconPicker or not GA_IconPicker.Ensure then
        print("|cffff4444[GlowAuras]|r Icon picker not loaded. Check your .toc order.")
        return
    end

    GA_IconPicker:Ensure(
        UI.frame,
        function() return GetAura() end,
        function(kind, value, label, tex)
            local aura = GetAura()
            if not aura then return end

            aura.iconKind  = kind
            aura.iconValue = value
            aura.iconTex   = tex
            aura.iconLabel = label

            -- auto-enable icon
            aura.showIcon = true
            if UI.cbIcon then UI.cbIcon:SetChecked(true) end
            if UI.iconPreviewTex then
                UI.iconPreviewTex:SetTexture(ResolveAuraIconTexture(aura))
            end
            if overlay and overlay:IsShown() then
                ShowAlert(ActiveAuraKey(), true)
            end
        end,
        PlaceAbove
    )
end

------------------------------------------------------------
-- Main Config UI
------------------------------------------------------------
local function SetActiveAuraKey(k)
    if k and GlowAurasDB.auras[k] then
        GlowAurasDB.activeAuraKey = k
        if UI.Refresh then UI:Refresh() end

        if UI.soundPicker and UI.soundPicker:IsShown() and UI.frame and UI.frame:IsShown() then
            PlaceLeftOf(UI.frame, UI.soundPicker, 20, 0)
            if UI.SoundPicker_UpdateList then UI.SoundPicker_UpdateList() end
        end
        if UI.alertEditor and UI.alertEditor:IsShown() and UI.frame and UI.frame:IsShown() then
            PlaceRightOf(UI.frame, UI.alertEditor, 20, 0)
            if UI.alertEditor.SyncSliders then UI.alertEditor:SyncSliders() end
        end
        if UI.newAuraPopup and UI.newAuraPopup:IsShown() and UI.frame and UI.frame:IsShown() then
            PlaceAbove(UI.frame, UI.newAuraPopup, 20, 0)
        end
        if GA_IconPicker and GA_IconPicker.frame and GA_IconPicker.frame:IsShown() then
            PlaceAbove(UI.frame, GA_IconPicker.frame, 20, 0)
        end
    end
end

local function EnsureConfig()
    if UI.frame then return end

    local frame = CreateFrame("Frame", "GA_Config", UIParent, "BackdropTemplate")
    frame:SetSize(560, 520)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    if type(GlowAurasDB.uiPoint) == "table" and GlowAurasDB.uiPoint[1] then
        frame:SetPoint(GlowAurasDB.uiPoint[1], UIParent, GlowAurasDB.uiPoint[2] or "CENTER", GlowAurasDB.uiPoint[3] or 0, GlowAurasDB.uiPoint[4] or 0)
    else
        frame:SetPoint("CENTER")
    end

    frame:SetScript("OnHide", function()
        local p, _, rp, x, y = frame:GetPoint(1)
        GlowAurasDB.uiPoint = { p or "CENTER", rp or "CENTER", x or 0, y or 0 }
    end)

    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.06, 0.08, 0.12, 0.95)
    frame:SetBackdropBorderColor(0.25, 0.3, 0.4, 0.9)
    frame:Hide()
    UI.frame = frame

    MakeLabel(frame, "GlowAuras", PAD, -PAD, "GameFontNormalLarge")

    local close = MakeButton(frame, "X", 26, 22, 560 - PAD - 26, -PAD)
    close:SetScript("OnClick", function()
        frame:Hide()
        HideAlert()
        StopLearning()
        if UI.newAuraPopup and UI.newAuraPopup:IsShown() then UI.newAuraPopup:Hide() end
        if UI.alertEditor and UI.alertEditor:IsShown() then UI.alertEditor:Hide() end
        if UI.soundPicker and UI.soundPicker:IsShown() then UI.soundPicker:Hide() end
        if GA_IconPicker and GA_IconPicker.frame and GA_IconPicker.frame:IsShown() then GA_IconPicker.frame:Hide() end
    end)

    -- Global enable
    local cbGlobal = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    cbGlobal:SetPoint("TOPLEFT", PAD, -48)
    cbGlobal.text:SetText("Enable addon")
    cbGlobal:SetScript("OnClick", function(btn) GlowAurasDB.enabled = btn:GetChecked() and true or false end)
    UI.cbGlobal = cbGlobal

    -- Aura dropdown
    MakeLabel(frame, "Glow Aura", PAD, -86)
    local dd = CreateFrame("Frame", "GA_AuraDropDown", frame, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", PAD - 16, -104)
    UIDropDownMenu_SetWidth(dd, 260)
    UI.dd = dd

    local function DropdownInit(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, k in ipairs(SortedAuraKeys()) do
            info.text = k
            info.checked = (k == ActiveAuraKey())
            info.func = function() SetActiveAuraKey(k) end
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(dd, DropdownInit)
    function UI:Dropdown_Refresh()
        UIDropDownMenu_Initialize(dd, DropdownInit)
        UIDropDownMenu_SetText(dd, ActiveAuraKey() and tostring(ActiveAuraKey()) or "(none)")
    end

    -- New aura (ABOVE)
    local newBtn = MakeButton(frame, "New Glow Aura…", 150, 26, PAD + 290, -106)
    newBtn:SetScript("OnClick", function() ToggleNewAuraPopup(true) end)

    -- Delete aura
    local deleteBtn = MakeButton(frame, "Delete", 90, 26, PAD + 450, -106)
    deleteBtn:SetScript("OnClick", function()
        local key = ActiveAuraKey()
        if not key then return end

        local count = 0
        for _ in pairs(GlowAurasDB.auras or {}) do count = count + 1 end
        if count <= 1 then
            print("|cffff4444[GlowAuras]|r You must have at least one aura.")
            return
        end

        GlowAurasDB.auras[key] = nil
        RebuildSpellMap()

        for k in pairs(GlowAurasDB.auras) do
            GlowAurasDB.activeAuraKey = k
            break
        end

        if UI.soundPicker and UI.soundPicker:IsShown() then UI.soundPicker:Hide() end
        if UI.alertEditor and UI.alertEditor:IsShown() then UI.alertEditor:Hide() end
        if GA_IconPicker and GA_IconPicker.frame and GA_IconPicker.frame:IsShown() then GA_IconPicker.frame:Hide() end
        HideAlert()

        if UI.Refresh then UI:Refresh() end
    end)

    -- Aura enabled
    local cbAura = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    cbAura:SetPoint("TOPLEFT", PAD, -145)
    cbAura.text:SetText("Enable selected aura")
    cbAura:SetScript("OnClick", function(btn)
        local aura = GetAura()
        if not aura then return end
        aura.enabled = btn:GetChecked() and true or false
    end)
    UI.cbAura = cbAura

    -- SpellID display + learn
    local spellFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spellFS:SetPoint("TOPLEFT", PAD, -175)
    spellFS:SetWidth(360)
    spellFS:SetJustifyH("LEFT")
    UI.spellFS = spellFS

    local learnBtn = MakeButton(frame, "Learn", 80, 24, PAD + 380, -170)
    learnBtn:SetScript("OnClick", function()
        local k = ActiveAuraKey()
        if not k then return end
        StartLearning(k)
        UI.spellFS:SetText(("GlowID: learning... trigger the proc now (%s)"):format(k))
    end)

    -- Message
    MakeLabel(frame, "Message", PAD, -210)
    local msgBox = MakeEditBox(frame, 360, PAD, -236)
    UI.msgBox = msgBox
    msgBox:SetScript("OnEnterPressed", function(box)
        local aura = GetAura()
        if not aura then return end
        aura.message = box:GetText()
        box:ClearFocus()
        if overlay and overlay:IsShown() and (aura.showText or false) then
            overlay.text:SetText(tostring(aura.message or "PROC!"))
        end
    end)

    -- toggles
    local cbText = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    cbText:SetPoint("TOPLEFT", PAD, -276)
    cbText.text:SetText("Show text")
    cbText:SetScript("OnClick", function(btn)
        local aura = GetAura()
        if not aura then return end
        aura.showText = btn:GetChecked() and true or false
        if overlay and overlay:IsShown() then ShowAlert(ActiveAuraKey(), true) end
    end)
    UI.cbText = cbText

    local cbSound = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    cbSound:SetPoint("TOPLEFT", PAD + 140, -276)
    cbSound.text:SetText("Play sound")
    cbSound:SetScript("OnClick", function(btn)
        local aura = GetAura()
        if not aura then return end
        aura.playSound = btn:GetChecked() and true or false
    end)
    UI.cbSound = cbSound

    local cbLock = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    cbLock:SetPoint("TOPLEFT", PAD + 280, -276)
    cbLock.text:SetText("Lock overlay")
    cbLock:SetScript("OnClick", function(btn)
        local aura = GetAura()
        if not aura then return end
        aura.overlayLocked = btn:GetChecked() and true or false
        ApplyOverlaySettings(ActiveAuraKey())
    end)
    UI.cbLock = cbLock

    local cbBg = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    cbBg:SetPoint("TOPLEFT", PAD + 420, -276)
    cbBg.text:SetText("Background")
    cbBg:SetScript("OnClick", function(btn)
        local aura = GetAura()
        if not aura then return end
        aura.showBackground = btn:GetChecked() and true or false
        ApplyOverlaySettings(ActiveAuraKey())
        if overlay and overlay:IsShown() then ShowAlert(ActiveAuraKey(), true) end
    end)
    UI.cbBg = cbBg

    -- Icon toggle + choose icon
    local cbIcon = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    cbIcon:SetPoint("TOPLEFT", PAD, -312)
    cbIcon.text:SetText("Show icon")
    cbIcon:SetScript("OnClick", function(btn)
        local aura = GetAura()
        if not aura then return end
        aura.showIcon = btn:GetChecked() and true or false
        if overlay and overlay:IsShown() then ShowAlert(ActiveAuraKey(), true) end
    end)
    UI.cbIcon = cbIcon

    local iconBtn = MakeButton(frame, "Choose Icon…", 150, 26, PAD + 250, -312)
    iconBtn:SetScript("OnClick", function()
        EnsureIconPicker()
        if GA_IconPicker and GA_IconPicker.Toggle then
            GA_IconPicker:Toggle()
        end
    end)

    UI.iconPreviewTex = frame:CreateTexture(nil, "ARTWORK")
    UI.iconPreviewTex:SetSize(22, 22)
    UI.iconPreviewTex:SetPoint("LEFT", iconBtn, "RIGHT", 10, 0)
    UI.iconPreviewTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    -- Sound picker + editor buttons
    local soundBtn = MakeButton(frame, "Choose Sound…", 150, 26, PAD, -350)
    soundBtn:SetScript("OnClick", function()
        EnsureSoundPicker()
        local sp = UI.soundPicker
        if sp:IsShown() then
            sp:Hide()
        else
            if UI.frame and UI.frame:IsShown() then
                PlaceLeftOf(UI.frame, sp, 20, 0)
            end
            UI.allSounds = BuildSoundList()
            UI.filteredSounds = UI.allSounds
            if UI.soundSearch then UI.soundSearch:SetText("") end
            RefreshSelectedSoundLabels()
            sp:Show()
            if UI.SoundPicker_UpdateList then UI.SoundPicker_UpdateList() end
        end
    end)

    UI.mainSoundLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.mainSoundLabel:SetPoint("LEFT", soundBtn, "RIGHT", 12, 0)
    UI.mainSoundLabel:SetWidth(360)
    UI.mainSoundLabel:SetJustifyH("LEFT")

    local editBtn = MakeButton(frame, "Edit Alert…", 150, 26, PAD + 250, -350)
    editBtn:SetScript("OnClick", function()
        EnsureAlertEditor()
        local ed = UI.alertEditor
        if ed:IsShown() then
            ed:Hide()
        else
            if UI.frame and UI.frame:IsShown() then
                PlaceRightOf(UI.frame, ed, 20, 0)
            end
            ed:Show()
        end
    end)

    -- Test/Hide
    local testBtn = MakeButton(frame, "Test", 90, 26, PAD, -388)
    testBtn:SetScript("OnClick", function()
        local k = ActiveAuraKey()
        if not k then return end
        hideToken = hideToken + 1
        ShowAlert(k, false)
    end)

    local hideBtn = MakeButton(frame, "Hide", 90, 26, PAD + 100, -388)
    hideBtn:SetScript("OnClick", function()
        hideToken = hideToken + 1
        HideAlert()
    end)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", PAD, -432)
    hint:SetWidth(520)
    hint:SetJustifyH("LEFT")
    hint:SetText("New Glow Aura opens ABOVE. Choose Sound opens LEFT. Edit Alert opens RIGHT. Choose Icon opens ABOVE. Learn captures the next proc glow.")

    function UI:Refresh()
        local auraKey = ActiveAuraKey()
        local aura = auraKey and GetAura(auraKey) or nil

        UI.cbGlobal:SetChecked(GlowAurasDB.enabled and true or false)

        if aura then
            NormalizeAuraDisplay(aura)
            UI.cbAura:SetChecked(aura.enabled and true or false)
            UI.cbText:SetChecked(aura.showText and true or false)
            if UI.cbIcon then UI.cbIcon:SetChecked(aura.showIcon and true or false) end
            UI.cbSound:SetChecked(aura.playSound and true or false)
            UI.cbLock:SetChecked(aura.overlayLocked and true or false)
            if UI.cbBg then UI.cbBg:SetChecked(aura.showBackground and true or false) end

            UI.iconPreviewTex:SetTexture(ResolveAuraIconTexture(aura))

            UI.msgBox:SetText(tostring(aura.message or "PROC!"))
            UI.spellFS:SetText("GlowID: " .. (aura.spellID and tostring(aura.spellID) or "(not learned)"))
            RefreshSelectedSoundLabels()
        else
            UI.spellFS:SetText("GlowID: (none)")
            if UI.mainSoundLabel then UI.mainSoundLabel:SetText("Selected: (none)") end
        end

        UI:Dropdown_Refresh()
    end

    frame:SetScript("OnShow", function()
        UI:Refresh()

        if UI.soundPicker and UI.soundPicker:IsShown() then PlaceLeftOf(UI.frame, UI.soundPicker, 20, 0) end
        if UI.alertEditor and UI.alertEditor:IsShown() then PlaceRightOf(UI.frame, UI.alertEditor, 20, 0) end
        if UI.newAuraPopup and UI.newAuraPopup:IsShown() then PlaceAbove(UI.frame, UI.newAuraPopup, 20, 0) end
        if GA_IconPicker and GA_IconPicker.frame and GA_IconPicker.frame:IsShown() then PlaceAbove(UI.frame, GA_IconPicker.frame, 20, 0) end
    end)
end

local function ToggleConfig()
    EnsureConfig()
    if UI.frame:IsShown() then
        UI.frame:Hide()
        if UI.soundPicker and UI.soundPicker:IsShown() then UI.soundPicker:Hide() end
        if UI.alertEditor and UI.alertEditor:IsShown() then UI.alertEditor:Hide() end
        if UI.newAuraPopup and UI.newAuraPopup:IsShown() then UI.newAuraPopup:Hide() end
        if GA_IconPicker and GA_IconPicker.frame and GA_IconPicker.frame:IsShown() then GA_IconPicker.frame:Hide() end
        HideAlert()
        StopLearning()
    else
        UI.frame:Show()
    end
end

------------------------------------------------------------
-- Events: login + glow detection
------------------------------------------------------------
local evt = CreateFrame("Frame")
evt:RegisterEvent("PLAYER_LOGIN")
evt:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
evt:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")

evt:SetScript("OnEvent", function(_, event, spellID)
    if event == "PLAYER_LOGIN" then
        InitDB()
        RebuildSpellMap()
        print("|cff00ff00[GlowAuras]|r Loaded. /ga to open settings.")
        return
    end

    if not GlowAurasDB.enabled then return end
    local sid = tonumber(spellID)
    if not sid then return end

    if learning.active and event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" and learning.auraKey then
        local learnedKey = learning.auraKey

        local aura = GetAura(learnedKey)
        if aura then
            aura.spellID = sid
            RebuildSpellMap()

            StopLearning()

            if UI.newAuraPopup and UI.newAuraPopup:IsShown() and UI.newAuraPopup.spellLabel then
                UI.newAuraPopup.spellLabel:SetText("GlowID: " .. tostring(sid) .. " (learned)")
            end

            if UI.Refresh then UI:Refresh() end
            print(("|cff00ff00[GlowAuras]|r Learned spellID %d for '%s'."):format(sid, learnedKey))
        end
        return
    end

    local auraKey = spellToAura[sid]
    if not auraKey then return end

    local aura = GetAura(auraKey)
    if not aura or not aura.enabled then return end
    NormalizeAuraDisplay(aura)
    if (not aura.showText) and (not aura.showIcon) and (not aura.playSound) then return end

    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        ShowAlert(auraKey, false)
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        if currentShownAuraKey == auraKey then
            hideToken = hideToken + 1
            HideAlert()
        end
    end
end)

------------------------------------------------------------
-- Slash
------------------------------------------------------------
SLASH_GLOWAURAS1 = "/ga"
SLASH_GLOWAURAS2 = "/glowauras"
SlashCmdList.GLOWAURAS = function()
    ToggleConfig()
end
