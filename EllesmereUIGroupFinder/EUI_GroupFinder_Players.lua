if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_GroupFinder_Players.lua
--  Player ratings: rating, favorite / blacklist and notes per player, the group
--  runs shared with them, tooltip lines, right-click rating and join alerts.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local CM = EllesmereUI

local PL = {}
ns.PL = PL

local MAX_PLAYER_RUNS  = 5    -- runs together kept per player
local MIN_SESSION_SEC  = 60   -- zoning in and straight back out is not a run
local MPLUS_DIFFICULTY = 8
local issecretvalue    = _G.issecretvalue

PL.STATUS_FAV, PL.STATUS_BLACK = "fav", "black"
PL.KIND_LABEL = { mplus = "Mythic+", dungeon = "Dungeon", raid = "Raid" }
PL.KIND_COLOR = {
    mplus   = { 0.72, 0.45, 1.00 },
    dungeon = { 0.35, 0.70, 1.00 },
    raid    = { 1.00, 0.55, 0.20 },
}
PL.FAV_COLOR   = { 0.35, 0.85, 0.40 }
PL.BLACK_COLOR = { 0.95, 0.30, 0.30 }
PL.ROLE_LABEL  = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }
local ICONS    = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\icons\\"
PL.STAR_TEX    = ICONS .. "star.png"
PL.HEART_TEX   = ICONS .. "heart.png"
PL.BAN_TEX     = ICONS .. "ban.png"
PL.TITLE       = "|cff0cd29fGroup Finder|r"

-- The Dungeons & Raids role art (GetIconForRole); large atlases scale down cleanly.
local ROLE_ATLAS = { TANK = "UI-LFG-RoleIcon-Tank", HEALER = "UI-LFG-RoleIcon-Healer", DAMAGER = "UI-LFG-RoleIcon-DPS" }

local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function PlainString(v)
    if type(v) == "string" and not IsSecret(v) and v ~= "" then return v end
end
local function PlainNumber(v)
    if type(v) == "number" and not IsSecret(v) then return v end
end
PL.PlainString, PL.PlainNumber = PlainString, PlainNumber

-- Settings (the search table; Group Finder settings page).
local PL_DEFAULTS = {
    plTooltip = true,         -- rating, status, runs and notes in unit tooltips
    plUnitMenu = true,        -- Rate Player on player right-click menus
    plBlacklistAlert = true,  -- chat warning when a blacklisted player joins
    plAlertSound = true,
    plFavoriteAlert = false,  -- chat note when a favorite joins
    plRaiderIO = true,        -- save Raider.IO scores with runs
    plPruneDays = 30,         -- forget unrated, unflagged players after N days (0 = never)
}
PL.DEFAULTS = PL_DEFAULTS

function PL.Opt(key)
    local c = ns.Cfg and ns.Cfg()
    local v = c and c[key]
    if v == nil then v = PL_DEFAULTS[key] end
    return v
end

-- The whole feature: the Player Ratings switch (its rail entry's).
function PL.On()
    local c = ns.Cfg and ns.Cfg()
    return not (c and c.railPage_players == false)
end

function PL.Say(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PL.TITLE .. ": " .. msg)
end

-------------------------------------------------------------------------------
--  Store
-------------------------------------------------------------------------------
local function Players()
    local sv = ns.PlayersStore()
    if type(sv.players) ~= "table" then sv.players = {} end
    return sv.players
end
PL.Players = Players

local listeners = {}
function PL.OnChange(fn) listeners[#listeners + 1] = fn end
function PL.Changed(key)
    for i = 1, #listeners do listeners[i](key) end
end

-- The realm form UnitFullName returns: no spaces or hyphens.
local function NormRealm(realm)
    realm = PlainString(realm)
    if not realm then return nil end
    realm = realm:gsub("[%s%-]", "")
    return realm ~= "" and realm or nil
end

local function MyRealm()
    return NormRealm(GetNormalizedRealmName and GetNormalizedRealmName()) or NormRealm(GetRealmName()) or "?"
end
PL.MyRealm = MyRealm

function PL.Key(name, realm) return name .. "-" .. realm end

-- "Name" or "Name-Realm", as typed or as a chat link gives it.
function PL.ParseName(text)
    text = type(text) == "string" and strtrim(text) or ""
    if text == "" then return nil end
    local name, realm = text:match("^([^%-]+)%-(.+)$")
    if not name then name, realm = text, MyRealm() end
    name = strtrim(name)
    realm = NormRealm(realm)
    if name == "" or not realm or name:find("%s") then return nil end
    -- Typed realms lose their case ("area52"): reuse a known spelling, so the
    -- key matches the one runs are recorded under.
    local low = realm:lower()
    if low == MyRealm():lower() then
        realm = MyRealm()
    else
        local known
        for _, p in pairs(Players()) do
            if p.realm and p.realm:lower() == low then known = p.realm; break end
        end
        realm = known or (realm:sub(1, 1):upper() .. realm:sub(2))
    end
    -- First letter up, the rest down, byte-wise (accented letters untouched).
    name = name:sub(1, 1):upper() .. name:sub(2):lower()
    return name, realm
end

function PL.Get(key) return key and Players()[key] end

function PL.Ensure(name, realm, class, role)
    local players = Players()
    local key = PL.Key(name, realm)
    local p = players[key]
    if not p then
        p = { name = name, realm = realm, added = time(), runs = {} }
        players[key] = p
    end
    if type(p.runs) ~= "table" then p.runs = {} end
    if class then p.class = class end
    if role and role ~= "NONE" then p.role = role end
    return p, key
end

-- Shown in the Players list and never pruned: anything you set yourself.
function PL.IsListed(p)
    return p ~= nil and (p.rating ~= nil or p.status ~= nil or p.notes ~= nil or p.manual == true)
end

local function Touch(key)
    local p = PL.Get(key)
    if p then p.touched = time() end
    PL.Changed(key)
end

function PL.SetRating(key, n)
    local p = PL.Get(key)
    if not p then return end
    n = tonumber(n)
    p.rating = (n and n >= 1 and n <= 5) and math.floor(n) or nil
    Touch(key)
end

function PL.SetStatus(key, status)
    local p = PL.Get(key)
    if not p then return end
    p.status = (status == PL.STATUS_FAV or status == PL.STATUS_BLACK) and status or nil
    Touch(key)
end

function PL.ToggleStatus(key, status)
    local p = PL.Get(key)
    if not p then return end
    PL.SetStatus(key, p.status ~= status and status or nil)
end

function PL.SetNotes(key, text)
    local p = PL.Get(key)
    if not p then return end
    text = type(text) == "string" and strtrim((text:gsub("[\r\n]+", " "))) or ""
    local new = text ~= "" and text or nil
    if new == p.notes then return end
    p.notes = new
    Touch(key)
end

function PL.SetRole(key, role)
    local p = PL.Get(key)
    if not p then return end
    p.role = PL.ROLE_LABEL[role] and role or nil
    Touch(key)
end

function PL.Remove(key)
    Players()[key] = nil
    PL.Changed(key)
end

-------------------------------------------------------------------------------
--  Display helpers (page, tooltip, chat alerts)
-------------------------------------------------------------------------------
function PL.StarsMarkup(n, size)
    n, size = n or 0, size or 12
    local on  = ("|T%s:%d:%d:0:0:64:64:0:64:0:64:255:209:77|t"):format(PL.STAR_TEX, size, size)
    local off = ("|T%s:%d:%d:0:0:64:64:0:64:0:64:90:90:90|t"):format(PL.STAR_TEX, size, size)
    return on:rep(n) .. off:rep(5 - n)
end

function PL.RoleMarkup(role, size)
    local atlas = ROLE_ATLAS[role] and ((GetIconForRole and GetIconForRole(role)) or ROLE_ATLAS[role])
    if atlas and CreateAtlasMarkup then return CreateAtlasMarkup(atlas, size or 14, size or 14) end
    return ""
end

function PL.ClassHex(class)
    local c = class and not IsSecret(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c and CM.GetClassColor then c = CM.GetClassColor(class) or c end
    if c then
        return ("%02x%02x%02x"):format(math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255))
    end
    return "ffffff"
end

-- Class-coloured name; the realm (grey) only when it is not your own.
function PL.NameText(name, realm, class)
    local s = ("|cff%s%s|r"):format(PL.ClassHex(class), name or "?")
    if realm and realm ~= MyRealm() then s = s .. "|cff808080-" .. realm .. "|r" end
    return s
end

-- "Oct 14" (the day only).
function PL.Day(ts)
    if not ts then return "" end
    return ("%s %d"):format(date("%b", ts), tonumber(date("%d", ts)) or 0)
end

function PL.Ago(ts)
    if not ts then return "-" end
    local d = time() - ts
    if d < 86400 then return "today" end
    if d < 2 * 86400 then return "yesterday" end
    if d < 30 * 86400 then return ("%dd ago"):format(math.floor(d / 86400)) end
    if d < 365 * 86400 then return ("%dmo ago"):format(math.floor(d / (30 * 86400))) end
    return ("%dy ago"):format(math.floor(d / (365 * 86400)))
end

local function Clock(sec)
    if type(sec) ~= "number" then return nil end
    return ("%d:%02d"):format(math.floor(sec / 60), math.floor(sec % 60))
end

-- "+12 Ara-Kara  Timed  28:31  3 deaths" / "Heroic Priory of the Sacred Flame"
function PL.RunText(r)
    if r.kind == "mplus" then
        local s = ("+%d %s"):format(r.level or 0, r.inst or "?")
        if r.completed then
            s = s .. (r.timed and "  |cff4dd964Timed|r" or "  |cffff6b6bDepleted|r")
            local clock = Clock(r.timeSec)
            if clock then s = s .. "  " .. clock end
            if r.deaths and r.deaths > 0 then
                s = s .. ("  |cffb0b0b0%d death%s|r"):format(r.deaths, r.deaths == 1 and "" or "s")
            end
        else
            s = s .. "  |cff999999Abandoned|r"
        end
        return s
    end
    return ((r.diff and r.diff ~= "") and (r.diff .. " ") or "") .. (r.inst or "?")
end

function PL.KindText(kind)
    local c = PL.KIND_COLOR[kind] or { 1, 1, 1 }
    return ("|cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, PL.KIND_LABEL[kind] or "?")
end

function PL.StatusText(p)
    if p and p.status == PL.STATUS_FAV then return "|cff59d966Favorite|r" end
    if p and p.status == PL.STATUS_BLACK then return "|cfff24d4dBlacklisted|r" end
    return nil
end

-------------------------------------------------------------------------------
--  Raider.IO (optional): the score at the time of the run.
-------------------------------------------------------------------------------
local function RioScore(name, realm)
    if PL.Opt("plRaiderIO") == false then return nil end
    local rio = _G.RaiderIO
    if not (rio and type(rio.GetProfile) == "function") then return nil end
    local ok, prof = pcall(rio.GetProfile, name, realm)
    local mk = ok and type(prof) == "table" and prof.mythicKeystoneProfile
    local s = type(mk) == "table" and tonumber(mk.currentScore)
    if s and s > 0 then return math.floor(s) end
    return nil
end

-------------------------------------------------------------------------------
--  Identity
-------------------------------------------------------------------------------
local myGUID

local function IdentityFromGUID(guid, unit)
    local name, realm, class
    if unit and UnitFullName then
        local n, r = UnitFullName(unit)
        name, realm = PlainString(n), NormRealm(r)
    end
    if GetPlayerInfoByGUID then
        local _, classFile, _, _, _, n, r = GetPlayerInfoByGUID(guid)
        class = PlainString(classFile)
        name = name or PlainString(n)
        realm = realm or NormRealm(r)
    end
    if not name then return nil end
    if unit and not class then class = PlainString((select(2, UnitClass(unit)))) end
    return name, realm or MyRealm(), class
end

-- guid, name, realm, class for a player unit (nil when unreadable).
function PL.UnitIdentity(unit)
    if not (UnitExists(unit) and UnitIsPlayer(unit)) then return nil end
    local guid = PlainString(UnitGUID(unit))
    if not guid then return nil end
    local name, realm, class = IdentityFromGUID(guid, unit)
    if not name then return nil end
    return guid, name, realm, class
end

function PL.IsMe(guid) return guid ~= nil and guid == myGUID end

-------------------------------------------------------------------------------
--  Tracking
-------------------------------------------------------------------------------
local cur   -- the instance you are in: kind, inst, diff, instID, t, level, members, order

local function Detect()
    if not IsInInstance() then return nil end
    local name, itype, diffID, diffName, _, _, _, instID = GetInstanceInfo()
    if itype == "party" then
        local cm = C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive()
        if diffID == MPLUS_DIFFICULTY or cm then return "mplus", name, diffName, instID end
        return "dungeon", name, diffName, instID
    elseif itype == "raid" then
        return "raid", name, diffName, instID
    end
    return nil
end

local function AddMember(s, name, realm, class, role)
    local key = PL.Key(name, realm)
    local m = s.members[key]
    if not m then
        m = { key = key, name = name, realm = realm }
        s.members[key] = m
        s.order[#s.order + 1] = key
    end
    if class then m.class = class end
    if role and role ~= "NONE" then m.role = role end
    if m.rio == nil then m.rio = RioScore(name, realm) or false end
end

local function SnapUnit(unit)
    local guid, name, realm, class = PL.UnitIdentity(unit)
    if not guid or guid == myGUID then return end
    AddMember(cur, name, realm, class, PlainString(UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)))
end

local function SnapAll()
    if not cur then return end
    if IsInRaid() then
        for i = 1, 40 do SnapUnit("raid" .. i) end
    else
        for i = 1, 4 do SnapUnit("party" .. i) end
    end
end

local function AddPlayerRun(p, run)
    table.insert(p.runs, 1, run)
    for i = #p.runs, MAX_PLAYER_RUNS + 1, -1 do p.runs[i] = nil end
    p.lastSeen = run.t
    p.runCount = (p.runCount or 0) + 1
    if run.rio then p.rio = run.rio end
    if run.kind == "mplus" and run.completed and run.level and (p.bestKey or 0) < run.level then
        p.bestKey = run.level
    end
end

local function Record(s, extra)
    if not s or #s.order == 0 then return end
    extra = extra or {}
    local t = time()
    for _, key in ipairs(s.order) do
        local m = s.members[key]
        local p = PL.Ensure(m.name, m.realm, m.class, m.role)
        AddPlayerRun(p, {
            t = t, kind = s.kind, inst = s.inst, diff = s.diff, level = s.level,
            completed = extra.completed, timed = extra.timed, timeSec = extra.timeSec, deaths = extra.deaths,
            role = m.role, rio = m.rio or nil,
        })
    end
    PL.Changed()
end

-- Leaving (or switching) instances closes the session. A completed key was
-- already recorded at completion; anything else is recorded here.
local function Finish()
    local s = cur
    cur = nil
    if not s or s.recorded or #s.order == 0 then return end
    if time() - s.t < MIN_SESSION_SEC then return end
    Record(s, { completed = false })
end

local function CheckInstance()
    if not PL.On() then cur = nil; return end
    local kind, inst, diff, instID = Detect()
    if kind then
        if cur and cur.instID ~= instID then Finish() end
        if not cur then
            cur = {
                kind = kind, inst = PlainString(inst) or "?", diff = PlainString(diff), instID = instID,
                t = time(), members = {}, order = {},
            }
        elseif kind == "mplus" then
            cur.kind = "mplus"
        end
        SnapAll()
    elseif cur then
        Finish()
    end
end

local function MapName(mapID)
    mapID = PlainNumber(mapID)
    if mapID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        return PlainString((C_ChallengeMode.GetMapUIInfo(mapID)))
    end
    return nil
end

local function OnKeyStart()
    CheckInstance()
    if not cur then return end
    cur.kind = "mplus"
    cur.recorded = nil
    cur.t = time()
    local level = C_ChallengeMode.GetActiveKeystoneInfo and C_ChallengeMode.GetActiveKeystoneInfo()
    cur.level = PlainNumber(level) or cur.level
    cur.inst = MapName(C_ChallengeMode.GetActiveChallengeMapID and C_ChallengeMode.GetActiveChallengeMapID()) or cur.inst
    SnapAll()
end

local function OnKeyComplete()
    if not PL.On() then return end
    if not cur then CheckInstance() end
    if not cur or cur.recorded then return end
    local info = C_ChallengeMode.GetChallengeCompletionInfo and C_ChallengeMode.GetChallengeCompletionInfo()
    if type(info) ~= "table" then return end
    SnapAll()
    -- The server-side roster survives people leaving before the chest.
    if type(info.members) == "table" then
        for _, m in ipairs(info.members) do
            local guid = PlainString(m.memberGUID)
            if guid and guid ~= myGUID then
                local name, realm, class = IdentityFromGUID(guid)
                if name then AddMember(cur, name, realm, class) end
            end
        end
    end
    cur.kind = "mplus"
    cur.inst = MapName(info.mapChallengeModeID) or cur.inst
    cur.level = PlainNumber(info.level) or cur.level
    local ms = PlainNumber(info.time)
    local deaths = C_ChallengeMode.GetDeathCount and PlainNumber((C_ChallengeMode.GetDeathCount()))
    cur.recorded = true
    Record(cur, {
        completed = true, timed = info.onTime == true,
        timeSec = ms and math.floor(ms / 1000), deaths = deaths,
    })
end

-------------------------------------------------------------------------------
--  Blacklist (and optional favorite) alert when someone joins your group
-------------------------------------------------------------------------------
local alerted = {}
local alertPending = false

local function ScanAlerts()
    alertPending = false
    if not IsInGroup() then wipe(alerted); return end
    if not PL.On() then return end
    local wantBlack, wantFav = PL.Opt("plBlacklistAlert") ~= false, PL.Opt("plFavoriteAlert") == true
    if not (wantBlack or wantFav) then return end
    local raid = IsInRaid()
    local black = false
    for i = 1, raid and 40 or 4 do
        local guid, name, realm = PL.UnitIdentity((raid and "raid" or "party") .. i)
        if guid and guid ~= myGUID then
            local key = PL.Key(name, realm)
            local p = not alerted[key] and PL.Get(key)
            if p and ((p.status == PL.STATUS_BLACK and wantBlack) or (p.status == PL.STATUS_FAV and wantFav)) then
                alerted[key] = true
                local line = ("%s %s"):format(PL.StatusText(p), PL.NameText(p.name, p.realm, p.class))
                if p.rating then line = line .. "  " .. PL.StarsMarkup(p.rating, 11) end
                if p.notes then line = line .. "  |cffd9ccb3\"" .. p.notes .. "\"|r" end
                PL.Say(line .. (p.status == PL.STATUS_BLACK and " |cfff24d4dis in your group.|r" or " is in your group."))
                if p.status == PL.STATUS_BLACK then black = true end
            end
        end
    end
    if black and PL.Opt("plAlertSound") ~= false and SOUNDKIT and SOUNDKIT.RAID_WARNING then
        PlaySound(SOUNDKIT.RAID_WARNING, "Master")
    end
end

-------------------------------------------------------------------------------
--  Prune: players you never rated, flagged or noted, not seen for N days.
-------------------------------------------------------------------------------
local function Prune()
    local days = tonumber(PL.Opt("plPruneDays")) or 30
    if days <= 0 then return end
    local cutoff = time() - days * 86400
    local players = Players()
    for key, p in pairs(players) do
        if not PL.IsListed(p) and (p.lastSeen or p.added or 0) < cutoff then players[key] = nil end
    end
end

-- Older saved data kept more runs per player: trimmed to the newest MAX_PLAYER_RUNS.
local function TrimRuns()
    for _, p in pairs(Players()) do
        if type(p.runs) == "table" then
            for i = #p.runs, MAX_PLAYER_RUNS + 1, -1 do p.runs[i] = nil end
        end
    end
end

-------------------------------------------------------------------------------
--  Unit tooltip lines
-------------------------------------------------------------------------------
local function OnUnitTooltip(tooltip)
    if tooltip ~= GameTooltip or not PL.On() or PL.Opt("plTooltip") == false then return end
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    unit = ok and PlainString(unit)
    if not unit then return end
    local guid, name, realm = PL.UnitIdentity(unit)
    if not guid or PL.IsMe(guid) then return end
    local p = PL.Get(PL.Key(name, realm))
    if not (p and (PL.IsListed(p) or (p.runCount or 0) > 0)) then return end

    local right = p.rating and PL.StarsMarkup(p.rating, 11) or ""
    local status = PL.StatusText(p)
    if status then right = right .. (right ~= "" and "  " or "") .. status end
    tooltip:AddDoubleLine(PL.TITLE, right ~= "" and right or " ")

    local parts = {}
    if (p.runCount or 0) > 0 then
        parts[#parts + 1] = ("%d run%s together"):format(p.runCount, p.runCount == 1 and "" or "s")
    end
    if p.bestKey then parts[#parts + 1] = ("best +%d"):format(p.bestKey) end
    if #parts > 0 then tooltip:AddLine(table.concat(parts, ", "), 0.75, 0.75, 0.75) end
    if p.notes then tooltip:AddLine("\"" .. p.notes .. "\"", 0.85, 0.80, 0.70, true) end
    tooltip:Show()
end

-------------------------------------------------------------------------------
--  Right-click menus: Rate Player (rating, favorite, blacklist), in place.
-------------------------------------------------------------------------------
local MENUS = {
    "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FOCUS",
    "MENU_UNIT_TARGET", "MENU_UNIT_FRIEND", "MENU_UNIT_ENEMY_PLAYER",
}

-- name, realm, class, role of the menu's player (nil for yourself/unreadable).
local function FromContext(cd)
    if type(cd) ~= "table" then return nil end
    local unit = PlainString(cd.unit)
    if unit then
        local guid, name, realm, class = PL.UnitIdentity(unit)
        if not guid or PL.IsMe(guid) then return nil end
        local role = PlainString(UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit))
        return name, realm, class, role
    end
    local name = PlainString(cd.name)
    if not name then return nil end
    local server = PlainString(cd.server)
    local n, r = PL.ParseName(server and (name .. "-" .. server) or name)
    if not n then return nil end
    if n == UnitName("player") and r == MyRealm() then return nil end
    return n, r
end

local function AddRate(_, root, cd)
    if not PL.On() or PL.Opt("plUnitMenu") == false then return end
    local name, realm, class, role = FromContext(cd)
    if not name then return end
    local key = PL.Key(name, realm)
    local p = PL.Get(key)
    local label = "Rate Player"
    if p and p.rating then label = label .. "  " .. PL.StarsMarkup(p.rating, 10) end
    local status = PL.StatusText(p)
    if status then label = label .. "  " .. status end
    local function Ensure()
        local _, k = PL.Ensure(name, realm, class, role)
        return k
    end
    root:CreateDivider()
    local sub = root:CreateButton(label)
    for n = 5, 1, -1 do
        sub:CreateRadio(PL.StarsMarkup(n, 12),
            function() local q = PL.Get(key); return q ~= nil and q.rating == n end,
            function() PL.SetRating(Ensure(), n) end)
    end
    sub:CreateButton("Clear Rating", function() if PL.Get(key) then PL.SetRating(key, nil) end end)
    sub:CreateDivider()
    sub:CreateCheckbox("Favorite",
        function() local q = PL.Get(key); return q ~= nil and q.status == PL.STATUS_FAV end,
        function() PL.ToggleStatus(Ensure(), PL.STATUS_FAV) end)
    sub:CreateCheckbox("Blacklist",
        function() local q = PL.Get(key); return q ~= nil and q.status == PL.STATUS_BLACK end,
        function() PL.ToggleStatus(Ensure(), PL.STATUS_BLACK) end)
end

-------------------------------------------------------------------------------
--  Start (PLAYER_LOGIN, or the module's OnEnable)
-------------------------------------------------------------------------------
local started
function ns.Players_Enable()
    if started then return end
    started = true
    myGUID = PlainString(UnitGUID("player"))
    Prune()
    TrimRuns()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
    end
    if Menu and Menu.ModifyMenu then
        for _, tag in ipairs(MENUS) do Menu.ModifyMenu(tag, AddRate) end
    end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    ev:RegisterEvent("CHALLENGE_MODE_START")
    ev:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    ev:SetScript("OnEvent", function(_, event)
        if not PL.On() then return end
        if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
            CheckInstance()
        elseif event == "GROUP_ROSTER_UPDATE" then
            if cur then SnapAll() end
            if not alertPending then
                alertPending = true
                C_Timer.After(0.5, ScanAlerts)
            end
        elseif event == "PLAYER_ROLES_ASSIGNED" then
            if cur then SnapAll() end
        elseif event == "CHALLENGE_MODE_START" then
            OnKeyStart()
        elseif event == "CHALLENGE_MODE_COMPLETED" then
            OnKeyComplete()
        end
    end)
    CheckInstance()
end
