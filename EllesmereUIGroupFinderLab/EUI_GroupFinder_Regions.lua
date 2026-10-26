if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_GroupFinder_Regions.lua - where a group's leader plays from
--  us: na / oce / mex / bra by realm. eu: the realm's language.
--  the region filter and the region tags read this. other regions: off
-------------------------------------------------------------------------------
local FOLDER, ns = ...
if EllesmereUI.HELD_BACK_ADDONS[FOLDER] then return end -- held back (EllesmereUIGroupFinder.lua)
local L = EllesmereUI.L

local FLAG_DIR = "Interface\\AddOns\\" .. FOLDER .. "\\media\\flags\\"

-- realm key: spaces, dashes, quotes, dots and brackets out, ascii lowercased
-- (accents and cyrillic stay as they are)
local function Key(realm)
    -- byte ranges only: %s / lower() can touch utf-8 bytes under some locales
    return (realm:gsub("[ 	%-'%(%)%.]", ""):gsub("[A-Z]", string.lower))
end

-- per region: the filter list (key, label, tag, color), the realms off the
-- default, and the default for every other realm
local SETS = {
    [1] = {
        list = {
            { key = "na",  label = L("North America"), tag = "NA",  r = 1,    g = 0.35, b = 0.35 },
            { key = "oce", label = L("Oceanic"),       tag = "OCE", r = 0.35, g = 0.65, b = 1 },
            { key = "la",  label = L("Latin America"), tag = "MEX", r = 1,    g = 0.5,  b = 0.82 },
            { key = "br",  label = L("Brazil"),        tag = "BRA", r = 0.35, g = 0.9,  b = 0.45 },
        },
        realms = {
            oce = { "amanthul", "barthilas", "caelestrasz", "dathremar", "dreadmaul", "frostmourne",
                    "gundrak", "jubeithos", "khazgoroth", "nagrand", "saurfang", "thaurissan" },
            br  = { "azralon", "gallywix", "goldrinn", "nemesis", "tolbarad" },
            la  = { "drakkari", "quelthalas", "ragnaros" },
        },
        default = "na",
    },
    [3] = {
        list = {
            { key = "en", label = L("English"),    tag = "EN", r = 0.35, g = 0.65, b = 1 },
            { key = "de", label = L("German"),     tag = "DE", r = 1,    g = 0.82, b = 0.2 },
            { key = "fr", label = L("French"),     tag = "FR", r = 0.6,  g = 0.6,  b = 1 },
            { key = "es", label = L("Spanish"),    tag = "ES", r = 1,    g = 0.55, b = 0.25 },
            { key = "it", label = L("Italian"),    tag = "IT", r = 0.35, g = 0.9,  b = 0.45 },
            { key = "pt", label = L("Portuguese"), tag = "PT", r = 0.3,  g = 0.85, b = 0.75 },
            { key = "ru", label = L("Russian"),    tag = "RU", r = 1,    g = 0.35, b = 0.35 },
        },
        language = true,  -- filter titled language, short names in two columns
        -- eu realms by language, english is everything else
        realms = {
            de = {
                "aegwynn", "alexstrasza", "alleria", "amanthul", "ambossar", "anetheron",
                "antonidas", "anubarak", "area52", "arthas", "arygos", "azshara", "baelgun",
                "blackhand", "blackmoore", "blackrock", "blutkessel", "dalvengyr", "daskonsortium",
                "dassyndikat", "derabyssischerat", "dermithrilorden", "derratvondalaran",
                "destromath", "dethecus", "diealdor", "diearguswacht", "dieewigewacht",
                "dienachtwache", "diesilbernehand", "dietodeskrallen", "dunmorogh", "durotan",
                "echsenkessel", "eredar", "festungderstürme", "forscherliga", "frostmourne",
                "frostwolf", "garrosh", "gilneas", "gorgonnash", "guldan", "kargath", "kelthuzad",
                "khazgoroth", "kiljaeden", "kragjin", "kultderverdammten", "lordaeron", "lothar",
                "madmortem", "malfurion", "malganis", "malorne", "malygos", "mannoroth", "mugthol",
                "nathrezim", "nazjatar", "nefarian", "nerathor", "nethersturm", "norgannon",
                "nozdormu", "onyxia", "perenolde", "proudmoore", "rajaxx", "rexxar", "senjin",
                "shattrath", "taerar", "teldrassil", "terrordar", "theradras", "thrall",
                "tichondrius", "tirion", "todeswache", "ulduar", "ungoro", "veklor",
                "wrathbringer", "ysera", "zirkeldescenarius", "zuluhed"
            },
            fr = {
                "arakarahm", "arathi", "archimonde", "chantséternels", "cho’gall",
                "confrérieduthorium", "conseildesombres", "cultedelarivenoire", "dalaran",
                "drekthar", "eitrigg", "eldrethalas", "elune", "garona", "hyjal", "illidan",
                "kaelthas", "khazmodan", "kirintor", "krasus", "lacroisadeécarlate",
                "lesclairvoyants", "lessentinelles", "marécagedezangar", "medivh", "naxxramas",
                "ner’zhul", "rashgarroth", "sargeras", "sinstralis", "suramar", "templenoir",
                "throkferoth", "uldaman", "varimathras", "voljin", "ysondre"
            },
            es = {
                "colinaspardas", "cthun", "dunmodr", "exodar", "loserrantes", "minahonda",
                "sanguino", "shendralar", "tyrande", "uldum", "zuljin"
            },
            it = {
                "nemesis", "pozzodelleternità"
            },
            pt = {
                "aggraportuguês"
            },
            ru = {
                "Азурегос", "Борейскаятундра", "ВечнаяПесня",
                "Галакронд", "Голдринн", "Гордунни", "Гром",
                "Дракономор", "Корольлич", "ПиратскаяБухта",
                "Подземье", "Разувий", "Ревущийфьорд",
                "СвежевательДуш", "Седогрив", "СтражСмерти",
                "Термоштепсель", "ТкачСмерти", "ЧерныйШрам",
                "Ясеневыйлес"
            },
        },
        default = "en",
    },
}

-- the region in use: the game's, or a test one (/gflabregion)
function ns.RegionID()
    local test = EllesmereUIDB and EllesmereUIDB.cawfeeRegionTest
    if test then return test end
    return GetCurrentRegion and GetCurrentRegion() or 1
end

local set, byKey, realmOf
local function Set()
    if set ~= nil then return set or nil end
    set = SETS[ns.RegionID()] or false
    if set then
        byKey, realmOf = {}, {}
        for _, d in ipairs(set.list) do
            d.flag = FLAG_DIR .. d.key .. ".png"
            byKey[d.key] = d
        end
        for k, realms in pairs(set.realms) do
            for _, r in ipairs(realms) do realmOf[r] = k end
        end
    end
    return set or nil
end

-- the filter's list for this region, nil where there's none
function ns.RegionList()
    local s = Set()
    return s and s.list
end

-- a realm's key, the region's default when it's not listed
local cache = {}
function ns.RegionOfRealm(realm)
    local s = Set()
    if not s or type(realm) ~= "string" then return nil end
    local k = cache[realm]
    if not k then
        k = realmOf[Key(realm)] or s.default
        cache[realm] = k
    end
    return k
end

-- tag text, color and flag for a key
function ns.RegionInfo(key)
    Set()
    return byKey and byKey[key]
end

-- eu realms list languages instead of regions
function ns.RegionIsLanguage()
    local s = Set()
    return s and s.language or false
end

-- test another region's tags and filter: /gflabregion eu | us | off, then /reload
SLASH_GFLABREGION1 = "/gflabregion"
SlashCmdList.GFLABREGION = function(arg)
    arg = (arg or ""):lower():gsub("%s", "")
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if arg == "eu" then EllesmereUIDB.cawfeeRegionTest = 3
    elseif arg == "us" then EllesmereUIDB.cawfeeRegionTest = 1
    elseif arg == "off" then EllesmereUIDB.cawfeeRegionTest = nil
    else
        print("|cff0cd29fGroup Finder Lab|r: /gflabregion eu | us | off (now: "
            .. (EllesmereUIDB.cawfeeRegionTest and ("test " .. EllesmereUIDB.cawfeeRegionTest) or "the game's") .. ")")
        return
    end
    print("|cff0cd29fGroup Finder Lab|r: region test " .. arg .. ". /reload to apply.")
end
