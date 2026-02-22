-- GlowAuras_IconPicker.lua
-- Standalone Icon/Texture picker for GlowAuras (Retail 12.0+)
-- Opens ABOVE main (no overlap) and lets you choose:
--   - Spell icon by spellID or spell name (best-effort)
--   - Texture by fileID
--   - Texture by path (Interface\...)
-- Also shows/filters Recent picks.

GA_IconPicker = GA_IconPicker or {}
local IP = GA_IconPicker
local C = {
    bg        = {0.067, 0.094, 0.153, 0.97},
    bgLight   = {0.122, 0.161, 0.216, 1.0},
    bgDark    = {0.04,  0.06,  0.10,  1.0},
    borderDim = {0.17,  0.22,  0.30,  0.9},
    text      = {0.92,  0.95,  1.0,   1.0},
    textDim   = {0.75,  0.80,  0.88,  1.0},
}

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

local function MakeLabel(parent, text, x, y, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    local col = (template == "GameFontHighlightSmall") and C.textDim or C.text
    fs:SetTextColor(unpack(col))
    return fs
end

local function MakeButton(parent, text, w, h, x, y)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    local fs = b:GetFontString()
    if fs then fs:SetTextColor(unpack(C.text)) end
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

-- Best-effort spell icon lookup (12.0+ safe)
local function GetSpellTextureCompat(spellIDOrName)
    if spellIDOrName == nil then return nil end

    -- Numeric spellID
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

    -- Spell name (GetSpellInfo sometimes works with name)
    if type(_G.GetSpellInfo) == "function" then
        local ok, name, _, icon = pcall(_G.GetSpellInfo, tostring(spellIDOrName))
        if ok and icon then return icon end
    end

    return nil
end

local function GetSpellNameCompat(spellIDOrName)
    local sid = tonumber(spellIDOrName)
    if sid and _G.C_Spell and type(_G.C_Spell.GetSpellInfo) == "function" then
        local ok, info = pcall(_G.C_Spell.GetSpellInfo, sid)
        if ok and info and info.name then return info.name end
    end
    if type(_G.GetSpellInfo) == "function" then
        local ok, name = pcall(_G.GetSpellInfo, spellIDOrName)
        if ok and name then return name end
    end
    return nil
end

local function EnsureRecentDB()
    GlowAurasDB = GlowAurasDB or {}
    GlowAurasDB.recentIcons = GlowAurasDB.recentIcons or {}
end

local function PushRecent(entry)
    EnsureRecentDB()
    local r = GlowAurasDB.recentIcons
    -- de-dupe
    for i = #r, 1, -1 do
        local e = r[i]
        if e and e.kind == entry.kind and tostring(e.value) == tostring(entry.value) then
            table.remove(r, i)
        end
    end
    table.insert(r, 1, entry)
    while #r > 30 do table.remove(r) end
end

local function Matches(q, s)
    q = tostring(q or ""):lower()
    s = tostring(s or ""):lower()
    return q == "" or s:find(q, 1, true) ~= nil
end

-- Build candidate list from query + recents
local function BuildCandidates(query, currentAura)
    EnsureRecentDB()
    local q = Trim(query)
    local items = {}
    local seen = {}

    local function add(kind, value, label, tex)
        local key = kind .. ":" .. tostring(value)
        if seen[key] then return end
        seen[key] = true
        items[#items+1] = { kind = kind, value = value, label = label, tex = tex }
    end

    -- Current aura spell icon (handy)
    if currentAura and tonumber(currentAura.spellID) then
        local sid = tonumber(currentAura.spellID)
        local name = GetSpellNameCompat(sid) or ("Spell " .. sid)
        add("SPELL", sid, ("Spell: %s (%d)"):format(name, sid), GetSpellTextureCompat(sid))
    end

    -- If query is present, resolve direct candidates
    if q ~= "" then
        local asNum = tonumber(q)

        -- spellID
        if asNum then
            local tex = GetSpellTextureCompat(asNum)
            local name = GetSpellNameCompat(asNum) or ("Spell " .. asNum)
            if tex then
                add("SPELL", asNum, ("Spell: %s (%d)"):format(name, asNum), tex)
            end
            -- fileID texture
            add("FILE", asNum, ("Texture fileID: %d"):format(asNum), asNum)
        end

        -- texture path
        if q:find("\\") or q:find("/") then
            local path = q:gsub("/", "\\")
            add("PATH", path, ("Texture path: %s"):format(path), path)
        end

        -- spell name (best-effort)
        local tex = GetSpellTextureCompat(q)
        if tex then
            local name = GetSpellNameCompat(q) or q
            add("SPELLNAME", q, ("Spell name: %s"):format(name), tex)
        end
    end

    -- Recents (filtered)
    for _, e in ipairs(GlowAurasDB.recentIcons) do
        if e and e.kind and e.value then
            local label = e.label or (e.kind .. ": " .. tostring(e.value))
            local tex = e.tex
            if not tex then
                if e.kind == "SPELL" then tex = GetSpellTextureCompat(e.value)
                elseif e.kind == "SPELLNAME" then tex = GetSpellTextureCompat(e.value)
                else tex = e.value end
            end
            if Matches(q, label) or Matches(q, e.value) then
                add(e.kind, e.value, "Recent: " .. label, tex)
            end
        end
    end

    -- Fallback default
    add("PATH", "Interface\\Icons\\INV_Misc_QuestionMark", "Default: Question Mark", "Interface\\Icons\\INV_Misc_QuestionMark")

    return items
end

function IP:Ensure(mainFrame, getAuraFunc, onPickFunc, placeAboveFunc)
    if self.frame then return end

    self.mainFrame = mainFrame
    self.getAura = getAuraFunc
    self.onPick = onPickFunc
    self.placeAbove = placeAboveFunc

    local f = CreateFrame("Frame", "GA_IconPicker", UIParent, "BackdropTemplate")
    f:SetSize(520, 380)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)

    f:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(unpack(C.bg))
    f:SetBackdropBorderColor(unpack(C.borderDim))

    -- movable via title strip
    f:SetMovable(true)
    f:EnableMouse(true)
    local drag = CreateFrame("Frame", nil, f)
    drag:SetPoint("TOPLEFT", 6, -6)
    drag:SetPoint("TOPRIGHT", -40, -6)
    drag:SetHeight(26)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() f:StartMoving() end)
    drag:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

    MakeLabel(f, "Choose Icon / Texture", 12, -12, "GameFontNormalLarge")
    local close = MakeButton(f, "X", 26, 22, 520 - 12 - 26, -10)
    close:SetScript("OnClick", function() f:Hide() end)

    MakeLabel(f, "Search (spellID, spell name, fileID, or path)", 12, -46, "GameFontNormal")
    local search = MakeEditBox(f, 360, 12, -70)
    search:SetText("")
    self.search = search

    local preview = MakeButton(f, "Preview", 120, 24, 520 - 12 - 120, -70)
    preview:SetScript("OnClick", function()
        local aura = self.getAura and self.getAura()
        if not aura then return end
        if self.onPick then
            -- just re-apply current selection
            self.onPick(aura.iconKind, aura.iconValue, aura.iconLabel, aura.iconTex)
        end
    end)

    -- list frame
    local listFrame = CreateFrame("Frame", nil, f, "BackdropTemplate")
    listFrame:SetSize(494, 250)
    listFrame:SetPoint("TOPLEFT", 12, -112)
    listFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    listFrame:SetBackdropColor(C.bgDark[1], C.bgDark[2], C.bgDark[3], 0.75)
    listFrame:SetBackdropBorderColor(unpack(C.borderDim))

    local scroll = CreateFrame("ScrollFrame", "GA_IconScrollFrame", f, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -26, 2)

    local ROW_H = 22
    local NUM_ROWS = 10
    self.rows = {}

    for i = 1, NUM_ROWS do
        local row = CreateFrame("Button", nil, listFrame)
        row:SetSize(468, ROW_H)
        row:SetPoint("TOPLEFT", 8, -(i - 1) * ROW_H - 6)
        row:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight")

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", 2, 0)

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWidth(430)

        self.rows[i] = row
    end

    self.items = {}
    self.filtered = {}

    local function ApplyFilterAndBuild()
        local aura = self.getAura and self.getAura() or nil
        local q = search:GetText() or ""
        self.items = BuildCandidates(q, aura)
        self.filtered = self.items
        FauxScrollFrame_SetOffset(scroll, 0)
    end

    local function UpdateList()
        local offset = FauxScrollFrame_GetOffset(scroll) or 0
        local total = #self.filtered
        FauxScrollFrame_Update(scroll, total, NUM_ROWS, ROW_H)

        for i = 1, NUM_ROWS do
            local idx = offset + i
            local row = self.rows[i]
            local it = self.filtered[idx]

            if it then
                row:Show()
                row._item = it
                row.text:SetText(it.label or (it.kind .. ": " .. tostring(it.value)))

                local tex = it.tex
                if not tex then
                    if it.kind == "SPELL" or it.kind == "SPELLNAME" then tex = GetSpellTextureCompat(it.value) end
                    if it.kind == "FILE" then tex = tonumber(it.value) end
                    if it.kind == "PATH" then tex = tostring(it.value) end
                end
                row.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")

                row:SetScript("OnClick", function()
                    local aura = self.getAura and self.getAura()
                    if not aura then return end
                    -- store selection on aura (so Preview works even if picker closed)
                    aura.iconKind  = it.kind
                    aura.iconValue = it.value
                    aura.iconLabel = it.label
                    aura.iconTex   = tex

                    PushRecent({ kind = it.kind, value = it.value, label = it.label, tex = tex })

                    if self.onPick then
                        self.onPick(it.kind, it.value, it.label, tex)
                    end
                    f:Hide()
                end)
            else
                row:Hide()
                row._item = nil
            end
        end
    end

    scroll:SetScript("OnVerticalScroll", function(_, delta)
        FauxScrollFrame_OnVerticalScroll(scroll, delta, ROW_H, UpdateList)
    end)

    search:SetScript("OnTextChanged", function()
        ApplyFilterAndBuild()
        UpdateList()
    end)

    local ok = MakeButton(f, "OK", 90, 24, 12, -312)
    ok:SetScript("OnClick", function() f:Hide() end)

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("LEFT", ok, "RIGHT", 12, 0)
    hint:SetWidth(400)
    hint:SetJustifyH("LEFT")
    hint:SetText("Tip: type a spellID (e.g. 124682) or a texture path (Interface\\Icons\\...).")

    f:SetScript("OnShow", function()
        if self.placeAbove and self.mainFrame then
            self.placeAbove(self.mainFrame, f, 20, 0)
        end
        search:SetText("")
        ApplyFilterAndBuild()
        UpdateList()
    end)

    f:Hide()
    self.frame = f
    self._apply = ApplyFilterAndBuild
    self._update = UpdateList
end

function IP:Toggle()
    if not self.frame then return end
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self.frame:Show()
    end
end
