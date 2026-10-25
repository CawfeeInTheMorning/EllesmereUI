if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_GroupFinder_Extras.lua  -  EllesmereUI Group Finder Lab
--  the lab's extra filters and display pieces: has / missing rows, specific
--  roles, menu icons, two-column group settings, region tags, row art, the
--  raid boss strip, the person / raid icons.
-------------------------------------------------------------------------------
local FOLDER, ns = ...
if EllesmereUI.HELD_BACK_ADDONS[FOLDER] then return end -- held back (EllesmereUIGroupFinder.lua)
-- the group finder's extra pieces (once cawfee extras), living in the module
ns.EUI = EllesmereUI
ns.CawfeeLab = true

-- account-wide switches in EllesmereUIDB (nil = on)
local function Switch(key)
    return function() return not (EllesmereUIDB and EllesmereUIDB[key] == false) end,
           function(v)
               if not EllesmereUIDB then EllesmereUIDB = {} end
               EllesmereUIDB[key] = v and true or false
           end
end
ns.RailArtOn, ns.SetRailArt = Switch("cawfeeRailArt")
ns.FinderLayoutOn, ns.SetFinderLayout = Switch("cawfeeFinderLayout")

-- runs fn once blizzard's group finder is loaded
function ns.WhenGroupFinder(fn)
    if C_AddOns.IsAddOnLoaded("Blizzard_GroupFinder") and PVEFrame then
        fn()
        return
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, _, name)
        if name ~= "Blizzard_GroupFinder" then return end
        self:UnregisterAllEvents()
        fn()
    end)
end
local GFNS = ns

-- filters menu > specific roles: two toggles picking how the role checks
-- combine. "match all (and)" = every check (ellesmere's default),
-- "match any (or)" = just one. saved in the group finder's search settings as
-- cawfeeRolesAny; read by hooks in RaidListKeep / ExtraKeep / AddRoleItems of
-- EUI_GroupFinder_Search.lua on local/cawfee.
GFNS.CawfeeRolesAny = function()
    local c = GFNS.Cfg and GFNS.Cfg()
    return c and c.cawfeeRolesAny == true or false
end

local CM = ns.EUI
local function Secret(v) return issecretvalue and issecretvalue(v) or false end
local HINT_GREY = 0.35  -- the (and) / (or) part, its own font string so it never takes the accent
-- the dim label colour (white at 53%) as a solid grey on the dark fill
local DIM_HEX = "|cff8f8f8f"

-- label + its greyed hint right after it
local function TwoPart(owner, K)
    local main = owner:CreateFontString(nil, "OVERLAY")
    K.Font(main, K.ITEM_FONT)
    main:SetPoint("LEFT", owner, "LEFT", 7, 0)
    local hint = owner:CreateFontString(nil, "OVERLAY")
    K.Font(hint, K.ITEM_FONT)
    hint:SetPoint("LEFT", main, "RIGHT", 3, 0)
    hint:SetTextColor(HINT_GREY, HINT_GREY, HINT_GREY, 1)
    return main, hint
end

local ARROW = "Interface\\AddOns\\" .. FOLDER .. "\\media\\icons\\eui-arrow.png"

-- our dropdowns sit outside the menu's frame at times; the menu's click-off
-- asks here first (hook in XF.FiltersInside) so clicks in them keep it open
local pops = {}
GFNS.CawfeeInside = function()
    for _, f in ipairs(pops) do
        if f:IsShown() and f:IsMouseOver() then return true end
    end
    return false
end

local MASK = "Interface\\AddOns\\" .. FOLDER .. "\\media\\masks\\rounded.png"

-- atlas icon with rounded corners, after the given text
local function RoundIcon(parent, atlas, after)
    local ic = parent:CreateTexture(nil, "OVERLAY")
    ic:SetSize(12, 12)
    ic:SetPoint("LEFT", after, "RIGHT", 4, 0)
    if atlas then ic:SetAtlas(atlas) end
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(ic)
    ic:AddMaskTexture(mask)
    ic.mask = mask
    return ic
end

-- skinned button with the filters button's look: label, grey hint, arrow
local function ArrowButton(owner, K)
    local btn = CreateFrame("Button", nil, owner)
    btn:SetNormalFontObject("GameFontHighlight")
    btn:SetText(" ")
    -- ellesmere's settings dropdown arrow, colour baked into the art
    btn.Arrow = btn:CreateTexture(nil, "OVERLAY")
    btn.Arrow:SetTexture(ARROW)
    btn.Arrow:SetSize(13, 13)  -- half its canvas: the size it shows at in the settings
    btn.Arrow:SetPoint("CENTER", btn, "RIGHT", -10, 0)
    btn.Label, btn.Hint = TwoPart(btn, K)
    btn.Label:SetTextColor(CM.TEXT_DIM_R, CM.TEXT_DIM_G, CM.TEXT_DIM_B, CM.TEXT_DIM_A)
    -- room for an icon after the label, made before the skin so its restrip keeps it
    btn.Icon = RoundIcon(btn, nil, btn.Label)
    btn.IconMask = btn.Icon.mask
    btn.Icon:Hide()
    local skin = CM._ModuleNS and CM._ModuleNS.EllesmereUIBlizzardSkin
    local S = skin and skin.WSkin
    if S and S.Button then
        S.Button(btn, { "Arrow", "Label", "Hint", "Icon", "IconMask" })
    else
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
        CM.MakeBorder(btn, K.ThemeBorder())
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.1)
    end
    return btn
end


-- under the button, or above it when it'd hang off the menu's bottom
-- (a click out there closes the menu)
local function OpenNear(pop, btn, bounds, pad)
    pad = pad or 0
    pop:ClearAllPoints()
    local bb, mb = btn:GetBottom(), bounds and bounds:GetBottom()
    if bb and mb and (bb - 2 - pop:GetHeight()) * btn:GetEffectiveScale() < mb * bounds:GetEffectiveScale() then
        pop:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", -pad, 2)
        pop:SetPoint("BOTTOMRIGHT", btn, "TOPRIGHT", pad, 2)
    else
        pop:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", -pad, -2)
        pop:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", pad, -2)
    end
    pop:Show()
end

-- arrow button + its list.
-- modes = { { label, hint, icon }, ... }, Get() = picked index, Set(i) on
-- pick. icon = an atlas shown after the label (list and button), rounded. no
-- anchors, the caller places it. the list opens downward
local function Dropdown(owner, K, modes, Get, Set)
    local btn = ArrowButton(owner, K)
    function btn:ShowMode()
        local mode = modes[Get()] or modes[1]
        self.Label:SetText(mode.button or mode.label)
        if mode.button then self.Label:SetTextColor(1, 1, 1, 1)
        else self.Label:SetTextColor(CM.TEXT_DIM_R, CM.TEXT_DIM_G, CM.TEXT_DIM_B, CM.TEXT_DIM_A) end
        self.Hint:SetText(mode.hint or "")
        if mode.icon then
            self.Icon:SetAtlas(mode.icon)
            self.Icon:Show()
        else
            self.Icon:Hide()
        end
    end
    btn:ShowMode()

    local list = CreateFrame("Frame", nil, K.parent or owner)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetFrameLevel(330)
    list:SetClampedToScreen(true)
    list:EnableMouse(true)
    local lbg = list:CreateTexture(nil, "BACKGROUND")
    lbg:SetAllPoints()
    lbg:SetColorTexture(0, 0, 0, 1)
    CM.MakeBorder(list, K.ThemeBorder())
    list.items = {}
    for i, mode in ipairs(modes) do
        local it = CreateFrame("Button", nil, list)
        it:SetHeight(K.ITEM_H)
        it:SetPoint("TOPLEFT", list, "TOPLEFT", 1, -(2 + (i - 1) * K.ITEM_H))
        it:SetPoint("TOPRIGHT", list, "TOPRIGHT", -1, -(2 + (i - 1) * K.ITEM_H))
        it.text, it.hint = TwoPart(it, K)
        it.text:SetText(mode.label)
        it.hint:SetText(mode.hint or "")
        if mode.icon then RoundIcon(it, mode.icon, it.text) end
        local ihl = it:CreateTexture(nil, "HIGHLIGHT")
        ihl:SetAllPoints()
        ihl:SetColorTexture(1, 1, 1, CM.DD_ITEM_HL_A or 0.08)
        it:SetScript("OnClick", function()
            Set(i)
            btn:ShowMode()
            list:Hide()
            K.Refilter()
            K.Paint()
        end)
        list.items[i] = it
    end
    list:SetHeight(4 + #modes * K.ITEM_H)
    btn.list = list
    pops[#pops + 1] = list
    K.ClickOff(list, function(self) return self:IsMouseOver() or btn:IsMouseOver() end)
    list:Hide()

    btn:SetScript("OnClick", function()
        if list:IsShown() then list:Hide() return end
        K.Untip()  -- no tooltip over the open list
        -- picked mode in the accent colour
        local ar, ag, ab = K.Accent()
        for i, it in ipairs(list.items) do
            if i == Get() then it.text:SetTextColor(ar, ag, ab, 1)
            else it.text:SetTextColor(CM.TEXT_DIM_R, CM.TEXT_DIM_G, CM.TEXT_DIM_B, CM.TEXT_DIM_A) end
        end
        list:ClearAllPoints()
        list:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
        list:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -2)
        list:Show()
    end)
    btn:SetScript("OnHide", function() list:Hide() end)
    btn:SetScript("OnShow", function(self) self:ShowMode() end)
    btn:SetScript("OnLeave", K.Untip)
    return btn
end

-- divider, like the menu's sections
local function Divider(m, y)
    local div = m:CreateTexture(nil, "ARTWORK")
    div:SetHeight(CM.PP.mult)
    div:SetColorTexture(1, 1, 1, 0.10)
    div:SetPoint("TOPLEFT", m, "TOPLEFT", 10, -y - 3)
    div:SetPoint("TOPRIGHT", m, "TOPRIGHT", -10, -y - 3)
    return y + 7
end

-------------------------------------------------------------------------------
--  specific roles: one button (under battle res) opening a dropdown with
--  match exact / match any toggles, a divider, then the tanks / healers /
--  dps count rows. opens above the button when it'd hang off the menu.
-------------------------------------------------------------------------------
local function Block(m, y)
    local f = CreateFrame("Frame", nil, m)
    f:SetPoint("TOPLEFT", m, "TOPLEFT", 0, -y)
    f:SetPoint("TOPRIGHT", m, "TOPRIGHT", 0, -y)
    return f
end

local function PlaceBlock(f, m, y)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", m, "TOPLEFT", 0, -y)
    f:SetPoint("TOPRIGHT", m, "TOPRIGHT", 0, -y)
end

local MATCH = {
    { any = false, label = "Match All",   hint = "(and)", tip = "Match all of the selected options below." },
    { any = true,  label = "Match Any",   hint = "(or)",  tip = "Match any of the selected options below." },
}

local function CountsOn(c)
    local n = 0
    for _, rule in pairs(type(c.roleCounts) == "table" and c.roleCounts or {}) do
        if type(rule) == "table" and rule.on then n = n + 1 end
    end
    return n
end

GFNS.CawfeeRoleCounts = function(m, y, K)
    local sg = Block(m, y)
    sg:SetHeight(K.ITEM_H)
    m.cawfeeSpecGrp = sg
    local btn = ArrowButton(sg, K)
    btn:SetHeight(K.ITEM_H - 2)
    btn:SetPoint("TOPLEFT", sg, "TOPLEFT", 9, -1)
    btn:SetPoint("TOPRIGHT", sg, "TOPRIGHT", -9, -1)
    btn.Label:SetText("Specific Roles")

    local pop = CreateFrame("Frame", nil, K.parent or m)
    pop:SetFrameStrata("FULLSCREEN_DIALOG")
    pop:SetFrameLevel(325)
    pop:SetClampedToScreen(true)
    pop:EnableMouse(true)
    local pbg = pop:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints()
    local fr, fg, fb = K.ThemeFill()
    pbg:SetColorTexture(fr, fg, fb, 0.98)  -- same fill as the filters menu
    CM.MakeBorder(pop, K.ThemeBorder())
    pops[#pops + 1] = pop

    -- while open: a veil of the menu's own fill over both columns, so their
    -- text and checkboxes fade but the panel stays solid. under the border,
    -- eats clicks (the pop-up's click-off then closes it)
    local veil = CreateFrame("Button", nil, K.parent or m)
    veil:SetFrameStrata("FULLSCREEN_DIALOG")
    veil:SetFrameLevel(m:GetFrameLevel() + 8)
    local vt = veil:CreateTexture(nil, "BACKGROUND")
    vt:SetAllPoints()
    vt:SetColorTexture(fr, fg, fb, 0.7)
    veil:Hide()

    -- match exact / any: one or the other
    local py, toggles = 2, {}
    local function PaintMatch()
        local any = K.Cfg().cawfeeRolesAny == true
        for _, t in ipairs(toggles) do t:SetChecked(t.any == any) end
    end
    for _, mode in ipairs(MATCH) do
        local t = K.MenuItem(pop, py, mode.label, function()
            K.Cfg().cawfeeRolesAny = mode.any or nil
            PaintMatch()
            K.Refilter()
            K.Paint()
        end)
        t.any = mode.any
        -- the grey (and) / (or) right after the label
        local _, cb = t.label:GetPoint(1)
        t.label:ClearAllPoints()
        t.label:SetPoint("LEFT", cb, "RIGHT", 7, 0)
        local hint = t:CreateFontString(nil, "OVERLAY")
        K.Font(hint, K.ITEM_FONT)
        hint:SetPoint("LEFT", t.label, "RIGHT", 3, 0)
        hint:SetTextColor(HINT_GREY, HINT_GREY, HINT_GREY, 1)
        hint:SetText(mode.hint)
        t:HookScript("OnEnter", function(self) K.Tip(self, mode.tip) end)
        t:HookScript("OnLeave", K.Untip)
        toggles[#toggles + 1] = t
        py = py + K.ITEM_H
    end
    py = Divider(pop, py)
    -- count rows land in m.counts so the menu still paints them
    m.counts = m.counts or {}
    pop.counts = m.counts
    for _, r in ipairs(K.COUNT_ROLES) do py = K.AddCountRow(pop, py, r.key, r.label) end
    pop:SetHeight(py + 2)
    K.ClickOff(pop, function(self)
        return self:IsMouseOver() or btn:IsMouseOver() or (K.OpListOver and K.OpListOver()) or false
    end)
    pop:Hide()

    -- "(2 active)" when count rows are ticked, so they aren't forgotten
    local function ShowHint()
        local n = CountsOn(K.Cfg())
        btn.Hint:SetText(n > 0 and ("(" .. n .. " active)") or "")
    end
    local sgLevel = sg:GetFrameLevel()
    pop:HookScript("OnShow", function()
        PaintMatch()
        -- the side panel comes after these rows, so anchor here
        veil:ClearAllPoints()
        veil:SetPoint("TOPLEFT", m.side or m, "TOPLEFT", 0, 0)
        veil:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", 0, 0)
        veil:Show()
        sg:SetFrameLevel(veil:GetFrameLevel() + 1)  -- the button stays lit
    end)
    pop:HookScript("OnHide", function()
        veil:Hide()
        sg:SetFrameLevel(sgLevel)
        ShowHint()
    end)
    btn:SetScript("OnClick", function()
        if pop:IsShown() then pop:Hide() return end
        OpenNear(pop, btn, m)  -- same width as the button
    end)
    btn:SetScript("OnShow", ShowHint)
    btn:SetScript("OnHide", function() pop:Hide() end)
    ShowHint()
    return y + K.ITEM_H
end

-------------------------------------------------------------------------------
--  raids and delves: the squares in one line that scrolls sideways (arrows at
--  each end, mouse wheel too) instead of a grid that pushes the list down. the
--  module's own squares, moved into a clipped window. hooks in LayoutBosses
--  and LayoutDelves of EUI_GroupFinder_Search.lua; returns 1 line
-------------------------------------------------------------------------------
local ARROW_W = 14
local ARROW_DIR = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"

local function PlaceStrip(s)
    if not s.list then return end
    local per = s.size + s.gap
    -- whole steps only, so the squares never shift by a sliver; the end stops
    -- once the last square is fully in view (any space left is under a square)
    local full = math.max(1, math.floor((s.clipW + s.gap) / per))
    local maxOff = math.max(0, #s.list - full)
    s.offset = math.max(0, math.min(s.offset, maxOff))
    local shift = -s.offset * per
    for i, sq in ipairs(s.squares) do
        local d = s.list[i]
        if d then
            local x = (i - 1) * per + shift
            sq:ClearAllPoints()
            sq:SetPoint("LEFT", s.clip, "LEFT", x, 0)
            -- squares fully outside the window are hidden so they can't be clicked
            sq:SetShown(x + s.size > 0 and x < s.clipW)
        end
    end
    for _, a in ipairs({ { s.left, s.offset > 0 }, { s.right, s.offset < maxOff } }) do
        local b, live = a[1], a[2]
        b.live = live
        b:EnableMouse(live)
        b.tex:SetAlpha(live and 0.8 or 0.2)
    end
end

local function ScrollStrip(s, step)
    s.offset = s.offset + step
    PlaceStrip(s)
    if s.paint then s.paint() end  -- the module colours the squares now in view
end

local function StripArrow(s, row, file, step)
    local b = CreateFrame("Button", nil, row)
    b.tex = b:CreateTexture(nil, "OVERLAY")
    b.tex:SetTexture(ARROW_DIR .. file)
    b.tex:SetSize(16, 16)
    b.tex:SetPoint("CENTER")
    b:SetScript("OnClick", function() ScrollStrip(s, step) end)
    b:SetScript("OnEnter", function(self) if self.live then self.tex:SetAlpha(1) end end)
    b:SetScript("OnLeave", function(self) self.tex:SetAlpha(self.live and 0.8 or 0.2) end)
    return b
end

-- one strip: key is the square's data field (boss / delve), fill dresses a
-- square for its entry
local function NewStrip(key, fill)
    local s = { offset = 0 }
    return function(list, squares, Make, size, after, show, cols, slots, row, gap, paint)
        s.paint = paint
        if not s.clip then
            s.clip = CreateFrame("Frame", nil, row)
            s.clip:SetClipsChildren(true)
            s.clip:EnableMouseWheel(true)
            s.clip:SetScript("OnMouseWheel", function(_, delta) ScrollStrip(s, delta > 0 and -1 or 1) end)
            s.left = StripArrow(s, row, "eui-arrow-left.png", -1)
            s.right = StripArrow(s, row, "eui-arrow-right.png", 1)
        end
        if not show or #list == 0 or not after then
            for _, sq in ipairs(squares) do sq[key] = nil; sq:Hide() end
            s.clip:Hide(); s.left:Hide(); s.right:Hide()
            s.list = nil
            return 1
        end
        -- the grid's room (after the raid button's slot), one line high
        local per = size + gap
        local startX = gap + (slots - cols) * per
        local room = cols * per - gap
        local fits = #list * per - gap <= room
        local vis = fits and #list or math.max(1, math.floor((room - 2 * (ARROW_W + gap) + gap) / per))
        s.clip:ClearAllPoints()
        s.left:ClearAllPoints()
        s.right:ClearAllPoints()
        s.left:SetSize(ARROW_W, size)
        s.right:SetSize(ARROW_W, size)
        if fits then
            s.left:Hide(); s.right:Hide()
            s.clip:SetPoint("LEFT", after, "RIGHT", startX, 0)
        else
            s.left:SetPoint("LEFT", after, "RIGHT", startX, 0)
            s.left:Show()
            s.clip:SetPoint("LEFT", s.left, "RIGHT", gap, 0)
        end
        -- scrolling: the window runs to the row's right edge (in line with row 1),
        -- the last square there can show cut off
        local clipW = vis * per - gap
        if fits then
            s.clip:SetSize(clipW, size)
        else
            s.right:SetPoint("RIGHT", row, "RIGHT", 4, 0)  -- a touch wider so the last square's border isn't clipped
            s.right:Show()
            s.clip:SetPoint("RIGHT", s.right, "LEFT", -gap, 0)
            s.clip:SetHeight(size)
            clipW = room + 4 - 2 * (ARROW_W + gap)
        end
        s.clip:Show()
        for i, d in ipairs(list) do
            local sq = squares[i]
            if not sq then sq = Make(); squares[i] = sq end
            if sq:GetParent() ~= s.clip then sq:SetParent(s.clip) end
            sq[key] = d
            fill(sq, d)
            sq:SetSize(size, size)
        end
        for i = #list + 1, #squares do squares[i][key] = nil; squares[i]:Hide() end
        s.list, s.squares, s.size, s.gap, s.clipW = list, squares, size, gap, clipW
        PlaceStrip(s)
        return 1
    end
end

GFNS.CawfeeBossStrip = NewStrip("boss", function(sq, d)
    sq.icon:SetTexture(d.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
end)
-- delves: the module dresses its own squares (font, short name) first
GFNS.CawfeeDelveStrip = NewStrip("delve", function(sq, d)
    if GFNS.LabDressDelve then GFNS.LabDressDelve(sq, d) end
end)

-- filters menu (side panel included) spans the search box's left edge to
-- refresh, the same width as the expressions menu
GFNS.CawfeeWidenMenu = function(m, anchor, gap)
    local sp = LFGListFrame and LFGListFrame.SearchPanel
    local left = sp and (sp.SearchBox or sp.BackButton)
    if not (left and left:IsVisible() and left:GetLeft() and anchor:GetLeft()) then return end
    local sideW = m.side and m.side:GetWidth() or 0
    local dx = (left:GetLeft() * left:GetEffectiveScale() - anchor:GetLeft() * anchor:GetEffectiveScale())
        / m:GetEffectiveScale() + sideW
    m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", dx, -gap)
end

-------------------------------------------------------------------------------
--  has / missing rows: bloodlust, battle res and your own class, each a
--  checkbox + has / missing dropdown. reuses the menu's hasLust / hasBrez
--  keys, adds cawfeeMyClass; the picks are cawfeeLustMissing,
--  cawfeeBrezMissing and cawfeeMyClassMissing (your class defaults to
--  missing). built through the AddRoleItems hook, kept through the ExtraKeep
--  hook of EUI_GroupFinder_Search.lua.
-------------------------------------------------------------------------------
local LUST = { SHAMAN = true, MAGE = true, HUNTER = true, EVOKER = true }
local BREZ = { DRUID = true, DEATHKNIGHT = true, WARLOCK = true, PALADIN = true }

local function MyClass()
    local name, file = UnitClass("player")
    return name, file
end

local CLASS_ROWS = {
    { key = "hasLust", pick = "cawfeeLustMissing", has = "Has Bloodlust", missing = "Missing Bloodlust",
      Tip = function(K) return "Bloodlust", {
        "A member whose class has one of these spells:",
        K.ClassLine("SHAMAN", "Bloodlust / Heroism (Shaman)"),
        K.ClassLine("MAGE", "Time Warp (Mage)"),
        K.ClassLine("HUNTER", "Primal Rage (Hunter pet)"),
        K.ClassLine("EVOKER", "Fury of the Aspects (Evoker)"),
        "Drums and other items don't count." } end },
    { key = "hasBrez", pick = "cawfeeBrezMissing", has = "Has Battle Res", missing = "Missing Battle Res",
      Tip = function(K) return "Battle Res", {
        "A member whose class has one of these spells:",
        K.ClassLine("DRUID", "Rebirth (Druid)"),
        K.ClassLine("DEATHKNIGHT", "Raise Ally (Death Knight)"),
        K.ClassLine("WARLOCK", "Soulstone (Warlock)"),
        K.ClassLine("PALADIN", "Intercession (Paladin)"),
        "Engineering and other items don't count." } end },
    { key = "cawfeeMyClass", pick = "cawfeeMyClassMissing", missingDefault = true,
      has = "Has Class", missing = "No Class",  -- your class name goes in at build
      Tip = function(K)
        local name, file = MyClass()
        local a = name and name:match("^[AEIOUaeiou]") and "an" or "a"
        return "Your Class", { "A member who's also " .. a .. " " .. (file and K.ClassLine(file, name) or "your class") .. "." }
      end },
}

local function Missing(c, row)
    local v = c[row.pick]
    if v == nil then return row.missingDefault == true end
    return v == true
end

GFNS.CawfeeClassRows = function(m, y, K)
    if K.FLAG_KEYS and not tContains(K.FLAG_KEYS, "cawfeeMyClass") then
        K.FLAG_KEYS[#K.FLAG_KEYS + 1] = "cawfeeMyClass"
    end
    m.cawfeeRolesEnd = y
    m.cawfeeItemH = K.ITEM_H
    local roleG, miscG = Block(m, y), Block(m, y + K.ITEM_H)
    m.cawfeeClassGrp, m.cawfeeMiscGrp = roleG, miscG
    local ry, my = 0, 0
    for _, row in ipairs(CLASS_ROWS) do
        local function ShowTip(self)
            if self.list and self.list:IsShown() then return end  -- list open: no tooltip
            local title, lines = row.Tip(K)
            K.Tip(self, title, unpack(lines))
        end
        local inRoles = row.key == "cawfeeMyClass"
        local has, missing = row.has, row.missing
        local hasBtn, missingBtn
        local icon
        if inRoles then
            local name, file = MyClass()
            -- class name in its class colour
            local cls = (name and file) and K.ClassLine(file, name) or name or "Class"
            has, missing = "Has " .. cls, "No " .. cls
            -- the button's label runs at full alpha so the class colour shows;
            -- "has" / "no" get the dim grey by hand
            hasBtn, missingBtn = DIM_HEX .. "Has|r " .. cls, DIM_HEX .. "No|r " .. cls
            icon = file and ("classicon-" .. file:lower())
        end
        local item = K.MenuItem(inRoles and roleG or miscG, inRoles and ry or my, "", function()
            local c = K.Cfg()
            c[row.key] = (not c[row.key]) or nil
            K.Refilter()
            K.Paint()
        end)
        m.items["flag_" .. row.key] = item
        item.label:Hide()
        local btn = Dropdown(item, K, {
            { label = has, button = hasBtn, icon = icon },
            { label = missing, button = missingBtn, icon = icon },
        }, function() return Missing(K.Cfg(), row) and 2 or 1 end,
        function(i)
            -- the class row turns on when picked; bloodlust / battle res leave the box alone
            local c = K.Cfg()
            c[row.pick] = (i == 2)
            if inRoles then c[row.key] = true end
        end)
        btn:SetHeight(K.ITEM_H - 2)  -- same as the match exact button
        btn:SetPoint("LEFT", item, "LEFT", 8 + K.CHECK_SZ + 7, 0)
        btn:SetPoint("RIGHT", item, "RIGHT", -8, 0)
        btn:SetScript("OnEnter", ShowTip)
        -- same step as the misc rows beside them
        if inRoles then ry = ry + K.ITEM_H else my = my + K.ITEM_H end
    end
    roleG:SetHeight(ry)
    miscG:SetHeight(my)
    return y + ry + my
end

-- false = drop the group. unknown (secret) members don't count either way
GFNS.CawfeeClassKeep = function(id, info, c)
    if not (c.hasLust or c.hasBrez or c.cawfeeMyClass) then return true end
    local n = info and info.numMembers
    if type(n) ~= "number" or Secret(n) then return true end
    local _, mine = MyClass()
    local have = { hasLust = false, hasBrez = false, cawfeeMyClass = false }
    for i = 1, n do
        local p = C_LFGList.GetSearchResultPlayerInfo(id, i)
        if p and (Secret(p) or (canaccesstable and not canaccesstable(p))) then p = nil end
        local cls = p and p.classFilename
        if cls and not Secret(cls) then
            if LUST[cls] then have.hasLust = true end
            if BREZ[cls] then have.hasBrez = true end
            if cls == mine then have.cawfeeMyClass = true end
        end
    end
    for _, row in ipairs(CLASS_ROWS) do
        if c[row.key] and have[row.key] == Missing(c, row) then return false end
    end
    return true
end

-------------------------------------------------------------------------------
--  region tags: OCE / NA / MEX / BRA after each group's playstyle, from the
--  leader's realm (us region only). toggle in group settings > misc, saved in
--  the group finder's search settings as cawfeeRegionTags. the row comes in
--  through the GROUP_MENU hook of EUI_GroupFinder_Search.lua.
-------------------------------------------------------------------------------
local TAGS = {
    oce = { "OCE", 0.35, 0.65, 1 },
    na  = { "NA",  1, 0.35, 0.35 },
    la  = { "MEX", 1, 0.5, 0.82 },
    br  = { "BRA", 0.35, 0.9, 0.45 },
}
-- us realms outside north america; everything else counts as na
local realmRegion = {}
for region, realms in pairs({
    oce = { "amanthul", "barthilas", "caelestrasz", "dathremar", "dreadmaul", "frostmourne",
            "gundrak", "jubeithos", "khazgoroth", "nagrand", "saurfang", "thaurissan" },
    br  = { "azralon", "gallywix", "goldrinn", "nemesis", "tolbarad" },
    la  = { "drakkari", "quelthalas", "ragnaros" },
}) do
    for _, r in ipairs(realms) do realmRegion[r] = region end
end

local function TagsOn()
    local c = GFNS.Cfg and GFNS.Cfg()
    return c and c.cawfeeRegionTags == true and GetCurrentRegion and GetCurrentRegion() == 1
end

local function RegionOf(resultID)
    local info = C_LFGList.GetSearchResultInfo(resultID)
    if not info or Secret(info) or (canaccesstable and not canaccesstable(info)) then return nil end
    local leader = info.leaderName
    if not leader or Secret(leader) then return nil end
    local realm = leader:match("%-(.+)$") or (GetNormalizedRealmName and GetNormalizedRealmName())
    if not realm or Secret(realm) then return nil end
    return realmRegion[(realm:gsub("[^%a]", "")):lower()] or "na"
end

local tagOf = setmetatable({}, { __mode = "k" })

-- flag art per region (media/flags/<region>.png, 64x42 with clear corners)
local FLAG_DIR = "Interface\\AddOns\\" .. FOLDER .. "\\media\\flags\\"
local FLAGS = { oce = FLAG_DIR .. "oce.png", na = FLAG_DIR .. "na.png", la = FLAG_DIR .. "la.png", br = FLAG_DIR .. "br.png" }

-- for the filtered results list: a group's tag, its colour and flag (us only)
function ns.RegionTagOf(resultID)
    if not TagsOn() then return nil end  -- the group settings switch, us only
    local region = RegionOf(resultID)
    local t = TAGS[region]
    if t then return t[1], t[2], t[3], t[4], FLAGS[region] end
end

-- "Relaxed | OCE [flag]" after the playstyle text on the third line (titles
-- are protected text and can't be measured; the playstyle is plain text, so
-- its box is exact). no playstyle: no divider, the tag starts the line.
local function Parts(entry)
    local p = tagOf[entry]
    if p then return p end
    -- our own child frame on the row, above its text
    local f = CreateFrame("Frame", nil, entry)
    f:SetAllPoints(entry)
    f:SetFrameLevel(entry:GetFrameLevel() + 4)
    f:EnableMouse(false)
    p = {
        sep  = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"),
        tag  = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"),
        flag = f:CreateTexture(nil, "OVERLAY"),
    }
    p.sep:SetText("||")  -- an escaped pipe draws one "|"
    p.sep:SetTextColor(0.35, 0.35, 0.35, 1)
    tagOf[entry] = p
    return p
end

-------------------------------------------------------------------------------
--  row art (group settings > display, cawfeeRowArt): the instance's art on
--  the left half of each row, fading from 30% to nothing.
--  compact rows (cawfeeCompact): one centred line, "MR +18" - a white short
--  activity name, then the title. blizzard's activity and playstyle lines
--  (and the region tag) fade out; the tag and the art are ours, their text
--  is never rewritten. row height stays
--  blizzard's: shrinking it means changing the list's layout, the risky
--  part. only alpha, the title's anchor and width change, the same kind of
--  write the module's own name colours / widths make, and only out of
--  combat. a row we can't read (secret results) stays stock.
-------------------------------------------------------------------------------
local NAME_X, NAME_Y = 10, -6  -- blizzard's title anchor
local TITLE_ROOM = 34  -- kept clear left of the role icons (leader rating)
local shifted = setmetatable({}, { __mode = "k" })  -- entry -> title width we set

local function CompactOn() return false end  -- compact mode retired

local function RowArtOn()
    local c = GFNS.Cfg and GFNS.Cfg()
    return c and c.cawfeeRowArt == true
end

-- "Murder Row" -> MR, "The Venomous Abyss" -> VA, "March on Quel'Danas" ->
-- MoQD: initials, a leading "the" dropped, small words lower case
local SMALL = { of = true, the = true, ["and"] = true, to = true, ["in"] = true, on = true, at = true }
local function Short(name)
    name = (name:match("^([^,:]+)") or name):gsub("\226\128\153", "'")
    local out = {}
    for word in name:gmatch("[^%s%-']+") do
        local w = word:gsub("[^%a]", "")
        if w ~= "" then
            local lw = w:lower()
            if #out == 0 and lw == "the" then
                -- skip
            elseif #out > 0 and SMALL[lw] then
                out[#out + 1] = w:sub(1, 1):lower()
            else
                out[#out + 1] = w:sub(1, 1):upper()
            end
        end
    end
    local ab = #out > 0 and table.concat(out) or name  -- no latin letters: whole name
    local ov = CM._dungeonAbbrevOverride
    return ov and ov[ab] or ab
end

-- wide instance art by instance map id: this season's keystone background,
-- else the journal's lore / background art (read by id, the journal's own
-- selection is left alone). cropped to a strip shaped like a quarter row
local ART_CROP = { 0.205, 0.795, 0.25, 0.50 }  -- left, right, top, bottom: half a row's shape, clear of the art's frame
local artOf = {}
local function Art(mapID)
    if not mapID or Secret(mapID) then return nil end
    local a = artOf[mapID]
    if a ~= nil then return a or nil end
    a = false
    local CMode = C_ChallengeMode
    for _, cm in ipairs(CMode and CMode.GetMapTable and CMode.GetMapTable() or {}) do
        local _, _, _, _, bgTex, mid = CMode.GetMapUIInfo(cm)
        if mid == mapID and bgTex then a = bgTex end
    end
    local CEJ = C_EncounterJournal
    if not a and CEJ and CEJ.GetInstanceForGameMap and EJ_GetInstanceInfo then
        local jid = CEJ.GetInstanceForGameMap(mapID)
        if jid then
            local _, _, bgImage, _, loreImage = EJ_GetInstanceInfo(jid)
            a = loreImage or bgImage or false
        end
    end
    artOf[mapID] = a
    return a or nil
end

-- keystones: "MR"; everything else keeps its difficulty: "VA (Heroic)"
local function Activity(resultID)
    local info = C_LFGList.GetSearchResultInfo(resultID)
    if not info or Secret(info) or (canaccesstable and not canaccesstable(info)) then return nil end
    local acts = info.activityIDs
    local act = type(acts) == "table" and not Secret(acts) and acts[1]
    if not act or Secret(act) then return nil end
    return C_LFGList.GetActivityInfoTable(act)
end

local function ActivityShort(resultID)
    local ai = Activity(resultID)
    local full = ai and ai.fullName
    if type(full) ~= "string" or Secret(full) then return nil end
    local base, diff = full:match("^(.-)%s*%(([^()]+)%)$")
    local ab = Short(base or full)
    if not ai.isMythicPlusActivity and diff then ab = ab .. " " .. DIM_HEX .. "(" .. diff .. ")|r" end  -- difficulty in grey
    return ab
end

local ART_SHARE, ART_ALPHA = 0.5, 0.2  -- half the row, 20% fading to 0
local FADE_MASK = "Interface\\AddOns\\" .. FOLDER .. "\\media\\masks\\fade.png"

-- the filtered results list's rows: a group's art (nil while row art is off),
-- and how to draw it
function ns.RowArtFor(resultID)
    if not RowArtOn() then return nil end
    local ai = Activity(resultID)
    return ai and Art(ai.mapID)
end
ns.ROW_ART = { crop = ART_CROP, share = ART_SHARE, alpha = ART_ALPHA, mask = FADE_MASK }

-- the art sits on the row itself, under blizzard's text (a frame of ours
-- would draw over it); the tag goes on our overlay, above
local function RowArt(entry, p)
    local art = RowArtOn() and entry.resultID
    local ai = art and Activity(entry.resultID)
    art = ai and Art(ai.mapID)
    if not art then
        if p.art then p.art:Hide() end
        return
    end
    if not p.art then
        p.art = entry:CreateTexture(nil, "BACKGROUND", nil, 7)
        p.art:SetAlpha(ART_ALPHA)
        -- a curved fade (media/masks/fade.png): full for the first fifth, then
        -- gone well before the right edge, so the art's own frame never shows
        local mask = entry:CreateMaskTexture()
        mask:SetTexture(FADE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(p.art)
        p.art:AddMaskTexture(mask)
    end
    -- the row's left half, inside its background inset
    p.art:SetTexture(art)
    p.art:SetTexCoord(unpack(ART_CROP))
    p.art:ClearAllPoints()
    p.art:SetPoint("TOPLEFT", entry, "TOPLEFT", 3, -2)
    p.art:SetPoint("BOTTOMLEFT", entry, "BOTTOMLEFT", 3, 0)
    p.art:SetWidth(math.max(1, math.floor((entry:GetWidth() or 0) * ART_SHARE)))
    p.art:Show()
end

local function Stock(entry, p)
    if not shifted[entry] then return end
    entry.Playstyle:SetAlpha(1)
    entry.ActivityName:SetAlpha(1)
    entry.Name:ClearAllPoints()
    entry.Name:SetPoint("TOPLEFT", entry, "TOPLEFT", NAME_X, NAME_Y)
    entry.Name:SetWidth(shifted[entry])  -- same right edge till blizzard's next update
    if p.short then p.short:Hide() end
    shifted[entry] = nil
end

local function CompactEntry(entry, p)
    if InCombatLockdown() or not (entry.Name and entry.ActivityName) then return end
    local short = CompactOn() and entry.resultID and ActivityShort(entry.resultID)
    if not short then return Stock(entry, p) end
    entry.Playstyle:SetAlpha(0)
    entry.ActivityName:SetAlpha(0)
    p.short = p.short or p.sep:GetParent():CreateFontString(nil, "OVERLAY", "GameFontNormal")

    local ok, path, size, flags = pcall(entry.Name.GetFont, entry.Name)
    if ok and path then p.short:SetFont(path, size, flags or "") end
    p.short:SetText(short)
    p.short:SetTextColor(1, 1, 1, 1)
    p.short:ClearAllPoints()
    p.short:SetPoint("LEFT", entry, "LEFT", NAME_X, 0)
    p.short:Show()
    local x = NAME_X + math.ceil(p.short:GetStringWidth()) + 5
    entry.Name:ClearAllPoints()
    entry.Name:SetPoint("LEFT", entry, "LEFT", x, 0)
    -- the title can't be measured (protected text): give it a box from here
    -- to just short of the role icons, it truncates inside that
    local dd, el = entry.DataDisplay, entry:GetLeft()
    local right = dd and dd:IsShown() and dd:GetLeft()
    local room = (right and el) and (right - el - x - TITLE_ROOM) or (176 - x)
    room = math.max(40, math.floor(room))
    entry.Name:SetWidth(room)
    shifted[entry] = room + x - NAME_X
end

local function TagEntry(entry)
    if not (entry and entry.Playstyle) then return end
    local p = Parts(entry)
    RowArt(entry, p)
    CompactEntry(entry, p)
    p.sep:Hide(); p.tag:Hide(); p.flag:Hide()
    if CompactOn() or not (TagsOn() and entry.resultID) then return end
    local region = RegionOf(entry.resultID)
    local t = TAGS[region]
    if not t then return end
    -- same size as the playstyle text it sits beside
    local play = entry.Playstyle
    local ok, _, size = pcall(play.GetFont, play)
    if ok and type(size) == "number" and not Secret(size) and size > 0 then
        for _, fs in ipairs({ p.sep, p.tag }) do
            local path, _, flags = fs:GetFont()
            if path then fs:SetFont(path, size, flags or "") end
        end
    else
        size = 10
    end
    local okText, text = pcall(play.GetText, play)
    local hasPlay = okText and type(text) == "string" and not Secret(text) and text ~= ""
    p.tag:ClearAllPoints()
    if hasPlay then
        p.sep:ClearAllPoints()
        p.sep:SetPoint("LEFT", play, "RIGHT", 5, 0)
        p.sep:Show()
        p.tag:SetPoint("LEFT", p.sep, "RIGHT", 5, 0)
    else
        p.tag:SetPoint("LEFT", play, "LEFT", 0, 0)
    end
    p.tag:SetText(t[1])
    p.tag:SetTextColor(t[2], t[3], t[4], 1)
    p.tag:Show()
    local art = FLAGS[region]
    if art then
        p.flag:SetTexture(art)
        p.flag:SetSize(math.floor(size * 1.5 + 0.5), size)
        p.flag:ClearAllPoints()
        p.flag:SetPoint("LEFT", p.tag, "RIGHT", 4, 0)
        p.flag:Show()
    end
end

local function RetagRows()
    local sp = LFGListFrame and LFGListFrame.SearchPanel
    local box = sp and sp.ScrollBox
    if box and box.ForEachFrame then box:ForEachFrame(TagEntry) end
    -- the filtered results list draws its own rows
    if ns.OwnListRefresh then ns.OwnListRefresh() end
end

ns.LabRetagRows = RetagRows  -- the settings page's row art

if ns.WhenGroupFinder then
    ns.WhenGroupFinder(function()
        if LFGListSearchEntry_Update then hooksecurefunc("LFGListSearchEntry_Update", TagEntry) end
    end)
end

-- group settings > misc: one more switch (us only), on the end of the list
local groupMenu
GFNS.CawfeeGroupMenu = function(list)
    if not groupMenu then
        groupMenu = {}
        -- listing's end: the first title after it. misc: the last title
        local listingEnd, misc
        for i, spec in ipairs(list) do
            if i > 1 and spec.title then
                listingEnd = listingEnd or i
                misc = i
            end
        end
        listingEnd = listingEnd or #list + 1
        -- bottom of listing: region tags (us only), show playstyle
        local listing = {}
        if GetCurrentRegion and GetCurrentRegion() == 1 then
            listing[#listing + 1] = { key = "cawfeeRegionTags", label = "Region Tags",
                tip = "Shows OCE, NA, MEX or BRA after each group's playstyle, from the leader's realm.",
                onToggle = RetagRows }
        end
        listing[#listing + 1] = { key = "cawfeeShowPlaystyle", label = "Show Playstyle", default = true,
            tip = "Each group's playstyle (Learning, Relaxed, Competitive, Carry Offered) on its third line.",
            onToggle = RetagRows }
        for i, spec in ipairs(list) do
            if i == listingEnd then for _, d in ipairs(listing) do groupMenu[#groupMenu + 1] = d end end
            if i == misc then
                -- misc is display now (a copy, ellesmere's list stays as it is)
                groupMenu[#groupMenu + 1] = { title = "Display" }
            else
                groupMenu[#groupMenu + 1] = spec
            end
        end
        if listingEnd > #list then for _, d in ipairs(listing) do groupMenu[#groupMenu + 1] = d end end
    end
    return groupMenu
end

-- group settings in two columns: listing split across both, then sign up
-- under it on the left and display (any later sections too) on the right.
-- built through the hook in XF.BuildGroupMenu; returns the taller column's
-- height. the width is set each time it opens (CawfeeGroupMenuPlace).
local GROUP_COL_W = 200
GFNS.CawfeeGroupColumns = function(m, list, G)
    m:SetWidth(GROUP_COL_W * 2)
    -- sections: { title, items }
    local sections = {}
    for _, spec in ipairs(list) do
        if spec.title or #sections == 0 then sections[#sections + 1] = { title = spec.title, items = {} } end
        if not spec.title then table.insert(sections[#sections].items, spec) end
    end
    m.cawfeeCols = {}
    local cols, ys = {}, {}
    for k, point in ipairs({ "TOPLEFT", "TOP" }) do
        local col = CreateFrame("Frame", nil, m)
        col:SetPoint("TOPLEFT", m, point, 0, 0)  -- left edge, or the middle
        col:SetWidth(GROUP_COL_W)
        col:SetHeight(1)
        m.cawfeeCols[k] = col
        cols[k], ys[k] = col, 3
    end
    local function Item(k, spec)
        m.items[#m.items + 1] = spec.stepper and G.StepperItem(cols[k], ys[k], spec) or G.SwitchItem(cols[k], ys[k], spec)
        ys[k] = ys[k] + G.ITEM_H
    end
    local function Section(k, sec)
        if sec.title then ys[k] = G.AddSection(cols[k], ys[k], sec.title) end
        for _, spec in ipairs(sec.items) do Item(k, spec) end
    end
    -- listing: title on the left, its rows split down both columns
    local first = sections[1]
    if first then
        if first.title then
            ys[1] = G.AddSection(cols[1], ys[1], first.title)
            ys[2] = ys[1]
        end
        local half = math.ceil(#first.items / 2)
        for i, spec in ipairs(first.items) do Item(i <= half and 1 or 2, spec) end
        local y = math.max(ys[1], ys[2])
        ys[1], ys[2] = y, y
    end
    if sections[2] then Section(1, sections[2]) end
    for i = 3, #sections do Section(2, sections[i]) end
    -- thin line between the columns
    local div = m:CreateTexture(nil, "ARTWORK")
    div:SetWidth(CM.PP.mult)
    div:SetColorTexture(1, 1, 1, 0.10)
    div:SetPoint("TOP", m, "TOP", 0, -6)
    div:SetPoint("BOTTOM", m, "BOTTOM", 0, 6)
    return math.max(ys[1], ys[2])
end

-- as wide as the top row: from the menu's left edge (the person button,
-- in line with the search box) to the refresh button's right
GFNS.CawfeeGroupMenuPlace = function(m, owner, refresh)
    if not (m.cawfeeCols and refresh and refresh:GetRight() and owner and owner:GetLeft()) then return end
    local w = (refresh:GetRight() * refresh:GetEffectiveScale() - owner:GetLeft() * owner:GetEffectiveScale())
        / m:GetEffectiveScale()
    if w < 100 then return end
    w = math.floor(w + 0.5)
    m:SetWidth(w)
    for _, col in ipairs(m.cawfeeCols) do col:SetWidth(w / 2) end
end

-------------------------------------------------------------------------------
--  menu icons: role icons (from ellesmere's raid frames) on the tank / healer
--  / damage rows, flags on the region rows. between the checkbox and the
--  text. hook after BuildSidePanel in EUI_GroupFinder_Search.lua.
-------------------------------------------------------------------------------
local ROLE_DIR = "Interface\\AddOns\\EllesmereUIRaidFrames\\media\\"
-- the same role art for the results list's open slots (show missing roles)
local ROLE_FILE = { TANK = "tank.png", HEALER = "healer.png", DAMAGER = "dps.png" }
function ns.RoleIconTex(role)
    local f = ROLE_FILE[role]
    return f and (ROLE_DIR .. f)
end
local ICONS = {
    role_needsTank   = { ROLE_DIR .. "tank.png",   12, 12 },
    role_needsHealer = { ROLE_DIR .. "healer.png", 12, 12 },
    role_needsDamage = { ROLE_DIR .. "dps.png",    12, 12 },
    region_na  = { FLAGS.na,  15, 10 },
    region_oce = { FLAGS.oce, 15, 10 },
    region_la  = { FLAGS.la,  15, 10 },
    region_br  = { FLAGS.br,  15, 10 },
}

-- specific roles closes the roles block. misc as two columns: a divider in
-- line with the side panel's misc one, bloodlust / battle res level with its
-- misc rows, your class right under. if roles run past misc, they just stack.
local function LayoutMisc(menu, side)
    local roleG, miscG, sg = menu.cawfeeClassGrp, menu.cawfeeMiscGrp, menu.cawfeeSpecGrp
    if not (roleG and miscG and sg and menu.cawfeeRolesEnd) then return end
    local y = menu.cawfeeRolesEnd
    PlaceBlock(sg, menu, y)
    y = y + sg:GetHeight()
    local miscY, rowsY = side and side.cawfeeMiscY, side and side.cawfeeMiscRowsY
    if miscY and rowsY and miscY >= y then
        Divider(menu, miscY)
        y = rowsY
    else
        y = Divider(menu, y)
    end
    PlaceBlock(miscG, menu, y)
    y = y + miscG:GetHeight()
    -- the side panel's next row (min. rating) is taller than ours: centre on it
    local nudge = 0
    if rowsY and y == rowsY + miscG:GetHeight() and side.cawfeeEndY and menu.cawfeeItemH then
        local nextH = side.cawfeeEndY - y
        if nextH > menu.cawfeeItemH then nudge = math.floor((nextH - menu.cawfeeItemH) / 2) end
    end
    PlaceBlock(roleG, menu, y + nudge)
    y = y + nudge + roleG:GetHeight()
    local h = math.max(side and side.cawfeeEndY and (side.cawfeeEndY + 3) or 0, y + 3)
    menu:SetHeight(h)
    if side then side:SetHeight(h) end
end

GFNS.CawfeeDecorateMenu = function(menu, side)
    if menu then LayoutMisc(menu, side) end
    for _, owner in ipairs({ menu, side }) do
        local items = owner and owner.items
        if items then
            for key, art in pairs(ICONS) do
                local item = items[key]
                if item and item.label and not item.cawfeeIcon then
                    local _, cb = item.label:GetPoint(1)  -- the checkbox
                    if cb then
                        local tex = item:CreateTexture(nil, "OVERLAY")
                        tex:SetTexture(art[1])
                        tex:SetSize(art[2], art[3])
                        tex:SetPoint("LEFT", cb, "RIGHT", 6, 0)
                        item.label:ClearAllPoints()
                        item.label:SetPoint("LEFT", tex, "RIGHT", 5, 0)
                        item.label:SetPoint("RIGHT", item, "RIGHT", -4, 0)
                        item.cawfeeIcon = tex
                    end
                end
            end
        end
    end
end

-- group settings button: the people icon
GFNS.CawfeePersonTex = "Interface\\AddOns\\" .. FOLDER .. "\\media\\icons\\eui-person.png"
-- raid list button: a smaller banner than the module's own
GFNS.CawfeeRaidTex = "Interface\\AddOns\\" .. FOLDER .. "\\media\\icons\\eui-raid.png"
