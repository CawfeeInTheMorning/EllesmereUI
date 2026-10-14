if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_GroupFinder_Rail.lua
--  Dungeons & Raids rail entries in the house button look with their art,
--  and the window's bottom tabs flush left.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local CM = EllesmereUI

local FFD = setmetatable({}, { __mode = "k" })
local ART = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\rail\\"
local BOX_H = 75      -- the box's height (the art's 300 px / 4); a little taller than Blizzard's 72
local NAME_X = 12    -- the name's inset from the box's left
local GAP = 3        -- the search rows' gap (Search.lua SQ_GAP)
-- Art per entry, by the name Blizzard gives it (the entries move around:
-- Scenarios, when shown, takes slot 2).
local function ArtFor(btn)
    local name = btn.name and btn.name:GetText()
    if not name then return nil end
    if name == LOOKING_FOR_DUNGEON_PVEFRAME then return "dungeon-finder.png" end
    if name == RAID_FINDER_PVEFRAME then return "raid-finder.png" end
    if name == LFGLIST_NAME then return "premade-groups.png" end
    return nil
end

local function RailButton(i)
    local gf = _G.GroupFinderFrame
    return gf and (gf["groupButton" .. i] or _G["GroupFinderFrameGroupButton" .. i])
end

-- The host skin re-strips these buttons whenever Blizzard repaints them, fading
-- every texture on them it does not know (alpha 0), ours included: ours go
-- straight back to full alpha (our own textures, so hooking them is safe).
local function Keep(tex)
    hooksecurefunc(tex, "SetAlpha", function(t, a)
        if a ~= 1 and not FFD[t] then
            FFD[t] = true
            t:SetAlpha(1)
            FFD[t] = nil
        end
    end)
    return tex
end

local PaintBorder   -- below

local function Style(btn, i)
    if not btn or (btn.IsForbidden and btn:IsForbidden()) or FFD[btn] then return end
    local d = {}
    FFD[btn] = d
    -- The drawn box: inset from the rail's sides by the search panel's side
    -- padding, as the Premade Groups category buttons (Questing ...
    d.box = CreateFrame("Frame", nil, btn)
    d.box:EnableMouse(false)
    d.bg = Keep(btn:CreateTexture(nil, "BACKGROUND", nil, 7))
    d.bg:SetAllPoints(d.box)
    d.bg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
    d.art = Keep(btn:CreateTexture(nil, "BORDER", nil, -8))
    d.art:SetAllPoints(d.box)
    local S = ns.Skin and ns.Skin()
    if S and S.AddBorder then
        S.AddBorder(d.box)
    elseif CM.MakeBorder then
        local r, g, b, a = 0.2, 0.2, 0.2, 1
        if ns.ThemeBorder then r, g, b, a = ns.ThemeBorder() end
        CM.MakeBorder(d.box, r, g, b, a, CM.PanelPP)
    end
    d.hover = Keep(btn:CreateTexture(nil, "HIGHLIGHT"))
    d.hover:SetAllPoints(d.box)
    d.hover:SetColorTexture(1, 1, 1, 0.1)
    -- A white border while hovered or selected (the theme's otherwise).
    d.index = i
    btn:HookScript("OnEnter", function(self) FFD[self].hovered = true; PaintBorder(self) end)
    btn:HookScript("OnLeave", function(self) FFD[self].hovered = nil; PaintBorder(self) end)
end

-- Selected = Blizzard's GroupFinderFrame.selectionIndex (set by
-- GroupFinderFrame_SelectGroupButton, post-hooked below).
PaintBorder = function(btn)
    local d = btn and FFD[btn]
    local PP = CM.PanelPP or CM.PP
    if not (d and d.box and PP and PP.SetBorderColor) then return end
    local gf = _G.GroupFinderFrame
    local open = ns.RailPageOpen and ns.RailPageOpen()
    local selected
    if d.page then
        selected = open == d.page.key
    else
        selected = not open and gf and gf.selectionIndex == d.index
        -- The host skin's selected wash (moved onto our box) off while a
        -- page of ours is the one showing.
        if d.selWash then d.selWash:SetAlpha(open and 0 or 1) end
    end
    if d.hovered or selected then
        PP.SetBorderColor(d.box, 1, 1, 1, 1)
    else
        local r, g, b, a = 0.2, 0.2, 0.2, 1
        if ns.ThemeBorder then r, g, b, a = ns.ThemeBorder() end
        PP.SetBorderColor(d.box, r, g, b, a)
    end
end

-- The full-width backgrounds behind our box: Blizzard's own (bg,
-- "bluemenu-main") and the host skin's card ("Ui-Dialog-New-Background", which
-- the skin re-fades to its own alpha on theme changes).
local CARD_ATLAS = "Ui-Dialog-New-Background"
local function Hide(tex)
    if not tex or FFD[tex] ~= nil then return end
    FFD[tex] = false
    tex:SetAlpha(0)
    hooksecurefunc(tex, "SetAlpha", function(t, a)
        if a ~= 0 and FFD[t] == false then
            FFD[t] = 0
            t:SetAlpha(0)
            FFD[t] = false
        end
    end)
end
local function HideBackgrounds(btn)
    Hide(btn.bg)
    local regions = { btn:GetRegions() }
    local card
    for _, r in ipairs(regions) do
        if r.GetAtlas and r:GetAtlas() == CARD_ATLAS then
            card = r
            Hide(r)
        end
    end
    -- The host skin's selected-entry wash hangs off that card (full width):
    -- moved onto our box instead (it is only ever anchored once).
    local d = FFD[btn]
    if card and d and not d.selMoved then
        for _, r in ipairs(regions) do
            local _, rel = r:GetPoint(1)
            if rel == card and r ~= card then
                r:ClearAllPoints()
                r:SetAllPoints(d.box)
                d.selMoved = true
                d.selWash = r
            end
        end
    end
end

-- The box (side padding, BOX_H centred), the entry's art, Blizzard's icon
-- and ring faded and its name at the box's left; re-done on every show.
local function Place(btn)
    local d = btn and FFD[btn]
    if not d then return end
    local pad = tonumber(ns.Cfg and ns.Cfg().padding) or 12
    local h = btn:GetHeight() or BOX_H
    local dy = (h - BOX_H) / 2   -- negative: the box reaches past the button
    d.box:ClearAllPoints()
    d.box:SetPoint("TOPLEFT", btn, "TOPLEFT", pad, -dy)
    d.box:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -pad, dy)
    local art = ArtFor(btn)
    if d.page then art = d.page.art end
    if art then d.art:SetTexture(d.page and art or (ART .. art)) end
    d.art:SetShown(art ~= nil)
    if d.page then
        btn.name:ClearAllPoints()
        btn.name:SetPoint("LEFT", d.box, "LEFT", NAME_X, 0)
        btn.name:SetJustifyH("LEFT")
    elseif art then
        Hide(btn.icon)
        Hide(btn.ring)
        local name = btn.name
        if name then
            name:ClearAllPoints()
            name:SetPoint("LEFT", d.box, "LEFT", NAME_X, 0)
            name:SetJustifyH("LEFT")
        end
    end
end

-- The window's bottom tab row (Dungeons & Raids / Player vs.
local function AlignTabs()
    local pve = _G.PVEFrame
    if not pve or InCombatLockdown() then return end
    local prev
    for i = 1, 4 do
        local t = _G["PVEFrameTab" .. i]
        if t and t:IsShown() then
            t:ClearAllPoints()
            if prev then
                t:SetPoint("LEFT", prev, "RIGHT", 0, 0)
            else
                t:SetPoint("BOTTOMLEFT", pve, "BOTTOMLEFT", 0, -30)
            end
            prev = t
        end
    end
end

-- An entry of ours for an extra page: the size of Blizzard's, its name in
-- the font of theirs.
local function PageButton(spec)
    if spec.railButton then return spec.railButton end
    local gf, ref = _G.GroupFinderFrame, RailButton(1)
    if not (gf and ref) then return nil end
    local b = CreateFrame("Button", nil, gf)
    b:SetSize(ref:GetSize())
    b.name = b:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    local src = ref.name
    if src and src.GetFont then
        local path, size, flags = src:GetFont()
        if path then b.name:SetFont(path, size, flags) end
        b.name:SetTextColor(src:GetTextColor())
        b.name:SetShadowOffset(src:GetShadowOffset())
    end
    b.name:SetText(spec.label or spec.key)
    b:SetScript("OnClick", function() if ns.OpenRailPage then ns.OpenRailPage(spec) end end)
    Style(b)
    FFD[b].page = spec
    spec.railButton = b
    return b
end

-- With an extra page entry showing, the boxes are re-stacked with the gap
-- Blizzard's own entries have between them (measured), our entries last, the
-- stack centred on the rail below the search row (the M+ Applications bar's
-- row); if it does not fit, the gap shrinks (to one search gap at least).
local function LayoutRail()
    local gf = _G.GroupFinderFrame
    if not gf or InCombatLockdown() then return end
    local pages = {}
    for _, spec in ipairs(ns.railPages or {}) do
        if not ns.RailPageEnabled or ns.RailPageEnabled(spec) then
            pages[#pages + 1] = spec
        elseif spec.railButton then
            spec.railButton:Hide()
        end
    end
    local list = {}
    for i = 1, 4 do
        local b = RailButton(i)
        if b and b:IsShown() and FFD[b] then list[#list + 1] = b end
    end
    local function Restore()
        for _, b in ipairs(list) do
            Place(b)
            b:SetHitRectInsets(0, 0, 0, 0)
        end
    end
    local ref = list[1]
    local gt, gl = gf:GetTop(), gf:GetLeft()
    local lf = _G.LFGListFrame
    local lt = (lf and lf:GetTop()) or gt
    if #pages == 0 or not (ref and gt and gl and lt and ref:GetLeft()) then
        Restore()
        return
    end
    local pad = tonumber(ns.Cfg and ns.Cfg().padding) or 12
    local r1, h1 = -42, 24
    if ns.Search_Rows then
        local _
        r1, _, _, h1 = ns.Search_Rows()
        h1 = h1 or 24
    end
    local railTop = lt + r1 - h1 / 2          -- under the search row (and the M+ bar)
    local railBottom = (lf and lf:GetBottom()) or gf:GetBottom() or (railTop - 374)
    local n = #list + #pages
    -- Blizzard's gap between two boxes: its buttons' gap plus what each box
    -- leaves of its (centred) button.
    local gap = 18
    local a, b2 = list[1], list[2]
    if a and b2 and a:GetBottom() and b2:GetTop() and a:GetHeight() then
        gap = (a:GetBottom() - b2:GetTop()) + (a:GetHeight() - BOX_H)
    end
    local avail = railTop - railBottom
    if n > 1 and n * BOX_H + (n - 1) * gap > avail - 2 * GAP then
        gap = math.max(GAP, (avail - 2 * GAP - n * BOX_H) / (n - 1))
    end
    local step = BOX_H + gap
    local top = railTop - (avail - (n * BOX_H + (n - 1) * gap)) / 2
    local x1, x2 = ref:GetLeft() - gl, ref:GetRight() - gl
    local k = 0
    for _, b in ipairs(list) do
        local d = FFD[b]
        local bt, bb = b:GetTop(), b:GetBottom()
        if bt and bb then
            local boxTop = top - k * step
            k = k + 1
            d.box:ClearAllPoints()
            d.box:SetPoint("TOPLEFT", gf, "TOPLEFT", x1 + pad, boxTop - gt)
            d.box:SetPoint("TOPRIGHT", gf, "TOPLEFT", x2 - pad, boxTop - gt)
            d.box:SetHeight(BOX_H)
            b:SetHitRectInsets(pad, pad, bt - boxTop, (boxTop - BOX_H) - bb)
        end
    end
    for _, spec in ipairs(pages) do
        local b = PageButton(spec)
        if b then
            local boxTop = top - k * step
            k = k + 1
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", gf, "TOPLEFT", x1, boxTop - gt)
            b:SetSize(x2 - x1, BOX_H)
            b:Show()
            Place(b)
        end
    end
end

local function StyleAll()
    AlignTabs()
    for i = 1, 4 do
        local b = RailButton(i)
        Style(b, i)
        Place(b)
        if b then HideBackgrounds(b); PaintBorder(b) end
    end
    LayoutRail()
    for _, spec in ipairs(ns.railPages or {}) do
        if spec.railButton then PaintBorder(spec.railButton) end
    end
end

function ns.Rail_Paint()
    for i = 1, 4 do PaintBorder(RailButton(i)) end
    for _, spec in ipairs(ns.railPages or {}) do
        if spec.railButton then PaintBorder(spec.railButton) end
    end
end

function ns.Rail_Refresh()
    local pve = _G.PVEFrame
    if pve and pve:IsShown() then StyleAll() end
end

local hooked
local function Hook()
    local pve = _G.PVEFrame
    if hooked or not pve then return end
    hooked = true
    -- Next frame: the host's skin lays the rail out on the same show.
    pve:HookScript("OnShow", function() C_Timer.After(0, StyleAll) end)
    if GroupFinderFrame_SelectGroupButton then
        hooksecurefunc("GroupFinderFrame_SelectGroupButton", function()
            for i = 1, 4 do PaintBorder(RailButton(i)) end
        end)
    end
    -- Blizzard's own switch (any rail entry, or the window opening) ends a
    -- page of ours; so does the Dungeons & Raids tab closing.
    if GroupFinderFrame_ShowGroupFrame then
        hooksecurefunc("GroupFinderFrame_ShowGroupFrame", function()
            if ns.CloseRailPage then ns.CloseRailPage() end
        end)
    end
    local gf = _G.GroupFinderFrame
    if gf then
        gf:HookScript("OnHide", function() if ns.CloseRailPage then ns.CloseRailPage() end end)
    end
    if GroupFinderFrame_EvaluateButtonVisibility then
        hooksecurefunc("GroupFinderFrame_EvaluateButtonVisibility", function() C_Timer.After(0, LayoutRail) end)
    end
    if pve:IsShown() then C_Timer.After(0, StyleAll) end
end

-- Started by the module's OnEnable while the module is on.
function ns.Rail_Enable() Hook() end
