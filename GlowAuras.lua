-- GlowAuras.lua
-- GlowAuras (Retail 12.0+)
-- Learns SPELL_ACTIVATION_OVERLAY_GLOW_* spellIDs and lets you configure per-glow alerts.
-- /ga to open


local ADDON = ...
GlowAurasDB = GlowAurasDB or {}
local UI
local Trim
local RebuildSpellMap
local RegisterLayoutControl
local OpenCopyProfilePopup
local OpenDeleteProfileConfirmPopup

------------------------------------------------------------
-- LibSharedMedia (optional)
------------------------------------------------------------
local LSM = (LibStub and LibStub("LibSharedMedia-3.0", true)) or nil
local LD = (LibStub and LibStub("LibDeflate", true)) or nil
local LS = (LibStub and LibStub("LibSerialize", true)) or nil
local GUI_C = {
    bg        = {0.067, 0.094, 0.153, 0.97},
    bgLight   = {0.122, 0.161, 0.216, 1.0},
    bgDark    = {0.04,  0.06,  0.10,  1.0},
    borderDim = {0.17,  0.22,  0.30,  0.9},
    text      = {0.92,  0.95,  1.0,   1.0},
    textDim   = {0.75,  0.80,  0.88,  1.0},
    accent    = {0.204, 0.827, 0.6,   1.0},
    danger    = {0.95,  0.33,  0.33,  1.0},
}

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
        bgColor        = { 0, 0, 0, 0.35 },
        fontColor      = { 1, 1, 1, 1 },
        bgW            = nil, -- nil = match overlay width
        bgH            = nil, -- nil = match overlay height
        bgX            = 0,
        bgY            = 0,
        bgAnchorToText = false,

        overlayLocked = true,
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

local currentProfileName = nil

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

local function CloneTable(src)
    if type(src) ~= "table" then return src end
    local out = {}
    for k, v in pairs(src) do
        out[CloneTable(k)] = CloneTable(v)
    end
    return out
end

local function ProfileDefaults()
    return {
        enabled = defaults.enabled,
        activeAuraKey = nil,
        uiPoint = nil,
        auras = {},
    }
end

local function CountTableKeys(t)
    local n = 0
    if type(t) ~= "table" then return 0 end
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function SeededDefaultProfile()
    local p = ProfileDefaults()
    p.auras = CloneTable(defaults.auras)
    return p
end

local function GetCharKey()
    local name = (UnitName and UnitName("player")) or "Unknown"
    local realm = (GetRealmName and GetRealmName()) or "UnknownRealm"
    realm = tostring(realm):gsub("%s+", "")
    return tostring(name) .. "-" .. realm
end

local function EnsureProfileContainer()
    GlowAurasDB.profiles = GlowAurasDB.profiles or {}
    GlowAurasDB.charProfiles = GlowAurasDB.charProfiles or {}
    GlowAurasDB.recentIcons = GlowAurasDB.recentIcons or {}
end

local function SnapshotRootToProfile()
    if not currentProfileName then return end
    EnsureProfileContainer()
    GlowAurasDB.profiles[currentProfileName] = {
        enabled = GlowAurasDB.enabled and true or false,
        activeAuraKey = GlowAurasDB.activeAuraKey,
        uiPoint = CloneTable(GlowAurasDB.uiPoint),
        auras = CloneTable(GlowAurasDB.auras or {}),
    }
end

local function LoadProfileToRoot(profileName)
    EnsureProfileContainer()
    local p = GlowAurasDB.profiles[profileName]
    if type(p) ~= "table" then
        p = (tostring(profileName) == "Default") and SeededDefaultProfile() or ProfileDefaults()
        GlowAurasDB.profiles[profileName] = CloneTable(p)
    end
    DeepCopyDefaults(p, ProfileDefaults())

    GlowAurasDB.enabled = p.enabled and true or false
    GlowAurasDB.activeAuraKey = p.activeAuraKey
    GlowAurasDB.uiPoint = CloneTable(p.uiPoint)
    GlowAurasDB.auras = CloneTable(p.auras or {})
    if (not GlowAurasDB.activeAuraKey) or (not GlowAurasDB.auras[GlowAurasDB.activeAuraKey]) then
        for k in pairs(GlowAurasDB.auras) do
            GlowAurasDB.activeAuraKey = k
            break
        end
    end
    currentProfileName = profileName
    GlowAurasDB.activeProfile = profileName
end

local function SortedProfileNames()
    local t = {}
    for k in pairs(GlowAurasDB.profiles or {}) do t[#t+1] = k end
    table.sort(t, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
    return t
end

local function EnsureProfileExists(name)
    name = Trim(name)
    if name == "" then return nil end
    EnsureProfileContainer()
    if not GlowAurasDB.profiles[name] then
        GlowAurasDB.profiles[name] = (tostring(name) == "Default") and SeededDefaultProfile() or ProfileDefaults()
    end
    return name
end

local function SwitchProfile(name, assignCurrentChar)
    name = EnsureProfileExists(name)
    if not name then return false, "invalid profile name" end
    SnapshotRootToProfile()
    LoadProfileToRoot(name)

    if assignCurrentChar then
        GlowAurasDB.charProfiles[GetCharKey()] = name
    end

    RebuildSpellMap()
    if UI and UI.Refresh then UI:Refresh() end
    return true
end

local function DeleteProfile(name)
    EnsureProfileContainer()
    if not name or not GlowAurasDB.profiles[name] then return false, "profile not found" end
    local names = SortedProfileNames()
    if #names <= 1 then return false, "must keep at least one profile" end
    if currentProfileName == name then
        SnapshotRootToProfile()
    end

    GlowAurasDB.profiles[name] = nil
    for charKey, pn in pairs(GlowAurasDB.charProfiles or {}) do
        if pn == name then GlowAurasDB.charProfiles[charKey] = nil end
    end

    local fallback = SortedProfileNames()[1] or "Default"
    if currentProfileName == name then
        LoadProfileToRoot(fallback)
        RebuildSpellMap()
        if UI and UI.Refresh then UI:Refresh() end
    end
    return true
end

local function ExportProfileString(profileName)
    SnapshotRootToProfile()
    local p = GlowAurasDB.profiles and GlowAurasDB.profiles[profileName or currentProfileName or "Default"]
    if type(p) ~= "table" then return nil end
    if not (LS and LD) then return nil end
    local serialized = LS:Serialize(CloneTable(p))
    local compressed = LD:CompressDeflate(serialized)
    if not compressed then return nil end
    local encoded = LD:EncodeForPrint(compressed)
    if not encoded then return nil end
    return "GA_PROFILE_V2:" .. encoded, CountTableKeys(p.auras)
end

local function ImportProfileString(text, newProfileName)
    text = Trim(text)
    if text == "" then return false, "empty import" end
    local tbl
    local bodyV2 = text:match("^GA_PROFILE_V2:(.+)$")
    if bodyV2 then
        if not (LS and LD) then return false, "serializer libs not loaded" end
        local decoded = LD:DecodeForPrint(bodyV2)
        if not decoded then return false, "decode failed" end
        local decompressed = LD:DecompressDeflate(decoded)
        if not decompressed then return false, "decompress failed" end
        local ok, data = LS:Deserialize(decompressed)
        if not ok or type(data) ~= "table" then return false, "deserialize failed" end
        tbl = data
    else
        -- Backward compat for earlier local serializer format.
        local body = text:match("^GA_PROFILE_V1:(.+)$")
        if not body then return false, "bad format" end
        local loader, err = loadstring("return " .. body)
        if not loader then return false, err or "parse error" end
        local ok, data = pcall(loader)
        if not ok or type(data) ~= "table" then return false, "invalid profile data" end
        tbl = data
    end

    local name = EnsureProfileExists(newProfileName)
    if not name then return false, "invalid profile name" end

    DeepCopyDefaults(tbl, ProfileDefaults())
    GlowAurasDB.profiles[name] = tbl
    return true, name, CountTableKeys(tbl.auras)
end

local function InitDB()
    DeepCopyDefaults(GlowAurasDB, defaults)
    GlowAurasDB.layoutOverride = nil -- runtime layout import disabled; prevent stale broken overrides
    EnsureProfileContainer()

    -- One-time migration from legacy flat DB into profiles.
    if not next(GlowAurasDB.profiles) then
        local migrated = {
            enabled = GlowAurasDB.enabled,
            activeAuraKey = GlowAurasDB.activeAuraKey,
            uiPoint = CloneTable(GlowAurasDB.uiPoint),
            auras = CloneTable(GlowAurasDB.auras or {}),
        }
        DeepCopyDefaults(migrated, SeededDefaultProfile())
        GlowAurasDB.profiles["Default"] = migrated
        GlowAurasDB.activeProfile = "Default"
    end

    if not GlowAurasDB.profiles["Default"] then
        GlowAurasDB.profiles["Default"] = SeededDefaultProfile()
    end

    local charKey = GetCharKey()
    if not GlowAurasDB.charProfiles[charKey] then
        local newCharProfile = EnsureProfileExists(charKey)
        GlowAurasDB.charProfiles[charKey] = newCharProfile or "Default"
    end
    local wanted = GlowAurasDB.charProfiles[charKey] or GlowAurasDB.activeProfile or "Default"
    if not GlowAurasDB.profiles[wanted] then
        wanted = "Default"
    end
    LoadProfileToRoot(wanted)

    if not GlowAurasDB.auras or next(GlowAurasDB.auras) == nil then
        GlowAurasDB.auras = CloneTable(defaults.auras)
    end

    if not GlowAurasDB.activeAuraKey or not GlowAurasDB.auras[GlowAurasDB.activeAuraKey] then
        for k in pairs(GlowAurasDB.auras) do
            GlowAurasDB.activeAuraKey = k
            break
        end
    end
    SnapshotRootToProfile()
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

Trim = function(s)
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

RebuildSpellMap = function()
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
local overlayPreviewFrames = {}
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
        local bgc = aura.bgColor
        local br = (type(bgc) == "table" and tonumber(bgc[1])) or 0
        local bg = (type(bgc) == "table" and tonumber(bgc[2])) or 0
        local bb = (type(bgc) == "table" and tonumber(bgc[3])) or 0
        local ba = (type(bgc) == "table" and tonumber(bgc[4])) or 0.35
        overlay.bg:ClearAllPoints()
        if aura.bgAnchorToText and overlay.text and overlay.text:IsShown() then
            overlay.bg:SetPoint("CENTER", overlay.text, "CENTER", tonumber(aura.bgX) or 0, tonumber(aura.bgY) or 0)
        else
            overlay.bg:SetPoint("CENTER", overlay, "CENTER", tonumber(aura.bgX) or 0, tonumber(aura.bgY) or 0)
        end
        overlay.bg:SetSize(
            Clamp(aura.bgW or aura.overlayW, 1, OVERLAY_MAX_W),
            Clamp(aura.bgH or aura.overlayH, 1, OVERLAY_MAX_H)
        )
        overlay.bg:SetColorTexture(br, bg, bb, ba)
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
    local fc = aura.fontColor
    overlay.text:SetTextColor(
        (type(fc) == "table" and tonumber(fc[1])) or 1,
        (type(fc) == "table" and tonumber(fc[2])) or 1,
        (type(fc) == "table" and tonumber(fc[3])) or 1,
        (type(fc) == "table" and tonumber(fc[4])) or 1
    )

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
    overlay.bg:SetPoint("CENTER")
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
        local key = currentShownAuraKey or ActiveAuraKey()
        local aura = GetAura(key)
        if not aura or not UI.overlayEditMode then return end
        self:StartMoving()
    end)
    overlay:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local key = currentShownAuraKey or ActiveAuraKey()
        local aura = GetAura(key)
        if not aura or not UI.overlayEditMode then return end

        local p, _, rp, x, y = self:GetPoint(1)
        aura.overlayPoint = { p or "CENTER", rp or "CENTER", x or 0, y or 0 }
    end)

    overlay:SetResizable(false)

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
UI = {}
_G.GA_UI = UI

local PAD = 14
local RefreshAllAuraOverlayPreviews

local function IsOverlayUnlockPreviewMode()
    return (UI.frame and UI.frame:IsShown() and UI.overlayEditMode) and true or false
end

local function RefreshOverlayVisuals()
    if IsOverlayUnlockPreviewMode() then
        RefreshAllAuraOverlayPreviews()
        return
    end
    local k = ActiveAuraKey()
    if not k then return end
    hideToken = hideToken + 1
    ShowAlert(k, true)
end

local function HideAllOverlayPreviews()
    for _, f in pairs(overlayPreviewFrames) do
        if f and f.Hide then f:Hide() end
    end
end

local function EnsureOverlayPreviewFrame(auraKey)
    local f = overlayPreviewFrames[auraKey]
    if f then return f end

    f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetPoint("CENTER")
    f.bg:SetColorTexture(0, 0, 0, 0.35)

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    f.text:SetPoint("CENTER")

    f.icon = f:CreateTexture(nil, "OVERLAY")
    f.icon:SetPoint("CENTER")
    f.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    f.icon:Hide()

    f.auraKey = auraKey
    f:SetScript("OnDragStart", function(self)
        local aura = GetAura(self.auraKey)
        if not aura or (not IsOverlayUnlockPreviewMode()) then return end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local aura = GetAura(self.auraKey)
        if not aura then return end
        local p, _, rp, x, y = self:GetPoint(1)
        aura.overlayPoint = { p or "CENTER", rp or "CENTER", x or 0, y or 0 }
        if self.auraKey == ActiveAuraKey() then
            currentShownAuraKey = self.auraKey
        end
    end)

    overlayPreviewFrames[auraKey] = f
    return f
end

RefreshAllAuraOverlayPreviews = function()
    if not IsOverlayUnlockPreviewMode() then
        HideAllOverlayPreviews()
        return
    end

    HideAlert()

    local seen = {}
    for key, aura in pairs(GlowAurasDB.auras or {}) do
        seen[key] = true
        NormalizeAuraDisplay(aura)
        local f = EnsureOverlayPreviewFrame(key)

        f:ClearAllPoints()
        if type(aura.overlayPoint) == "table" and aura.overlayPoint[1] then
            f:SetPoint(
                aura.overlayPoint[1],
                UIParent,
                aura.overlayPoint[2] or "CENTER",
                aura.overlayPoint[3] or 0,
                aura.overlayPoint[4] or 180
            )
        else
            f:SetPoint("CENTER", 0, 180)
        end

        f:SetSize(
            Clamp(aura.overlayW, OVERLAY_MIN_W, OVERLAY_MAX_W),
            Clamp(aura.overlayH, OVERLAY_MIN_H, OVERLAY_MAX_H)
        )

        if aura.showBackground then
            local bgc = aura.bgColor
            f.bg:SetColorTexture(
                (type(bgc) == "table" and tonumber(bgc[1])) or 0,
                (type(bgc) == "table" and tonumber(bgc[2])) or 0,
                (type(bgc) == "table" and tonumber(bgc[3])) or 0,
                (type(bgc) == "table" and tonumber(bgc[4])) or 0.35
            )
            f.bg:ClearAllPoints()
            if aura.bgAnchorToText and f.text and f.text:IsShown() then
                f.bg:SetPoint("CENTER", f.text, "CENTER", tonumber(aura.bgX) or 0, tonumber(aura.bgY) or 0)
            else
                f.bg:SetPoint("CENTER", f, "CENTER", tonumber(aura.bgX) or 0, tonumber(aura.bgY) or 0)
            end
            f.bg:SetSize(
                Clamp(aura.bgW or aura.overlayW, 1, OVERLAY_MAX_W),
                Clamp(aura.bgH or aura.overlayH, 1, OVERLAY_MAX_H)
            )
            f.bg:Show()
        else
            f.bg:Hide()
        end

        f.text:ClearAllPoints()
        local tx = Clamp(aura.textX, -2000, 2000)
        local ty = Clamp(aura.textY, -2000, 2000)
        local wantIcon = aura.showIcon or false
        local wantText = aura.showText or false
        if not wantIcon and not wantText then
            wantText = true
        end

        if wantIcon then
            f.icon:ClearAllPoints()
            f.icon:SetPoint("CENTER", f, "CENTER",
                Clamp(aura.iconX, -2000, 2000),
                Clamp(aura.iconY, -2000, 2000)
            )
            local isz = Clamp(aura.iconSize, 12, 200)
            f.icon:SetSize(isz, isz)
            f.icon:SetTexture(ResolveAuraIconTexture(aura))
            f.icon:Show()
        else
            f.icon:Hide()
        end

        if wantText then
            local anchorToIcon = (aura.textAnchorToIcon and wantIcon and f.icon)
            if anchorToIcon then
                local gap = Clamp(aura.textGap, 0, 200)
                local pos = tostring(aura.textPos or "CENTER"):upper()
                if pos == "TOP" then
                    f.text:SetPoint("BOTTOM", f.icon, "TOP", tx, ty + gap)
                elseif pos == "BOTTOM" then
                    f.text:SetPoint("TOP", f.icon, "BOTTOM", tx, ty - gap)
                elseif pos == "LEFT" then
                    f.text:SetPoint("RIGHT", f.icon, "LEFT", tx - gap, ty)
                elseif pos == "RIGHT" then
                    f.text:SetPoint("LEFT", f.icon, "RIGHT", tx + gap, ty)
                else
                    f.text:SetPoint("CENTER", f.icon, "CENTER", tx, ty)
                end
            else
                f.text:SetPoint("CENTER", f, "CENTER", tx, ty)
            end

            local j = tostring(aura.textJustify or "CENTER"):upper()
            if j ~= "LEFT" and j ~= "CENTER" and j ~= "RIGHT" then j = "CENTER" end
            f.text:SetJustifyH(j)
            local fontPath = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
            local size = Clamp(aura.fontSize, 8, 96)
            f.text:SetFont(fontPath, size, "OUTLINE")
            local fc = aura.fontColor
            f.text:SetTextColor(
                (type(fc) == "table" and tonumber(fc[1])) or 1,
                (type(fc) == "table" and tonumber(fc[2])) or 1,
                (type(fc) == "table" and tonumber(fc[3])) or 1,
                (type(fc) == "table" and tonumber(fc[4])) or 1
            )
            f.text:SetText(tostring(aura.message or "PROC!"))
            f.text:Show()
        else
            f.text:Hide()
        end

        f:Show()
    end

    for key, f in pairs(overlayPreviewFrames) do
        if (not seen[key]) and f then
            f:Hide()
        end
    end
end

local function MakeLabel(parent, text, x, y, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    if GUI_C then
        local c = (template == "GameFontHighlightSmall") and GUI_C.textDim or GUI_C.text
        fs:SetTextColor(unpack(c))
    end
    return RegisterLayoutControl(fs, "Label: " .. tostring(text))
end

local function CopyProfileToProfile(sourceName, targetName)
    EnsureProfileContainer()
    sourceName = Trim(sourceName)
    targetName = Trim(targetName)
    if sourceName == "" or targetName == "" then return false, "invalid profile name" end
    if sourceName == targetName then return false, "source and target are the same" end
    SnapshotRootToProfile()
    local src = GlowAurasDB.profiles[sourceName]
    if type(src) ~= "table" then return false, "source profile not found" end
    if not GlowAurasDB.profiles[targetName] then return false, "target profile not found" end
    GlowAurasDB.profiles[targetName] = CloneTable(src)

    if currentProfileName == targetName then
        LoadProfileToRoot(targetName)
        RebuildSpellMap()
        if UI and UI.Refresh then UI:Refresh() end
    end
    return true
end

local function MakeButton(parent, text, w, h, x, y)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    local fs = b:GetFontString()
    if fs and GUI_C then fs:SetTextColor(unpack(GUI_C.text)) end
    return RegisterLayoutControl(b, text)
end

local function StyleCheckText(cb)
    if not cb then return end
    local fs = cb.text or cb.Text
    if fs and GUI_C then fs:SetTextColor(unpack(GUI_C.text)) end
end

local function StyleDropdownText(dd)
    if not dd then return end
    local fs = dd.Text or (dd.GetName and dd:GetName() and _G[dd:GetName() .. "Text"]) or nil
    if fs and GUI_C then fs:SetTextColor(unpack(GUI_C.text)) end
end

local function SetSwatchColor(tex, c, fallback)
    if not tex then return end
    local fc = fallback or { 1, 1, 1, 1 }
    local r = (type(c) == "table" and tonumber(c[1])) or fc[1] or 1
    local g = (type(c) == "table" and tonumber(c[2])) or fc[2] or 1
    local b = (type(c) == "table" and tonumber(c[3])) or fc[3] or 1
    local a = (type(c) == "table" and tonumber(c[4])) or fc[4] or 1
    tex:SetColorTexture(r, g, b, a)
end

local function UpdateAuraColorSwatches()
    local aura = GetAura()
    if not aura then return end
    if UI.fontColorSwatch then
        SetSwatchColor(UI.fontColorSwatch, aura.fontColor, { 1, 1, 1, 1 })
    end
    if UI.bgColorSwatch then
        SetSwatchColor(UI.bgColorSwatch, aura.bgColor, { 0, 0, 0, 0.35 })
    end
    if UI.edFontColorSwatch then
        SetSwatchColor(UI.edFontColorSwatch, aura.fontColor, { 1, 1, 1, 1 })
    end
    if UI.edBgColorSwatch then
        SetSwatchColor(UI.edBgColorSwatch, aura.bgColor, { 0, 0, 0, 0.35 })
    end
end

local function OpenAuraColorPicker(kind)
    local aura = GetAura()
    if not aura or not _G.ColorPickerFrame then return end

    local isBg = (kind == "bg")
    local cur = isBg and (aura.bgColor or { 0, 0, 0, 0.35 }) or (aura.fontColor or { 1, 1, 1, 1 })
    local baseR = tonumber(cur[1]) or (isBg and 0 or 1)
    local baseG = tonumber(cur[2]) or (isBg and 0 or 1)
    local baseB = tonumber(cur[3]) or (isBg and 0 or 1)
    local baseA = tonumber(cur[4]) or (isBg and 0.35 or 1)

    local function applyFromPicker(restore)
        local r, g, b = baseR, baseG, baseB
        local a = baseA

        if restore then
            r, g, b, a = restore.r, restore.g, restore.b, restore.a
        else
            if ColorPickerFrame.GetColorRGB then
                r, g, b = ColorPickerFrame:GetColorRGB()
            elseif ColorPickerFrame.Content and ColorPickerFrame.Content.ColorPicker and ColorPickerFrame.Content.ColorPicker.GetColorRGB then
                r, g, b = ColorPickerFrame.Content.ColorPicker:GetColorRGB()
            end
            if type(ColorPickerFrame.HasOpacity) == "function" and ColorPickerFrame:HasOpacity() and OpacitySliderFrame and OpacitySliderFrame.GetValue then
                a = 1 - (OpacitySliderFrame:GetValue() or (1 - baseA))
            elseif ColorPickerFrame.opacity then
                a = 1 - (ColorPickerFrame.opacity or (1 - baseA))
            end
        end

        if isBg then
            aura.bgColor = { r, g, b, a }
        else
            aura.fontColor = { r, g, b, 1 }
        end
        UpdateAuraColorSwatches()
        RefreshOverlayVisuals()
    end

    local restore = { r = baseR, g = baseG, b = baseB, a = baseA }

    ColorPickerFrame.func = function() applyFromPicker(nil) end
    ColorPickerFrame.opacityFunc = function() applyFromPicker(nil) end
    ColorPickerFrame.cancelFunc = function(prev) applyFromPicker(prev or restore) end
    ColorPickerFrame.hasOpacity = isBg and true or false
    ColorPickerFrame.opacity = 1 - baseA
    if ColorPickerFrame.SetColorRGB then
        ColorPickerFrame:SetColorRGB(baseR, baseG, baseB)
    end
    ColorPickerFrame.previousValues = restore
    ColorPickerFrame:Hide()
    ColorPickerFrame:Show()
end

local function MakeEditBox(parent, w, x, y)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(w, 30)
    eb:SetPoint("TOPLEFT", x, y)
    eb:SetAutoFocus(false)
    eb:SetTextInsets(10, 10, 0, 0)
    return RegisterLayoutControl(eb, "EditBox")
end

local function MakeMultiLineEditBox(parent, w, h, x, y)
    local wrap = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    wrap:SetSize(w, h)
    wrap:SetPoint("TOPLEFT", x, y)
    wrap:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8x8",
        edgeFile = "Interface/Buttons/WHITE8x8",
        edgeSize = 1,
    })
    wrap:SetBackdropColor(0, 0, 0, 0.35)
    wrap:SetBackdropBorderColor(unpack(GUI_C.borderDim))
    RegisterLayoutControl(wrap, "Profile Export Box")

    local scroll = CreateFrame("ScrollFrame", nil, wrap, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)

    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    eb:SetTextInsets(4, 4, 4, 4)
    eb:SetWidth(math.max(60, w - 38))
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnTextChanged", function(self)
        local newH = h - 8
        if self.GetStringHeight then
            newH = math.max(h - 8, (self:GetStringHeight() or 0) + 12)
        end
        self:SetHeight(newH)
        if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
    end)
    eb:SetScript("OnCursorChanged", function(self, xoff, yoff, _, h2)
        local scrollY = scroll:GetVerticalScroll()
        local viewH = scroll:GetHeight()
        if yoff < scrollY then
            scroll:SetVerticalScroll(yoff)
        elseif (yoff + h2) > (scrollY + viewH) then
            scroll:SetVerticalScroll((yoff + h2) - viewH)
        end
    end)
    scroll:SetScrollChild(eb)
    eb._gaScroll = scroll
    eb._gaWrap = wrap
    wrap.editBox = eb
    return eb, wrap
end

local function MakeSlider(parent, name, label, minV, maxV, step, x, y, w)
    local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", x, y)
    s:SetWidth(w or 260)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s._labelBase = label
    s._labelFS = _G[s:GetName() .. "Text"]
    local function FormatSliderValue(v)
        v = tonumber(v) or 0
        if math.abs(v - math.floor(v + 0.5)) < 0.001 then
            return tostring(math.floor(v + 0.5))
        end
        return string.format("%.1f", v)
    end
    function s:SetValueLabel(v)
        if self._labelFS then
            self._labelFS:SetText(("%s: %s"):format(self._labelBase or "", FormatSliderValue(v)))
        end
    end
    s:SetValueLabel(minV)
    _G[s:GetName() .. "Low"]:SetText(tostring(minV))
    _G[s:GetName() .. "High"]:SetText(tostring(maxV))
    return RegisterLayoutControl(s, label)
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

------------------------------------------------------------
-- Alert Editor (RIGHT)
------------------------------------------------------------
local EDIT_MIN_W, EDIT_MIN_H = 620, 460
local EDIT_MAX_W, EDIT_MAX_H = 980, 700

local function EnsureAlertEditor()
    if UI.alertEditor then return end

    local ed = CreateFrame("Frame", "GA_EditorFrame", UIParent, "BackdropTemplate")
    ed:SetSize(680, 500)
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
    ed:SetBackdropColor(unpack(GUI_C.bg))
    ed:SetBackdropBorderColor(unpack(GUI_C.borderDim))
    ed:Hide()
    UI.alertEditor = ed

    local edTitle = MakeLabel(ed, "Edit Alert", PAD, -PAD, "GameFontNormalLarge")
    ed.titleFS = edTitle

    local close = MakeButton(ed, "X", 26, 22, 680 - PAD - 26, -PAD)
    ed.closeBtn = close
    close:SetScript("OnClick", function()
        ed:Hide()
        HideAlert()
    end)

    ed.alertTextLabel = MakeLabel(ed, "Alert Text", PAD, -50)
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
        RefreshOverlayVisuals()
    end)

    ed.textAlignLabel = MakeLabel(ed, "Text Align", PAD + 350, -50)
    local dd = CreateFrame("Frame", "GA_TextAlignDropDown", ed, "UIDropDownMenuTemplate")
    RegisterLayoutControl(dd, "Display Text Align Dropdown")
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
        RefreshOverlayVisuals()
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

    local cbAnchor = RegisterLayoutControl(CreateFrame("CheckButton", nil, ed, "UICheckButtonTemplate"), "Display Anchor Text To Icon")
    cbAnchor:SetPoint("TOPLEFT", PAD, -110)
    cbAnchor.text:SetText("Anchor text to icon")
    cbAnchor:SetScript("OnClick", function(btn)
        local aura = GetAura(); if not aura then return end
        aura.textAnchorToIcon = btn:GetChecked() and true or false
        ApplyOverlaySettings(ActiveAuraKey())
        RefreshOverlayVisuals()
    end)
    ed.cbAnchor = cbAnchor

    local cbBgAnchor = RegisterLayoutControl(CreateFrame("CheckButton", nil, ed, "UICheckButtonTemplate"), "Display Anchor BG To Text")
    cbBgAnchor:SetPoint("TOPLEFT", PAD + 190, -110)
    cbBgAnchor.text:SetText("Anchor BG to text")
    if cbBgAnchor.text then
        cbBgAnchor.text:ClearAllPoints()
        cbBgAnchor.text:SetPoint("RIGHT", cbBgAnchor, "LEFT", -4, 0)
        cbBgAnchor.text:SetJustifyH("RIGHT")
    end
    cbBgAnchor:SetScript("OnClick", function(btn)
        local aura = GetAura(); if not aura then return end
        aura.bgAnchorToText = btn:GetChecked() and true or false
        ApplyOverlaySettings(ActiveAuraKey())
        RefreshOverlayVisuals()
    end)
    ed.cbBgAnchor = cbBgAnchor

    ed.textPosLabel = MakeLabel(ed, "Text Position", PAD + 210, -110)
    local posDD = CreateFrame("Frame", "GA_TextPosDropDown", ed, "UIDropDownMenuTemplate")
    RegisterLayoutControl(posDD, "Display Text Position Dropdown")
    posDD:SetPoint("TOPLEFT", PAD + 190, -126)
    UIDropDownMenu_SetWidth(posDD, 120)
    ed.posDD = posDD

    local fontColorBtn = MakeButton(ed, "Font Colour", 110, 24, PAD + 500, -78)
    fontColorBtn:SetScript("OnClick", function()
        OpenAuraColorPicker("font")
    end)
    ed.fontColorBtn = fontColorBtn
    UI.edFontColorSwatch = ed:CreateTexture(nil, "ARTWORK")
    UI.edFontColorSwatch:SetSize(18, 18)
    UI.edFontColorSwatch:SetPoint("LEFT", fontColorBtn, "RIGHT", 8, 0)

    local bgColorBtn = MakeButton(ed, "BG Colour", 100, 24, PAD + 500, -110)
    bgColorBtn:SetScript("OnClick", function()
        OpenAuraColorPicker("bg")
    end)
    ed.bgColorBtn = bgColorBtn
    UI.edBgColorSwatch = ed:CreateTexture(nil, "ARTWORK")
    UI.edBgColorSwatch:SetSize(18, 18)
    UI.edBgColorSwatch:SetPoint("LEFT", bgColorBtn, "RIGHT", 8, 0)

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
        RefreshOverlayVisuals()
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
    local col2 = PAD + 330

    ed.wSlider        = MakeSlider(ed, "GA_AlertWidthSlider",   "Width",        OVERLAY_MIN_W, OVERLAY_MAX_W, 5,   x0,   y0,       280)
    ed.hSlider        = MakeSlider(ed, "GA_AlertHeightSlider",  "Height",       OVERLAY_MIN_H, OVERLAY_MAX_H, 2,   x0,   y0 - 55,  280)
    ed.bgWSlider      = MakeSlider(ed, "GA_BgWidthSlider",      "BG Size X",    1,             OVERLAY_MAX_W, 1,   x0,   y0 - 110, 280)
    ed.bgHSlider      = MakeSlider(ed, "GA_BgHeightSlider",     "BG Size Y",    1,             OVERLAY_MAX_H, 1,   x0,   y0 - 165, 280)
    ed.bgXSlider      = MakeSlider(ed, "GA_BgXSlider",          "BG X",         -300,          300,           1,   x0,   y0 - 220, 280)
    ed.bgYSlider      = MakeSlider(ed, "GA_BgYSlider",          "BG Y",         -300,          300,           1,   x0,   y0 - 275, 280)
    ed.dSlider        = MakeSlider(ed, "GA_AlertLenSlider",     "Length (sec)", 0,             10,            0.5, x0,   y0 - 330, 280)
    ed.lengthHelpFS   = MakeLabel(ed, "0 = Show Until Proc Used", x0 + 4, y0 - 350, "GameFontHighlightSmall")
    ed.iconSizeSlider = MakeSlider(ed, "GA_IconSizeSlider",     "Icon Size",    12,            200,           1,   x0,   y0 - 385, 280)

    ed.txSlider = MakeSlider(ed, "GA_TextXSlider",        "Text X",       -200,          200,           1,   col2, y0,       280)
    ed.tySlider = MakeSlider(ed, "GA_TextYSlider",        "Text Y",       -100,          100,           1,   col2, y0 - 55,  280)
    ed.fsSlider = MakeSlider(ed, "GA_FontSizeSlider",     "Font Size",    12,            64,            1,   col2, y0 - 110, 280)
    ed.gapSlider = MakeSlider(ed, "GA_TextGapSlider",     "Text Gap",     0,             50,            1,   col2, y0 - 165, 280)

    local function HookSlider(slider, getter, setter)
        slider:SetScript("OnValueChanged", function(_, value)
            slider:SetValueLabel(value)
            setter(value)
            ApplyOverlaySettings(ActiveAuraKey())
            local aura = GetAura()
            if overlay and overlay:IsShown() and aura and (aura.showText or false) then
                overlay.text:SetText(tostring(aura.message or "PROC!"))
            end
            RefreshAllAuraOverlayPreviews()
        end)
        slider:SetScript("OnShow", function(self)
            local v = getter()
            self:SetValue(v)
            self:SetValueLabel(v)
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

    HookSlider(ed.bgWSlider,
        function()
            local aura = GetAura()
            local ow = aura and Clamp(aura.overlayW, OVERLAY_MIN_W, OVERLAY_MAX_W) or OVERLAY_MIN_W
            return aura and Clamp(aura.bgW or ow, 1, OVERLAY_MAX_W) or ow
        end,
        function(v)
            local aura = GetAura(); if not aura then return end
            aura.bgW = math.floor(v + 0.5)
        end
    )

    HookSlider(ed.bgHSlider,
        function()
            local aura = GetAura()
            local oh = aura and Clamp(aura.overlayH, OVERLAY_MIN_H, OVERLAY_MAX_H) or OVERLAY_MIN_H
            return aura and Clamp(aura.bgH or oh, 1, OVERLAY_MAX_H) or oh
        end,
        function(v)
            local aura = GetAura(); if not aura then return end
            aura.bgH = math.floor(v + 0.5)
        end
    )

    HookSlider(ed.bgXSlider,
        function()
            local aura = GetAura()
            return aura and (tonumber(aura.bgX) or 0) or 0
        end,
        function(v)
            local aura = GetAura(); if not aura then return end
            aura.bgX = math.floor(v + 0.5)
        end
    )

    HookSlider(ed.bgYSlider,
        function()
            local aura = GetAura()
            return aura and (tonumber(aura.bgY) or 0) or 0
        end,
        function(v)
            local aura = GetAura(); if not aura then return end
            aura.bgY = math.floor(v + 0.5)
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
        self.bgWSlider:SetValue(Clamp(aura.bgW or aura.overlayW, 1, OVERLAY_MAX_W))
        self.bgHSlider:SetValue(Clamp(aura.bgH or aura.overlayH, 1, OVERLAY_MAX_H))
        if self.bgXSlider then self.bgXSlider:SetValue(tonumber(aura.bgX) or 0) end
        if self.bgYSlider then self.bgYSlider:SetValue(tonumber(aura.bgY) or 0) end
        self.dSlider:SetValue(tonumber(aura.alertDuration) or 0)
        self.iconSizeSlider:SetValue(Clamp(aura.iconSize, 12, 200))
        self.txSlider:SetValue(tonumber(aura.textX) or 0)
        self.tySlider:SetValue(tonumber(aura.textY) or 0)
        self.fsSlider:SetValue(Clamp(aura.fontSize, 12, 64))
        UIDropDownMenu_SetText(self.alignDD, AlignLabel(tostring(aura.textJustify or "CENTER"):upper()))
        UIDropDownMenu_SetText(self.posDD, PosLabel(tostring(aura.textPos or "CENTER"):upper()))
        self.cbAnchor:SetChecked(aura.textAnchorToIcon and true or false)
        if self.cbBgAnchor then self.cbBgAnchor:SetChecked(aura.bgAnchorToText and true or false) end
        self.gapSlider:SetValue(Clamp(aura.textGap, 0, 50))
        self.msgBox:SetText(tostring(aura.message or "PROC!"))
        UpdateAuraColorSwatches()
    end

    local grip = CreateFrame("Button", nil, ed)
    ed.resizeGrip = grip
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
        RefreshAllAuraOverlayPreviews()
    end)

    ed:SetScript("OnHide", function()
        HideAllOverlayPreviews()
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
    p:SetBackdropColor(unpack(GUI_C.bg))
    p:SetBackdropBorderColor(unpack(GUI_C.borderDim))
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
-- Profile Manager
------------------------------------------------------------
local function EnsureProfileManager()
    if UI.profileManager then return end

    local p = CreateFrame("Frame", "GA_ProfileManager", UIParent, "BackdropTemplate")
    p:SetSize(560, 360)
    p:SetFrameStrata("DIALOG")
    p:SetClampedToScreen(true)
    p:SetMovable(true)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)
    p:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    p:SetBackdropColor(unpack(GUI_C.bg))
    p:SetBackdropBorderColor(unpack(GUI_C.borderDim))
    p:Hide()
    UI.profileManager = p

    MakeLabel(p, "Profiles", PAD, -PAD, "GameFontNormalLarge")
    local close = MakeButton(p, "X", 26, 22, 560 - PAD - 26, -PAD)
    close:SetScript("OnClick", function() p:Hide() end)
    p.closeBtn = close

    MakeLabel(p, "Current Profile", PAD, -46)
    local dd = CreateFrame("Frame", "GA_ProfileDropDown", p, "UIDropDownMenuTemplate")
    RegisterLayoutControl(dd, "Profiles Dropdown")
    dd:SetPoint("TOPLEFT", PAD - 16, -64)
    UIDropDownMenu_SetWidth(dd, 220)
    p.profileDD = dd

    MakeLabel(p, "Create", PAD, -110)
    local newName = MakeEditBox(p, 220, PAD, -138)
    newName:SetText("")
    p.newNameBox = newName
    local createBtn = MakeButton(p, "Create", 80, 24, PAD + 230, -144)
    createBtn:SetScript("OnClick", function()
        local name = Trim(newName:GetText())
        if name == "" then
            print("|cffffcc00[GlowAuras]|r Enter a profile name.")
            return
        end
        EnsureProfileContainer()
        if GlowAurasDB.profiles[name] then
            print("|cffffcc00[GlowAuras]|r Profile already exists.")
            return
        end
        SnapshotRootToProfile()
        GlowAurasDB.profiles[name] = CloneTable(ProfileDefaults())
        p.selectedProfileName = name
        local ok, err = SwitchProfile(name, true)
        if not ok then
            print("|cffff4444[GlowAuras]|r Profile switch failed: " .. tostring(err))
            return
        end
        if UI.profileManager_Refresh then UI.profileManager_Refresh() end
        print(("|cff00ff00[GlowAuras]|r Created and switched to profile '%s'."):format(name))
    end)

    local deleteBtn = MakeButton(p, "Delete", 80, 24, PAD + 320, -144)
    deleteBtn:SetScript("OnClick", function()
        local name = p.selectedProfileName or currentProfileName
        if not name then
            print("|cffffcc00[GlowAuras]|r No profile selected.")
            return
        end
        OpenDeleteProfileConfirmPopup(name)
    end)

    p.charFS = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.charFS:SetPoint("TOPLEFT", PAD, -172)
    p.charFS:SetWidth(520)
    p.charFS:SetJustifyH("LEFT")
    RegisterLayoutControl(p.charFS, "Label: Character Assigned Profile")

    MakeLabel(p, "Export (current/selected)", PAD, -224)
    local exportBox, exportBoxWrap = MakeMultiLineEditBox(p, 520, 182, PAD, -252)
    p.exportBox = exportBox
    p.exportBoxWrap = exportBoxWrap
    local exportBtn = MakeButton(p, "Export", 100, 24, PAD, -252)
    exportBtn:SetScript("OnClick", function()
        local selectedName = p.selectedProfileName or currentProfileName
        local s, auraCount = ExportProfileString(selectedName)
        if not s then
            print("|cffff4444[GlowAuras]|r Failed to export profile.")
            return
        end
        exportBox:SetText(s)
        exportBox:SetFocus()
        if exportBox.SetCursorPosition then exportBox:SetCursorPosition(0) end
        if exportBox._gaScroll and exportBox._gaScroll.SetVerticalScroll then
            exportBox._gaScroll:SetVerticalScroll(0)
        end
        print(("|cff00ff00[GlowAuras]|r Exported %d auras from profile '%s'."):format(tonumber(auraCount) or 0, tostring(selectedName)))
    end)

    p.importNameBox = nil
    local importBtn = MakeButton(p, "Import", 80, 24, PAD + 118, -252)
    importBtn:SetScript("OnClick", function()
        local targetName = currentProfileName or "Default"
        local ok, result, auraCount = ImportProfileString(exportBox:GetText(), targetName)
        if not ok then
            print("|cffff4444[GlowAuras]|r Import failed: " .. tostring(result))
            return
        end
        p.selectedProfileName = result
        if result == currentProfileName then
            LoadProfileToRoot(result)
            RebuildSpellMap()
            if UI and UI.Refresh then UI:Refresh() end
        end
        if UI.profileManager_Refresh then UI.profileManager_Refresh() end
        print(("|cff00ff00[GlowAuras]|r Imported %d auras into profile '%s'."):format(tonumber(auraCount) or 0, tostring(result)))
    end)

    local function ProfileDropdownInit(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, name in ipairs(SortedProfileNames()) do
            info.text = name
            info.checked = ((p.selectedProfileName or currentProfileName) == name)
            info.func = function()
                p.selectedProfileName = name
                local ok, err = SwitchProfile(name, true)
                if not ok then
                    print("|cffff4444[GlowAuras]|r Profile switch failed: " .. tostring(err))
                    return
                end
                if UI.profileManager_Refresh then UI.profileManager_Refresh() end
                print(("|cff00ff00[GlowAuras]|r Switched profile to '%s'."):format(tostring(name)))
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(dd, ProfileDropdownInit)
    StyleDropdownText(dd)
    function UI.profileManager_Refresh()
        EnsureProfileContainer()
        UIDropDownMenu_Initialize(dd, ProfileDropdownInit)
        local selected = p.selectedProfileName or currentProfileName or "Default"
        UIDropDownMenu_SetText(dd, selected)
        StyleDropdownText(dd)

        p.charFS:SetText(("Current Profile: %s")
            :format(tostring(currentProfileName or "Default")))
    end

    p:SetScript("OnShow", function()
        p.selectedProfileName = currentProfileName or GlowAurasDB.activeProfile or "Default"
        if UI.profileManager_Refresh then UI.profileManager_Refresh() end
    end)
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
            RefreshOverlayVisuals()
        end,
        PlaceAbove
    )
end

local function EnsureCopyProfilePopup()
    if UI.copyProfilePopup then return end

    local p = CreateFrame("Frame", "GA_CopyProfilePopup", UIParent, "BackdropTemplate")
    p:SetSize(420, 170)
    p:SetFrameStrata("DIALOG")
    p:SetMovable(true)
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)
    p:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    p:SetBackdropColor(unpack(GUI_C.bg))
    p:SetBackdropBorderColor(unpack(GUI_C.borderDim))
    p:Hide()
    UI.copyProfilePopup = p

    local title = MakeLabel(p, "Copy Profile", 14, -14)
    p.titleFS = title

    local close = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    close:SetSize(26, 22)
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetText("X")
    local cfs = close:GetFontString()
    if cfs then cfs:SetTextColor(unpack(GUI_C.text)) end
    close:SetScript("OnClick", function() p:Hide() end)
    RegisterLayoutControl(close, "X")

    p.sourceFS = MakeLabel(p, "From: (none)", 14, -48, "GameFontHighlightSmall")
    MakeLabel(p, "Copy To", 14, -74)

    local dd = CreateFrame("Frame", "GA_CopyProfileTargetDropDown", p, "UIDropDownMenuTemplate")
    RegisterLayoutControl(dd, "Copy Profile Target Dropdown")
    dd:SetPoint("TOPLEFT", -2, -96)
    UIDropDownMenu_SetWidth(dd, 220)
    p.targetDD = dd

    local copyBtn = MakeButton(p, "Copy", 90, 24, 250, -102)
    local cancelBtn = MakeButton(p, "Cancel", 90, 24, 346, -102)
    p.copyBtn = copyBtn
    p.cancelBtn = cancelBtn
    cancelBtn:SetScript("OnClick", function() p:Hide() end)

    local function TargetDropdownInit(self, level)
        local source = p.sourceProfileName or currentProfileName or "Default"
        local info = UIDropDownMenu_CreateInfo()
        for _, name in ipairs(SortedProfileNames()) do
            if name ~= source then
                info.text = name
                info.checked = (p.targetProfileName == name)
                info.func = function()
                    p.targetProfileName = name
                    UIDropDownMenu_SetText(dd, name)
                    StyleDropdownText(dd)
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end

    UIDropDownMenu_Initialize(dd, TargetDropdownInit)
    StyleDropdownText(dd)

    function p:Refresh()
        local source = p.sourceProfileName or currentProfileName or "Default"
        p.sourceFS:SetText("From: " .. tostring(source))
        UIDropDownMenu_Initialize(dd, TargetDropdownInit)

        if p.targetProfileName == source or not (p.targetProfileName and GlowAurasDB.profiles and GlowAurasDB.profiles[p.targetProfileName]) then
            p.targetProfileName = nil
            for _, name in ipairs(SortedProfileNames()) do
                if name ~= source then
                    p.targetProfileName = name
                    break
                end
            end
        end

        UIDropDownMenu_SetText(dd, p.targetProfileName or "(none)")
        StyleDropdownText(dd)
    end

    copyBtn:SetScript("OnClick", function()
        local source = p.sourceProfileName or currentProfileName or "Default"
        local target = p.targetProfileName
        if not target then
            print("|cffffcc00[GlowAuras]|r No target profile available to copy to.")
            return
        end
        local ok, err = CopyProfileToProfile(source, target)
        if not ok then
            print("|cffff4444[GlowAuras]|r Copy failed: " .. tostring(err))
            return
        end
        if UI.profileManager_Refresh then UI.profileManager_Refresh() end
        if p.Refresh then p:Refresh() end
        print(("|cff00ff00[GlowAuras]|r Copied profile '%s' to '%s'."):format(tostring(source), tostring(target)))
        p:Hide()
    end)

    local copyBtn = MakeButton(p, "Copy Profile", 110, 24, PAD + 424, -144)
    copyBtn:SetScript("OnClick", function()
        local source = p.selectedProfileName or currentProfileName
        if not source then
            print("|cffffcc00[GlowAuras]|r No source profile selected.")
            return
        end
        OpenCopyProfilePopup(source)
    end)
end

OpenCopyProfilePopup = function(sourceProfileName)
    EnsureCopyProfilePopup()
    local p = UI.copyProfilePopup
    p.sourceProfileName = sourceProfileName or currentProfileName or "Default"
    p.targetProfileName = nil
    if p.Refresh then p:Refresh() end
    if UI.frame and UI.frame:IsShown() then
        PlaceRightOf(UI.frame, p, 20, 0)
    else
        p:ClearAllPoints()
        p:SetPoint("CENTER")
    end
    p:Show()
    p:Raise()
end

local function EnsureDeleteProfileConfirmPopup()
    if UI.deleteProfileConfirmPopup then return end

    local p = CreateFrame("Frame", "GA_DeleteProfileConfirmPopup", UIParent, "BackdropTemplate")
    p:SetSize(420, 150)
    p:SetFrameStrata("DIALOG")
    p:SetMovable(true)
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)
    p:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    p:SetBackdropColor(unpack(GUI_C.bg))
    p:SetBackdropBorderColor(unpack(GUI_C.borderDim))
    p:Hide()
    UI.deleteProfileConfirmPopup = p

    MakeLabel(p, "Delete Profile", 14, -14)
    local close = MakeButton(p, "X", 26, 22, 420 - 14 - 26, -10)
    close:SetScript("OnClick", function() p:Hide() end)

    p.msg = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    p.msg:SetPoint("TOPLEFT", 14, -48)
    p.msg:SetWidth(392)
    p.msg:SetJustifyH("LEFT")
    p.msg:SetJustifyV("TOP")
    p.msg:SetTextColor(unpack(GUI_C.text))
    RegisterLayoutControl(p.msg, "Label: Delete Profile Confirm")

    local yesBtn = MakeButton(p, "Delete", 90, 24, 14, -108)
    local noBtn = MakeButton(p, "Cancel", 90, 24, 114, -108)
    p.yesBtn = yesBtn
    p.noBtn = noBtn
    noBtn:SetScript("OnClick", function() p:Hide() end)

    yesBtn:SetScript("OnClick", function()
        local name = p.profileName
        if not name then p:Hide() return end
        local ok, err = DeleteProfile(name)
        if not ok then
            print("|cffff4444[GlowAuras]|r " .. tostring(err))
            return
        end
        if UI.profileManager then
            UI.profileManager.selectedProfileName = currentProfileName or (SortedProfileNames()[1]) or "Default"
        end
        if UI.profileManager_Refresh then UI.profileManager_Refresh() end
        print(("|cffffcc00[GlowAuras]|r Deleted profile '%s'."):format(tostring(name)))
        p:Hide()
    end)
end

OpenDeleteProfileConfirmPopup = function(profileName)
    EnsureDeleteProfileConfirmPopup()
    local p = UI.deleteProfileConfirmPopup
    p.profileName = profileName
    p.msg:SetText(("Delete profile '%s'?\nThis cannot be undone."):format(tostring(profileName or "(none)")))
    if UI.frame and UI.frame:IsShown() then
        PlaceRightOf(UI.frame, p, 20, 0)
    else
        p:ClearAllPoints()
        p:SetPoint("CENTER")
    end
    p:Show()
    p:Raise()
end

local layoutEdit = {
    nextId = 1,
}

local DEFAULT_LAYOUT = {
    window = { w = 971.90368652344, h = 810.65374755859 },
    controls = {
        ["UI.header|FontString|Label: GlowAuras#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=12, y=-10.000000953674, w=81.967666625977, h=17.203054428101 },
        ["UI.header|FontString|Label: Version: 2.1#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=101.06809234619, y=-16.047889709473, w=65.776512145996, h=12.143363952637 },
        ["UI.header|Button|X#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=932.00012207031, y=-10.000000953674, w=26.000028610229, h=21.999980926514 },

        ["UI.sidebar|Button|Tab: Auras#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=8, y=-13.999999046326, w=163.99998474121, h=21.999980926514 },
        ["UI.sidebar|Button|Tab: Display#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=8, y=-42.000003814697, w=163.99998474121, h=21.999980926514 },
        ["UI.sidebar|Button|Tab: Actions#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=8, y=-70.000015258789, w=163.99998474121, h=21.999980926514 },
        ["UI.sidebar|Button|Tab: Profiles#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=8, y=-116.00001525879, w=163.99998474121, h=21.999980926514 },

        ["UI.topTabs|Button|Tab: Main#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=0, y=0, w=89.999984741211, h=21.999980926514 },
        ["UI.topTabs|Button|Tab: Display#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=102.04782104492, y=1.0120011568069, w=100.00001525879, h=21.999980926514 },
        ["UI.topTabs|Button|Tab: Sound#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=210.46241760254, y=-1.0120011568069, w=89.999984741211, h=21.999980926514 },
        ["UI.topTabs|Button|Tab: Profiles#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=308.46243286133, y=-1.0120011568069, w=109.99999237061, h=21.999980926514 },

        ["UI.subTabs|Button|Tab: Aura#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=0, y=0, w=69.999992370605, h=21.999980926514 },
        ["UI.subTabs|Button|Tab: Trigger#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=76.000015258789, y=0, w=80.000007629395, h=21.999980926514 },
        ["UI.subTabs|Button|Tab: Display#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=162.00003051758, y=0, w=84.999931335449, h=21.999980926514 },
        ["UI.subTabs|Button|Tab: Actions#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=253.00001525879, y=0, w=82.000030517578, h=21.999980926514 },

        ["UI.configPageDisplay|FontString|Label: Display#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=14, y=-14 },
        ["UI.configPageAuras|FontString|Label: Main#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=14, y=-14 },
        ["UI.configPageActions|FontString|Label: Sound#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=14, y=-14 },
        ["UI.profileManager|FontString|Label: Profiles#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=9.9522228240967, y=49.752758026123 },
        ["UI.profileManager|FontString|Label: Current Profile#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=9.952166557312, y=-22.725357055664 },
        ["UI.profileManager|Frame|Profiles Dropdown#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=-8.071605682373, y=-54.89245223999, w=270.00006103516, h=32.000007629395 },
        ["UI.profileManager|EditBox|EditBox#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=14, y=-138, w=219.99993896484, h=29.999984741211 },
        ["UI.profileManager|Button|Create#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=242.98797607422, y=-138.94036865234, w=80.000007629395, h=24.000003814697 },
        ["UI.profileManager|Button|Delete#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=328.9401550293, y=-138.9402923584, w=80.000007629395, h=24.000003814697 },
        ["UI.profileManager|FontString|Label: Character Assigned Profile#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=10.964224815369, y=13.186346054077, w=520.00006103516, h=12.143363952637 },
        ["UI.profileManager|EditBox|EditBox#3"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=12.837792396545, y=-205.04437255859, w=139.99989318848, h=29.999984741211 },
        ["UI.profileManager|FontString|Label: Export (current/selected)#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=9.9523391723633, y=-224 },
        ["UI.profileManager|Frame|Profile Export Box#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=10.964169502258, y=-284, w=520.00012207031, h=182 },
        ["UI.profileManager|Button|Export#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=7.9282231330872, y=-252, w=100.00001525879, h=24.000003814697 },
        ["UI.profileManager|Button|Import#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=120.33602142334, y=-252, w=80.000007629395, h=24.000003814697 },

        ["UI.configPageAuras|FontString|Label: Aura#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=14, y=-34 },
        ["UI.configPageAuras|Frame|Main Aura Dropdown#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=-2, y=-72.000007629395, w=350.00003051758, h=32.000007629395 },
        ["UI.configPageAuras|Button|New Aura#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=360, y=-72, w=110, h=26.000028610229 },
        ["UI.configPageAuras|Button|Delete#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=480, y=-72, w=90.000038146973, h=26.000028610229 },
        ["UI.configPageAuras|CheckButton|Main Enable Selected Aura#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=199.18615722656, y=-109.71339416504 },
        ["UI.configPageAuras|FontString|Label: Enable/Disable Aura#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=10.964054107666, y=-117.05967712402 },
        ["UI.configPageAuras|Button|Re-learn#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=580, y=-72, w=90.000038146973, h=26.000028610229 },
        ["UI.configPageAuras|FontString|Label: Toggles#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=14, y=-196.89250183105 },
        ["UI.configPageAuras|CheckButton|Main Show Text#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=14, y=-228 },
        ["UI.configPageAuras|CheckButton|Main Play Sound#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=164, y=-228 },
        ["UI.configPageAuras|CheckButton|Main Show Background#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=314, y=-228 },
        ["UI.configPageAuras|CheckButton|Main Show Icon#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=464.00003051758, y=-228 },
        ["UI.configPageAuras|FontString|Label: Actions#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=17.035888671875, y=-291.1552734375 },
        ["UI.configPageAuras|Button|Test#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=125.31428527832, y=-327.27478027344, w=90.000038146973, h=26.000028610229 },
        ["UI.configPageAuras|Button|Hide#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=14.829158782959, y=-328.28677368164, w=90.000038146973, h=26.000028610229 },

        ["UI.configPageDisplay|FontString|Label: Aura#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=14, y=-42.095779418945 },
        ["UI.configPageDisplay|Frame|Aura Dropdown#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=-2, y=-67.952125549316, w=350.00003051758, h=32.000007629395 },
        ["UI.configPageDisplay|FontString|Label: Message#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=16.023946762085, y=-112.04781341553 },
        ["UI.configPageDisplay|EditBox|EditBox#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=17.035888671875, y=-143.10758972168, w=500.00012207031, h=29.999984741211 },
        ["UI.configPageDisplay|FontString|Label: Icon#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=417.76681518555, y=-41.411182403564 },
        ["UI.configPageDisplay|Button|Choose Icon#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=358.06182861328, y=-72.470817565918, w=150, h=26.000028610229 },

        ["UI.configPageActions|FontString|Label: Aura#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=15.011832237244, y=-44.199592590332 },
        ["UI.configPageActions|Frame|Aura Dropdown#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=-9.083532333374, y=-69.044616699219, w=350, h=32.000007629395 },
        ["UI.configPageActions|FontString|Label: Search#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=14, y=-128 },
        ["UI.configPageActions|EditBox|EditBox#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=76, y=-120, w=260, h=29.999984741211 },
        ["UI.configPageActions|Button|Preview#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=350, y=-126, w=90, h=24.000003814697 },

        ["UI.alertEditor|FontString|Label: Text Align#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=49.41809463501, y=-17.035774230957 },
        ["UI.alertEditor|Frame|Display Text Align Dropdown#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=-4.3738980293274, y=-44.191097259521, w=170, h=32.000007629395 },
        ["UI.alertEditor|CheckButton|Display Anchor Text To Icon#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=-4.2149338722229, y=37.051128387451 },
        ["UI.alertEditor|FontString|Label: Text Position#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=209.88024902344, y=-16.605623245239 },
        ["UI.alertEditor|Frame|Display Text Position Dropdown#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=171.42332458496, y=-44.77307510376, w=170.00006103516, h=32.000007629395 },
        ["UI.alertEditor|Button|Font Colour#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=358.68618774414, y=-46.334403991699, w=109.99999237061, h=24.000003814697 },
        ["UI.alertEditor|Button|BG Colour#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=711.01940917969, y=-48.988178253174, w=99.999969482422, h=24.000003814697 },
        ["UI.alertEditor|CheckButton|Display Anchor BG To Text#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=648, y=-52, w=32.000007629395, h=32.000007629395 },
        ["UI.alertEditor|Slider|Width#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=569.55865478516, y=123.61657714844, w=300 },
        ["UI.alertEditor|Slider|Height#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=569.55877685547, y=81.688011169434, w=300 },
        ["UI.alertEditor|Slider|BG Size X#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=557.41528320312, y=-97.865333557129, w=300 },
        ["UI.alertEditor|Slider|BG Size Y#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=558.42749023438, y=-150.92497253418, w=300 },
        ["UI.alertEditor|Slider|BG X#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=558.42749023438, y=-203.98457336426, w=300 },
        ["UI.alertEditor|Slider|BG Y#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=558.42749023438, y=-257.04415893555, w=300 },
        ["UI.alertEditor|Slider|Length (sec)#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=566.52294921875, y=175.43579101562, w=300 },
        ["UI.alertEditor|FontString|Label: 0 = Show Until Proc Used#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=615, y=159 },
        ["UI.alertEditor|Slider|Text X#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=-2.3007953166962, y=-103.05967712402, w=300 },
        ["UI.alertEditor|Slider|Text Y#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=-2.3007953166962, y=-144.98805236816, w=300 },
        ["UI.alertEditor|Slider|Font Size#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=1.7470948696136, y=-190.96421813965, w=299.99996948242 },
        ["UI.alertEditor|Slider|Text Gap#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=0.73497915267944, y=-230.86856079102, w=300 },
        ["UI.alertEditor|Slider|Icon Size#1"] = { point="TOPLEFT", relativePoint="TOPLEFT", x=573.49694824219, y=31.799011230469, w=300 },
    }
}

local function LayoutParentTag(parent)
    if not parent then return "nil" end
    if UI then
        if parent == UI.frame then return "UI.frame" end
        if parent == UI.header then return "UI.header" end
        if parent == UI.sidebar then return "UI.sidebar" end
        if parent == UI.contentWrap then return "UI.contentWrap" end
        if parent == UI.topTabs then return "UI.topTabs" end
        if parent == UI.subTabs then return "UI.subTabs" end
        if parent == UI.configPageAuras then return "UI.configPageAuras" end
        if parent == UI.configPageDisplay then return "UI.configPageDisplay" end
        if parent == UI.configPageActions then return "UI.configPageActions" end
        if parent == UI.configPageProfiles then return "UI.configPageProfiles" end
        if parent == UI.alertEditor then return "UI.alertEditor" end
        if parent == UI.profileManager then return "UI.profileManager" end
    end
    return parent.GetName and parent:GetName() or tostring(parent)
end

local function ApplyDefaultLayoutControl(f, ot, label)
    if not f then return end
    local key = f._gaDefaultLayoutKey
    if not key then
        layoutEdit._keySeen = layoutEdit._keySeen or {}
        local parentTag = LayoutParentTag(f:GetParent())
        local base = ("%s|%s|%s"):format(parentTag, tostring(ot or (f.GetObjectType and f:GetObjectType()) or "?"), tostring(label or f._gaLayoutLabel or ""))
        layoutEdit._keySeen[base] = (layoutEdit._keySeen[base] or 0) + 1
        key = ("%s#%d"):format(base, layoutEdit._keySeen[base])
        f._gaDefaultLayoutKey = key
    end
    f._gaLayoutKey = key
    local o = DEFAULT_LAYOUT and DEFAULT_LAYOUT.controls and DEFAULT_LAYOUT.controls[key]
    if not o then return end
    local rel = f:GetParent()
    f:ClearAllPoints()
    f:SetPoint(o.point or "TOPLEFT", rel, o.relativePoint or o.point or "TOPLEFT", o.x or 0, o.y or 0)
    if o.w and f.SetWidth then f:SetWidth(o.w) end
    if o.h and f.SetHeight then f:SetHeight(o.h) end
end

RegisterLayoutControl = function(f, label)
    if not f or f._gaLayoutRegistered then return f end
    if type(f.GetObjectType) ~= "function" then return f end
    local ot = f:GetObjectType()
    if ot ~= "Frame" and ot ~= "Button" and ot ~= "CheckButton" and ot ~= "EditBox" and ot ~= "Slider" and ot ~= "ScrollFrame" and ot ~= "FontString" then
        return f
    end

    local id = ("c%03d"):format(layoutEdit.nextId)
    layoutEdit.nextId = layoutEdit.nextId + 1
    f._gaLayoutRegistered = true
    f._gaLayoutId = id
    f._gaLayoutLabel = label or (f.GetName and f:GetName()) or id
    ApplyDefaultLayoutControl(f, ot, f._gaLayoutLabel)
    return f
end

local function LayoutAlertEditorEmbedded(ed)
    if not ed then return end

    -- The Display tab already provides top-level Message + Choose Icon rows.
    if ed.alertTextLabel then ed.alertTextLabel:Hide() end
    if ed.msgBox then ed.msgBox:Hide() end

    if ed.textAlignLabel then
        ed.textAlignLabel:Show()
        ed.textAlignLabel:ClearAllPoints()
        ed.textAlignLabel:SetPoint("TOPLEFT", 18, -16)
    end
    if ed.alignDD then
        ed.alignDD:ClearAllPoints()
        ed.alignDD:SetPoint("TOPLEFT", 108, -30)
    end

    if ed.cbAnchor then
        ed.cbAnchor:ClearAllPoints()
        ed.cbAnchor:SetPoint("TOPLEFT", 14, -54)
    end
    if ed.cbBgAnchor then
        ed.cbBgAnchor:ClearAllPoints()
        ed.cbBgAnchor:SetPoint("TOPLEFT", 648, -52)
    end

    if ed.textPosLabel then
        ed.textPosLabel:Show()
        ed.textPosLabel:ClearAllPoints()
        ed.textPosLabel:SetPoint("TOPLEFT", 214, -48)
    end
    if ed.posDD then
        ed.posDD:ClearAllPoints()
        ed.posDD:SetPoint("TOPLEFT", 300, -66)
    end

    if ed.fontColorBtn then
        ed.fontColorBtn:ClearAllPoints()
        ed.fontColorBtn:SetPoint("TOPLEFT", 466, -20)
        ed.fontColorBtn:Show()
    end
    if UI.edFontColorSwatch then
        UI.edFontColorSwatch:ClearAllPoints()
        UI.edFontColorSwatch:SetPoint("LEFT", ed.fontColorBtn, "RIGHT", 8, 0)
        UI.edFontColorSwatch:Show()
    end
    if ed.bgColorBtn then
        ed.bgColorBtn:ClearAllPoints()
        ed.bgColorBtn:SetPoint("TOPLEFT", 654, -20)
        ed.bgColorBtn:Show()
    end
    if ed.lengthHelpFS then
        ed.lengthHelpFS:Show()
    end
    if UI.edBgColorSwatch then
        UI.edBgColorSwatch:ClearAllPoints()
        UI.edBgColorSwatch:SetPoint("LEFT", ed.bgColorBtn, "RIGHT", 8, 0)
        UI.edBgColorSwatch:Show()
    end

    -- Default layout is the single source of truth for embedded editor positions.
    local overrides = {
        ed.alignDD, ed.cbAnchor, ed.posDD, ed.fontColorBtn, ed.bgColorBtn,
        ed.cbBgAnchor,
        ed.wSlider, ed.hSlider, ed.bgWSlider, ed.bgHSlider, ed.bgXSlider, ed.bgYSlider, ed.dSlider,
        ed.lengthHelpFS,
        ed.iconSizeSlider, ed.txSlider, ed.tySlider, ed.fsSlider, ed.gapSlider,
        ed.textAlignLabel, ed.textPosLabel
    }
    for _, f in ipairs(overrides) do
        if f and f._gaLayoutLabel then
            ApplyDefaultLayoutControl(f, (f.GetObjectType and f:GetObjectType()) or nil, f._gaLayoutLabel)
        end
    end
end

------------------------------------------------------------
-- Main Config UI
------------------------------------------------------------
local function SetActiveAuraKey(k)
    if k and GlowAurasDB.auras[k] then
        GlowAurasDB.activeAuraKey = k
        if UI.Refresh then UI:Refresh() end

        if UI.SoundPicker_UpdateList then UI.SoundPicker_UpdateList() end
        if UI.alertEditor and UI.alertEditor:IsShown() and UI.frame and UI.frame:IsShown() then
            if UI.alertEditor.SyncSliders then UI.alertEditor:SyncSliders() end
        end
        if UI.newAuraPopup and UI.newAuraPopup:IsShown() and UI.frame and UI.frame:IsShown() then
            PlaceAbove(UI.frame, UI.newAuraPopup, 20, 0)
        end
        if GA_IconPicker and GA_IconPicker.frame and GA_IconPicker.frame:IsShown() then
            PlaceRightOf(UI.frame, GA_IconPicker.frame, 20, 0)
        end
        RefreshAllAuraOverlayPreviews()
    end
end

local function EnsureConfig()
    if UI.frame then return end

    local frame = CreateFrame("Frame", "GA_Config", UIParent, "BackdropTemplate")
    if DEFAULT_LAYOUT and DEFAULT_LAYOUT.window then
        frame:SetSize(DEFAULT_LAYOUT.window.w or 980, DEFAULT_LAYOUT.window.h or 840)
    else
        frame:SetSize(980, 840)
    end
    frame:SetResizable(true)
    if frame.SetMinResize then frame:SetMinResize(760, 560) end
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
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
    frame:SetBackdropColor(unpack(GUI_C.bg))
    frame:SetBackdropBorderColor(unpack(GUI_C.borderDim))
    frame:Hide()
    UI.frame = frame

    local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 6, -6)
    header:SetPoint("TOPRIGHT", -6, -6)
    header:SetHeight(44)
    header:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    header:SetBackdropColor(unpack(GUI_C.bgDark))
    header:SetBackdropBorderColor(unpack(GUI_C.borderDim))
    UI.header = header

    local sidebar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    sidebar:SetPoint("BOTTOMLEFT", 6, 6)
    sidebar:SetWidth(180)
    sidebar:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    sidebar:SetBackdropColor(unpack(GUI_C.bgDark))
    sidebar:SetBackdropBorderColor(unpack(GUI_C.borderDim))
    sidebar:Hide()
    UI.sidebar = sidebar

    local contentWrap = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    contentWrap:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    contentWrap:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
    contentWrap:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    contentWrap:SetBackdropColor(GUI_C.bgLight[1], GUI_C.bgLight[2], GUI_C.bgLight[3], 0.85)
    contentWrap:SetBackdropBorderColor(unpack(GUI_C.borderDim))
    UI.contentWrap = contentWrap

    local topTabs = CreateFrame("Frame", nil, contentWrap)
    topTabs:SetPoint("TOPLEFT", 8, -8)
    topTabs:SetPoint("TOPRIGHT", -8, -8)
    topTabs:SetHeight(28)
    UI.topTabs = topTabs

    local subTabs = CreateFrame("Frame", nil, contentWrap)
    subTabs:SetPoint("TOPLEFT", topTabs, "BOTTOMLEFT", 0, -8)
    subTabs:SetPoint("TOPRIGHT", topTabs, "BOTTOMRIGHT", 0, -8)
    subTabs:SetHeight(24)
    subTabs:Hide()
    UI.subTabs = subTabs

    local pageAuras = CreateFrame("Frame", nil, contentWrap, "BackdropTemplate")
    pageAuras:SetPoint("TOPLEFT", contentWrap, "TOPLEFT", 10, -42)
    pageAuras:SetPoint("BOTTOMRIGHT", contentWrap, "BOTTOMRIGHT", -10, 10)
    pageAuras:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    pageAuras:SetBackdropColor(GUI_C.bgLight[1], GUI_C.bgLight[2], GUI_C.bgLight[3], 0.70)
    pageAuras:SetBackdropBorderColor(unpack(GUI_C.borderDim))
    UI.configPageAuras = pageAuras

    local pageProfiles = CreateFrame("Frame", nil, contentWrap, "BackdropTemplate")
    pageProfiles:SetPoint("TOPLEFT", contentWrap, "TOPLEFT", 10, -42)
    pageProfiles:SetPoint("BOTTOMRIGHT", contentWrap, "BOTTOMRIGHT", -10, 10)
    pageProfiles:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    pageProfiles:SetBackdropColor(GUI_C.bgLight[1], GUI_C.bgLight[2], GUI_C.bgLight[3], 0.70)
    pageProfiles:SetBackdropBorderColor(unpack(GUI_C.borderDim))
    pageProfiles:Hide()
    UI.configPageProfiles = pageProfiles

    local pageDisplay = CreateFrame("Frame", nil, contentWrap, "BackdropTemplate")
    pageDisplay:SetPoint("TOPLEFT", contentWrap, "TOPLEFT", 10, -42)
    pageDisplay:SetPoint("BOTTOMRIGHT", contentWrap, "BOTTOMRIGHT", -10, 10)
    pageDisplay:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    pageDisplay:SetBackdropColor(GUI_C.bgLight[1], GUI_C.bgLight[2], GUI_C.bgLight[3], 0.70)
    pageDisplay:SetBackdropBorderColor(unpack(GUI_C.borderDim))
    if pageDisplay.SetClipsChildren then pageDisplay:SetClipsChildren(true) end
    pageDisplay:Hide()
    UI.configPageDisplay = pageDisplay

    local pageActions = CreateFrame("Frame", nil, contentWrap, "BackdropTemplate")
    pageActions:SetPoint("TOPLEFT", contentWrap, "TOPLEFT", 10, -42)
    pageActions:SetPoint("BOTTOMRIGHT", contentWrap, "BOTTOMRIGHT", -10, 10)
    pageActions:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    pageActions:SetBackdropColor(GUI_C.bgLight[1], GUI_C.bgLight[2], GUI_C.bgLight[3], 0.70)
    pageActions:SetBackdropBorderColor(unpack(GUI_C.borderDim))
    pageActions:Hide()
    UI.configPageActions = pageActions

    local title = MakeLabel(header, "GlowAuras", 12, -10, "GameFontNormalLarge")
    title:SetTextColor(unpack(GUI_C.text))
    local versionFS = MakeLabel(header, "Version: 2.1", 180, -12, "GameFontHighlightSmall")
    versionFS:SetTextColor(unpack(GUI_C.textDim))

    local close = MakeButton(header, "X", 26, 22, 980 - 6 - 6 - 26 - 10, -10)
    close:SetScript("OnClick", function()
        frame:Hide()
        HideAlert()
        HideAllOverlayPreviews()
        StopLearning()
        if UI.newAuraPopup and UI.newAuraPopup:IsShown() then UI.newAuraPopup:Hide() end
        if UI.alertEditor and UI.alertEditor:IsShown() then UI.alertEditor:Hide() end
        if GA_IconPicker and GA_IconPicker.frame and GA_IconPicker.frame:IsShown() then GA_IconPicker.frame:Hide() end
    end)

    local function UpdateEnabledHeaderToggle(btn)
        if not btn then return end
        if GlowAurasDB.enabled then
            btn.txt:SetText("Enabled")
            btn:SetBackdropBorderColor(unpack(GUI_C.accent))
        else
            btn.txt:SetText("Disabled")
            btn:SetBackdropBorderColor(unpack(GUI_C.danger))
        end
    end

    local function ApplyLockStateFromButton(locked)
        UI.overlayEditMode = not (locked and true or false)
        ApplyOverlaySettings(ActiveAuraKey())

        if not UI.overlayEditMode then
            HideAllOverlayPreviews()
            HideAlert()
        else
            RefreshAllAuraOverlayPreviews()
        end
    end

    local function UpdateLockHeaderToggle(btn)
        if not btn then return end
        local locked = not (UI.overlayEditMode and true or false)
        if locked then
            btn.txt:SetText("Locked")
            btn:SetBackdropBorderColor(unpack(GUI_C.accent))
        else
            btn.txt:SetText("Unlocked")
            btn:SetBackdropBorderColor(unpack(GUI_C.danger))
        end
    end

    local enabledBtn = CreateFrame("Button", nil, header, "BackdropTemplate")
    enabledBtn:SetSize(92, 22)
    enabledBtn:SetPoint("RIGHT", close, "LEFT", -8, 0)
    enabledBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    enabledBtn:SetBackdropColor(unpack(GUI_C.bgDark))
    enabledBtn.txt = enabledBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    enabledBtn.txt:SetPoint("CENTER")
    enabledBtn.txt:SetTextColor(unpack(GUI_C.text))
    enabledBtn:SetScript("OnClick", function(self)
        GlowAurasDB.enabled = not (GlowAurasDB.enabled and true or false)
        UpdateEnabledHeaderToggle(self)
        if UI.Refresh then UI:Refresh() end
    end)
    enabledBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(GUI_C.accent))
    end)
    enabledBtn:SetScript("OnLeave", function(self)
        UpdateEnabledHeaderToggle(self)
    end)
    UI.btnEnabledToggle = enabledBtn
    RegisterLayoutControl(enabledBtn, "Header Enabled Toggle")
    UpdateEnabledHeaderToggle(enabledBtn)

    local lockBtn = CreateFrame("Button", nil, header, "BackdropTemplate")
    lockBtn:SetSize(92, 22)
    lockBtn:SetPoint("RIGHT", enabledBtn, "LEFT", -8, 0)
    lockBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    lockBtn:SetBackdropColor(unpack(GUI_C.bgDark))
    lockBtn.txt = lockBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lockBtn.txt:SetPoint("CENTER")
    lockBtn.txt:SetTextColor(unpack(GUI_C.text))
    lockBtn:SetScript("OnClick", function(self)
        ApplyLockStateFromButton(UI.overlayEditMode)
        UpdateLockHeaderToggle(self)
        if UI.Refresh then UI:Refresh() end
    end)
    lockBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(GUI_C.accent))
    end)
    lockBtn:SetScript("OnLeave", function(self)
        UpdateLockHeaderToggle(self)
    end)
    UI.btnLockToggle = lockBtn
    RegisterLayoutControl(lockBtn, "Header Lock Toggle")
    UpdateLockHeaderToggle(lockBtn)

    local function SkinTab(btn, active)
        if not btn then return end
        if active then
            btn:GetNormalFontObject():SetTextColor(unpack(GUI_C.accent))
            btn:SetBackdropColor(unpack(GUI_C.bgDark))
            btn:SetBackdropBorderColor(unpack(GUI_C.accent))
        else
            btn:GetNormalFontObject():SetTextColor(unpack(GUI_C.text))
            btn:SetBackdropColor(unpack(GUI_C.bgDark))
            btn:SetBackdropBorderColor(unpack(GUI_C.borderDim))
        end
    end

    local function MakeFlatTab(parent, text, w, x, y, active)
        local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
        b:SetSize(w, 22)
        b:SetPoint("TOPLEFT", x, y)
        b:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        b:SetNormalFontObject("GameFontNormalSmall")
        b:SetHighlightFontObject("GameFontHighlightSmall")
        b:SetText(text)
        SkinTab(b, active)
        return RegisterLayoutControl(b, "Tab: " .. tostring(text))
    end

    local sideTabs = {
        MakeFlatTab(sidebar, "Auras",   164, 8, -14, true),
        MakeFlatTab(sidebar, "Display", 164, 8, -42, false),
        MakeFlatTab(sidebar, "Actions", 164, 8, -70, false),
        MakeFlatTab(sidebar, "Profiles",164, 8, -116, false),
    }
    local topTabButtons = {
        MakeFlatTab(topTabs, "Main",     90, 0,   0, true),
        MakeFlatTab(topTabs, "Display", 100, 102.04782104492, 1.0120011568069, false),
        MakeFlatTab(topTabs, "Sound", 90, 210.46241760254, -1.0120011568069, false),
        MakeFlatTab(topTabs, "Profiles",110, 308.46243286133, -1.0120011568069, false),
    }
    local subTabButtons = {
        MakeFlatTab(subTabs, "Aura",     70, 0, 0, true),
        MakeFlatTab(subTabs, "Trigger",  80, 76, 0, false),
        MakeFlatTab(subTabs, "Display",  85, 162, 0, false),
        MakeFlatTab(subTabs, "Actions",  82, 253, 0, false),
    }
    for _, b in ipairs(sideTabs) do
        b:SetScript("OnClick", function()
            for _, x in ipairs(sideTabs) do SkinTab(x, x == b) end
        end)
    end
    local function SetConfigPage(which)
        UI.configActivePage = which or "main"
        if UI.configPageAuras then UI.configPageAuras:SetShown(UI.configActivePage == "main") end
        if UI.configPageDisplay then UI.configPageDisplay:SetShown(UI.configActivePage == "display") end
        if UI.configPageActions then UI.configPageActions:SetShown(UI.configActivePage == "actions") end
        if UI.configPageProfiles then UI.configPageProfiles:SetShown(UI.configActivePage == "profiles") end
        if UI.profileManager and UI.profileManager:GetParent() == UI.configPageProfiles then
            if UI.configActivePage == "profiles" then
                UI.profileManager:Show()
                if UI.profileManager_Refresh then UI.profileManager_Refresh() end
            else
                UI.profileManager:Hide()
            end
        end
        if UI.alertEditor and UI.alertEditor:GetParent() == UI.configPageDisplay then
            if UI.configActivePage == "display" then
                LayoutAlertEditorEmbedded(UI.alertEditor)
                UI.alertEditor:Show()
            else
                UI.alertEditor:Hide()
            end
        end
        for i, x in ipairs(topTabButtons) do
            local active = (i == 1 and which == "main")
                or (i == 2 and which == "display")
                or (i == 3 and which == "actions")
                or (i == 4 and which == "profiles")
            SkinTab(x, active)
        end
    end
    topTabButtons[1]:SetScript("OnClick", function() SetConfigPage("main") end)
    topTabButtons[2]:SetScript("OnClick", function() SetConfigPage("display") end)
    topTabButtons[3]:SetScript("OnClick", function() SetConfigPage("actions") end)
    topTabButtons[4]:SetScript("OnClick", function() SetConfigPage("profiles") end)
    for _, b in ipairs(subTabButtons) do
        b:SetScript("OnClick", function()
            for _, x in ipairs(subTabButtons) do SkinTab(x, x == b) end
        end)
    end
    SetConfigPage("main")

    local mTitle = MakeLabel(pageAuras, "Main", PAD, -PAD, "GameFontNormalLarge")
    mTitle:SetTextColor(unpack(GUI_C.text))

    local dTitle = MakeLabel(pageDisplay, "Display", PAD, -PAD, "GameFontNormalLarge")
    dTitle:SetTextColor(unpack(GUI_C.text))

    local aTitle = MakeLabel(pageActions, "Sound", PAD, -PAD, "GameFontNormalLarge")
    aTitle:SetTextColor(unpack(GUI_C.text))

    EnsureProfileManager()
    if UI.profileManager then
        UI.profileManager:SetParent(pageProfiles)
        UI.profileManager:ClearAllPoints()
        UI.profileManager:SetPoint("TOPLEFT", pageProfiles, "TOPLEFT", 0, -58)
        UI.profileManager:SetPoint("BOTTOMRIGHT", pageProfiles, "BOTTOMRIGHT", 0, 0)
        UI.profileManager:SetMovable(false)
        UI.profileManager:SetBackdropColor(0, 0, 0, 0)
        UI.profileManager:SetBackdropBorderColor(0, 0, 0, 0)
        UI.profileManager:EnableMouse(true)
        if UI.profileManager.closeBtn then UI.profileManager.closeBtn:Hide() end
        UI.profileManager:Show()
    end
    UI.configProfilesInfo = nil
    function UI:RefreshProfilePage()
        if UI.profileManager_Refresh then UI.profileManager_Refresh() end
    end

    -- Global enable
    -- Global enabled toggle moved to header (Prototype-style)
    UI.cbGlobal = nil

    -- Lock overlay toggle moved to header (Prototype-style)
    UI.cbLock = nil

    -- Aura dropdown
    MakeLabel(pageAuras, "Aura", PAD, -34, "GameFontNormal")
    local dd = CreateFrame("Frame", "GA_AuraDropDown", pageAuras, "UIDropDownMenuTemplate")
    RegisterLayoutControl(dd, "Main Aura Dropdown")
    dd:SetPoint("TOPLEFT", PAD - 16, -72)
    UIDropDownMenu_SetWidth(dd, 300)
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
        if UI.auraDropdowns then
            for _, xdd in ipairs(UI.auraDropdowns) do
                UIDropDownMenu_Initialize(xdd, DropdownInit)
                UIDropDownMenu_SetText(xdd, ActiveAuraKey() and tostring(ActiveAuraKey()) or "(none)")
                StyleDropdownText(xdd)
            end
        else
            UIDropDownMenu_Initialize(dd, DropdownInit)
            UIDropDownMenu_SetText(dd, ActiveAuraKey() and tostring(ActiveAuraKey()) or "(none)")
            StyleDropdownText(dd)
        end
    end
    UI.auraDropdowns = { dd }

    local function AddAuraSelectorRow(parent, yLabel, yDD)
        MakeLabel(parent, "Aura", PAD, yLabel, "GameFontNormal")
        local xdd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
        xdd:SetPoint("TOPLEFT", PAD - 16, yDD)
        RegisterLayoutControl(xdd, "Aura Dropdown")
        UIDropDownMenu_SetWidth(xdd, 300)
        UI.auraDropdowns[#UI.auraDropdowns + 1] = xdd
        UIDropDownMenu_Initialize(xdd, DropdownInit)
        UIDropDownMenu_SetText(xdd, ActiveAuraKey() and tostring(ActiveAuraKey()) or "(none)")
        StyleDropdownText(xdd)
        return xdd
    end
    UI.ddDisplay = AddAuraSelectorRow(pageDisplay, -34, -72)
    UI.ddActions = AddAuraSelectorRow(pageActions, -112, -150)

    -- New aura (ABOVE)
    local newBtn = MakeButton(pageAuras, "New Aura", 110, 26, 360, -72)
    newBtn:SetScript("OnClick", function() ToggleNewAuraPopup(true) end)

    -- Delete aura
    local deleteBtn = MakeButton(pageAuras, "Delete", 90, 26, 480, -72)
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

        if UI.alertEditor and UI.alertEditor:IsShown() then UI.alertEditor:Hide() end
        if GA_IconPicker and GA_IconPicker.frame and GA_IconPicker.frame:IsShown() then GA_IconPicker.frame:Hide() end
        HideAlert()

        if UI.Refresh then UI:Refresh() end
    end)

    -- Aura enabled
    local cbAura = RegisterLayoutControl(CreateFrame("CheckButton", nil, pageAuras, "UICheckButtonTemplate"), "Main Enable Selected Aura")
    MakeLabel(pageAuras, "Enable/Disable Aura", PAD, -112, "GameFontNormal")
    cbAura:SetPoint("TOPLEFT", PAD, -134)
    cbAura.text:SetText("Enable aura")
    cbAura:SetScript("OnClick", function(btn)
        local aura = GetAura()
        if not aura then return end
        aura.enabled = btn:GetChecked() and true or false
    end)
    UI.cbAura = cbAura
    StyleCheckText(cbAura)

    local learnBtn = MakeButton(pageAuras, "Re-learn", 90, 26, 580, -72)
    learnBtn:SetScript("OnClick", function()
        local k = ActiveAuraKey()
        if not k then return end
        StartLearning(k)
        UI.spellFS:SetText(("GlowID: learning... trigger the proc now (%s)"):format(k))
    end)

    -- SpellID display + learn
    local spellFS = pageAuras:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spellFS:SetPoint("LEFT", learnBtn, "RIGHT", 12, 0)
    spellFS:SetWidth(260)
    spellFS:SetJustifyH("LEFT")
    UI.spellFS = spellFS

    -- Message
    MakeLabel(pageDisplay, "Message", PAD, -108, "GameFontNormal")
    local msgBox = MakeEditBox(pageDisplay, 500, PAD, -134)
    UI.msgBox = msgBox
    msgBox:SetScript("OnEnterPressed", function(box)
        local aura = GetAura()
        if not aura then return end
        aura.message = box:GetText()
        box:ClearFocus()
        if overlay and overlay:IsShown() and (aura.showText or false) then
            overlay.text:SetText(tostring(aura.message or "PROC!"))
        end
        RefreshOverlayVisuals()
    end)

    MakeLabel(pageAuras, "Toggles", PAD, -206, "GameFontNormal")
    -- toggles
    local cbText = RegisterLayoutControl(CreateFrame("CheckButton", nil, pageAuras, "UICheckButtonTemplate"), "Main Show Text")
    cbText:SetPoint("TOPLEFT", PAD, -228)
    cbText.text:SetText("Show text")
    cbText:SetScript("OnClick", function(btn)
        local aura = GetAura()
        if not aura then return end
        aura.showText = btn:GetChecked() and true or false
        RefreshOverlayVisuals()
    end)
    UI.cbText = cbText
    StyleCheckText(cbText)

    local cbSound = RegisterLayoutControl(CreateFrame("CheckButton", nil, pageAuras, "UICheckButtonTemplate"), "Main Play Sound")
    cbSound:SetPoint("TOPLEFT", PAD + 150, -228)
    cbSound.text:SetText("Play sound")
    cbSound:SetScript("OnClick", function(btn)
        local aura = GetAura()
        if not aura then return end
        aura.playSound = btn:GetChecked() and true or false
    end)
    UI.cbSound = cbSound
    StyleCheckText(cbSound)

    local cbBg = RegisterLayoutControl(CreateFrame("CheckButton", nil, pageAuras, "UICheckButtonTemplate"), "Main Show Background")
    cbBg:SetPoint("TOPLEFT", PAD + 300, -228)
    cbBg.text:SetText("Background")
    cbBg:SetScript("OnClick", function(btn)
        local aura = GetAura()
        if not aura then return end
        aura.showBackground = btn:GetChecked() and true or false
        ApplyOverlaySettings(ActiveAuraKey())
        RefreshOverlayVisuals()
    end)
    UI.cbBg = cbBg
    StyleCheckText(cbBg)

    -- Icon toggle + choose icon
    local cbIcon = RegisterLayoutControl(CreateFrame("CheckButton", nil, pageAuras, "UICheckButtonTemplate"), "Main Show Icon")
    cbIcon:SetPoint("TOPLEFT", PAD + 450, -228)
    cbIcon.text:SetText("Show icon")
    cbIcon:SetScript("OnClick", function(btn)
        local aura = GetAura()
        if not aura then return end
        aura.showIcon = btn:GetChecked() and true or false
        RefreshOverlayVisuals()
    end)
    UI.cbIcon = cbIcon
    StyleCheckText(cbIcon)

    MakeLabel(pageDisplay, "Icon", PAD, -176, "GameFontNormal")
    local iconBtn = MakeButton(pageDisplay, "Choose Icon", 150, 26, PAD, -202)
    iconBtn:SetScript("OnClick", function()
        EnsureIconPicker()
        if GA_IconPicker and GA_IconPicker.Toggle then
            GA_IconPicker:Toggle()
        end
    end)

    UI.iconPreviewTex = pageDisplay:CreateTexture(nil, "ARTWORK")
    UI.iconPreviewTex:SetSize(22, 22)
    UI.iconPreviewTex:SetPoint("LEFT", iconBtn, "RIGHT", 10, 0)
    UI.iconPreviewTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    -- Embedded Sound picker
    MakeLabel(pageActions, "Search", PAD, -128, "GameFontNormal")
    local soundSearch = MakeEditBox(pageActions, 260, PAD + 62, -120)
    soundSearch:SetText("")
    UI.soundSearch = soundSearch

    local previewBtn = MakeButton(pageActions, "Preview", 90, 24, PAD + 336, -126)
    previewBtn:SetScript("OnClick", function()
        local k = ActiveAuraKey()
        if not k then return end
        local aura = GetAura(k)
        if not aura then return end
        local was = aura.playSound
        aura.playSound = true
        PlayConfiguredSound(k)
        aura.playSound = was
    end)

    local soundListFrame = CreateFrame("Frame", nil, pageActions, "BackdropTemplate")
    soundListFrame:SetSize(430, 245)
    soundListFrame:SetPoint("TOPLEFT", PAD, -164)
    soundListFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    soundListFrame:SetBackdropColor(0, 0, 0, 0.25)
    soundListFrame:SetBackdropBorderColor(0.2, 0.25, 0.35, 1.0)
    RegisterLayoutControl(soundListFrame, "Sound List Frame")

    local soundScroll = CreateFrame("ScrollFrame", "GA_SoundScrollFrame", pageActions, "FauxScrollFrameTemplate")
    soundScroll:SetPoint("TOPLEFT", soundListFrame, "TOPLEFT", 0, -2)
    soundScroll:SetPoint("BOTTOMRIGHT", soundListFrame, "BOTTOMRIGHT", -26, 2)

    local ROW_H = 20
    local NUM_ROWS = 11
    UI.soundRows = {}

    for i = 1, NUM_ROWS do
        local row = CreateFrame("Button", nil, soundListFrame)
        row:SetSize(400, ROW_H)
        row:SetPoint("TOPLEFT", 8, -(i - 1) * ROW_H - 6)
        row:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight")

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 4, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWidth(390)

        UI.soundRows[i] = row
    end

    UI.allSounds = BuildSoundList()
    UI.filteredSounds = UI.allSounds

    local function ApplySoundFilter()
        local q = (soundSearch:GetText() or ""):lower()
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
        FauxScrollFrame_SetOffset(soundScroll, 0)
    end

    local function UpdateSoundList()
        local aura = GetAura()
        local items = UI.filteredSounds or UI.allSounds or {}
        local offset = FauxScrollFrame_GetOffset(soundScroll) or 0
        local total = #items

        FauxScrollFrame_Update(soundScroll, total, NUM_ROWS, ROW_H)

        for i = 1, NUM_ROWS do
            local idx = offset + i
            local row = UI.soundRows[i]
            local name = items[idx]

            if name then
                row:Show()
                row.soundName = name
                row.text:SetText(name)
                if aura and name == aura.sound then
                    row.text:SetTextColor(0.2, 1.0, 0.2)
                else
                    row.text:SetTextColor(0.85, 0.85, 0.85)
                end
                row:SetScript("OnClick", function()
                    local a = GetAura()
                    if not a then return end
                    a.sound = row.soundName
                    RefreshSelectedSoundLabels()
                    UpdateSoundList()
                end)
            else
                row:Hide()
                row.soundName = nil
            end
        end
    end

    soundScroll:SetScript("OnVerticalScroll", function(_, delta)
        FauxScrollFrame_OnVerticalScroll(soundScroll, delta, ROW_H, UpdateSoundList)
    end)

    soundSearch:SetScript("OnTextChanged", function()
        ApplySoundFilter()
        UpdateSoundList()
    end)

    UI.mainSoundLabel = pageActions:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.mainSoundLabel:SetPoint("TOPLEFT", soundListFrame, "BOTTOMLEFT", 4, -38)
    UI.mainSoundLabel:SetWidth(430)
    UI.mainSoundLabel:SetJustifyH("LEFT")
    UI.soundValueLabel = UI.mainSoundLabel

    UI.SoundPicker_UpdateList = UpdateSoundList
    UI.SoundPicker_ApplyFilter = ApplySoundFilter

    EnsureAlertEditor()
    if UI.alertEditor then
        local ed = UI.alertEditor
        ed:SetParent(pageDisplay)
        ed:ClearAllPoints()
        ed:SetPoint("TOPLEFT", pageDisplay, "TOPLEFT", PAD, -226)
        ed:SetSize(740, 500)
        ed:SetMovable(false)
        ed:RegisterForDrag()
        ed:SetBackdropColor(0, 0, 0, 0)
        ed:SetBackdropBorderColor(0, 0, 0, 0)
        if ed.closeBtn then ed.closeBtn:Hide() end
        if ed.titleFS then ed.titleFS:Hide() end
        if ed.resizeGrip then ed.resizeGrip:Hide() end
        LayoutAlertEditorEmbedded(ed)
        ed:Show()
    end

    -- Test/Hide
    MakeLabel(pageAuras, "Actions", PAD, -278, "GameFontNormal")
    local testBtn = MakeButton(pageAuras, "Test", 90, 26, PAD, -304)
    testBtn:SetScript("OnClick", function()
        local k = ActiveAuraKey()
        if not k then return end
        hideToken = hideToken + 1
        ShowAlert(k, false)
    end)

    local hideBtn = MakeButton(pageAuras, "Hide", 90, 26, PAD + 100, -304)
    hideBtn:SetScript("OnClick", function()
        hideToken = hideToken + 1
        HideAlert()
    end)

    function UI:Refresh()
        local auraKey = ActiveAuraKey()
        local aura = auraKey and GetAura(auraKey) or nil

        if UI.btnEnabledToggle then UpdateEnabledHeaderToggle(UI.btnEnabledToggle) end

        if aura then
            NormalizeAuraDisplay(aura)
            UI.cbAura:SetChecked(aura.enabled and true or false)
            if UI.cbAura and (UI.cbAura.text or UI.cbAura.Text) then
                local auraName = tostring(auraKey or ActiveAuraKey() or "aura")
                local cbAuraText = UI.cbAura.text or UI.cbAura.Text
                cbAuraText:SetText("Enable " .. auraName)
            end
            UI.cbText:SetChecked(aura.showText and true or false)
            if UI.cbIcon then UI.cbIcon:SetChecked(aura.showIcon and true or false) end
            UI.cbSound:SetChecked(aura.playSound and true or false)
            if UI.btnLockToggle then UpdateLockHeaderToggle(UI.btnLockToggle) end
            if UI.cbBg then UI.cbBg:SetChecked(aura.showBackground and true or false) end

            UI.iconPreviewTex:SetTexture(ResolveAuraIconTexture(aura))
            UpdateAuraColorSwatches()

            UI.msgBox:SetText(tostring(aura.message or "PROC!"))
            UI.spellFS:SetText("GlowID: " .. (aura.spellID and tostring(aura.spellID) or "(not learned)"))
            RefreshSelectedSoundLabels()
        else
            UI.spellFS:SetText("GlowID: (none)")
            if UI.cbAura and (UI.cbAura.text or UI.cbAura.Text) then
                local cbAuraText = UI.cbAura.text or UI.cbAura.Text
                cbAuraText:SetText("Enable aura")
            end
            if UI.msgBox then UI.msgBox:SetText("") end
            if UI.iconPreviewTex then UI.iconPreviewTex:SetTexture(nil) end
            if UI.edFontColorSwatch then SetSwatchColor(UI.edFontColorSwatch, {1,1,1,1}, {1,1,1,1}) end
            if UI.edBgColorSwatch then SetSwatchColor(UI.edBgColorSwatch, {0,0,0,0}, {0,0,0,0}) end
            if UI.fontColorSwatch then SetSwatchColor(UI.fontColorSwatch, {1,1,1,1}, {1,1,1,1}) end
            if UI.bgColorSwatch then SetSwatchColor(UI.bgColorSwatch, {0,0,0,0}, {0,0,0,0}) end
            if UI.mainSoundLabel then UI.mainSoundLabel:SetText("Selected: (none)") end
        end

        UI:Dropdown_Refresh()
        if UI.RefreshProfilePage then UI:RefreshProfilePage() end
        RefreshAllAuraOverlayPreviews()
    end

    frame:SetScript("OnShow", function()
        if UI.overlayEditMode == nil then UI.overlayEditMode = false end
        UI:Refresh()

        if UI.alertEditor and UI.alertEditor:GetParent() ~= pageDisplay and UI.alertEditor:IsShown() then PlaceRightOf(UI.frame, UI.alertEditor, 20, 0) end
        if UI.newAuraPopup and UI.newAuraPopup:IsShown() then PlaceAbove(UI.frame, UI.newAuraPopup, 20, 0) end
        if GA_IconPicker and GA_IconPicker.frame and GA_IconPicker.frame:IsShown() then PlaceRightOf(UI.frame, GA_IconPicker.frame, 20, 0) end
        RefreshAllAuraOverlayPreviews()
    end)
end

local function ToggleConfig()
    EnsureConfig()
    if UI.frame:IsShown() then
        UI.frame:Hide()
        if UI.alertEditor and UI.alertEditor:IsShown() then UI.alertEditor:Hide() end
        if UI.profileManager and UI.profileManager:IsShown() then UI.profileManager:Hide() end
        if UI.newAuraPopup and UI.newAuraPopup:IsShown() then UI.newAuraPopup:Hide() end
        if GA_IconPicker and GA_IconPicker.frame and GA_IconPicker.frame:IsShown() then GA_IconPicker.frame:Hide() end
        HideAlert()
        HideAllOverlayPreviews()
        UI.overlayEditMode = false
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
evt:RegisterEvent("PLAYER_LOGOUT")
evt:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
evt:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")

evt:SetScript("OnEvent", function(_, event, spellID)
    if event == "PLAYER_LOGIN" then
        InitDB()
        RebuildSpellMap()
        print("|cff00ff00[GlowAuras]|r Loaded. /ga to open settings.")
        return
    end

    if event == "PLAYER_LOGOUT" then
        SnapshotRootToProfile()
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





