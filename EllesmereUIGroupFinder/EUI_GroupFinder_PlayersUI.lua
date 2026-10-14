if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_GroupFinder_PlayersUI.lua
--  The Players page in the Dungeons & Raids rail: the player list with its
--  search and filters, and a player's detail.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local CM = EllesmereUI
local PL = ns.PL
if not PL then return end

local floor, max, min = math.floor, math.max, math.min
local ROW_H   = 24
local CTRL_W  = 110   -- the Filters button's width
local GAP     = 3     -- the search rows' gap
local DIM     = 0.35  -- dimmed rows (as the Filters menu dims the search panel)

-------------------------------------------------------------------------------
--  Widgets
-------------------------------------------------------------------------------
local function Accent()
    local a = CM.ELLESMERE_GREEN
    if a and a.r then return a.r, a.g, a.b end
    return 0.894, 0.827, 0.690
end

local function SetFS(fs, size, flags)
    local path = (CM.GetFontPath and CM.GetFontPath()) or STANDARD_TEXT_FONT
    fs:SetFont(path, size, flags or "")
end

local function Text(parent, size, r, g, b, a)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    SetFS(fs, size or 13)
    fs:SetTextColor(r or 1, g or 1, b or 1, a or 1)
    fs:SetWordWrap(false)
    fs:SetJustifyH("LEFT")
    return fs
end

local function Pixel() return (CM.PP and CM.PP.mult) or 1 end

-- A one-pixel line under a list row (the /keys window's row separators).
local function Underline(row)
    local sep = row:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(1, 1, 1, 0.10)
    local PP = CM.PP
    if PP and PP.DisablePixelSnap then PP.DisablePixelSnap(sep) end
    sep:SetHeight(Pixel())
    sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    return sep
end

local function Fill(f, r, g, b, a, layer)
    local t = f:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(r, g, b, a)
    return t
end

-- The font of the Premade Groups result list's group names: a shown
-- result's own (Name), else the font object they use (GameFontNormal).
local function ResultFont()
    local sp = _G.LFGListFrame and _G.LFGListFrame.SearchPanel
    local box = sp and sp.ScrollBox
    local found
    if box and box.ForEachFrame then
        box:ForEachFrame(function(fr)
            if not found and fr.Name and fr.Name.GetFont then
                local path, size, flags = fr.Name:GetFont()
                if path then found = { path, size, flags } end
            end
        end)
    end
    if found then return found[1], found[2], found[3] end
    local fo = _G.GameFontNormal
    if fo and fo.GetFont then return fo:GetFont() end
end

-- A Blizzard font object's face and size on one of our strings (our own colours
-- kept): the result list's title (GameFontNormal) and its dungeon line
-- (GameFontDisableSmallLeft).
local function UseFont(fs, objName)
    local fo = _G[objName]
    local path, size, flags
    if fo and fo.GetFont then path, size, flags = fo:GetFont() end
    if path then fs:SetFont(path, size, flags or "") end
end

local function ResultFontSize()
    local _, size = ResultFont()
    return size and floor(size + 0.5) or 12
end

-- Five clickable stars; clicking the current rating again clears it (unless
-- noClear). The hovered star and every one before it get a white outline.
local function Stars(parent, size, onSet, noClear)
    local f = CreateFrame("Frame", nil, parent)
    local gap = 2
    f:SetSize(size * 5 + gap * 4, size)
    f.value, f.btns, f.onSet = 0, {}, onSet
    local function Paint(n, hover)
        for i = 1, 5 do
            local b = f.btns[i]
            if i <= n then b.tex:SetVertexColor(1, 0.82, 0.30, 1) else b.tex:SetVertexColor(0.30, 0.30, 0.30, 0.9) end
            b.edge:SetShown(hover ~= nil and i <= hover)
        end
    end
    for i = 1, 5 do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(size, size)
        b:SetPoint("LEFT", f, "LEFT", (i - 1) * (size + gap), 0)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b.tex:SetTexture(PL.STAR_TEX)
        b.edge = b:CreateTexture(nil, "BACKGROUND")
        b.edge:SetPoint("CENTER")
        b.edge:SetSize(size + 3, size + 3)
        b.edge:SetTexture(PL.STAR_TEX)
        b.edge:SetVertexColor(1, 1, 1, 1)
        b.edge:Hide()
        b:SetScript("OnEnter", function() Paint(i, i) end)
        b:SetScript("OnLeave", function() Paint(f.value) end)
        b:SetScript("OnClick", function()
            local v = (f.value == i and not noClear) and 0 or i
            f.value = v
            Paint(v, i)
            if f.onSet then f.onSet(v) end
        end)
        f.btns[i] = b
    end
    function f:SetValue(n)
        self.value = n or 0
        Paint(self.value)
    end
    Paint(0)
    return f
end

-- Mouse-wheel scroll area with a thin thumb at its right edge; content in sf.child.
local function Scroll(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)
    sf:EnableMouseWheel(true)
    local thumb = sf:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(1, 1, 1, 0.25)
    thumb:SetWidth(3)
    thumb:Hide()
    function sf:UpdateThumb()
        local h, ch = self:GetHeight(), child:GetHeight()
        local maxS = max(0, ch - h)
        local cur = min(self:GetVerticalScroll(), maxS)
        if cur ~= self:GetVerticalScroll() then self:SetVerticalScroll(cur) end
        if maxS <= 0 or h <= 0 then thumb:Hide(); return end
        local th = max(24, h * h / ch)
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -((h - th) * cur / maxS))
        thumb:Show()
    end
    sf:SetScript("OnMouseWheel", function(self, delta)
        local maxS = max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(min(maxS, max(0, self:GetVerticalScroll() - delta * 48)))
        self:UpdateThumb()
    end)
    sf:SetScript("OnSizeChanged", function(self, w)
        child:SetWidth(w)
        self:UpdateThumb()
    end)
    function sf:SetContentHeight(hh)
        child:SetHeight(max(1, hh))
        self:UpdateThumb()
    end
    function sf:SyncWidth()
        local w = self:GetWidth()
        if w and w > 0 then child:SetWidth(w) end
    end
    sf.child = child
    return sf
end

-- A glyph square (the search panel's look) that toggles a coloured state.
local function GlyphToggle(parent, size, tex, color, tip, onClick)
    local b = ns.MakeGlyphButton(parent, size, tex)
    b.Glyph:SetSize(floor(size * 0.6), floor(size * 0.6))
    function b:SetOn(on)
        self.on = on
        if on then
            self.Glyph:SetVertexColor(color[1], color[2], color[3], 1)
            if ns.SetBorderColor then ns.SetBorderColor(self, color[1], color[2], color[3], 1) end
        else
            local g = ns.GLYPH or 0.6
            self.Glyph:SetVertexColor(g, g, g, 0.8)
            if ns.SetBorderColor and ns.ThemeBorder then ns.SetBorderColor(self, ns.ThemeBorder()) end
        end
    end
    b:SetScript("OnEnter", function(self)
        self.Glyph:SetVertexColor(color[1], color[2], color[3], 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(tip(self), 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self:SetOn(self.on)
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", onClick)
    b:SetOn(false)
    return b
end

-------------------------------------------------------------------------------
--  Player actions
-------------------------------------------------------------------------------
local UI = {}

-- "2096io" in the score's Raider.IO colour (Blizzard's score colour without
-- Raider.IO, white without either).
function UI.ScoreText(score)
    local r, g, b
    local rio = _G.RaiderIO
    if rio and type(rio.GetScoreColor) == "function" then
        local ok, cr, cg, cb = pcall(rio.GetScoreColor, score)
        if ok and type(cr) == "number" then r, g, b = cr, cg, cb end
        if ok and type(cr) == "table" and cr.r then r, g, b = cr.r, cr.g, cr.b end
    end
    if not r and C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor then
        local c = C_ChallengeMode.GetDungeonScoreRarityColor(score)
        if c and c.GetRGB then r, g, b = c:GetRGB() end
    end
    local text = ("%dio"):format(score)
    if not r then return text end
    return ("|cff%02x%02x%02x%s|r"):format(floor(r * 255), floor(g * 255), floor(b * 255), text)
end

function UI.Whisper(p)
    local target = p.name .. "-" .. p.realm
    if ChatFrameUtil and ChatFrameUtil.SendTell then
        ChatFrameUtil.SendTell(target)
    elseif ChatFrame_SendTell then
        ChatFrame_SendTell(target)
    end
end

function UI.Invite(p)
    local target = p.name .. "-" .. p.realm
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(target)
    elseif InviteUnit then
        InviteUnit(target)
    end
end

function UI.ConfirmRemove(key)
    local p = PL.Get(key)
    if not (p and CM.ShowConfirmPopup) then return end
    CM:ShowConfirmPopup({
        title = "Remove Player",
        message = ("Remove %s-%s, their rating, notes and run history?"):format(p.name, p.realm),
        confirmText = "Remove",
        cancelText = "Cancel",
        onConfirm = function() PL.Remove(key) end,
    })
end

function UI.PromptAdd()
    if not CM.ShowInputPopup then return end
    CM:ShowInputPopup({
        title = "Add Player",
        message = "Character name, as Name or Name-Realm.",
        placeholder = "Name-Realm",
        maxLetters = 64,
        confirmText = "Add",
        onConfirm = function(text)
            local name, realm = PL.ParseName(text)
            if not name then
                PL.Say("Couldn't read that name. Use Name or Name-Realm.")
                return
            end
            local p, key = PL.Ensure(name, realm)
            p.manual = true
            PL.Changed(key)
            if UI.open then UI.open(key) end
        end,
    })
end

function UI.PlayerMenu(key)
    local p = PL.Get(key)
    if not (p and CM.ShowContextMenu) then return end
    CM.ShowContextMenu(nil, {
        { text = "Whisper", onClick = function() UI.Whisper(p) end },
        { text = "Invite", onClick = function() UI.Invite(p) end },
        "---",
        { text = p.status == PL.STATUS_FAV and "Remove Favorite" or "Favorite",
          onClick = function() PL.ToggleStatus(key, PL.STATUS_FAV) end },
        { text = p.status == PL.STATUS_BLACK and "Remove from Blacklist" or "Blacklist",
          onClick = function() PL.ToggleStatus(key, PL.STATUS_BLACK) end },
        "---",
        { text = "View Details", onClick = function() if UI.open then UI.open(key) end end },
        { text = "|cffff7070Remove Player|r", onClick = function() UI.ConfirmRemove(key) end },
    })
end

-------------------------------------------------------------------------------
--  Players list
-------------------------------------------------------------------------------
local filters = { search = "", status = "listed", role = "all", minKey = 0 }
local sortKey, sortAsc = "lastSeen", false

local STATUS_OPTS = {
    { "listed", "All Rated", "Players you rated, favorited, blacklisted, wrote a note on or added." },
    { "fav", "Favorites", "Only your favorites." },
    { "black", "Blacklisted", "Only players you blacklisted." },
    { "unrated", "Non Rated", "Only players you have not rated yet (from your recent runs)." },
}
local ROLE_OPTS = {
    { "all", "All Roles", "Players of every role." },
    { "TANK", "Tanks", "Only players last seen as a tank." },
    { "HEALER", "Healers", "Only players last seen as a healer." },
    { "DAMAGER", "DPS", "Only players last seen as damage." },
}

local SORT_VAL = {
    name     = function(p) return (p.name or ""):lower() end,
    rating   = function(p) return p.rating or 0 end,
    lastSeen = function(p) return p.lastSeen or p.added or 0 end,
    bestKey  = function(p) return p.bestKey or 0 end,
    status   = function(p) return p.status == PL.STATUS_FAV and 2 or (p.status == PL.STATUS_BLACK and 0 or 1) end,
}

-- Status icon, the name filling the row, rating stars and best key from the right.
local PCOLS = {
    { key = "status",  header = "",       left = 2,  w = 20 },
    { key = "name",    header = "Player", left = 24 },
    { key = "rating",  header = "Rating", right = 40, w = 73 },
    { key = "bestKey", header = "Best",   right = 0,  w = 34, center = true },
}
local NAME_R = 40 + 73 + 6

local function Passes(p)
    local f = filters
    if f.status == "listed" and not PL.IsListed(p) then return false end
    if f.status == "fav" and p.status ~= PL.STATUS_FAV then return false end
    if f.status == "black" and p.status ~= PL.STATUS_BLACK then return false end
    if f.status == "unrated" and p.rating ~= nil then return false end
    if f.role ~= "all" and p.role ~= f.role then return false end
    if f.minKey > 0 and (p.bestKey or 0) < f.minKey then return false end
    if f.search ~= "" then
        local hay = ((p.name or "") .. "-" .. (p.realm or "") .. " " .. (p.notes or "")):lower()
        if not hay:find(f.search, 1, true) then return false end
    end
    return true
end

local function FiltersSet()
    return filters.status ~= "listed" or filters.role ~= "all" or (filters.minKey or 0) > 0
end

local function MakePlayerRow(parent, ctx)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.stripe = Fill(row, 1, 1, 1, 0)
    Underline(row)
    Fill(row, 1, 1, 1, 0.05, "HIGHLIGHT")
    row.status = row:CreateTexture(nil, "ARTWORK")
    row.status:SetSize(14, 14)
    row.status:SetPoint("LEFT", row, "LEFT", 5, 0)
    row.best = Text(row, 13)
    row.best:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.best:SetWidth(34)
    row.best:SetJustifyH("CENTER")
    row.stars = Stars(row, 13, function(v) if row.key then PL.SetRating(row.key, v) end end)
    row.stars:SetPoint("RIGHT", row, "RIGHT", -40, 0)
    row.name = Text(row, 13)
    row.name:SetPoint("LEFT", row, "LEFT", 24, 0)
    row.name:SetPoint("RIGHT", row.stars, "LEFT", -6, 0)
    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then UI.PlayerMenu(self.key) else ctx.open(self.key) end
    end)
    return row
end

local function FillPlayerRow(row, key, p, i)
    row.key = key
    row.stripe:SetColorTexture(1, 1, 1, 0)   -- rows are told apart by their underlines
    if p.status == PL.STATUS_FAV then
        row.status:SetTexture(PL.HEART_TEX)
        row.status:SetVertexColor(PL.FAV_COLOR[1], PL.FAV_COLOR[2], PL.FAV_COLOR[3], 1)
        row.status:Show()
    elseif p.status == PL.STATUS_BLACK then
        row.status:SetTexture(PL.BAN_TEX)
        row.status:SetVertexColor(PL.BLACK_COLOR[1], PL.BLACK_COLOR[2], PL.BLACK_COLOR[3], 1)
        row.status:Show()
    else
        row.status:Hide()
    end
    -- Name, realm and best key in the result list's group-name font, one size smaller.
    local path, size, flags = ResultFont()
    if path then
        size = max(8, (size or 13) - 1)
        row.name:SetFont(path, size, flags or "")
        row.best:SetFont(path, size, flags or "")
    end
    local role = p.role and (PL.RoleMarkup(p.role, 13) .. " ") or ""
    local note = p.notes and "  |cff8c8c8c*|r" or ""
    row.name:SetText(role .. PL.NameText(p.name, p.realm, p.class) .. note)
    row.stars:SetValue(p.rating or 0)
    row.best:SetText(p.bestKey and ("+" .. p.bestKey) or "-")
end

-- ctx: row1 = the page's search row, controls = the frame its controls go on,
-- open(key) = show a player, listR = how far the list (and its scroll thumb)
-- reaches past the page's right edge (rows stop at it).
local function BuildPlayersPage(body, ctx)
    local page = CreateFrame("Frame", nil, body)
    page:Hide()
    local function Rerender() page:Render() end
    local over = ctx.listR or 0
    local holder = ctx.controls or page
    local row1 = ctx.row1 or page

    -- The search row: search box, Filters, Reset Filters (as the search
    -- panel's search box, Filters and Search Again).
    local reset = ns.MakeResetButton(holder, row1:GetHeight() or 24)
    reset:SetPoint("RIGHT", row1, "RIGHT", 0, 0)
    local filtersBtn = ns.MakeDropButton(holder, CTRL_W)
    filtersBtn:SetPoint("RIGHT", reset, "LEFT", -GAP, 0)
    filtersBtn:SetText("Filters")
    local search = ns.MakeSearchBox(holder, "Search name or notes")
    search:HookScript("OnTextChanged", function(self, user)
        if not user then return end
        filters.search = strtrim(self:GetText() or ""):lower()
        Rerender()
    end)
    search:SetPoint("LEFT", row1, "LEFT", 0, 0)
    search:SetPoint("RIGHT", filtersBtn, "LEFT", -GAP, 0)

    local function Opt(field, key, label, tip)
        return {
            label = label, tip = tip,
            active = function() return filters[field] == key end,
            click = function() filters[field] = key; Rerender() end,
        }
    end
    local showItems, roleItems = {}, {}
    for _, o in ipairs(STATUS_OPTS) do showItems[#showItems + 1] = Opt("status", o[1], o[2], o[3]) end
    for _, o in ipairs(ROLE_OPTS) do roleItems[#roleItems + 1] = Opt("role", o[1], o[2], o[3]) end
    local function PaintFilters()
        local lbl = filtersBtn.label or filtersBtn:GetFontString()
        if lbl then
            if FiltersSet() then lbl:SetTextColor(Accent()) else lbl:SetTextColor(1, 1, 1, 1) end
        end
        reset:SetActive(FiltersSet())
    end
    local menu = ns.MakeFilterMenu(filtersBtn, {
        sections = { { title = "Show |cff5a5a5a(Pick One)|r", items = showItems }, { title = "Role |cff5a5a5a(Pick One)|r", items = roleItems } },
        number = {
            title = false, label = "Min. Best Key",
            tip = "Only players whose best key with you is at least this level.",
            get = function() return (filters.minKey or 0) > 0 and filters.minKey or nil end,
            set = function(n) filters.minKey = n or 0; Rerender() end,
        },
        onChange = PaintFilters,
        dim = function() return { page } end,   -- the list, as the Filters menu dims the results
        width = CTRL_W + GAP + (row1:GetHeight() or 24),
    })
    filtersBtn:SetScript("OnClick", function() menu:Toggle() end)
    reset:SetScript("OnClick", function()
        filters.status, filters.role, filters.minKey = "listed", "all", 0
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if menu:IsShown() then menu:Paint() end
        Rerender()
    end)

    local fs = ctx.fontSize or 12
    local hdr = CreateFrame("Frame", nil, page)
    hdr:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    hdr:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    hdr:SetHeight(20)
    hdr.cols = {}
    for _, col in ipairs(PCOLS) do
        local b = CreateFrame("Button", nil, hdr)
        b:SetHeight(20)
        if col.right then
            b:SetPoint("RIGHT", hdr, "RIGHT", -col.right, 0)
            b:SetWidth(col.w)
        elseif col.w then
            b:SetPoint("LEFT", hdr, "LEFT", col.left, 0)
            b:SetWidth(col.w)
        else
            b:SetPoint("LEFT", hdr, "LEFT", col.left, 0)
            b:SetPoint("RIGHT", hdr, "RIGHT", -NAME_R, 0)
        end
        b.label = Text(b, fs)
        b.label:SetAllPoints()
        b.label:SetJustifyH(col.center and "CENTER" or "LEFT")
        b.label:SetText(col.header)
        b:SetScript("OnClick", function()
            if sortKey == col.key then
                sortAsc = not sortAsc
            else
                sortKey, sortAsc = col.key, (col.key == "name")
            end
            Rerender()
        end)
        b:SetScript("OnEnter", function(self)
            if sortKey ~= col.key then b.label:SetTextColor(1, 1, 1, 0.8) end
            if col.header ~= "" then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText("Click to swap sorting order.", 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function()
            if sortKey ~= col.key then b.label:SetTextColor(1, 1, 1, 0.45) end
            GameTooltip:Hide()
        end)
        hdr.cols[col.key] = b
    end
    local sep = page:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(Pixel())
    sep:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("TOPRIGHT", hdr, "BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(1, 1, 1, 0.10)

    local list = Scroll(page)
    list:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -3)
    list:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", over, 0)
    local empty = Text(page, 13, 1, 1, 1, 0.5)
    empty:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -40)
    empty:SetPoint("TOPRIGHT", hdr, "BOTTOMRIGHT", 0, -40)
    empty:SetJustifyH("CENTER")
    page.rows = {}

    function page:Render()
        PaintFilters()
        for key, b in pairs(hdr.cols) do
            b.label:SetTextColor(1, 1, 1, key == sortKey and 1 or 0.45)
        end
        local players = PL.Players()
        local data = {}
        for key, p in pairs(players) do
            if Passes(p) then data[#data + 1] = key end
        end
        local val = SORT_VAL[sortKey] or SORT_VAL.lastSeen
        table.sort(data, function(a, b)
            local va, vb = val(players[a]), val(players[b])
            if va ~= vb then
                if sortAsc then return va < vb end
                return va > vb
            end
            return a < b
        end)
        list:SyncWidth()
        for i, key in ipairs(data) do
            local row = self.rows[i]
            if not row then
                row = MakePlayerRow(list.child, ctx)
                self.rows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", list.child, "TOPLEFT", 0, -(i - 1) * ROW_H)
            row:SetPoint("TOPRIGHT", list.child, "TOPRIGHT", -over, -(i - 1) * ROW_H)
            FillPlayerRow(row, key, players[key], i)
            row:Show()
        end
        for i = #data + 1, #self.rows do self.rows[i]:Hide() end
        list:SetContentHeight(#data * ROW_H)
        empty:SetShown(#data == 0)
        empty:SetText(next(players) and "No players match these filters."
            or "No players yet. Players you group with show up here; use Add Player for anyone else.")
    end
    return page
end

-------------------------------------------------------------------------------
--  A player's detail (in the list's place)
-------------------------------------------------------------------------------
-- ctx: key() = the player shown, back() = leave the page, fontSize, listR as above.
local function BuildDetailPage(body, ctx)
    local page = CreateFrame("Frame", nil, body)
    page:Hide()
    local over = ctx.listR or 0
    local function Key() return ctx.key() end
    local SQ = 28
    if ns.Search_Rows then
        local _, _, size = ns.Search_Rows()
        if size then SQ = floor(size) end
    end

    -- Top row (squares the size of the dungeon row's): the role, the name, then
    -- Favorite, Blacklist and Remove at the right edge (level with Reset
    -- Filters above).
    local remove = ns.MakeGlyphButton(page, SQ, ns.X_TEX)
    remove.Glyph:SetSize(floor(SQ * 0.5), floor(SQ * 0.5))   -- as Reset Filters' X
    remove.Glyph:SetVertexColor(1, 0.3, 0.3, 0.9)
    remove:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    remove:SetScript("OnClick", function() UI.ConfirmRemove(Key()) end)
    remove:SetScript("OnEnter", function(self)
        self.Glyph:SetVertexColor(1, 0.3, 0.3, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Remove Player", 1, 1, 1)
        GameTooltip:Show()
    end)
    remove:SetScript("OnLeave", function(self)
        self.Glyph:SetVertexColor(1, 0.3, 0.3, 0.9)
        GameTooltip:Hide()
    end)
    local black = GlyphToggle(page, SQ, PL.BAN_TEX, PL.BLACK_COLOR,
        function(b) return b.on and "Remove from Blacklist" or "Blacklist" end,
        function() PL.ToggleStatus(Key(), PL.STATUS_BLACK) end)
    black:SetPoint("RIGHT", remove, "LEFT", -GAP, 0)
    local fav = GlyphToggle(page, SQ, PL.HEART_TEX, PL.FAV_COLOR,
        function(b) return b.on and "Remove Favorite" or "Favorite" end,
        function() PL.ToggleStatus(Key(), PL.STATUS_FAV) end)
    fav:SetPoint("RIGHT", black, "LEFT", -GAP, 0)

    -- The role: a square showing it (an X for none), its menu below it.
    local ROLE_ATLAS = { TANK = "UI-LFG-RoleIcon-Tank", HEALER = "UI-LFG-RoleIcon-Healer", DAMAGER = "UI-LFG-RoleIcon-DPS" }
    -- The role: its icon alone in a bordered frame (the house border; white
    -- while hovered), an X for none; its menu (icons only) below it.
    local role = CreateFrame("Button", nil, page)
    role:SetSize(SQ, SQ)
    role:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    local px = Pixel()
    role.icon = role:CreateTexture(nil, "ARTWORK")
    role.icon:SetPoint("TOPLEFT", role, "TOPLEFT", px, -px)
    role.icon:SetPoint("BOTTOMRIGHT", role, "BOTTOMRIGHT", -px, px)
    -- Hovered: the icon lit up (an added-light copy over it), or a soft
    -- square where no role is set, so the spot reads as clickable.
    role.glow = role:CreateTexture(nil, "HIGHLIGHT")
    role.glow:SetPoint("TOPLEFT", role, "TOPLEFT", px, -px)
    role.glow:SetPoint("BOTTOMRIGHT", role, "BOTTOMRIGHT", -px, px)
    local function RoleBorder(hover)
        role.icon:SetAlpha(hover and 1 or 0.85)
    end
    function role:Paint(r)
        local atlas = r and ((GetIconForRole and GetIconForRole(r)) or ROLE_ATLAS[r])
        self.icon:ClearAllPoints()
        self.icon:SetPoint("TOPLEFT", self, "TOPLEFT", px, -px)
        self.icon:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -px, px)
        if atlas then
            self.icon:SetAtlas(atlas, false)
            self.icon:SetVertexColor(1, 1, 1, 1)
            self.icon:Show()
            self.glow:SetAtlas(atlas, false)
            self.glow:SetBlendMode("ADD")
            self.glow:SetVertexColor(1, 1, 1, 0.5)
        else
            self.icon:Hide()   -- None: no icon (the spot still opens the menu)
            self.glow:SetColorTexture(1, 1, 1, 0.12)
            self.glow:SetBlendMode("BLEND")
        end
    end
    role:SetScript("OnEnter", function(self)
        RoleBorder(true)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Role", 1, 1, 1)
        GameTooltip:AddLine("Click to set this player's role.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    role:SetScript("OnLeave", function() RoleBorder(false); GameTooltip:Hide() end)
    -- Its menu in the Filters menu's look: each role's icon and name, None.
    local roleItems = {}
    for _, r in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
        roleItems[#roleItems + 1] = {
            label = PL.RoleMarkup(r, 18) .. " " .. PL.ROLE_LABEL[r],
            active = function() local p = PL.Get(Key()); return p ~= nil and p.role == r end,
            click = function() PL.SetRole(Key(), r) end,
        }
    end
    roleItems[#roleItems + 1] = {
        label = "None",
        active = function() local p = PL.Get(Key()); return p ~= nil and p.role == nil end,
        click = function() PL.SetRole(Key(), nil) end,
    }
    local roleMenu = ns.MakeFilterMenu(role, {
        sections = { { title = "Role", items = roleItems } },
        alignLeft = true,
        width = CTRL_W,
    })
    role:SetScript("OnClick", function()
        GameTooltip:Hide()
        roleMenu:Toggle()
    end)
    RoleBorder(false)

    local name = Text(page, 15)
    name:SetPoint("LEFT", role, "RIGHT", 8, 0)
    name:SetPoint("RIGHT", fav, "LEFT", -8, 0)
    local info = Text(page, 12, 1, 1, 1, 0.7)
    info:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(SQ + 8))
    info:SetPoint("RIGHT", page, "RIGHT", 0, 0)
    info:SetJustifyH("CENTER")

    -- The rating, centred. It can be changed here, not cleared (Remove takes
    -- a player off the list).
    local stars = Stars(page, 24, function(v) PL.SetRating(Key(), v) end, true)
    stars:SetPoint("TOP", info, "BOTTOM", 0, -14)

    -- Notes, in the search box's look.
    local holder = CreateFrame("Frame", nil, page)
    holder:SetHeight(54)
    holder:SetPoint("TOP", stars, "BOTTOM", 0, -16)
    holder:SetPoint("LEFT", page, "LEFT", 0, 0)
    holder:SetPoint("RIGHT", page, "RIGHT", 0, 0)
    local notes = CreateFrame("EditBox", nil, holder)
    notes:SetAllPoints(holder)
    notes:SetAutoFocus(false)
    notes:SetMultiLine(true)
    notes:SetMaxLetters(250)
    notes:SetTextInsets(7, 7, 6, 6)
    local font = ns.StyleInputBox(notes)
    if not font then SetFS(notes, 12) end
    notes:SetTextColor(1, 1, 1, 1)
    notes.ph = notes:CreateFontString(nil, "OVERLAY")
    local fpath, fsize, fflags
    if font then fpath, fsize, fflags = font:GetFont() end
    if fpath then notes.ph:SetFont(fpath, fsize, fflags or "") else SetFS(notes.ph, 12) end
    -- Three lines of text inside the insets.
    local LINE_H = floor((fsize or 12) * 1.35 + 0.5)
    holder:SetHeight(LINE_H * 3 + 14)
    -- Measures the text as the box wraps it (same font, the inner width).
    local measure = holder:CreateFontString(nil, "OVERLAY")
    if fpath then measure:SetFont(fpath, fsize, fflags or "") else SetFS(measure, 12) end
    measure:SetWordWrap(true)
    measure:SetNonSpaceWrap(true)
    measure:Hide()
    local function Lines(text)
        local w = holder:GetWidth()
        if not (w and w > 14) then return 1 end
        measure:SetWidth(w - 14)
        measure:SetText(text ~= "" and text or " ")
        if measure.GetNumLines then return measure:GetNumLines() end
        return floor((measure:GetStringHeight() or 0) / LINE_H + 0.5)
    end
    local lastOK = ""
    notes.ph:SetTextColor(0.4, 0.4, 0.4, 1)
    notes.ph:SetPoint("TOPLEFT", notes, "TOPLEFT", 8, -6)
    notes.ph:SetText("Add a note, e.g. great healer, always uses cooldowns")
    local function PH() notes.ph:SetShown(notes:GetText() == "" and not notes:HasFocus()) end
    notes:SetScript("OnEditFocusGained", PH)
    notes:SetScript("OnEditFocusLost", function(self)
        PH()
        if Key() then PL.SetNotes(Key(), self:GetText()) end
    end)
    notes:SetScript("OnTextChanged", function(self, user)
        local text = self:GetText() or ""
        if user then
            -- One paragraph (Enter ends editing), three lines at most.
            local flat = text:gsub("[\r\n]", "")
            if flat ~= text or Lines(flat) > 3 then
                local keep = (flat ~= text and Lines(flat) <= 3) and flat or lastOK
                self:SetText(keep)
                self:SetCursorPosition(#keep)
                text = keep
            end
        end
        lastOK = text
        PH()
    end)
    notes:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    notes:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    page:SetScript("OnHide", function() if notes:HasFocus() then notes:ClearFocus() end end)

    -- Whisper and Invite: two equal buttons across.
    local whisper = ns.MakeButton(page, 100, 22, "Whisper")
    whisper:SetScript("OnClick", function() local p = PL.Get(Key()); if p then UI.Whisper(p) end end)
    whisper:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -GAP)
    local invite = ns.MakeButton(page, 100, 22, "Invite")
    invite:SetScript("OnClick", function() local p = PL.Get(Key()); if p then UI.Invite(p) end end)
    invite:SetPoint("LEFT", whisper, "RIGHT", GAP, 0)
    for b, tip in pairs({ [whisper] = "Automatically starts a /whisper to this player.",
                          [invite] = "Sends a group invite to this player." }) do
        b:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local function LayoutRows()
        local W = page:GetWidth()
        if not (W and W > 0) then return end
        local w = floor((W - GAP) / 2)
        whisper:SetWidth(w)
        invite:SetWidth(w)
    end
    page:SetScript("OnSizeChanged", LayoutRows)

    local histLbl = Text(page, 11, 1, 1, 1, 0.5)
    histLbl:SetPoint("TOPLEFT", whisper, "BOTTOMLEFT", 0, -18)
    histLbl:SetText("Last 5 Runs Together")
    local sep = page:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(Pixel())
    sep:SetPoint("TOPLEFT", histLbl, "BOTTOMLEFT", 0, -4)
    sep:SetPoint("RIGHT", page, "RIGHT", 0, 0)
    sep:SetColorTexture(1, 1, 1, 0.10)

    local list = Scroll(page)
    list:SetPoint("TOPLEFT", histLbl, "BOTTOMLEFT", 0, -7)
    list:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", over, 0)
    local empty = Text(page, 12, 1, 1, 1, 0.45)
    empty:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -6)
    empty:SetText("No runs recorded with this player yet.")
    page.rows = {}
    local fsz = ctx.fontSize or 12

    function page:Render()
        local p = PL.Get(Key())
        if not p then
            ctx.back()
            return
        end
        LayoutRows()
        UseFont(name, "GameFontNormal")
        UseFont(info, "GameFontDisableSmallLeft")
        name:SetText(PL.NameText(p.name, p.realm, p.class))
        role:Paint(p.role)
        local parts = { ("Runs Together: %d"):format(p.runCount or 0) }
        if p.rio then parts[#parts + 1] = UI.ScoreText(p.rio) end
        if p.lastSeen then parts[#parts + 1] = "Last Seen: " .. PL.Day(p.lastSeen) end
        info:SetText(table.concat(parts, "   |cff606060|||r   "))
        stars:SetValue(p.rating or 0)
        fav:SetOn(p.status == PL.STATUS_FAV)
        black:SetOn(p.status == PL.STATUS_BLACK)
        if not notes:HasFocus() then
            lastOK = p.notes or ""
            notes:SetText(p.notes or "")
            PH()
        end

        list:SyncWidth()
        local runs = p.runs or {}
        for i, r in ipairs(runs) do
            local row = self.rows[i]
            if not row then
                row = CreateFrame("Frame", nil, list.child)
                row:SetHeight(22)
                row.stripe = Fill(row, 1, 1, 1, 0)
                Underline(row)
                row.when = Text(row, fsz, 1, 1, 1, 0.55)
                row.when:SetPoint("LEFT", row, "LEFT", 4, 0)
                row.when:SetWidth(52)
                row.kind = Text(row, fsz)
                row.kind:SetPoint("LEFT", row, "LEFT", 58, 0)
                row.kind:SetWidth(56)
                row.extra = Text(row, fsz, 1, 1, 1, 0.6)
                row.extra:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                row.extra:SetJustifyH("RIGHT")
                row.text = Text(row, fsz)
                row.text:SetPoint("LEFT", row, "LEFT", 116, 0)
                row.text:SetPoint("RIGHT", row, "RIGHT", -30, 0)
                self.rows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", list.child, "TOPLEFT", 0, -(i - 1) * 22)
            row:SetPoint("TOPRIGHT", list.child, "TOPRIGHT", -over, -(i - 1) * 22)
            row.stripe:SetColorTexture(1, 1, 1, 0)
            for _, fs in ipairs({ row.when, row.kind, row.text, row.extra }) do
                UseFont(fs, "GameFontDisableSmallLeft")
            end
            row.when:SetText(PL.Day(r.t))
            row.kind:SetText(PL.KindText(r.kind))
            row.text:SetText(PL.RunText(r))
            row.extra:SetText(PL.RoleMarkup(r.role, 18))
            row:Show()
        end
        for i = #runs + 1, #self.rows do self.rows[i]:Hide() end
        list:SetContentHeight(#runs * 22)
        empty:SetShown(#runs == 0)
    end
    return page
end

-------------------------------------------------------------------------------
--  The rail page
-------------------------------------------------------------------------------
local list, detail, openKey
local ctl, block, back, add, railPage

local function Bottom()
    local sl = railPage and railPage.slots
    if not (sl and back) then return end
    back:ClearAllPoints()
    back:SetPoint("BOTTOMLEFT", railPage, "BOTTOMLEFT", sl[1], sl[3])
    back:SetSize(sl[2], sl[4])
    add:ClearAllPoints()
    add:SetPoint("BOTTOMLEFT", railPage, "BOTTOMLEFT", sl[1] + sl[5], sl[3])
    add:SetSize(sl[2], sl[4])
end

local function ShowList()
    openKey = nil
    if detail then detail:Hide() end
    if ctl then ctl:SetAlpha(1) end
    if block then block:Hide() end
    if back then back:Disable() end
    Bottom()
    if list then
        list:Show()
        list:Render()
    end
end

local function ShowPlayer(key)
    if not (list and PL.Get(key)) then return end
    openKey = key
    list:Hide()
    ctl:SetAlpha(DIM)
    block:Show()
    back:Enable()
    detail:Show()
    detail:Render()
end
UI.open = ShowPlayer

ns.RegisterRailPage({
    key = "players",
    label = "Players",
    art = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\rail\\player-group.png",
    noTitle = true,
    toggle = "Player Ratings",
    toggleTip = "A Players entry in the Dungeons & Raids rail: everyone you ran a dungeon, key or raid with, with your rating, favorite / blacklist and notes for each. Also in unit tooltips and on player right-click menus.",
    build = function(body, page)
        railPage = page
        local pad = body.pad or 12
        -- Lists run on past the body to the thumb's spot (centred in the
        -- padding); rows stop at the padding line.
        local over = pad / 2 + 1.5
        local fontSize = ResultFontSize()
        ctl = CreateFrame("Frame", nil, body)
        ctl:SetAllPoints(page)
        list = BuildPlayersPage(body, {
            row1 = page.row1, controls = ctl, listR = over, fontSize = fontSize, open = ShowPlayer,
        })
        detail = BuildDetailPage(body, {
            listR = over, fontSize = fontSize,
            key = function() return openKey end,
            back = ShowList,
        })
        -- Both start at the dungeon row's top (the row is free on this page).
        for _, f in ipairs({ list, detail }) do
            f:SetPoint("TOPLEFT", page.band, "TOPLEFT", 0, 0)
            f:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
        end
        -- Over the search row while a player shows: it stays visible, dimmed, but takes no clicks.
        block = CreateFrame("Frame", nil, body)
        block:SetAllPoints(page.row1)
        block:SetFrameLevel(ctl:GetFrameLevel() + 20)
        block:EnableMouse(true)
        block:Hide()
        back = ns.MakeButton(body, 140, 22, BACK or "Back")
        back:SetScript("OnClick", ShowList)
        add = ns.MakeButton(body, 140, 22, "Add Player")
        add:SetScript("OnClick", function() UI.PromptAdd() end)
    end,
    show = ShowList,
})

PL.OnChange(function()
    if detail and detail:IsVisible() then
        detail:Render()
    elseif list and list:IsVisible() then
        list:Render()
    end
end)
