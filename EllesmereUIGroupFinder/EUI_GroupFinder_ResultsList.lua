if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ResultsList.lua  -  EllesmereUI Group Finder
--  test: our own premade results list. blizzard's list keeps working but is
--  hidden; in its place we draw only the groups that pass the filters,
--  packed with no gaps, so filtered groups are gone instead of faded. we only
--  read the results; blizzard's list, data and order are never written.
--  click a row to select it (blizzard's sign up button then works),
--  double-click to sign up - the same calls the module's quick signup makes.
--  when results go secret (keys, restricted content) ours steps aside and
--  blizzard's list shows again. saved in EllesmereUIDB.cawfeeOwnList
--  { enabled, rowHeight }; nothing is built or listened to while it's off.
--  hooks on local/cawfee: Refilter (ns.CawfeeRefilter), filter checks
--  (ns.CawfeePasses, ns.CawfeeResultsSecret), redecorate (ns.CawfeeRedecorate)
-------------------------------------------------------------------------------
local _, ns = ...
local GFNS = ns
local EUI = EllesmereUI

local DUNGEONS, RAIDS = 2, 3
local X_TEX = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png"
local CANCEL_SZ = 24  -- the search again button's size
local GAP = 2
local function Secret(v) return issecretvalue and issecretvalue(v) or false end
local function Readable(t) return type(t) == "table" and not Secret(t) and not (canaccesstable and not canaccesstable(t)) end

local function DB()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    local t = EllesmereUIDB.cawfeeOwnList
    if type(t) ~= "table" then
        t = {}
        EllesmereUIDB.cawfeeOwnList = t
    end
    return t
end
function ns.OwnListOn() return DB().enabled == true end
function ns.OwnListRowHeight() return tonumber(DB().rowHeight) or 50 end
function ns.OwnListOpt(k) return DB()[k] ~= false end  -- playstyle, regionTags (nil = on)
-- text sizes: title, dungeon / raid name, the playstyle / region line
local SIZE_DEFAULTS = { titleSize = 12, nameSize = 10, lineSize = 10 }
function ns.OwnListSize(k) return tonumber(DB()[k]) or SIZE_DEFAULTS[k] end
function ns.SetOwnListSize(k, v)
    DB()[k] = v
    if ns.OwnListRefresh then ns.OwnListRefresh() end
end
function ns.SetOwnListOpt(k, v)
    DB()[k] = v and true or false
    if ns.OwnListRefresh then ns.OwnListRefresh() end
end

local SP, frame, body, rows, shown = nil, nil, nil, {}, {}
local scrollPx = 0
local active = false
local guard = false
local lastClickID, lastClickTime = nil, 0

local function Accent()
    local a = EUI.ELLESMERE_GREEN
    if a then return a.r, a.g, a.b end
    return 0.05, 0.82, 0.62
end

-------------------------------------------------------------------------------
--  which groups show: blizzard's order, applications first like blizzard,
--  only the ones that pass the filters
-------------------------------------------------------------------------------
local function Collect()
    wipe(shown)
    local res = SP and SP.results
    if type(res) ~= "table" then return end
    local seen = {}
    local apps = C_LFGList.GetApplications() or {}
    for _, id in ipairs(apps) do
        if not Secret(id) and not seen[id] then
            seen[id] = true
            shown[#shown + 1] = id
        end
    end
    for _, id in ipairs(res) do
        if not Secret(id) and not seen[id] then
            seen[id] = true
            if not GFNS.CawfeePasses or GFNS.CawfeePasses(id) then shown[#shown + 1] = id end
        end
    end
end

-------------------------------------------------------------------------------
--  right-click: the same three things blizzard's row menu offers, in
--  ellesmereui's context menu
-------------------------------------------------------------------------------
function ns.OwnListMenu(anchor, id)
    if not EUI.ShowContextMenu then return end
    local info = C_LFGList.GetSearchResultInfo(id)
    if not Readable(info) then return end
    local leader = info.leaderName
    if Secret(leader) then leader = nil end
    local items = {
        { text = WHISPER_LEADER or "Whisper Leader", noLoc = true,
          isDisabled = function() return not leader end,
          tooltip = not leader and (LFG_LIST_MUST_SIGN_UP_TO_WHISPER or "Sign up to whisper the leader") or nil,
          onClick = function() ChatFrameUtil.SendTell(leader) end },
        "---",
        { text = LFG_LIST_REPORT_GROUP_FOR or "Report Group", noLoc = true,
          onClick = function() LFGList_ReportListing(id, leader) end },
        { text = REPORT_GROUP_FINDER_ADVERTISEMENT or "Report Advertisement", noLoc = true,
          onClick = function() LFGList_ReportAdvertisement(id) end },
    }
    EUI.ShowContextMenu(anchor, items)
end

-------------------------------------------------------------------------------
--  a row
-------------------------------------------------------------------------------
local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3 }

local function MakeRow(i)
    local r = CreateFrame("Button", nil, body)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, 0.03)
    r.sel = r:CreateTexture(nil, "BORDER")
    r.sel:SetAllPoints()
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.06)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.act = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.act:SetJustifyH("LEFT")
    r.act:SetWordWrap(false)
    -- after the activity: "| Relaxed | OCE [flag]"
    r.sep1 = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.sep1:SetText("||")
    r.style = r:CreateFontString(nil, "OVERLAY", "GameFontGreenSmall")
    r.sep2 = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.sep2:SetText("||")
    r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.flag = r:CreateTexture(nil, "OVERLAY")
    r.flag:SetSize(15, 10)
    -- cancel an application, like blizzard's x
    r.cancel = CreateFrame("Button", nil, r)
    r.cancel.bg = r.cancel:CreateTexture(nil, "BACKGROUND")
    r.cancel.bg:SetAllPoints()
    r.cancel.bg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
    r.cancel.edge = EUI.MakeBorder(r.cancel, 0.25, 0.25, 0.25, 1, EUI.PanelPP)
    r.cancel.tex = r.cancel:CreateTexture(nil, "OVERLAY")
    r.cancel.tex:SetTexture(X_TEX)
    r.cancel.tex:SetPoint("CENTER")
    r.cancel.tex:SetVertexColor(0.8, 0.8, 0.8, 1)
    r.cancel:SetScript("OnEnter", function(self)
        self.tex:SetVertexColor(1, 0.3, 0.3, 1)
        if self.edge and self.edge.SetColor then self.edge:SetColor(1, 0.3, 0.3, 1) end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(CANCEL_SIGN_UP or "Cancel Sign Up")
        GameTooltip:Show()
    end)
    r.cancel:SetScript("OnLeave", function(self)
        self.tex:SetVertexColor(0.8, 0.8, 0.8, 1)
        if self.edge and self.edge.SetColor then self.edge:SetColor(0.25, 0.25, 0.25, 1) end
        GameTooltip_Hide()
    end)
    r.cancel:SetScript("OnClick", function(self)
        local id = self:GetParent().resultID
        if id and not Secret(id) then C_LFGList.CancelApplication(id) end
    end)
    r.status = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.status:SetJustifyH("RIGHT")
    r.score = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.score:SetJustifyH("RIGHT")
    r.icons = {}
    for k = 1, 5 do
        local t = r:CreateTexture(nil, "ARTWORK")
        r.icons[k] = t
    end
    r:SetScript("OnClick", function(self, button)
        local id = self.resultID
        if not id or not active then return end
        if button == "RightButton" then return ns.OwnListMenu(self, id) end
        local now = GetTime()
        local double = lastClickID == id and (now - lastClickTime) < 0.4
        lastClickID, lastClickTime = id, now
        -- the checks blizzard's own row click makes, read-only
        if not LFGListSearchPanelUtil_CanSelectResult(id) then return end
        if SP.selectedResult ~= id then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            LFGListSearchPanel_SelectResult(SP, id)
        end
        if double and SP.SignUpButton and SP.SignUpButton:IsEnabled() then
            lastClickID = nil
            LFGListSearchPanel_SignUp(SP)
        end
    end)
    r:SetScript("OnEnter", function(self)
        if not self.resultID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 25, 0)
        LFGListUtil_SetSearchEntryTooltip(GameTooltip, self.resultID)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = r
    return r
end

local function SetSize(fs, size)
    local ok, path, _, flags = pcall(fs.GetFont, fs)
    if ok and path then fs:SetFont(path, size, flags or "") end
end

local function IconSize(h)
    local c = GFNS.Cfg and GFNS.Cfg()
    local pct = tonumber(c and c.iconSize) or (GFNS.DEFAULTS and GFNS.DEFAULTS.iconSize) or 125
    return math.max(8, math.min(h - 4, math.floor(16 * pct / 100 + 0.5)))
end

local function Layout(r, h)
    local pad = 6
    local tS, nS, lS = ns.OwnListSize("titleSize"), ns.OwnListSize("nameSize"), ns.OwnListSize("lineSize")
    SetSize(r.name, tS)
    SetSize(r.act, nS)
    for _, fs in ipairs({ r.sep1, r.style, r.sep2, r.tag }) do SetSize(fs, lS) end
    -- which lines fit: always the title, then the dungeon, then the third
    local room = h - 4
    local lines = { tS + 2 }
    if room >= tS + nS + 6 then lines[2] = nS + 2 end
    if lines[2] and room >= tS + nS + lS + 10 then lines[3] = lS + 2 end
    local total = 0
    for _, lh in ipairs(lines) do total = total + lh end
    total = total + (#lines - 1) * 2
    local y = math.floor((h - total) / 2)
    r.lineY = {}
    for i, lh in ipairs(lines) do
        r.lineY[i] = y
        y = y + lh + 2
    end
    r.name:ClearAllPoints()
    r.name:SetPoint("TOPLEFT", r, "TOPLEFT", pad, -r.lineY[1])
    r.act:ClearAllPoints()
    if lines[2] then
        r.act:SetPoint("TOPLEFT", r, "TOPLEFT", pad, -r.lineY[2])
        r.act:Show()
    else
        r.act:Hide()
    end
    r.lines = #lines
    r.pad = pad

    local isz = IconSize(h)
    local x = -pad
    for k = 5, 1, -1 do
        local t = r.icons[k]
        t:SetSize(isz, isz)
        t:ClearAllPoints()
        t:SetPoint("RIGHT", r, "RIGHT", x, 0)
        x = x - isz - 2
    end
    r.score:ClearAllPoints()
    r.score:SetPoint("RIGHT", r, "RIGHT", x - 4, 0)
    local csz = math.min(CANCEL_SZ, h - 4)
    r.cancel:SetSize(csz, csz)
    r.cancel.tex:SetSize(math.floor(csz * 0.5), math.floor(csz * 0.5))
    r.cancel:ClearAllPoints()
    r.cancel:SetPoint("RIGHT", r.score, "LEFT", -8, 0)
    r.status:ClearAllPoints()
    r.status:SetPoint("RIGHT", r.cancel, "LEFT", -6, 0)
    r.name:SetPoint("RIGHT", r.status, "LEFT", -8, 0)
    r.act:SetPoint("RIGHT", r.status, "LEFT", -8, 0)
end

-- line three: "Relaxed | OCE [flag]" (either part can be off or missing)
local function LineThree(r, id, info)
    for _, p in ipairs({ r.sep1, r.style, r.sep2, r.tag, r.flag }) do p:Hide() end
    if (r.lines or 0) < 3 then return end
    local style = ""
    local ps = info.generalPlaystyle
    if ns.OwnListOpt("playstyle") and type(ps) == "number" and not Secret(ps) then
        style = _G["GROUP_FINDER_GENERAL_PLAYSTYLE" .. ps] or ""
    end
    local tag, tr, tg, tb, flag
    if ns.OwnListOpt("regionTags") and ns.RegionTagOf then tag, tr, tg, tb, flag = ns.RegionTagOf(id) end
    local prev
    local function Put(p, gap)
        p:ClearAllPoints()
        if prev then p:SetPoint("LEFT", prev, "RIGHT", gap, 0)
        else p:SetPoint("TOPLEFT", r, "TOPLEFT", r.pad, -r.lineY[3]) end
        p:Show()
        prev = p
    end
    if style ~= "" then
        r.style:SetText(style)
        Put(r.style)
    end
    if tag then
        if prev then Put(r.sep2, 4) end
        r.tag:SetText(tag)
        r.tag:SetTextColor(tr, tg, tb, 1)
        Put(r.tag, 4)
        if flag then
            local fh = math.max(8, ns.OwnListSize("lineSize"))
            r.flag:SetSize(math.floor(fh * 1.5 + 0.5), fh)
            r.flag:SetTexture(flag)
            Put(r.flag, 4)
        end
    end
end

local function Fill(r, id)
    r.resultID = id
    local info = C_LFGList.GetSearchResultInfo(id)
    if not Readable(info) then r:Hide() return end
    -- the title is protected text: handed straight to the font string
    r.name:SetText(info.name)
    local acts = info.activityIDs
    local act = type(acts) == "table" and not Secret(acts) and acts[1]
    local ai = act and not Secret(act) and C_LFGList.GetActivityInfoTable(act)
    r.act:SetText(ai and ai.fullName or "")
    LineThree(r, id, info)
    local score = info.leaderOverallDungeonScore
    if type(score) == "number" and not Secret(score) and score > 0 then
        local c = C_ChallengeMode.GetDungeonScoreRarityColor(score)
        r.score:SetText(c and c:WrapTextInColorCode(score) or score)
    else
        r.score:SetText("")
    end
    local _, appStatus = C_LFGList.GetApplicationInfo(id)
    local st = not Secret(appStatus) and STATUS[appStatus]
    if info.isDelisted and not Secret(info.isDelisted) then st = STATUS.declined_delisted end
    if st then
        r.status:SetText(st[1])
        r.status:SetTextColor(st[2], st[3], st[4], 1)
    else
        r.status:SetText("")
    end
    r.cancel:SetShown(appStatus == "applied" and not Secret(appStatus))
    -- members as class icons, tanks first; open spots greyed
    local members = {}
    local n = info.numMembers
    if type(n) == "number" and not Secret(n) then
        for k = 1, n do
            local p = C_LFGList.GetSearchResultPlayerInfo(id, k)
            if Readable(p) and p.classFilename and not Secret(p.classFilename) then
                members[#members + 1] = { cls = p.classFilename, role = p.assignedRole }
            end
        end
    end
    table.sort(members, function(a, b) return (ROLE_ORDER[a.role] or 4) < (ROLE_ORDER[b.role] or 4) end)
    local cap = ai and ai.maxNumPlayers or 5
    for k = 1, 5 do
        local t, m = r.icons[k], members[k]
        if cap > 5 then
            t:Hide()
        elseif m then
            t:SetAtlas("classicon-" .. m.cls:lower())
            t:SetDesaturated(false)
            t:SetAlpha(1)
            t:Show()
        elseif k <= cap then
            t:SetAtlas("groupfinder-icon-emptyslot")
            t:SetAlpha(0.5)
            t:Show()
        else
            t:Hide()
        end
    end
    if cap > 5 then
        -- raids: just the count
        r.score:SetText((n or "?") .. "/" .. cap)
    end
    local ar, ag, ab = Accent()
    r.sel:SetColorTexture(ar, ag, ab, SP.selectedResult == id and 0.18 or 0)
    r:SetAlpha((st and st ~= STATUS.applied and st ~= STATUS.invited) and 0.5 or 1)
    r:Show()
end

-------------------------------------------------------------------------------
--  the list
-------------------------------------------------------------------------------
local empty, thumb

local function Paint()
    if not (frame and active) then return end
    local h = ns.OwnListRowHeight()
    local height = body:GetHeight() or 0
    local per = h + GAP
    local maxPx = math.max(0, #shown * per - GAP - height)
    scrollPx = math.max(0, math.min(scrollPx, maxPx))
    local first = math.floor(scrollPx / per)
    local slots = math.ceil(height / per) + 1
    for i = 1, slots do
        local r = rows[i] or MakeRow(i)
        local idx = first + i
        local id = shown[idx]
        local y = (idx - 1) * per - scrollPx
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
        r:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -y)
        r:SetHeight(h)
        if id and y < height then
            Layout(r, h)
            Fill(r, id)
        else
            r.resultID = nil
            r:Hide()
        end
    end
    for i = slots + 1, #rows do rows[i]:Hide() end
    -- a slim thumb on the right while there's more than fits
    if maxPx > 0 then
        local share = height / (maxPx + height)
        local th = math.max(16, height * share)
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -(height - th) * (scrollPx / maxPx))
        thumb:Show()
    else
        thumb:Hide()
    end
    if SP.searching then
        empty:SetText("Searching...")
    elseif #shown == 0 then
        local total = type(SP.results) == "table" and #SP.results or 0
        empty:SetText(total > 0 and (total .. " groups found, none match your filters") or "No groups found")
    else
        empty:SetText("")
    end
end

-- blizzard's list hidden while ours shows; the module's own dimming sets its
-- alpha back, so it's held at 0 while we're active
local function HoldHidden(f, a)
    if guard or not active or a == 0 then return end
    guard = true
    f:SetAlpha(0)
    guard = false
end

local function Build()
    if frame then return end
    SP = LFGListFrame and LFGListFrame.SearchPanel
    if not (SP and SP.ScrollBox) then return end
    frame = CreateFrame("Frame", nil, SP)
    frame:SetPoint("TOPLEFT", SP.ScrollBox, "TOPLEFT", 3, 0)
    frame:SetPoint("BOTTOMRIGHT", SP.ScrollBar or SP.ScrollBox, "BOTTOMRIGHT", 0, 0)
    frame:SetFrameLevel(SP.ScrollBox:GetFrameLevel() + 10)
    frame:EnableMouse(true)  -- blizzard's hidden rows never get the clicks
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        -- a row per notch
        scrollPx = scrollPx - delta * (ns.OwnListRowHeight() + GAP)
        Paint()
    end)
    frame:SetScript("OnSizeChanged", Paint)
    body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", SP.ScrollBox, "BOTTOMRIGHT", -3, 0)
    body:SetClipsChildren(true)  -- the bottom row cut off at the edge
    empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOP", frame, "TOP", 0, -30)
    thumb = frame:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    thumb:SetColorTexture(1, 1, 1, 0.3)
    hooksecurefunc(SP.ScrollBox, "SetAlpha", HoldHidden)
    if SP.ScrollBar then hooksecurefunc(SP.ScrollBar, "SetAlpha", HoldHidden) end
    hooksecurefunc("LFGListSearchPanel_UpdateResults", function(panel)
        if panel == SP then ns.OwnListRefresh() end
    end)
    frame:SetScript("OnEvent", function(_, event)
        if event == "LFG_LIST_SEARCH_RESULT_UPDATED" or event == "LFG_LIST_APPLICATION_STATUS_UPDATED" then
            Paint()
        end
    end)
end

-- on or off for the current state: ours only with the setting on, the panel
-- showing a dungeon / raid search, and readable results
function ns.OwnListRefresh()
    local want = ns.OwnListOn()
    if want and not frame then Build() end
    if not frame then return end
    local cat = SP.categoryID
    local secret = GFNS.CawfeeResultsSecret and GFNS.CawfeeResultsSecret()
    local now = want and SP:IsVisible() and (cat == DUNGEONS or cat == RAIDS) and not secret
    if now ~= active then
        active = now
        local a = active and 0 or 1
        guard = true
        SP.ScrollBox:SetAlpha(a)
        if SP.ScrollBar then SP.ScrollBar:SetAlpha(a) end
        guard = false
        frame:SetShown(active)
        if active then
            frame:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
            frame:RegisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED")
        else
            frame:UnregisterAllEvents()
        end
    end
    if active then
        Collect()
        Paint()
    end
end

function ns.SetOwnListOn(v)
    DB().enabled = v and true or nil
    scrollPx = 0
    ns.OwnListRefresh()
end
function ns.SetOwnListRowHeight(v)
    DB().rowHeight = v
    if active then Paint() end
end

-- the filters changed, a display setting changed: same list, new contents
GFNS.CawfeeRefilter = function() if active or ns.OwnListOn() then ns.OwnListRefresh() end end
GFNS.CawfeeRedecorate = GFNS.CawfeeRefilter

-- menus open: dim ours like the module dims blizzard's list
local prevDim = GFNS.CawfeeOnDim
GFNS.CawfeeOnDim = function(on)
    if prevDim then prevDim(on) end
    if frame then frame:SetAlpha(on and 0.35 or 1) end
end

if ns.WhenGroupFinder then
    ns.WhenGroupFinder(function()
        local sp = LFGListFrame and LFGListFrame.SearchPanel
        if sp then
            sp:HookScript("OnShow", function() if ns.OwnListOn() then ns.OwnListRefresh() end end)
        end
    end)
end
