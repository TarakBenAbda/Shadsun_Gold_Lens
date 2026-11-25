-- =============================================================================
-- Shadsun Gold Lens — tests/repro_v030_flicker.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Exécute les tests hors jeu sous Lua 5.1 avec un client simulé.
--      Usage : lua5.1 run_tests.lua <dossier ShadsunGoldLens>
-- EN : Offline test runner (Lua 5.1, simulated client).
-- =============================================================================
print(string.rep("=", 70))
print(" Shadsun Gold Lens — tests hors jeu / offline tests")
print(" Auteur : Tarak Ben Abda")
print(string.rep("=", 70))

local rprint = print
local ADDON = arg[1] or "../../ShadsunGoldLens"
package.path = "./?.lua;" .. package.path
local M = dofile((arg[0]:match("^(.*[/\\])") or "./") .. "wowmock.lua")

local passed, failed, results = 0, 0, {}
local function check(name, cond, detail)
    if cond then passed = passed + 1; results[#results + 1] = "  OK    " .. name
    else failed = failed + 1; results[#results + 1] = "  ÉCHEC " .. name .. (detail and (" — " .. tostring(detail)) or "") end
end

-- -----------------------------------------------------------------------------
-- Environnement global simulé / simulated globals
-- -----------------------------------------------------------------------------
local function installGlobals(opts)
    opts = opts or {}
    M.ResetEvents()
    M.timers = {}
    _G.CreateFrame = M.CreateFrame
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    _G.tinsert = table.insert
    _G.strsplit = function(sep, s)
        local out = {}
        for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%-", "%%-")) do out[#out + 1] = part end
        return unpack(out)
    end
    _G.date = os.date
    _G.time = function() return 1763300000 end
    _G.GetTime = function() return M.time end
    _G.debugprofilestop = function() return os.clock() * 1000 end
    _G.debugstack = function() return "(pile simulée)" end
    _G.hooksecurefunc = function(a, b, c)
        if type(a) == "table" then
            local orig = a[b]
            a[b] = function(...) local r = { orig(...) }; c(...); return unpack(r) end
        else
            local orig = _G[a]
            _G[a] = function(...) local r = { orig(...) }; b(...); return unpack(r) end
        end
    end
    _G.print = function(...)
        local t = {}
        for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
        M.printed[#M.printed + 1] = table.concat(t, " ")
    end
    _G.GetLocale = function() return M.locale end
    _G.GetBuildInfo = function() return "1.60.1", "70938", "Nov 2026", 16001 end
    _G.WOW_PROJECT_ID, _G.WOW_PROJECT_MAINLINE = 99, 1
    _G.UnitName = function(u) if u == "player" then return "Aurelia" end return M.npcName end
    _G.UnitFactionGroup = function(u) if u == "player" then return "Alliance" end return M.npcFaction end
    _G.UnitGUID = function(u) if u == "npc" then return M.npcGUID end return "Player-1-0000" end
    _G.UnitReaction = function() return 5 end
    _G.InCombatLockdown = function() return M.combat end
    _G.IsShiftKeyDown = function() return M.shift end
    _G.GetCursorPosition = function() return 0, 0 end
    _G.Enum = { TooltipDataType = { Item = 0, Spell = 1 }, ItemClass = { Recipe = 9, Questitem = 12 } }
    _G.TooltipDataProcessor = { AddTooltipPostCall = function(kind, cb) if kind == 0 then table.insert(M.postCalls, cb) end end }
    M.postCalls = {}
    _G.C_Timer = { After = function(_, fn) table.insert(M.timers, fn) end }
    local maps = { [1453] = "Hurlevent", [1429] = "Forêt d'Elwynn", [1436] = "Marche de l'Ouest", [1411] = "Durotar",
        [1413] = "Les Tarides", [1434] = "Strangleronce", [1424] = "Contreforts de Hautebrande", [1412] = "Mulgore" }
    _G.C_Map = {
        GetBestMapForUnit = function() return 1453 end,
        GetPlayerMapPosition = function() return { x = 0.551, y = 0.698 } end,
        GetMapInfo = function(id) if maps[id] then return { name = maps[id] } end return nil end,
        CanSetUserWaypointOnMap = function(id) return maps[id] ~= nil end,
        SetUserWaypoint = function(p) M.userWaypoint = p end,
    }
    _G.UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { uiMapID = m, x = x, y = y } end }
    _G.C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }
    _G.OpenWorldMap = function(m) M.openedMap = m end
    _G.C_Item = {
        GetItemInfo = function(id)
            local it = M.items[id]
            if not it or M.uncached[id] then return nil end
            return it.name, "|cffffffff|Hitem:" .. id .. "|h[" .. it.name .. "]|h|r", 1, 1, 1, "t", "s", 20, "", 134400,
                it.sell, it.class, it.sub, it.bind
        end,
        GetItemInfoInstant = function(id)
            local it = M.items[id]
            if not it then return id, "Divers", "", "", 134400, 15, 0 end
            return id, "t", "s", "", 134400, it.class, it.sub
        end,
        RequestLoadItemDataByID = function(id) M.requested = id end,
        GetItemSubClassInfo = function(c, s) if c == 9 then return ({ [5] = "Cuisine", [1] = "Travail du cuir" })[s] or ("Recette " .. s) end return "Sous-classe" end,
        GetItemClassInfo = function(c) return ({ [9] = "Recette", [0] = "Consommable", [7] = "Artisanat" })[c] or "Classe" end,
        GetItemSpell = function(id) if id == 6325 then return "Goujon brillant", 7751 end return nil end,
    }
    _G.C_Container = { GetContainerItemID = function(b, s) return M.bag and M.bag[b .. ":" .. s] end }
    _G.C_AddOns = { IsAddOnLoaded = function(n) return n == "Auctionator" and _G.Auctionator ~= nil end }
    _G.C_MerchantFrame = { GetItemInfo = function(i) return M.merchant and M.merchant[i] and M.merchant[i].info end }
    _G.GetMerchantNumItems = function() return M.merchant and #M.merchant or 0 end
    _G.GetMerchantItemLink = function(i) return M.merchant and M.merchant[i] and ("|Hitem:" .. M.merchant[i].id .. "|h[x]|h") end
    _G.UIParent = M.CreateFrame("Frame", "UIParent")
    _G.Minimap = M.CreateFrame("Frame", "Minimap"); Minimap:SetSize(140, 140)
    _G.UISpecialFrames = {}
    _G.SlashCmdList = {}
    _G.GameTooltip = M.CreateFrame("GameTooltip", "GameTooltip", UIParent, "GameTooltipTemplate")
    _G.ItemRefTooltip = M.CreateFrame("GameTooltip", "ItemRefTooltip", UIParent, "GameTooltipTemplate")
    _G.ShoppingTooltip1 = M.CreateFrame("GameTooltip", "ShoppingTooltip1", UIParent, "GameTooltipTemplate")
    _G.ShoppingTooltip2 = M.CreateFrame("GameTooltip", "ShoppingTooltip2", UIParent, "GameTooltipTemplate")
    _G.Settings = {
        RegisterCanvasLayoutCategory = function(frame, name) return { frame = frame, name = name } end,
        RegisterAddOnCategory = function(c) M.settingsCategory = c end,
    }
    _G.ChatEdit_InsertLink = function() return false end
    _G.LibStub = nil
    _G.issecretvalue = nil
    if opts.auctionator ~= false then
        M.ahPrices = { [6325] = 15000, [159] = 30, [7005] = 300, [5441] = 900 }
        M.ahAges = { [6325] = 2, [159] = 0, [7005] = 12 }
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemID = function(caller, id)
                assert(type(caller) == "string", "callerID string")
                assert(type(id) == "number", "itemID number")
                return M.ahPrices[id]
            end,
            GetAuctionPriceByItemLink = function(caller, link) return nil end,
            GetAuctionAgeByItemID = function(caller, id) return M.ahAges[id] end,
            RegisterForDBUpdate = function(caller, cb) M.dbUpdate = cb end,
            GetVendorPriceByItemID = function(caller, id) return M.items[id] and M.items[id].sell end,
        } } }
    else
        _G.Auctionator = nil
    end
    if opts.tomtom ~= false then
        _G.TomTom = { AddWaypoint = function(self, m, x, y, o) M.tomtom = { m = m, x = x, y = y, o = o }; return { "uid" } end }
    else
        _G.TomTom = nil
    end
end

-- Chargement des fichiers dans l'ordre du .toc / load files in .toc order
local function loadAddon(svGlobal, svChar)
    _G.ShadsunGoldLensGlobal, _G.ShadsunGoldLensDB = svGlobal, svChar
    local ns = {}
    local toc = assert(io.open(ADDON .. "/ShadsunGoldLens.toc")):read("*a")
    for line in toc:gmatch("[^\r\n]+") do
        if not line:match("^#") and line:match("%.lua$") then
            local path = ADDON .. "/" .. line:gsub("\\", "/")
            local chunk, err = loadfile(path)
            if not chunk then error("chargement " .. path .. " : " .. err) end
            chunk("ShadsunGoldLens", ns)
        end
    end
    return ns
end

local function boot(opts, svGlobal, svChar)
    installGlobals(opts)
    M.printed = {}
    local ns = loadAddon(svGlobal, svChar)
    M.FireEvent("ADDON_LOADED", "ShadsunGoldLens")
    M.FireEvent("PLAYER_LOGIN")
    M.FireEvent("PLAYER_ENTERING_WORLD")
    M.RunTimers()
    return ns
end

local function linesOf(tt)
    local out = {}
    for _, l in ipairs(tt.lines) do out[#out + 1] = l.left .. (l.right and (" | " .. l.right) or "") end
    return out
end
local function joined(tt) return table.concat(linesOf(tt), "\n") end
local function countMatches(tt, pat)
    local n = 0
    for _, l in ipairs(tt.lines) do if l.left:find(pat, 1, true) then n = n + 1 end end
    return n
end
local function strip(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end


-- Reproduction du clignotement v0.3.0 / v0.3.0 flicker reproduction
-- Charge le code d'origine v0.3.0 (GoldLens.lua + données) dans le client simulé,
-- puis enchaîne 6 reconstructions d'infobulle (RefreshData) comme le client.
installGlobals({})
_G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
local addon = {}
for _, f in ipairs({ "../tools/input/Reference_v030.lua", "../tools/input/Vendors_v030.lua", "v030/GoldLens.lua" }) do
    assert(loadfile(f))("ShadsunGoldLens", addon)
end
addon.initUI = function() end
M.FireEvent("ADDON_LOADED", "ShadsunGoldLens")
M.FireEvent("PLAYER_LOGIN")
local tt = GameTooltip
local heights = {}
M.ProcessItem(tt, 6325)                       -- survol initial
heights[#heights + 1] = tt.height
for i = 1, 6 do
    M.RunTimers()                             -- image suivante : lignes ajoutées + Show()
    heights[#heights + 1] = tt.height
    tt:RefreshData()                          -- reconstruction périodique du client
    heights[#heights + 1] = tt.height
end
rprint("v0.3.0 — hauteurs successives de l'infobulle (lignes) : " .. table.concat(heights, ", "))
local changes = 0
for i = 2, #heights do if heights[i] ~= heights[i - 1] then changes = changes + 1 end end
rprint("v0.3.0 — changements de taille sur 6 reconstructions : " .. changes)

-- Même scénario avec la version actuelle / same scenario with v0.4.0
local ns = boot({}, nil, nil)
local h2 = {}
M.ProcessItem(tt, 6325)
h2[#h2 + 1] = tt.height
for i = 1, 6 do
    M.RunTimers(); h2[#h2 + 1] = tt.height
    tt:RefreshData(); h2[#h2 + 1] = tt.height
end
rprint("version actuelle — hauteurs successives de l'infobulle (lignes) : " .. table.concat(h2, ", "))
local c2 = 0
for i = 2, #h2 do if h2[i] ~= h2[i - 1] then c2 = c2 + 1 end end
rprint("version actuelle — changements de taille sur 6 reconstructions : " .. c2)
os.exit((changes > 0 and c2 == 0) and 0 or 1)
