if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- EllesmereUIGroupFinder.lua: premade group filters, list tweaks and the M+
-- applications bar. nothing hooks in until it's enabled.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EllesmereUI and EllesmereUI._ModuleNS and EllesmereUI.Lite and EllesmereUI.HELD_BACK_ADDONS) then EUI_CLIENT_BLOCKED = true; return end  -- stale-parent guard: a half-updated install goes dormant instead of erroring
-- lab: never alongside the live group finder
if C_AddOns.IsAddOnLoaded("EllesmereUIGroupFinder") then
    EllesmereUI.HELD_BACK_ADDONS[ADDON_NAME] = true
    print("|cff0cd29fEllesmereUI|r Group Finder Lab is off: the live Group Finder is enabled too. Turn one of them off.")
end
if EllesmereUI.HELD_BACK_ADDONS[ADDON_NAME] then return end
-- lab: own name, so the live settings page never picks it up
EllesmereUI._ModuleNS[ADDON_NAME] = ns

local GF = EllesmereUI.Lite.NewAddon(ADDON_NAME)
-- blizzard frame work that waits for combat to end
ns.CombatQueue = EllesmereUI.NewCombatQueue(CreateFrame("Frame"))

local DEFAULTS = {
    padding          = 12,
    nameColors       = true,
    classTooltip     = true,
    leaderRating     = true,
    leaderCrown      = true,
    missingRoles     = true,
    specIcons        = true,
    iconSize         = 125,
    cancelOldest     = false,
    dungeonAbbr      = false,
    dungeonScore     = false,
}
ns.DEFAULTS = DEFAULTS

local APPS_DEFAULTS = {
    enabled       = false,
    scope         = "character",
    texture       = "none",
    showAccepted  = true,
    showDeclined  = true,
    showDelisted  = true,
    showCancelled = true,
}
ns.APPS_DEFAULTS = APPS_DEFAULTS

local db

local function Profile() return db and db.profile end

-- account-wide bits, outside profiles
local function Account(key)
    if not EllesmereUIDB then EllesmereUIDB = {} end
    local t = EllesmereUIDB[key]
    if type(t) ~= "table" then
        t = {}
        EllesmereUIDB[key] = t
    end
    return t
end

-- account-wide so profile swaps never flip it
function ns.Enabled()
    local t = EllesmereUIDB and EllesmereUIDB.groupFinder
    return type(t) == "table" and t.enabled == true or false
end

function ns.SetEnabled(v)
    Account("groupFinder").enabled = v and true or false
end

-- true while another premade filter hooking the same panel is loaded
function ns.Blocked()
    return C_AddOns.IsAddOnLoaded("PremadeGroupsFilter") and true or false
end

local readOnly = { search = setmetatable({}, { __index = DEFAULTS, __newindex = function() end }),
                   apps   = setmetatable({}, { __index = APPS_DEFAULTS, __newindex = function() end }) }

local function Search()
    local p = Profile()
    return p and p.search or readOnly.search
end

-- filters belong to the character, everything else to the profile
local FILTER_KEYS = {}
for _, k in ipairs({ "ratingOn", "ratingValue", "regions", "delves", "delveTiers", "bosses", "raidDiffs",
    "raidPlaystyles", "raidRoles", "partyFit", "notDeclined", "hasLust", "hasBrez", "cawfeeMyClass",
    "cawfeeExpr", "cawfeeRolesAny", "roleCounts", "dimPicks" }) do FILTER_KEYS[k] = true end

local charDB
local function CharFilters() return charDB and charDB.filters end

local cfg = setmetatable({}, {
    __index = function(_, k)
        if FILTER_KEYS[k] then
            local f = CharFilters()
            return f and f[k]
        end
        return Search()[k]
    end,
    __newindex = function(_, k, v)
        if FILTER_KEYS[k] then
            local f = CharFilters()
            if f then f[k] = v end
            return
        end
        Search()[k] = v
    end,
})

function ns.Cfg() return cfg end

-- blizzard's dungeon picks for this character, nil until saved once
function ns.CharBlizzFilter() return charDB and charDB.blizz end
function ns.SetCharBlizzFilter(t) if charDB then charDB.blizz = t end end

function ns.AppsCfg()
    local p = Profile()
    return p and p.apps or readOnly.apps
end

function ns.AppCountsStore()
    local t = Account("groupFinderApps")
    if type(t.dungeon) ~= "table" then t.dungeon = {} end
    return t.dungeon
end

function ns.ResetSettings()
    if db then db:ResetProfile() end
    if charDB then wipe(charDB.filters) end
end

function GF:OnInitialize()
    -- lab: own settings, copied once from the live module's
    local profiles = EllesmereUIDB and EllesmereUIDB.profiles
    local prof = profiles and profiles[EllesmereUIDB.activeProfile or "Default"]
    local addons = type(prof) == "table" and prof.addons
    if type(addons) == "table" and addons.EllesmereUIGroupFinderLab == nil
       and type(addons.EllesmereUIGroupFinder) == "table" then
        addons.EllesmereUIGroupFinderLab = CopyTable(addons.EllesmereUIGroupFinder)
    end
    db = EllesmereUI.Lite.NewDB("EllesmereUIGroupFinderLabDB", { profile = { search = DEFAULTS, apps = APPS_DEFAULTS } })
    if type(EllesmereUIGroupFinderLabCharDB) ~= "table" then EllesmereUIGroupFinderLabCharDB = {} end
    charDB = EllesmereUIGroupFinderLabCharDB
    if type(charDB.filters) ~= "table" then
        -- first login after the move: this character takes the profile's old filters, the rest start clean
        charDB.filters = {}
        local s = Profile() and Profile().search
        if s then
            for k in pairs(FILTER_KEYS) do
                charDB.filters[k] = s[k]
                s[k] = nil
            end
        end
    end
end

function GF:OnEnable()
    if not ns.Enabled() then return end
    -- PGF hooks the same panel, so we turn ourselves off while it's loaded.
    if ns.Blocked() then
        ns.SetEnabled(false)
        EllesmereUI.Print(EllesmereUI.COLOR_CODES.BRAND .. "EllesmereUI|r "
            .. EllesmereUI.L("Group Finder has been turned off because Premade Groups Filter is loaded."))
        return
    end

    if ns.Apps_Enable then ns.Apps_Enable() end
    local function Start()
        if ns.Search_OnEnable then ns.Search_OnEnable() end
    end
    if C_AddOns.IsAddOnLoaded("Blizzard_GroupFinder") and PVEFrame then
        Start()
        return
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, _, name)
        if name == "Blizzard_GroupFinder" then
            self:UnregisterEvent("ADDON_LOADED")
            Start()
        end
    end)
end
