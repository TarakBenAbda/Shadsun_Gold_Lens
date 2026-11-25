-- =============================================================================
-- Shadsun Gold Lens — tests/run_tests.lua
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
            return it.name, "|cffffffff|Hitem:" .. id .. "|h[" .. it.name .. "]|h|r", it.quality or 1, 1, 1, "t", "s", 20, "", 134400,
                it.sell, it.class, it.sub, it.bind
        end,
        GetItemInfoInstant = function(id)
            local it = M.items[id]
            if not it then return id, "Divers", "", "", 134400, 15, 0 end
            return id, "t", "s", it.loc or "", it.icon or 134400, it.class, it.sub
        end,
        RequestLoadItemDataByID = function(id) M.requested = id; M.requestCount = (M.requestCount or 0) + 1 end,
        GetItemCount = function(id, includeBank) local o = M.owned and M.owned[id] if not o then return 0 end return includeBank and (o[1] + o[2]) or o[1] end,
        GetItemQualityColor = function(q) local h = ({ [0] = "ff9d9d9d", [1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee" })[q] return 1, 1, 1, h end,
        GetItemSubClassInfo = function(c, s) if c == 9 then return ({ [5] = "Cuisine", [1] = "Travail du cuir" })[s] or ("Recette " .. s) end
            if c == 4 then return ({ [0] = "Divers", [1] = "Tissu", [2] = "Cuir" })[s] or "Sous-classe" end return "Sous-classe" end,
        GetItemClassInfo = function(c) return ({ [9] = "Recette", [0] = "Consommable", [7] = "Artisanat", [4] = "Armure", [2] = "Arme" })[c] or "Classe" end,
        GetItemSpell = function(id) if id == 6325 then return "Goujon brillant", 7751 end return nil end,
    }
    _G.C_Container = {
        GetContainerItemID = function(b, s) return M.bag and M.bag[b .. ":" .. s] end,
        GetContainerNumSlots = function(b) return (M.containers and M.containers[b]) and #M.containers[b] or 0 end,
        GetContainerItemInfo = function(b, s) local c = M.containers and M.containers[b]; local it = c and c[s]
            if it then return { itemID = it[1], stackCount = it[2] } end return nil end,
    }
    M.containers = nil
    _G.GetNormalizedRealmName = function() return M.realm or "Forever" end
    _G.GetRealmName = function() return M.realm or "Forever" end
    _G.GetMoney = function() return M.money or 123456 end
    _G.C_AddOns = { IsAddOnLoaded = function(n) return n == "Auctionator" and _G.Auctionator ~= nil end }
    _G.C_MerchantFrame = { GetItemInfo = function(i) return M.merchant and M.merchant[i] and M.merchant[i].info end }
    _G.GetMerchantNumItems = function() return M.merchant and #M.merchant or 0 end
    _G.GetMerchantItemLink = function(i) return M.merchant and M.merchant[i] and ("|Hitem:" .. M.merchant[i].id .. "|h[x]|h") end
    _G.UIParent = M.CreateFrame("Frame", "UIParent")
    rawset(UIParent, "__right", 1280); rawset(UIParent, "__top", 720)
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
    _G.MERCHANT_ITEMS_PER_PAGE = 10
    _G.MerchantFrame = M.CreateFrame("Frame", "MerchantFrame", UIParent)
    rawset(MerchantFrame, "page", 1); rawset(MerchantFrame, "selectedTab", 1)
    for i = 1, 10 do M.CreateFrame("Button", "MerchantItem" .. i .. "ItemButton", MerchantFrame) end
    _G.MerchantFrame_UpdateMerchantInfo = function() end
    M.listings, M.replicateCalls = {}, 0
    _G.C_AuctionHouse = {
        ReplicateItems = function() M.replicateCalls = M.replicateCalls + 1 end,
        GetNumReplicateItems = function() return #M.listings end,
        GetReplicateItemInfo = function(i)
            local l = M.listings[i + 1]
            return l.name or (M.items[l.id] and M.items[l.id].name) or "nom", 134400, l.count, 1, true, 1, 0, 0, 0, l.buyout, 0, false, nil, nil, nil, 0, l.id, true
        end,
    }
    _G.AuctionHouseFrame = M.CreateFrame("Frame", "AuctionHouseFrame", UIParent)
    rawset(AuctionHouseFrame, "__right", 800); rawset(AuctionHouseFrame, "__top", 650)
    rawset(AuctionHouseFrame, "SearchBar", { SearchBox = M.CreateFrame("EditBox", nil, AuctionHouseFrame, "InputBoxTemplate"),
        StartSearch = function(self) M.blizzSearch = self.SearchBox:GetText() end })
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
            GetVendorPriceByItemID = function(caller, id) return 999999 end, -- prix d'ACHAT marchand : ne doit jamais servir
            MultiSearchExact = function(caller, terms) M.atrExact = terms[1] end,
            MultiSearch = function(caller, terms) M.atrSearch = terms[1] end,
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
-- Ramène les icônes de pièces au texte « po/pa/pc » pour comparer facilement.
local function strip(s)
    s = s:gsub("|TInterface\\MoneyFrame\\UI%-GoldIcon[^|]*|t", "\194\160po")
    s = s:gsub("|TInterface\\MoneyFrame\\UI%-SilverIcon[^|]*|t", "\194\160pa")
    s = s:gsub("|TInterface\\MoneyFrame\\UI%-CopperIcon[^|]*|t", "\194\160pc")
    s = s:gsub("|T[^|]*|t ?", "")          -- autres icônes (faction…) / other inline icons
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- =============================================================================
-- 1. Chargement / loading
-- =============================================================================
local okBoot, ns = pcall(boot, {}, nil, nil)
check("Chargement complet de l'add-on (ordre du .toc, ADDON_LOADED, PLAYER_LOGIN)", okBoot, ns)
if not okBoot then for _, r in ipairs(results) do rprint(r) end os.exit(1) end
check("Post-call d'infobulle enregistré une seule fois", #M.postCalls == 1, #M.postCalls)
check("Méthode d'infobulle = TooltipDataProcessor", ns.Tooltip.method:find("TooltipDataProcessor") ~= nil, ns.Tooltip.method)
check("Commande /sgl enregistrée", type(SlashCmdList.SHADSUNGOLDLENS) == "function")
check("Catégorie Options > AddOns enregistrée", M.settingsCategory ~= nil)
check("Bannière de démarrage signée « Créé par Shadsun »", (M.printed[#M.printed] or ""):find("Créé par Shadsun", 1, true) ~= nil, M.printed[#M.printed])
check("Icône de minicarte enregistrée (LibDBIcon)", _G.LibDBIcon10_ShadsunGoldLens ~= nil)
check("Aucune erreur interne au démarrage", ns.Diag.counters.errors == 0, ns.Diag.errors[1] and ns.Diag.errors[1].err)

-- =============================================================================
-- 2. Calculs économiques / economy
-- =============================================================================
local E, U = ns.Economy, ns.U
local r = E.Compute(2000, 1, 15000, 0.05)
check("Exemple du cahier des charges : bénéfice = 1 po 22 pa 50 pc", r.profit == 12250, r.profit)
check("Exemple : rentabilité = 612,5 %", math.abs(r.roi - 612.5) < 1e-9, r.roi)
check("Exemple : commission = 7 pa 50 pc", r.cut == 750, r.cut)
check("Seuil de rentabilité : ⌈2000 / 0,95⌉ = 2106 pc", r.breakEven == 2106, r.breakEven)
check("Formatage monnaie : 12250 → « 1 po 22 pa 50 pc »", strip(U.Money(12250, true)) == "1\194\160po 22\194\160pa 50\194\160pc", U.Money(12250, true))
check("Formatage pourcentage français : « +612,5 % »", U.Percent(612.5, true) == "+612,5\194\160%", U.Percent(612.5, true))
check("Monnaie négative et zéro", strip(U.Money(-150, true)) == "-1\194\160pa 50\194\160pc" and strip(U.Money(0, true)) == "0\194\160pc")
check("Séparateur de milliers : 1 234 po", strip(U.Money(12340000, true)):find("1\194\160234\194\160po") ~= nil, U.Money(12340000, true))
check("Montants avec les icônes de pièces du jeu (or, argent, cuivre)",
    U.Money(3877, true) == "38|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t 77|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t", U.Money(3877, true))
ns.settings.display.coinIcons = false
check("Option désactivée : montants en texte « 38 pa 77 pc »", U.Money(3877, true) == "38\194\160pa 77\194\160pc", U.Money(3877, true))
ns.settings.display.coinIcons = true
local lot = E.Compute(25, 5, 30, 0.05) -- eau : lot de 5 à 25 pc, HDV 30 pc/u
check("Lot de 5 : revenu = 150 − ⌈7,5⌉ = 142 pc, bénéfice 117 pc", lot.revenue == 142 and lot.profit == 117, lot.profit)
local neutral = E.Compute(2000, 1, 15000, 0.15)
check("HDV neutre 15 % : bénéfice = 10 750 pc", neutral.profit == 10750, neutral.profit)
check("Calcul impossible sans prix HDV", select(2, E.Evaluate(6325, ns.Catalog.GetView(6325).best, nil)) ~= nil)
check("Objet lié quand ramassé : revente impossible", select(2, E.Evaluate(18170, { price = 100, qty = 1 }, 5000)) == ns.L.REASON_BOUND)
check("Achat en devise : pas de faux bénéfice", select(2, E.Evaluate(1, { price = 0, qty = 1, ext = true }, 5000)) == ns.L.REASON_EXTCOST)

-- =============================================================================
-- 3. Base de données / catalog
-- =============================================================================
local C = ns.Catalog
local v = C.GetView(6325)
check("Recette 6325 : statut confirmé (observée sur Forever)", v.status == "CONFIRMED", v.status)
check("Recette 6325 : meilleur vendeur accessible à l'Alliance", v.best and v.best.accessible and (v.best.side == "A" or v.best.side == "N"), v.best and v.best.side)
check("Recette 6325 : prix d'achat 40 pc (et non le prix de vente)", v.best and v.best.price == 40, v.best and v.best.price)
check("Recette 6325 : priorité à un vendeur de la zone actuelle (Hurlevent)", v.best and v.best.map == 1453, v.best and v.best.map)
local water = C.GetView(159)
check("Eau (159) : lot de 5 conservé", water.best and water.best.qty == 5, water.best and water.best.qty)
check("Eau : prix de base 25 pc malgré des observations remisées à 23 pc", water.best and water.best.price == 25, water.best and water.best.price)
local knife = C.GetView(7005)
check("Couteau à dépecer : prix Forever (10 pc) retenu au lieu du prix Classic (82 pc)", knife.best and knife.best.price == 10, knife.best and knife.best.price)
local none = C.GetView(25)
check("Objet connu sans vendeur : statut « aucun vendeur confirmé », pas d'invention", none.status == "NONE" and #none.offers == 0, none.status)
local nodata = C.GetView(99999)
check("Objet absent des bases : « information non disponible »", nodata.status == "NODATA", nodata.status)
-- Plusieurs vendeurs : zones/factions/coordonnées propres à chaque PNJ
local mixOK, multi = true, nil
for _, o in ipairs(water.offers) do
    local raw = ns.Data.npcs[o.npc]
    if raw and not o.personal and (o.map ~= (raw[4] or nil) or o.side ~= raw[3]) then mixOK = false; multi = o.npc end
end
check("Plusieurs vendeurs (" .. #water.offers .. ") : aucune confusion de zone/faction entre PNJ", mixOK, multi)
-- Exclusivité
local exclA
for id, flat in pairs(ns.Data.items) do
    local ok = #flat >= 12
    for i = 1, #flat, 6 do if ns.Data.npcs[flat[i]][3] ~= "A" then ok = false end end
    if ok then exclA = id; break end
end
local ve = C.GetView(exclA)
check("Exclusivité Alliance calculée sur tous les vendeurs (objet " .. tostring(exclA) .. ")", ve.excl.code == "A", ve.excl.code)
local single
for id, flat in pairs(ns.Data.items) do
    if #flat == 6 and ns.Data.npcs[flat[1]][3] == "A" and flat[4] % 4 < 2 then single = id; break end
end
local vs = C.GetView(single)
check("Un seul vendeur Alliance en référence : confiance non « élevée »", vs.excl.confidence ~= "HIGH", vs.excl.confidence)
-- Statistiques
local live = ns.LiveStats()
check("Statistiques recalculées = rapport de construction (objets)", live.items == ns.Data.meta.items, live.items .. " vs " .. tostring(ns.Data.meta.items))
check("Statistiques recalculées = rapport (associations)", live.pairs == ns.Data.meta.pairs, live.pairs)
check("Statistiques recalculées = rapport (PNJ)", live.npcs == ns.Data.meta.npcs_used, live.npcs)
-- Intégrité : chaque association pointe vers un PNJ existant
local orphan = 0
for _, flat in pairs(ns.Data.items) do for i = 1, #flat, 6 do if not ns.Data.npcs[flat[i]] then orphan = orphan + 1 end end end
check("Intégrité : aucune association vers un PNJ inexistant", orphan == 0, orphan)
local badCoord = 0
for _, n in pairs(ns.Data.npcs) do if n[5] and (n[5] <= 0 or n[5] >= 100 or n[6] <= 0 or n[6] >= 100) then badCoord = badCoord + 1 end end
check("Intégrité : coordonnées dans ]0;100[", badCoord == 0, badCoord)

-- =============================================================================
-- 4. Infobulle : stabilité, doublons, récursion, recettes
-- =============================================================================
local tt = GameTooltip
M.bag = { ["0:3"] = 6325 }
M.ProcessItem(tt, 6325, { info = { getterName = "GetBagItem", getterArgs = { 0, 3 } } })
local first = joined(tt)
check("Test 2 — recette dans le sac : bloc Shadsun Gold Lens présent", first:find("Shadsun Gold Lens", 1, true) ~= nil, first)
check("Test 2 — recette : prix d'achat PNJ affiché (40 pc)", strip(first):find("Achat PNJ | 40\194\160pc", 1, true) ~= nil, strip(first))
check("Test 2 — recette : profession affichée", strip(first):find("Profession | Cuisine", 1, true) ~= nil)
check("Test 1/6 — prix Auctionator et bénéfice affichés", strip(first):find("HDV | 1\194\160po 50\194\160pa", 1, true) ~= nil
    and strip(first):find("Bénéfice net | +1\194\160po", 1, true) ~= nil, strip(first))
local h0, n0 = tt.height, #tt.lines
local stable = true
for i = 1, 150 do -- 30 s de rafraîchissements toutes les 0,2 s
    tt:RefreshData()
    if joined(tt) ~= first or tt.height ~= h0 or #tt.lines ~= n0 then stable = false; break end
end
check("Test 4 — 150 reconstructions (≈30 s) : contenu et hauteur identiques", stable)
check("Test 4 — aucune duplication du bloc", countMatches(tt, "Shadsun Gold Lens") == 1)
check("Ajout synchrone : aucun minuteur programmé par l'infobulle", #M.timers == 0, #M.timers)
-- Post-call appelé deux fois dans la même passe
M.ProcessItem(tt, 6325, { double = true })
check("Post-call double dans une même passe : un seul bloc", countMatches(tt, "Shadsun Gold Lens") == 1)
-- Recette avec infobulle imbriquée de l'objet créé (6290) appelée AVANT la recette
M.ProcessItem(tt, 6325, { nested = 6290 })
local nestedTxt = strip(joined(tt))
check("Recette imbriquée : un seul bloc, décrit la recette (40 pc), pas l'objet créé",
    countMatches(tt, "Shadsun Gold Lens") == 1 and nestedTxt:find("40\194\160pc", 1, true) ~= nil, nestedTxt)
check("Recette imbriquée : appel imbriqué compté et ignoré", ns.Diag.counters.skippedNested >= 1)
-- Changement rapide entre 10 objets
local ids = { 6325, 159, 7005, 25, 99999, 5441, 6290, 6325, 159, 7005 }
local leak = false
M.shift = true
for _, id in ipairs(ids) do
    M.ProcessItem(tt, id)
    local txt = strip(joined(tt)) .. "\n"
    if countMatches(tt, "Shadsun Gold Lens") > 1 then leak = "doublon " .. id end
    for _, other in ipairs(ids) do
        if other ~= id and txt:find("Objet n° " .. other .. "\n", 1, true) then leak = "texte de " .. other .. " sur " .. id end
    end
    if not txt:find("Objet n° " .. id, 1, true) and C.GetView(id).best then leak = "ID absent " .. id end
end
M.shift = false
check("Test 5 — 10 objets en rafale : pas de texte de l'objet précédent, pas de doublon", not leak, leak)
-- Reconstruction SANS OnTooltipCleared (cas défensif) : le bloc est remis, une seule fois
do
    M.ProcessItem(tt, 159)
    local saved = tt.lines
    rawset(tt, "lines", { { left = "Eau" }, { left = "Ligne Blizzard 2" } }) -- lignes refaites sans effacement signalé
    for _, cb in ipairs(M.postCalls) do cb(tt, { type = 0, id = 159 }) end
    check("Reconstruction sans OnTooltipCleared : bloc rétabli, sans doublon", countMatches(tt, "Shadsun Gold Lens") == 1)
    for _, cb in ipairs(M.postCalls) do cb(tt, { type = 0, id = 159 }) end
    check("Reconstruction sans OnTooltipCleared : second appel ignoré", countMatches(tt, "Shadsun Gold Lens") == 1)
end
-- Réentrance : un post-call déclenché pendant notre rendu est ignoré
local before = ns.Diag.counters.skippedReentrant
local origAdd = tt.AddDoubleLine
rawset(tt, "AddDoubleLine", function(self, ...)
    rawset(self, "AddDoubleLine", nil)
    for _, cb in ipairs(M.postCalls) do cb(self, { type = 0, id = 159 }) end
    return origAdd(self, ...)
end)
M.ProcessItem(tt, 7005)
rawset(tt, "AddDoubleLine", nil)
check("Récursion : post-call réentrant ignoré", ns.Diag.counters.skippedReentrant == before + 1)
check("Récursion : un seul bloc malgré l'appel réentrant", countMatches(tt, "Shadsun Gold Lens") == 1)
-- Comparaison d'équipement ignorée
M.ProcessItem(ShoppingTooltip1, 6325)
check("Infobulles de comparaison ignorées", countMatches(ShoppingTooltip1, "Shadsun Gold Lens") == 0)
-- Test 3 : objet sans vendeur connu
M.ProcessItem(tt, 25)
local t3 = strip(joined(tt))
check("Test 3 — objet connu sans vendeur : message honnête, non définitif", t3:find("non définitif", 1, true) ~= nil and not t3:find("Achat PNJ |", 1, true), t3)
M.ProcessItem(tt, 99999)
check("Test 3 — objet hors base : « information non disponible »", strip(joined(tt)):find("Information non disponible", 1, true) ~= nil)
-- Test 7 : pas de prix HDV
M.ProcessItem(tt, 6290)
M.ahPrices[6325] = nil; M.dbUpdate()
M.ProcessItem(tt, 6325)
local t7 = strip(joined(tt))
check("Test 7 — sans prix HDV : « Prix HDV indisponible — effectuer un scan Auctionator. »", t7:find("Prix HDV indisponible — effectuer un scan Auctionator.", 1, true) ~= nil, t7)
check("Test 7 — sans prix HDV : « Calcul impossible », aucun faux bénéfice", t7:find("Calcul impossible", 1, true) ~= nil and not t7:find("Bénéfice net | +", 1, true))
M.ahPrices[6325] = 15000; M.dbUpdate()
M.ProcessItem(tt, 6325)
check("Mise à jour Auctionator (RegisterForDBUpdate) : prix rechargé", strip(joined(tt)):find("1\194\160po 50\194\160pa", 1, true) ~= nil)
-- Limite de lignes
ns.settings.tooltip.maxLines = 4
M.ProcessItem(tt, 6325)
check("Paramètre « lignes maximum » respecté (4)", #tt.lines == 2 + 4, #tt.lines)
ns.settings.tooltip.maxLines = 9
-- Désactivation
ns.settings.tooltip.enabled = false
M.ProcessItem(tt, 6325)
check("Infobulle désactivée : aucune ligne ajoutée", countMatches(tt, "Shadsun Gold Lens") == 0)
ns.settings.tooltip.enabled = true
-- Objet non encore en cache
M.uncached[159] = true
M.ProcessItem(tt, 159)
check("Objet non chargé : chargement demandé, pas d'erreur", M.requested == 159 and ns.Diag.counters.errors == 0)
M.uncached[159] = nil
-- Métier des composants d'artisanat
M.ProcessItem(tt, 2589)
check("Composant (tissu) : « Métier | Couture, Secourisme »", strip(joined(tt)):find("Métier | Couture, Secourisme", 1, true) ~= nil, strip(joined(tt)))
M.ProcessItem(tt, 2449)
check("Composant (herbe) : « Métier | Alchimie »", strip(joined(tt)):find("Métier | Alchimie", 1, true) ~= nil)
M.ProcessItem(tt, 4306)
check("Sous-catégorie générique : aucun métier supposé", not strip(joined(tt)):find("Métier |", 1, true))
M.ProcessItem(tt, 6325)
check("Recette : profession toujours affichée", strip(joined(tt)):find("Profession | Cuisine", 1, true) ~= nil)
-- Lien de chat
M.ProcessItem(ItemRefTooltip, 7005)
check("Lien d'objet du chat (ItemRefTooltip) : bloc présent", countMatches(ItemRefTooltip, "Shadsun Gold Lens") == 1)
-- Mesure de coût
local t0 = os.clock()
for i = 1, 500 do M.ProcessItem(tt, 6325) end
local per = (os.clock() - t0) / 500 * 1000
check(string.format("Coût d'un rendu en cache < 1 ms (mesuré %.3f ms, hors client)", per), per < 1)

-- =============================================================================
-- 5. Marchand, TomTom, interface / merchant, navigation, UI
-- =============================================================================
M.npcGUID, M.npcName, M.npcFaction = "Creature-0-1-2-3-5494-0000ABCD", "Catherine Leland", "Alliance"
M.merchant = { { id = 6325, info = { price = 36, stackCount = 1, numAvailable = -1, isPurchasable = true, hasExtendedCost = false } },
    { id = 159, info = { price = 23, stackCount = 5, numAvailable = -1, isPurchasable = true } } }
M.FireEvent("MERCHANT_SHOW")
M.RunTimers()
local obs = ShadsunGoldLensGlobal.observations[6325]
check("Test 8 — relevé marchand enregistré (prix payé 36 pc, PNJ 5494)", obs and obs["5494:1:0"] and obs["5494:1:0"].price == 36)
local v2 = C.GetView(6325)
check("Test 8 — l'observation personnelle prime dans l'infobulle", v2.best.source == "PERSONAL" and v2.best.price == 36, v2.best.source)
M.FireEvent("MERCHANT_CLOSED")

local okNav, msg = ns.Navigation.AddWaypoint(v2.best, "Recette")
check("Test 9 — TomTom : waypoint ajouté avec uiMapID et coordonnées 0–1", okNav and M.tomtom and M.tomtom.m == 1453 and math.abs(M.tomtom.x - 0.551) < 1e-6, msg)
check("Test 9 — commande /tway #mapID vérifiée", ns.Navigation.Command(v2.best) == "/tway #1453 55.1 69.8 Catherine Leland", ns.Navigation.Command(v2.best))
check("Test 9 — pas de commande sans coordonnées", ns.Navigation.Command({ nopos = true }) == nil)
check("Test 9 — carte inconnue du client refusée", select(2, ns.Navigation.Validate({ map = 424242, x = 50, y = 50 })) == ns.L.NAV_BAD_MAP)

-- Interface : ouverture de chaque onglet et actions principales
local uiOK, uiErr = pcall(function()
    ns.UI.Show("detail", 6325)
    ns.UI.Show("opp")
    ns.UI.Show("options")
    ns.UI.Show("db")
    ns.UI.ShowItem(159)
    SlashCmdList.SHADSUNGOLDLENS("diag")
    SlashCmdList.SHADSUNGOLDLENS("stats")
    SlashCmdList.SHADSUNGOLDLENS("info 6325")
    SlashCmdList.SHADSUNGOLDLENS("objet 7005")
    SlashCmdList.SHADSUNGOLDLENS("debug on")
    SlashCmdList.SHADSUNGOLDLENS("minimap")
    SlashCmdList.SHADSUNGOLDLENS("minimap")
    SlashCmdList.SHADSUNGOLDLENS("resetui")
    SlashCmdList.SHADSUNGOLDLENS("aide")
end)
check("Interface : 4 onglets et commandes /sgl sans erreur", uiOK and ns.Diag.counters.errors == 0, uiErr or (ns.Diag.errors[1] and ns.Diag.errors[1].err))
local detailPage = ns.UI.pages.detail
check("Onglet Objet : vendeurs listés pour l'eau", detailPage.list and #detailPage.list.data > 1, detailPage.list and #detailPage.list.data)
-- Boutons de la liste des vendeurs (premier rang)
local row1 = detailPage.list.rows[1]
M.tomtom = nil
row1.tomtom:Click()
check("Bouton TomTom d'une ligne vendeur : action réelle", M.tomtom ~= nil)
row1.map:Click()
check("Bouton Carte : ouvre la carte de la zone du vendeur", M.openedMap == row1.data.map, M.openedMap)
-- Opportunités
ns.UI.Show("opp")
local oppPage = ns.UI.pages.opp
check("Opportunités : calcul sans erreur", ns.Diag.counters.errors == 0)
-- Minicarte : clics
local btn = _G.LibDBIcon10_ShadsunGoldLens
ns.UI.frame:Hide()
btn.__scripts.OnClick(btn, "LeftButton")
check("Minicarte clic gauche : ouvre la fenêtre principale", ns.UI.frame:IsShown())
btn.__scripts.OnClick(btn, "RightButton")
check("Minicarte clic droit : ouvre les paramètres", ns.UI.current == "options" and ns.UI.frame:IsShown(), ns.UI.current)
-- Position de l'icône mémorisée dans les SavedVariables
check("Test 10 — position de l'icône stockée dans ShadsunGoldLensGlobal", ShadsunGoldLensGlobal.settings.minimap.minimapPos ~= nil)
-- Paramètre modifié puis persistance au rechargement
ShadsunGoldLensGlobal.settings.economy.market = "neutral"
ShadsunGoldLensGlobal.settings.windows.main = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 50, y = -60 }
local savedG = ShadsunGoldLensGlobal
local ns2 = boot({}, savedG, ShadsunGoldLensDB)
check("Test 10 — réglages conservés après rechargement", ns2.settings.economy.market == "neutral")
local _, pct = ns2.Economy.Rate()
check("Marché neutre : commission 15 % utilisée", pct == 15, pct)
check("Test 10 — observations conservées après rechargement", ns2.DB.CountObservations() >= 2)

-- =============================================================================
-- 5b. Arbitrage HDV → PNJ / reverse arbitrage
-- =============================================================================
do
    local ns = boot({}, nil, nil)
    local A = ns.Arbitrage
    local r = A.ComputeListings(100, { 50, 900, 120 }, { 1, 10, 1 })
    check("Arbitrage : gain = (100−50) + (10×100−900) = 150 pc sur 11 u.", r.gain == 150 and r.qty == 11 and r.spend == 950 and r.minUnit == 50, r.gain)
    check("Arbitrage : annonce plus chère que le rachat PNJ ignorée", A.ComputeListings(100, { 120 }, { 1 }).gain == 0)
    check("Arbitrage : sans HDV ouvert, scan refusé proprement", select(1, A.RequestFullScan()) == false)
    -- Annonces : couteau (rachat 16 pc) à 5 pc ×3, eau (1 pc) à 30 pc, 4 000 annonces neutres
    M.listings = { { id = 7005, count = 3, buyout = 15 }, { id = 159, count = 5, buyout = 150 }, { id = 7005, count = 1, buyout = 40 } }
    for i = 1, 4000 do M.listings[#M.listings + 1] = { id = 6290, count = 1, buyout = 500 } end
    M.FireEvent("AUCTION_HOUSE_SHOW")
    M.RunTimers()
    check("Panneau Gold Lens ouvert automatiquement avec l'HDV", _G.ShadsunGoldLensAuctionPanel and ShadsunGoldLensAuctionPanel:IsShown())
    local ok1 = A.RequestFullScan()
    check("Scan complet : une seule requête ReplicateItems", ok1 and M.replicateCalls == 1, M.replicateCalls)
    local ok2, msg2 = A.RequestFullScan()
    check("Scan complet : limite de 15 min respectée", ok2 == false and M.replicateCalls == 1, msg2)
    -- Le client signale la liste plusieurs fois : une seule lecture après 2 s de calme.
    local reads = 0
    local origRead = A.ReadReplicate
    A.ReadReplicate = function(force) local r = origRead(force); if r then reads = reads + 1 end; return r end
    for i = 1, 5 do M.FireEvent("REPLICATE_ITEM_LIST_UPDATE") end
    M.RunTimers()
    check("Signal répété 5 fois : une seule lecture des annonces", reads == 1, reads)
    M.FireEvent("REPLICATE_ITEM_LIST_UPDATE")
    M.RunTimers()
    check("Nouveau signal, même liste : pas de relecture (plus de défilement sans fin)", reads == 1, reads)
    check("Lecture de 4 003 annonces en tranches sans erreur", A.live and A.live.total == 4003 and ns.Diag.counters.errors == 0, A.live and A.live.total)
    local knife
    for _, x in ipairs((A.Results("live") and A.liveResults)) do if x.id == 7005 then knife = x end end
    check("Opportunité directe : couteau 3 u. à 5 pc → gain 33 pc, qté 3", knife and knife.gain == 33 and knife.qty == 3 and knife.gainUnit == 11, knife and knife.gain)
    check("Pas de fausse opportunité (eau à 30 pc > rachat 1 pc)", (function() for _, x in ipairs((A.Results("live") and A.liveResults)) do if x.id == 159 then return false end end return true end)())
    M.ProcessItem(GameTooltip, 7005)
    local tx = strip(joined(GameTooltip))
    -- Prix de rachat : uniquement celui du jeu (jamais le prix d'achat marchand d'Auctionator)
    local usesBuy = false
    for _, x in ipairs((A.Results("live") and A.liveResults)) do if x.sell == 999999 then usesBuy = true end end
    check("Prix « PNJ / u. » = prix de vente au marchand du jeu (pas le prix d'achat marchand)", not usesBuy and knife and knife.sell == 16)
    M.uncached[5441] = true
    M.listings[#M.listings + 1] = { id = 5441, count = 2, buyout = 20 } -- giberne : rachat 25 pc
    A.ReadReplicate(true); M.RunTimers()
    local early = false
    for _, x in ipairs((A.Results("live") and A.liveResults)) do if x.id == 5441 then early = true end end
    check("Objet non chargé : absent tant que son prix de rachat est inconnu (pas de valeur de repli)", not early)
    M.uncached[5441] = nil
    M.FireEvent("GET_ITEM_INFO_RECEIVED", 5441, true)
    M.RunTimers()
    local late
    for _, x in ipairs((A.Results("live") and A.liveResults)) do if x.id == 5441 then late = x end end
    check("Objet chargé ensuite : ajouté avec son vrai prix de rachat (25 pc, gain 30 pc)", late and late.sell == 25 and late.gain == 30, late and late.gain)
    table.remove(M.listings)
    A.ReadReplicate(true); M.RunTimers()
    check("Infobulle : ligne « Revente PNJ » avec annonces en cours", tx:find("Revente PNJ (HDV » PNJ) | +11\194\160pc / u. · 3 u. à 5\194\160pc", 1, true) ~= nil, tx)
    M.ProcessItem(GameTooltip, 159)
    check("Infobulle : pas de ligne « Revente PNJ » si non rentable", not strip(joined(GameTooltip)):find("Revente PNJ", 1, true))
    -- Historique Auctionator : giberne (rachat 25 pc) cotée 10 pc
    M.ahPrices[5441] = 10
    ns.Prices.Invalidate()
    A.ComputeHistoric()
    M.RunTimers()
    local pouch
    for _, x in ipairs(A.histResults) do if x.id == 5441 then pouch = x end end
    check("Historique : giberne cotée 10 pc → gain 15 pc / u.", pouch and pouch.gainUnit == 15 and pouch.source == "HIST", pouch and pouch.gainUnit)
    local all = A.Results("all")
    local dup = 0
    for _, x in ipairs(all) do if x.id == 7005 and x.source == "HIST" then dup = dup + 1 end end
    check("Résultats combinés : annonces en cours prioritaires, sans doublon", dup == 0)
    -- Panneau : liste, bouton Rechercher
    local panel = ShadsunGoldLensAuctionPanel.panel
    panel.Refresh()
    check("Panneau HDV : 2 opportunités listées (couteau direct, giberne historique)", #panel.list.data == 2, #panel.list.data)
    local okRow = pcall(function() panel.list.rows[1].search:Click() end)
    check("Panneau HDV : bouton Rechercher d'une ligne fonctionnel", okRow and M.atrSearch ~= nil)
    local okS, msgS = A.Search(7005)
    check("Rechercher : recherche Auctionator NON exacte (toutes les variantes)", okS and M.atrSearch == "Couteau à dépecer" and M.atrExact == nil, msgS)
    _G.Auctionator.API.v1.MultiSearch = nil
    local okB = A.Search(7005)
    check("Rechercher : repli sur la barre de recherche Blizzard", okB and M.blizzSearch == "Couteau à dépecer", M.blizzSearch)
    local uiOK, uiErr = pcall(function()
        SlashCmdList.SHADSUNGOLDLENS("hdv")
        SlashCmdList.SHADSUNGOLDLENS("arb")
        ns.UI.Show("opp")
        ns.UI.pages.opp.SetDirection("reverse")
        ns.UI.pages.opp.SetDirection("cross")
        ns.UI.pages.opp.SetDirection("forward")
        ns.UI.Show("opp")
    end)
    check("Panneau HDV, /sgl hdv, /sgl arb et mode « HDV → PNJ » sans erreur", uiOK and ns.Diag.counters.errors == 0, uiErr or (ns.Diag.errors[1] and ns.Diag.errors[1].err))
    M.FireEvent("AUCTION_HOUSE_CLOSED")
    M.FireEvent("AUCTION_HOUSE_SHOW")
    -- Arrêt de la lecture
    local okR = A.ReadReplicate(true)
    local stopped = A.CancelRead()
    M.RunTimers()
    check("Bouton « Arrêter la lecture » : lecture interrompue, données précédentes conservées",
        okR and stopped and not A.processing and A.liveTotal == 4003 and #A.Results("live") >= 1)
    -- Liste figée : aucune mise à jour automatique
    local pnl = ShadsunGoldLensAuctionPanel.panel
    local freezeBtn
    for _, f in ipairs(M.allFrames) do if f.__type == "CheckButton" and f:GetParent() == pnl and f.label and f.label.__text == "Figer la liste" then freezeBtn = f end end
    freezeBtn:SetChecked(true); freezeBtn.__scripts.OnClick(freezeBtn)
    local before = #pnl.list.data
    M.ahPrices[6290] = 1; M.items[6290].sell = 50; ns.Prices.Invalidate()
    A.ComputeHistoric(); M.RunTimers()
    check("Liste figée : les lignes ne changent pas pendant les mises à jour", #pnl.list.data == before, #pnl.list.data)
    freezeBtn:SetChecked(false); freezeBtn.__scripts.OnClick(freezeBtn)
    check("Liste défigée : nouvelles données appliquées", #pnl.list.data == before + 1, #pnl.list.data)
    -- Filtre de source par boutons
    local liveBtn = pnl.sourceButtons:Find("live")
    liveBtn:Click()
    local onlyLive = true
    for _, d in ipairs(pnl.list.data) do if d.source ~= "LIVE" then onlyLive = false end end
    check("Filtre « Direct (annonces) » : seules les annonces actuelles", onlyLive and #pnl.list.data >= 1)
    -- Bouton « Replacer à côté de l'HDV » : visible seulement après un déplacement
    local fr = ShadsunGoldLensAuctionPanel
    check("Bouton « Replacer » masqué tant que le panneau n'a pas été déplacé", not fr.redock:IsShown())
    fr.__scripts.OnDragStop(fr)
    for _, h in ipairs(fr.__hooks.OnDragStop or {}) do h(fr) end
    check("Bouton « Replacer » visible après un déplacement", fr.redock:IsShown())
    fr.redock:Click()
    check("Bouton « Replacer » : panneau raccroché à l'HDV, bouton masqué", ns.settings.windows.ahpanel == nil and not fr.redock:IsShown())
    -- Taille du panneau : ajustée à la place libre à droite de l'HDV
    ns.settings.windows.ahpanel = nil
    ns.settings.ah.scale = nil
    ns.AuctionPanel.Anchor()
    local sc = fr.__scale
    check(string.format("Taille auto : panneau réduit pour tenir à droite de l'HDV (échelle %.2f)", sc or -1),
        sc and sc < 1 and sc >= 0.6 and fr.__point[2] == AuctionHouseFrame)
    local plusBtn, autoBtn
    for _, f in ipairs(M.allFrames) do
        if f.__type == "Button" and f:GetParent() == fr and f.__text == "+" then plusBtn = f end
        if f.__type == "Button" and f:GetParent() == fr and f.__text == "Auto" then autoBtn = f end
    end
    plusBtn:Click()
    check("Bouton « + » : taille augmentée de 5 % et mémorisée", ns.settings.ah.scale and math.abs(ns.settings.ah.scale - (math.floor((sc + 0.05) * 100 + 0.5) / 100)) < 1e-9, ns.settings.ah.scale)
    autoBtn:Click()
    check("Bouton « Auto » : retour à l'ajustement automatique", ns.settings.ah.scale == nil and math.abs(fr.__scale - sc) < 1e-9)
    rawset(AuctionHouseFrame, "__right", 1150)
    ns.AuctionPanel.Anchor()
    check("Écran trop étroit : panneau au bord droit de l'écran, sans dépasser", fr.__scale == 0.6 and fr.__point[1] == "TOPRIGHT" and fr.__point[2] == UIParent)
    rawset(AuctionHouseFrame, "__right", 800)
    -- Aucun caractère absent de la police du jeu (→, −, –, ≠, ✓…)
    local badGlyph
    local function scan(t)
        for seq in t:gmatch("[\226-\239][\128-\191][\128-\191]") do
            if seq ~= "\226\128\148" and seq ~= "\226\128\166" then badGlyph = t end
        end
    end
    for _, f in ipairs(M.allFrames) do if type(f.__text) == "string" then scan(f.__text) end end
    for _, p in ipairs(M.printed) do scan(p) end
    check("Interface : aucun caractère absent de la police du jeu", not badGlyph, badGlyph)
    -- Performance : demandes d'infos étalées, calcul incrémental, libération à la fermeture
    M.listings = {}
    for i = 1, 500 do
        local id = 700000 + i
        M.items[id] = { name = "Objet " .. i, sell = 100, class = 15, sub = 0, bind = 0 }
        M.uncached[id] = true
        M.listings[#M.listings + 1] = { id = id, count = 1, buyout = 50 }
    end
    M.timers = {}
    M.requestCount = 0
    A.ReadReplicate(true)
    while A.processing do M.RunOneTimer() end
    check("Lecture : aucune demande d'infos envoyée d'un coup (file d'attente)", M.requestCount == 0, M.requestCount)
    local guard = 0
    while M.requestCount == 0 and guard < 50 do M.RunOneTimer(); guard = guard + 1 end
    check("Demandes d'infos au serveur : 20 au plus par tranche de 0,25 s", M.requestCount > 0 and M.requestCount <= 20, M.requestCount)
    local calls = 0
    local origCL = A.ComputeListings
    A.ComputeListings = function(...) calls = calls + 1; return origCL(...) end
    M.uncached[700001] = nil
    M.FireEvent("GET_ITEM_INFO_RECEIVED", 700001, true)
    A.ComputeListings = origCL
    check("Info reçue pour un objet : un seul calcul (plus de recalcul complet)", calls == 1, calls)
    local has = false
    for _, x in ipairs((A.Results("live") and A.liveResults)) do if x.id == 700001 then has = true end end
    check("Objet chargé ajouté immédiatement aux opportunités", has)
    -- Bouton « Tout arrêter » / « /sgl stop » : tout s'interrompt, résultats conservés
    local keepLive = #A.Results("live")
    A.ComputeHistoric()                       -- analyse lancée (première tranche exécutée)
    check("Analyse de l'historique en cours, demandes d'infos en file", A.histRunning and A.QueueSize() > 0, A.QueueSize())
    local stopBtnAll = ShadsunGoldLensAuctionPanel.scan.stopButton
    stopBtnAll:Click()
    local before2 = M.requestCount
    M.RunTimers()
    check("« Tout arrêter » : analyse stoppée, file vidée, plus aucune demande au serveur",
        not A.histRunning and A.QueueSize() == 0 and A.PendingPrices() == 0 and M.requestCount == before2 and not A.IsBusy())
    check("« Tout arrêter » : résultats déjà obtenus conservés", #A.Results("live") == keepLive and #A.histResults >= 1)
    A.ReadReplicate(true)
    SlashCmdList.SHADSUNGOLDLENS("stop")
    M.RunTimers()
    check("/sgl stop : lecture des annonces interrompue", not A.processing and not A.IsBusy())
    -- Vitesse « Rapide » : 50 demandes par tranche (aucune limite de volume)
    ns.settings.ah.speed = "fast"
    for i = 1, 120 do M.uncached[700000 + i] = true end
    M.requestCount = 0
    for i = 1, 120 do A.SellPrice(700000 + i) end
    local g2 = 0
    while M.requestCount == 0 and g2 < 20 do M.RunOneTimer(); g2 = g2 + 1 end
    check("Vitesse « Rapide » : 50 demandes par tranche de 0,25 s", M.requestCount == 50, M.requestCount)
    M.RunTimers()
    check("Volume non limité : les 120 objets ont tous été demandés", M.requestCount == 120, M.requestCount)
    ns.settings.ah.speed = "normal"
    M.FireEvent("AUCTION_HOUSE_CLOSED")
    check("Fermeture de l'HDV : annonces brutes libérées et file d'attente vidée", A.live == nil and A.PendingPrices() == 0)
    local before = M.requestCount
    M.RunTimers()
    check("Après fermeture : plus aucune demande d'infos au serveur", M.requestCount == before, M.requestCount - before)
    check("Après fermeture : résultats compacts conservés", A.LiveFor(700001) ~= nil and #A.Results("live") >= 1)
    for i = 1, 500 do M.items[700000 + i] = nil; M.uncached[700000 + i] = nil end
    -- Mémoire sur un volume réel : 54 555 annonces, 8 000 objets
    M.FireEvent("AUCTION_HOUSE_SHOW")
    M.listings = {}
    for i = 1, 54555 do M.listings[i] = { id = 800000 + (i % 8000), count = 1 + (i % 20), buyout = 1000 + i } end
    collectgarbage("collect")
    local m0 = collectgarbage("count")
    A.ReadReplicate(true)
    while A.processing do M.RunOneTimer() end
    collectgarbage("collect")
    local m1 = collectgarbage("count")
    M.FireEvent("AUCTION_HOUSE_CLOSED")
    M.listings = {}
    collectgarbage("collect")
    local m2 = collectgarbage("count")
    check(string.format("Mémoire : +%.1f Mo pendant la lecture de 54 555 annonces, %.1f Mo conservés après fermeture de l'HDV",
        (m1 - m0) / 1024, math.max(0, m2 - m0) / 1024), (m2 - m0) < (m1 - m0) * 0.1)
    M.timers = {}
    check("Fermeture de l'HDV : panneau masqué", not ShadsunGoldLensAuctionPanel:IsShown())
    -- Signature : aucun texte d'interface ne contient le nom réel
    local leak
    for _, f in ipairs(M.allFrames) do
        if type(f.__text) == "string" and f.__text:find("Tarak", 1, true) then leak = f.__text end
    end
    for _, p in ipairs(M.printed) do if p:find("Tarak", 1, true) then leak = p end end
    check("Interface : signature « Shadsun » uniquement, nom réel absent des textes affichés", not leak, leak)
end

-- =============================================================================
-- 5b'. Variantes d'équipement, sens PNJ » HDV dans l'HDV, possédé, qualité, taille
-- =============================================================================
do
    local ns = boot({}, nil, nil)
    local A, P, U = ns.Arbitrage, ns.Prices, ns.U
    M.items[2520] = { name = "Bâtarde aiguisée", sell = 1377, class = 2, sub = 8, bind = 0, quality = 2 }
    M.listings = {
        { id = 2520, count = 1, buyout = 1600 },                                       -- version simple
        { id = 2520, count = 1, buyout = 1300, name = "Bâtarde aiguisée de l'aigle" }, -- variante moins chère
        { id = 2520, count = 1, buyout = 5000, name = "Bâtarde aiguisée de force" },   -- variante plus chère
        { id = 7005, count = 2, buyout = 10 },                                         -- couteau : 5 pc / u.
    }
    M.FireEvent("AUCTION_HOUSE_SHOW")
    M.RunTimers()
    A.ReadReplicate(true)
    M.RunTimers()
    local p1, _, st1 = P.Best(2520)
    check("Équipement : prix HDV = version simple seulement (16 pa, pas la variante à 13 pa)", p1 == 1600 and st1 == "LIVE", p1)
    local rv = A.LiveFor(2520)
    check("Équipement, sens HDV » PNJ : variantes prises en compte (rachat PNJ identique)", rv and rv.gain == 77, rv and rv.gain)
    local p2, _, st2 = P.Best(7005)
    check("Prix HDV : annonces du dernier scan prioritaires sur l'historique (5 pc et non 3 pa)", p2 == 5 and st2 == "LIVE", p2)
    ns.Market.Delete("A")
    M.ahPrices[2520] = 9999
    local p3, _, st3 = P.Best(2520)
    check("Équipement sans annonces lues : historique Auctionator non utilisé (variantes mélangées)", p3 == nil and st3 == "VARIANTS", st3)
    M.ahPrices[2520] = nil
    -- Nombre possédé
    M.owned = { [6325] = { 2, 1 } }
    M.ProcessItem(GameTooltip, 6325)
    check("Infobulle : « Possédé | 2 (sacs) · 1 (banque) »", strip(joined(GameTooltip)):find("Possédé | 2 (sacs) · 1 (banque)", 1, true) ~= nil, strip(joined(GameTooltip)))
    M.ProcessItem(GameTooltip, 7005)
    check("Infobulle : aucune ligne « Possédé » si l'objet n'est pas possédé", not strip(joined(GameTooltip)):find("Possédé", 1, true))
    -- Qualité
    check("Nom coloré selon la qualité (vert)", (U.QualityName(2520) or ""):find("^|cff1eff00Bâtarde aiguisée") ~= nil, U.QualityName(2520))
    -- Panneau HDV, sens PNJ » HDV
    local fr = ShadsunGoldLensAuctionPanel
    check("Panneau HDV : sens HDV » PNJ par défaut", fr.panel:IsShown() and not fr.fwd:IsShown())
    fr.tabs:Find("forward"):Click()
    check("Sélecteur de sens : liste PNJ » HDV affichée dans l'HDV", fr.fwd:IsShown() and not fr.panel:IsShown() and ns.settings.ah.direction == "forward")
    -- Même liste que l'onglet Opportunités : filtres présents, Rechercher, pas d'Aller
    local typeFilter = fr.fwd.filters and fr.fwd.filters.cat
    check("Liste PNJ » HDV de l'HDV : mêmes filtres que l'onglet Opportunités", typeFilter ~= nil and (typeFilter.__text or ""):find("^Catégorie : ") ~= nil)
    fr.fwd.Compute()
    local recipeRow
    for idx, d in ipairs(fr.fwd.list.data) do if d.id == 6325 then recipeRow = idx end end
    check("Liste PNJ » HDV : recette achetée 40 pc, revendue 1 po 50 pa", recipeRow ~= nil, #fr.fwd.list.data)
    fr.fwd.list.offset = recipeRow - 1
    fr.fwd.list:Refresh()
    local row = fr.fwd.list.rows[1]
    check("Liste PNJ » HDV : colonne « Sacs » = 2 (sacs du personnage, sans la banque)", strip(row.cells[10].__text or "") == "2", row.cells[10].__text)
    check("Liste PNJ » HDV : colonne « Vente » = « - » (rien en vente)", strip(row.cells[11].__text or "") == "-", row.cells[11].__text)
    check("Liste PNJ » HDV : nom coloré selon la qualité", (row.cells[1].__text or ""):find("^|c") ~= nil)
    M.atrSearch = nil
    row.search:Click()
    check("Liste PNJ » HDV de l'HDV : bouton Rechercher, sans bouton Aller", M.atrSearch == "Recette : Goujon brillant" and row.go == nil)
    -- Tri par « Sacs »
    fr.fwd.SortBy("bags", true)
    check("Tri par « Sacs » : l'objet possédé (2) passe en tête", fr.fwd.list.data[1].id == 6325, fr.fwd.list.data[1].id)
    M.owned = { [6325] = { 0, 0 }, [159] = { 5, 0 } }
    M.FireEvent("BAG_UPDATE_DELAYED")
    check("Tri par « Sacs » : mis à jour quand les sacs changent", fr.fwd.list.data[1].id ~= 6325 and fr.fwd.list.data[1].bags >= 1, fr.fwd.list.data[1].id)
    M.owned = { [6325] = { 2, 1 } }
    -- Onglet Opportunités : icônes Aller et Copier
    ns.UI.Show("opp")
    local opp = ns.UI.pages.opp.forward
    opp.Compute()
    local ridx
    for idx, d in ipairs(opp.list.data) do if d.id == 6325 then ridx = idx end end
    opp.list.offset = ridx - 1
    opp.list:Refresh()
    local orow = opp.list.rows[1]
    M.tomtom = nil
    orow.go:Click()
    check("Onglet Opportunités : icône Aller → point TomTom vers le marchand", M.tomtom ~= nil and orow.search == nil)
    orow.copy:Click()
    local expected = ns.Navigation.Command(orow.data.offer)
    check("Onglet Opportunités : icône Copier → commande /tway présélectionnée", ns.UI.copyLine and ns.UI.copyLine:IsShown()
        and ns.UI.copyLine.edit:GetText() == expected and expected:find("^/tway #%d+ ") ~= nil, ns.UI.copyLine and ns.UI.copyLine.edit:GetText())
    ns.UI.copyLine:Hide()
    -- Armes et armures : prix à l'unité (lots de 200 de la référence ignorés)
    M.items[2947] = { name = "Petit couteau de lancer", sell = 1, class = 2, sub = 16, bind = 0 }
    ns.Catalog.Invalidate(2947)
    local knife2 = ns.Catalog.GetView(2947).best
    check("Arme de jet : vendue à l'unité (15 pc), plus de lot de 200 à 0 pc", knife2 and knife2.qty == 1 and knife2.price == 15, knife2 and (knife2.qty .. " / " .. knife2.price))
    M.items[2947] = nil
    fr.tabs:Find("reverse"):Click()
    -- Taille de la fenêtre principale
    ns.UI.Show("detail")
    local mf = ns.UI.frame
    local plusB, resetB
    for _, f in ipairs(M.allFrames) do
        if f.__type == "Button" and f:GetParent() == mf and f.__text == "+" then plusB = f end
        if f.__type == "Button" and f:GetParent() == mf and f.__text == "100 %" then resetB = f end
    end
    plusB:Click(); plusB:Click()
    check("Fenêtre principale : « + » agrandit (120 %) et mémorise", math.abs(mf.__scale - 1.2) < 1e-9 and math.abs(ns.settings.display.mainScale - 1.2) < 1e-9, mf.__scale)
    for i = 1, 10 do plusB:Click() end
    check("Fenêtre principale : taille plafonnée à 150 %", math.abs(mf.__scale - 1.5) < 1e-9, mf.__scale)
    resetB:Click()
    check("Fenêtre principale : « 100 % » rétablit la taille normale", mf.__scale == 1)
    check("Aucune erreur interne (bloc v0.7.0)", ns.Diag.counters.errors == 0, ns.Diag.errors[1] and ns.Diag.errors[1].err)
    M.owned = nil
    M.items[2520] = nil
    M.FireEvent("AUCTION_HOUSE_CLOSED")
end

-- =============================================================================
-- 5c. Bordure dans la fenêtre du marchand / merchant border
-- =============================================================================
do
    local ns = boot({}, nil, nil)
    M.npcGUID, M.npcName, M.npcFaction = "Creature-0-1-2-3-5494-0000ABCD", "Catherine Leland", "Alliance"
    M.merchant = {
        { id = 6325, info = { price = 40, stackCount = 1, numAvailable = -1, isPurchasable = true } },      -- HDV 1 po 50 : rentable
        { id = 5441, info = { price = 2000, stackCount = 1, numAvailable = -1, isPurchasable = true } },    -- HDV 9 pa : perte
        { id = 25, info = { price = 100, stackCount = 1, numAvailable = -1, isPurchasable = true } },       -- aucun prix HDV
        { id = 7005, info = { price = 0, stackCount = 1, hasExtendedCost = true, isPurchasable = true } },  -- devise
    }
    M.FireEvent("MERCHANT_SHOW")
    M.RunTimers()
    MerchantFrame_UpdateMerchantInfo()
    local function shown(i)
        local btn = _G["MerchantItem" .. i .. "ItemButton"]
        for _, f in ipairs(M.allFrames) do
            if f:GetParent() == btn and f.__backdrop and f:IsShown() then return f end
        end
        return nil
    end
    local b1 = shown(1)
    check("Marchand : objet rentable entouré (recette, 40 pc → 1 po 50 pa)", b1 ~= nil)
    check("Marchand : objets non rentables, sans prix HDV ou payés en devise non entourés", not shown(2) and not shown(3) and not shown(4))
    local noText = true
    for _, f in ipairs(M.allFrames) do if f:GetParent() == b1 and f.__type == "FontString" then noText = false end end
    check("Marchand : aucun texte ajouté sur l'icône", noText)
    check("Marchand : couleur par défaut verte", b1 and b1.__border and b1.__border[2] == 1)
    ns.settings.ah.borderColor = { 1, 0.82, 0 }
    ns.MerchantOverlay.Update()
    check("Marchand : couleur choisie appliquée (or)", b1.__border[1] == 1 and b1.__border[2] == 0.82)
    rawset(MerchantFrame, "selectedTab", 2)
    ns.MerchantOverlay.Update()
    check("Onglet Rachats : aucune bordure", not shown(1))
    rawset(MerchantFrame, "selectedTab", 1)
    ns.settings.ah.merchantBorder = false
    ns.MerchantOverlay.Update()
    check("Option désactivée : aucune bordure", not shown(1))
    ns.settings.ah.merchantBorder = true
    rawset(MerchantFrame, "page", 2)
    ns.MerchantOverlay.Update()
    check("Page 2 du marchand (emplacements vides) : aucune bordure, pas d'erreur", not shown(1) and ns.Diag.counters.errors == 0)
    rawset(MerchantFrame, "page", 1)
    M.merchant = nil
end

-- =============================================================================
-- 6. Mode dégradé et migration / degraded mode and migration
-- =============================================================================
local ns3 = boot({ auctionator = false, tomtom = false }, nil, nil)
check("Test 11 — sans Auctionator : chargement sans erreur", ns3.Diag.counters.errors == 0)
M.ProcessItem(GameTooltip, 6325)
local t11 = strip(joined(GameTooltip))
check("Test 11 — sans Auctionator : indisponibilité clairement affichée", t11:find("Auctionator absent", 1, true) ~= nil, t11)
check("Test 11 — sans Auctionator : achat PNJ toujours affiché", t11:find("Achat PNJ | 40", 1, true) ~= nil)
check("Test 11 — bannière signale l'absence d'Auctionator", (M.printed[#M.printed] or ""):find("Auctionator absent", 1, true) ~= nil)
local okN, msgN = ns3.Navigation.AddWaypoint(ns3.Catalog.GetView(6325).best)
check("Sans TomTom : repère natif du jeu utilisé", okN and M.userWaypoint and M.userWaypoint.uiMapID ~= nil, msgN)

local legacy = { offers = { [6325] = { ["5494:1:false"] = { npc = 5494, knownSide = true, name = "Catherine Leland",
    map = 1453, x = 55.1, y = 69.8, price = 38, quantity = 1, extra = false, seen = 1763000000 } } },
    options = { tooltip = true, showMissing = false, shiftOnly = false }, minimap = { minimapPos = 123 } }
local ns4 = boot({}, nil, legacy)
check("Migration v0.3.0 : relevé transféré", ShadsunGoldLensGlobal.observations[6325] and ShadsunGoldLensGlobal.observations[6325]["5494:1:0"] ~= nil)
check("Migration v0.3.0 : options et position de minicarte reprises", ns4.settings.tooltip.showNoVendorLine == false and ns4.settings.minimap.minimapPos == 123)
check("Migration v0.3.0 : sauvegarde de l'ancien contenu conservée", ShadsunGoldLensDB.legacy030 ~= nil and ShadsunGoldLensDB.migrated040 == true)
check("Migration v0.3.0 : 1 relevé compté", ns4.DB.migratedRows == 1, ns4.DB.migratedRows)
local ns5 = boot({}, ShadsunGoldLensGlobal, ShadsunGoldLensDB)
check("Migration idempotente (pas de double import)", ns5.DB.migratedRows == 0, ns5.DB.migratedRows)

-- Valeurs secrètes (client Midnight) : aucune erreur
_G.issecretvalue = function(v) return v == 6325 end
M.ProcessItem(GameTooltip, 6325)
check("Valeur secrète : infobulle ignorée sans erreur", countMatches(GameTooltip, "Shadsun Gold Lens") == 0 and ns5.Diag.counters.errors == 0)
_G.issecretvalue = nil

-- =============================================================================
-- 6. v0.8.0 : marchés par serveur et par HDV, inventaire du compte,
--    catégories de l'HDV, arbitrage HDV » HDV, interface
-- =============================================================================
do
    local ns = boot({}, nil, nil)
    local A, MK, INV, U, W = ns.Arbitrage, ns.Market, ns.Inventory, ns.U, ns.W
    local G = ShadsunGoldLensGlobal
    -- --- Utilitaires --------------------------------------------------------
    check("Recherche sans accents : « Épée » → « epee »", U.Fold("Épée Œil") == "epee oeil", U.Fold("Épée Œil"))
    check("Âge lisible : il y a 3 h", U.Ago(time() - 3 * 3600) == "il y a 3 h" and U.Ago(time() - 2 * 86400) == "il y a 2 j", U.Ago(time() - 3 * 3600))
    local pk = MK.Pack(123456789, 4321)
    local up, uq = MK.Unpack(pk)
    check("Emballage prix/quantité réversible et sous 10^14", up == 123456789 and uq == 4321 and MK.Pack(MK.PMAX, 99999) < 1e14
        and string.format("%.14g", MK.Pack(MK.PMAX, 99999)) == string.format("%.0f", MK.Pack(MK.PMAX, 99999)), pk)
    check("Quantité plafonnée à 99 999, prix plafonné", select(2, MK.Unpack(MK.Pack(10, 250000))) == 99999 and MK.Unpack(MK.Pack(5e12, 1)) == MK.PMAX)
    check("Schéma de données 4 et nouvelles tables", G.schema == 4 and type(G.markets) == "table" and type(G.chars) == "table")

    -- --- Choix de l'HDV : zone + bouton -----------------------------------------
    check("Zone de Hurlevent : HDV Alliance proposé", MK.ZoneKey() == "A" and MK.Current() == "A" and MK.Choice() == nil)
    local origBest = C_Map.GetBestMapForUnit
    C_Map.GetBestMapForUnit = function() return 1446 end
    check("Zone de Tanaris (Gadgetzan) : HDV neutre proposé", MK.ZoneKey() == "N" and MK.Current() == "N")
    C_Map.GetBestMapForUnit = origBest

    -- --- Scan enregistré pour l'HDV choisi --------------------------------------
    M.listings = {
        { id = 7005, count = 2, buyout = 100 },    -- 50 pc / u.
        { id = 7005, count = 3, buyout = 240 },    -- 80 pc / u.
        { id = 2589, count = 20, buyout = 2000 },  -- 1 pa / u.
    }
    M.FireEvent("AUCTION_HOUSE_SHOW")
    M.RunTimers()
    A.ReadReplicate(true)
    M.RunTimers()
    local snapA = G.markets["Forever"] and G.markets["Forever"].A
    local pA, qA = MK.Item(snapA, 7005)
    check("Scan enregistré pour l'HDV Alliance du serveur « Forever »", pA == 50 and qA == 5 and snapA.char == "Aurelia", pA)
    check("Stockage compact : un seul nombre par objet (50 × 100 000 + 5)", snapA.d[7005] == 5000005 and snapA.p == nil, snapA.d[7005])
    check("Scan : nombre d'annonces et heure conservés", snapA and snapA.total == 3 and snapA.time == time())
    -- Choix corrigé après le scan : le scan est déplacé vers l'HDV neutre
    MK.SetChoice("neutral")
    check("Choix mémorisé pour le personnage (ShadsunGoldLensDB)", ShadsunGoldLensDB.ahMarket == "neutral")
    check("Choix corrigé après le scan : scan déplacé vers l'HDV neutre", G.markets.Forever.N and MK.Item(G.markets.Forever.N, 7005) == 50 and G.markets.Forever.A == nil)
    check("Avertissement : la zone (Hurlevent) ne concorde pas avec « HDV neutre »", MK.Mismatch() == true)
    local scan = ShadsunGoldLensAuctionPanel.scan
    scan.Update()
    check("Barre de scan : avertissement affiché", strip(scan.hint.__text or ""):find("La zone indique HDV Alliance", 1, true) ~= nil, scan.hint.__text)
    MK.SetChoice("faction")
    check("Retour à « HDV de ma faction » : scan redéplacé, pas d'avertissement", G.markets.Forever.A and G.markets.Forever.N == nil and not MK.Mismatch())
    -- Visite suivante : un changement de choix ne déplace plus l'ancien scan
    M.FireEvent("AUCTION_HOUSE_CLOSED")
    M.FireEvent("AUCTION_HOUSE_SHOW")
    M.RunTimers()
    MK.SetChoice("neutral")
    check("Visite suivante : le scan précédent n'est pas déplacé", G.markets.Forever.A and G.markets.Forever.N == nil)
    -- Deuxième scan : HDV neutre (autre personnage, mêmes données de compte)
    M.time = M.time + 16 * 60
    M.listings = { { id = 7005, count = 1, buyout = 200 }, { id = 2589, count = 5, buyout = 400 }, { id = 6325, count = 1, buyout = 20000 } }
    A.ReadReplicate(true)
    M.RunTimers()
    local snapN = G.markets.Forever.N
    check("Deuxième scan enregistré pour l'HDV neutre, celui de l'Alliance conservé", snapN and MK.Item(snapN, 7005) == 200 and MK.Item(G.markets.Forever.A, 7005) == 50)
    M.FireEvent("AUCTION_HOUSE_CLOSED")
    MK.SetChoice("faction")
    M.FireEvent("AUCTION_HOUSE_SHOW")
    M.RunTimers()

    -- Équipement chargé après le scan : prix de la version simple ajouté à la photo
    M.FireEvent("AUCTION_HOUSE_CLOSED"); M.FireEvent("AUCTION_HOUSE_SHOW"); M.RunTimers()
    M.items[2530] = { name = "Hache de bûcheron", sell = 100, class = 2, sub = 0, bind = 0 }
    M.uncached[2530] = true
    M.listings = { { id = 7005, count = 1, buyout = 200 }, { id = 2589, count = 5, buyout = 400 }, { id = 6325, count = 1, buyout = 20000 },
        { id = 2530, count = 1, buyout = 900 }, { id = 2530, count = 1, buyout = 700, name = "Hache de bûcheron du singe" } }
    MK.SetChoice("neutral")
    A.ReadReplicate(true)
    while A.processing do M.RunOneTimer() end
    local before = MK.Price(2530, "N")
    M.uncached[2530] = nil
    M.FireEvent("GET_ITEM_INFO_RECEIVED", 2530, true)
    local after = MK.Price(2530, "N")
    check("Équipement chargé après le scan : version simple ajoutée à la photo (9 pa)", before == nil and after == 900, tostring(before) .. " / " .. tostring(after))
    M.RunTimers()
    M.FireEvent("AUCTION_HOUSE_CLOSED")
    MK.SetChoice("faction")
    M.FireEvent("AUCTION_HOUSE_SHOW"); M.RunTimers()
    M.items[2530] = nil

    -- --- Infobulle : un prix par HDV scanné --------------------------------------
    M.ProcessItem(GameTooltip, 7005)
    local tx = strip(joined(GameTooltip))
    check("Infobulle : ligne « HDV Alliance » (50 pc, 5 en vente, âge)", tx:find("HDV Alliance | 50\194\160pc (5 en vente · ", 1, true) ~= nil, tx)
    check("Infobulle : ligne « HDV neutre » (2 pa, 1 en vente)", tx:find("HDV neutre | 2\194\160pa (1 en vente · ", 1, true) ~= nil, tx)
    check("Infobulle : plus de ligne Auctionator quand un HDV est scanné", not tx:find("\nHDV | ", 1, true))
    M.ProcessItem(GameTooltip, 159)
    local tx2 = strip(joined(GameTooltip))
    check("Objet absent des scans : prix Auctionator conservé", tx2:find("HDV | 30\194\160pc", 1, true) ~= nil, tx2)
    G.markets.Forever.H = { time = time(), total = 1, char = "Grok", d = { [7005] = MK.Pack(75, 1) } }
    M.ProcessItem(GameTooltip, 7005)
    check("HDV de l'autre faction affiché par défaut (v0.9.0)", strip(joined(GameTooltip)):find("HDV Horde | 75\194\160pc", 1, true) ~= nil)
    ns.settings.tooltip.showOtherFaction = false
    M.ProcessItem(GameTooltip, 7005)
    check("Option désactivée : HDV de l'autre faction masqué", not strip(joined(GameTooltip)):find("HDV Horde", 1, true))

    -- --- Prix de revente : marché choisi -----------------------------------------
    local p1, _, st1, _, q1, k1 = ns.Prices.Best(7005)
    check("PNJ » HDV : prix du scan de l'HDV de faction (50 pc)", p1 == 50 and st1 == "LIVE" and q1 == 5 and k1 == "A", p1)
    ns.settings.economy.market = "neutral"
    local p2, _, _, _, _, k2 = ns.Prices.Best(7005)
    check("Marché de revente neutre : prix du scan neutre (2 pa)", p2 == 200 and k2 == "N", p2)
    ns.settings.economy.market = "faction"
    G.markets.Forever.A.time = time() - 10 * 86400
    local p3, _, st3 = ns.Prices.Best(7005)
    check("Scan ancien (10 j > 7 j) : historique Auctionator préféré (3 pa)", p3 == 300 and st3 == "OK", p3)
    G.markets.Forever.A.time = time()

    -- --- Arbitrage HDV » HDV --------------------------------------------------------
    local gain, cut, roi = MK.CrossUnit(50, 200, 0.15)
    check("HDV » HDV : 200 − commission 30 − 50 = gain 120 pc (240 %)", gain == 120 and cut == 30 and math.abs(roi - 240) < 1e-9, gain)
    local cross = MK.Cross("A>N")
    local knife
    for _, r in ipairs(cross) do if r.id == 7005 then knife = r end end
    check("HDV » HDV : couteau acheté HDV Alliance, revendu HDV neutre", knife and knife.gain == 120 and knife.qty == 5 and knife.direct, knife and knife.gain)
    local ah = false
    for _, r in ipairs(MK.Cross()) do if r.pair == "A>H" then ah = r end end
    check("Paire Alliance » Horde marquée « indirecte »", ah and ah.direct == false)
    check("Paires disponibles : 6 (trois HDV scannés)", #MK.Pairs() == 6, #MK.Pairs())

    -- --- Inventaire de tous les personnages -------------------------------------------
    M.containers = { [0] = { { 6325, 3 }, { 2589, 10 } }, [1] = { { 2589, 5 } } }
    INV.ScanBags()
    local me = G.chars.Forever.Aurelia
    check("Sacs du personnage enregistrés (compte, par serveur)", me and me.bags[2589] == 15 and me.bags[6325] == 3 and me.money == 123456)
    G.chars.Forever.Kael = { side = "A", bags = { [6325] = 4 }, bank = { [6325] = 1 }, time = time() }
    G.chars.Autre = { Zed = { side = "H", bags = { [6325] = 99 } } }
    M.owned = { [6325] = { 3, 0 } }
    local total, list = INV.Count(6325)
    check("Possédé : personnage connecté + autres personnages du serveur (3 + 5)", total == 8 and #list == 2 and list[1].name == "Aurelia", total)
    M.ProcessItem(GameTooltip, 6325)
    check("Infobulle : « Possédé | 8 : Aurelia 3 · Kael 5 »", strip(joined(GameTooltip)):find("Possédé | 8 : Aurelia 3 · Kael 5", 1, true) ~= nil, strip(joined(GameTooltip)))
    check("Personnage d'un autre serveur non compté", total == 8)
    M.containers[-1] = { { 7005, 2 } }
    M.FireEvent("BANKFRAME_OPENED")
    M.RunTimers()
    check("Banque relevée à l'ouverture", me.bank and me.bank[7005] == 2 and me.bankTime ~= nil)

    -- --- Catégories de l'HDV -------------------------------------------------------
    M.items[2589].loc = ""
    M.items[18170].loc = "INVTYPE_SHOULDER"
    M.items[18171] = { name = "Robe de givre", sell = 0, class = 4, sub = 1, bind = 0, loc = "INVTYPE_ROBE", quality = 3 }
    M.items[18172] = { name = "Capuche de givre", sell = 0, class = 4, sub = 1, bind = 0, loc = "INVTYPE_HEAD", quality = 3 }
    MK.Set("A", 18171, 5000, 1)
    MK.Set("A", 18172, 4000, 1)
    ns.Categories.Invalidate()
    local tree = ns.Categories.Tree()
    local recipe, armor
    for _, c in ipairs(tree) do if c.class == 9 then recipe = c end; if c.class == 4 then armor = c end end
    check("Catégories : « Recette » présente, noms donnés par le jeu", recipe and recipe.name == "Recette")
    local cloth
    for _, sb in ipairs(armor and armor.subs or {}) do if sb.sub == 1 then cloth = sb end end
    check("Catégories : Armure » Tissu » emplacements (Tête, Torse)", cloth and #cloth.slots == 2 and cloth.slots[1].slot == "INVTYPE_HEAD" and cloth.slots[2].slot == "INVTYPE_CHEST",
        cloth and #cloth.slots)
    check("Ordre de l'HDV : Armes avant Armure avant Artisanat", (function()
        local pos = {}
        for i, c in ipairs(tree) do pos[c.class] = i end
        return (pos[2] or 0) < (pos[4] or 99) and (pos[4] or 0) < (pos[7] or 99)
    end)())
    check("Filtre catégorie : Robe rangée avec le torse", ns.Categories.Match({ class = 4, sub = 1, slot = "INVTYPE_CHEST" }, 18171)
        and not ns.Categories.Match({ class = 4, sub = 1, slot = "INVTYPE_CHEST" }, 18172))
    local st = ns.Filters.New()
    st.text = "epee"
    check("Recherche « epee » trouve « Épée courte usée »", ns.Filters.Match(st, 25) and not ns.Filters.Match(st, 159))
    st.text, st.quality = "", 3
    check("Qualité min. Rare : objet bleu accepté, objet blanc refusé", ns.Filters.Match(st, 18171) and not ns.Filters.Match(st, 159))

    -- --- Interface : menus déroulants ------------------------------------------------
    local fr = ShadsunGoldLensAuctionPanel
    check("Panneau HDV : onglets HDV » PNJ, PNJ » HDV, HDV » HDV et Listes", #fr.tabs.buttons == 4 and fr.tabs.buttons[3].__text == "HDV » HDV" and fr.tabs.buttons[4].__text == "Listes")
    fr.tabs:Find("forward"):Click()
    local fwd = fr.fwd
    fwd.Compute()
    local catBtn = fwd.filters.cat
    catBtn:Click()
    local recipeItem = W.Menu.Find("Recette")
    check("Menu Catégorie ouvert : « Recette » proposé", recipeItem ~= nil and W.Menu.levels[1]:IsShown())
    recipeItem:Click()
    local onlyRecipes = #fwd.list.data > 0
    for _, d in ipairs(fwd.list.data) do if ns.U.ItemInstant(d.id).classID ~= 9 then onlyRecipes = false end end
    check("Filtre « Recette » appliqué à la liste PNJ » HDV", onlyRecipes and not W.Menu.levels[1]:IsShown(), #fwd.list.data)
    check("Libellé du filtre : « Catégorie : Recette »", strip(catBtn.__text or "") == "Catégorie : Recette", catBtn.__text)
    catBtn:Click()
    local armorItem = W.Menu.Find("Armure")
    armorItem.__scripts.OnEnter(armorItem)
    local clothItem = W.Menu.Find("Tissu", 2)
    check("Survol : sous-menu des sous-catégories (niveau 2)", clothItem ~= nil and W.Menu.levels[2]:IsShown())
    clothItem.__scripts.OnEnter(clothItem)
    local headItem = W.Menu.Find("Tête", 3)
    check("Survol : sous-menu des emplacements (niveau 3)", headItem ~= nil)
    headItem:Click()
    check("Sélection d'un emplacement : « Armure » Tissu » Tête »", strip(catBtn.__text or "") == "Catégorie : Armure » Tissu » Tête", catBtn.__text)
    catBtn:Click(); W.Menu.Find("Toutes les catégories"):Click()
    -- Sélecteur à choix fixes : menu, molette, clic droit
    local q = fwd.filters.quality
    q:Click()
    W.Menu.Find("Rare"):Click()
    check("Qualité choisie dans le menu : « Rare »", strip(q.__text or "") == "Qualité min. : Rare", q.__text)
    q.__scripts.OnMouseWheel(q, -1)
    check("Molette : qualité suivante (Épique)", strip(q.__text or "") == "Qualité min. : Épique", q.__text)
    q.__scripts.OnClick(q, "RightButton")
    q.__scripts.OnClick(q, "RightButton")
    check("Clic droit : qualité précédente (Inhabituelle)", strip(q.__text or "") == "Qualité min. : Inhabituelle", q.__text)
    q:Click(); W.Menu.Find("Toutes"):Click()
    -- Recherche par nom
    local sb = fwd.filters.search
    sb:SetText("goujon")
    sb.__scripts.OnTextChanged(sb, true)
    M.RunTimers()
    local allGoujon = #fwd.list.data > 0
    for _, d in ipairs(fwd.list.data) do if not U.Fold(d.name):find("goujon", 1, true) then allGoujon = false end end
    check("Recherche par nom (après 0,3 s) : seules les lignes « Goujon »", allGoujon, #fwd.list.data)
    sb.clear:Click()
    check("Effacer la recherche : toutes les lignes reviennent", #fwd.list.data > 1, #fwd.list.data)
    -- Icônes
    local row = fwd.list.rows[1]
    check("Loupe : icône (sans texte « Rechercher »)", row.search and row.search.icon ~= nil and row.search.__text == nil)
    -- Sens HDV » HDV dans l'HDV
    fr.tabs:Find("cross"):Click()
    local crossPage = fr.cross
    check("HDV » HDV : liste affichée, couteau en tête (gain le plus élevé)", crossPage:IsShown() and #crossPage.list.data > 0, #crossPage.list.data)
    local onlyAN = #crossPage.list.data > 0
    for _, d in ipairs(crossPage.list.data) do if d.pair ~= "A>N" then onlyAN = false end end
    check("HDV » HDV : sens par défaut « Faction » Neutre » (Alliance » neutre uniquement)", onlyAN, #crossPage.list.data)
    check("HDV » HDV : en-têtes « Achat alliance », « Revente neutre », « Repère Horde »",
        crossPage.header.cells[2].text.__text == "Achat alliance" and crossPage.header.cells[3].text.__text == "Revente neutre"
        and crossPage.header.cells[4].text.__text == "Repère Horde", crossPage.header.cells[2].text.__text)
    local knifeRow
    for _, d in ipairs(crossPage.list.data) do if d.id == 7005 then knifeRow = d end end
    check("HDV » HDV : repère Horde du couteau (75 pc), moins cher que la revente au neutre", knifeRow and knifeRow.ref == 75 and knifeRow.refKey == "H")
    crossPage.directions:Find("NF"):Click()
    local onlyNA = true
    for _, d in ipairs(crossPage.list.data) do if d.pair ~= "N>A" then onlyNA = false end end
    check("HDV » HDV : sens « Neutre » Faction »", onlyNA and crossPage.header.cells[2].text.__text == "Achat neutre", crossPage.header.cells[2].text.__text)
    crossPage.directions:Find("FN"):Click()
    local crow = crossPage.list.rows[1]
    crow.__scripts.OnEnter(crow)
    check("HDV » HDV : infobulle de ligne (achat, revente, commission, gain)", strip(joined(GameTooltip)):find("Commission de l'HDV de revente", 1, true) ~= nil)
    fr.tabs:Find("reverse"):Click()

    -- --- Onglet Marchés ------------------------------------------------------------
    ns.UI.Show("markets")
    local mp = ns.UI.pages.markets
    check("Onglet « Marchés » présent dans la fenêtre principale", mp and ns.UI.tabs.markets ~= nil and mp:IsShown())
    local scansTxt = ""
    for _, f in ipairs(M.allFrames) do if f.__type == "FontString" and f:GetParent() and f:GetParent():GetParent() == mp and type(f.__text) == "string" then scansTxt = scansTxt .. strip(f.__text) .. "\n" end end
    check("Marchés : HDV Alliance scanné par Aurelia, annonces comptées", scansTxt:find("Scanné par Aurelia", 1, true) ~= nil and scansTxt:find("annonces", 1, true) ~= nil, scansTxt)
    local names = {}
    for _, d in ipairs(mp.charList.data) do names[#names + 1] = d.name end
    check("Marchés : personnages du serveur (Aurelia, Kael), pas ceux des autres serveurs", table.concat(names, ",") == "Aurelia,Kael", table.concat(names, ","))
    -- Effacement d'un scan en deux clics
    local delBtn
    for _, f in ipairs(M.allFrames) do
        if f.__type == "Button" and f.__text == "Effacer" and f:GetParent() and f:GetParent().key == "H" then delBtn = f end
    end
    delBtn:Click()
    check("Effacer : premier clic = demande de confirmation", G.markets.Forever.H ~= nil and delBtn.__text == "Confirmer ?")
    delBtn:Click()
    check("Effacer : second clic = scan Horde supprimé", G.markets.Forever.H == nil)

    -- Commandes et diagnostic
    local okCmd = pcall(function() SlashCmdList.SHADSUNGOLDLENS("marches"); SlashCmdList.SHADSUNGOLDLENS("diag"); SlashCmdList.SHADSUNGOLDLENS("hdv") end)
    local rep = ns.Diag.Report()
    check("/sgl marches, /sgl diag, /sgl hdv : marchés et personnages dans le rapport", okCmd and ns.UI.current == "markets"
        and rep:find("HDV Alliance : ", 1, true) ~= nil and rep:find("Personnages du serveur : Aurelia", 1, true) ~= nil, rep:match("Marchés[^\n]*"))

    -- --- Persistance et séparation des serveurs -------------------------------------
    local ns2 = boot({}, G, ShadsunGoldLensDB)
    check("Rechargement : scans et inventaires conservés", ns2.Market.Get("A") and ns2.Market.Item(ns2.Market.Get("A"), 7005) == 50 and G.chars.Forever.Kael ~= nil)
    M.realm = "Autre"
    check("Autre serveur : aucun scan de « Forever » utilisé", ns2.Market.Get("A") == nil and ns2.Inventory.Total(6325) == 3 + 99)
    M.realm = nil
    G.markets.Forever.N.time = time() - 40 * 86400
    local ns3 = boot({}, G, ShadsunGoldLensDB)
    check("Scans de plus de 30 jours supprimés au démarrage", ns3.Market.Get("N") == nil and ns3.Market.Get("A") ~= nil)
    -- Migration : 9 lignes → 11 lignes
    local oldG = { schema = 1, settings = { tooltip = { maxLines = 9 } } }
    local ns4 = boot({}, oldG, {})
    check("Migrations v0.8.0 et v0.11.0 : infobulle portée de 9 à 12 lignes", ns4.settings.tooltip.maxLines == 12 and oldG.schema == 4 and ns4.settings.tooltip.showOtherFaction == true)

    -- --- Volume : 25 000 objets par HDV --------------------------------------------
    do
        local MK3 = ns3.Market
        local p, q = {}, {}
        for i = 1, 25000 do p[800000 + i] = 100 + (i % 977) * 37; q[800000 + i] = 1 + i % 50 end
        collectgarbage(); collectgarbage()
        local before = collectgarbage("count")
        MK3.Commit("A", p, q, time(), 300000)
        local p2 = {}
        for i = 1, 25000 do p2[800000 + i] = p[800000 + i] * 2 end
        MK3.Commit("N", p2, q, time(), 60000)
        p, p2 = nil, nil
        collectgarbage(); collectgarbage()
        local kb = collectgarbage("count") - before
        local t0 = os.clock()
        local rows = MK3.Cross()
        local ms = (os.clock() - t0) * 1000
        -- Taille approximative dans les SavedVariables (une ligne « [id] = valeur, » par objet)
        local bytes = 0
        for id, v in pairs(MK3.Get("A").d) do bytes = bytes + #string.format("[%d] = %.14g,\n", id, v) end
        rprint(string.format("  (mesure) 2 HDV × 25 000 objets : %.0f Ko en mémoire Lua · HDV » HDV calculé en %.0f ms · ≈ %.0f Ko par HDV dans les SavedVariables",
            kb, ms, bytes / 1024))
        check(string.format("Volume : 2 × 25 000 objets, HDV » HDV en moins de 500 ms (%.0f ms)", ms), #rows == 25000 and ms < 500, #rows)
        check(string.format("Volume : mémoire des deux scans sous 3 Mo (%.0f Ko)", kb), kb < 3072, kb)
    end

    -- --- Police du jeu : aucun caractère manquant dans les nouveaux textes -------------
    local badGlyph
    for _, f in ipairs(M.allFrames) do
        if type(f.__text) == "string" then
            for seq in f.__text:gmatch("[\226-\239][\128-\191][\128-\191]") do
                if seq ~= "\226\128\148" and seq ~= "\226\128\166" then badGlyph = f.__text end
            end
        end
    end
    check("Interface v0.8.0 : aucun caractère absent de la police du jeu", not badGlyph, badGlyph)
    check("Aucune erreur interne (bloc v0.8.0)", ns.Diag.counters.errors == 0 and ns2.Diag.counters.errors == 0 and ns3.Diag.counters.errors == 0,
        (ns.Diag.errors[1] and ns.Diag.errors[1].err) or (ns2.Diag.errors[1] and ns2.Diag.errors[1].err))
    M.owned, M.containers = nil, nil
    M.items[18171], M.items[18172] = nil, nil
    M.FireEvent("AUCTION_HOUSE_CLOSED")
end

-- =============================================================================
-- 7. v0.9.0 : prix de l'API Blizzard (module ShadsunGoldLens_Prix)
--    Le module est produit par test_sgl_prix_api.py (faux serveur local).
-- =============================================================================
do
    local fx = "fixtures/ShadsunGoldLens_Prix/Prix.lua"
    local f = io.open(fx, "r")
    if not f then
        check("Module de prix généré par test_sgl_prix_api.py présent", false, "lancez d'abord python3 test_sgl_prix_api.py")
    else
        f:close()
        local LAST = 1763600000
        local savedTime = _G.time
        _G.time = function() return LAST + 3600 end
        M.time = LAST + 3600
        M.region = "EU"
        _G.GetCurrentRegionName = function() return M.region end
        _G.ShadsunGoldLensExternal = nil
        dofile(fx)
        check("Prix.lua chargé dans le client simulé (globale ShadsunGoldLensExternal)", type(ShadsunGoldLensExternal) == "table")
        local G = {}
        local ns = boot({}, G, {})
        _G.time = function() return LAST + 3600 end
        M.time = LAST + 3600
        local MK, U = ns.Market, ns.U
        check("Prix API acceptés (région EU = client EU)", MK.extStatus == "ok" and MK.External("H") and MK.External("H").house == 114, MK.extStatus)
        -- Infobulle : prix Horde depuis l'API
        M.ProcessItem(GameTooltip, 7005)
        local tx = strip(joined(GameTooltip))
        check("Infobulle : « HDV Horde | 75 pc (1 en vente · API, il y a 1 h) »", tx:find("HDV Horde | 75\194\160pc (1 en vente · API, il y a 1 h)", 1, true) ~= nil, tx)
        -- Donnée la plus récente : votre scan ou l'API
        G.markets.Forever = { A = { time = M.time - 60, total = 1, char = "Aurelia", d = { [50001] = MK.Pack(90, 2) } } }
        check("Votre scan plus récent que l'API : scan utilisé", MK.Price(50001, "A") == 90 and MK.Snap("A").source == nil)
        G.markets.Forever.A.time = LAST - 7200
        check("API plus récente que votre scan : API utilisée", MK.Price(50001, "A") == 100 and MK.Snap("A").source == "api")
        G.markets.Forever = nil
        -- HDV » HDV avec les données de l'API
        local rows = MK.Cross("A>N")
        local r1
        for _, r in ipairs(rows) do if r.id == 50002 then r1 = r end end
        -- achat 200 (A), revente 260 (N), commission ceil(39) = 39, gain 21 ; repère Horde 300
        check("HDV » HDV depuis l'API : achat 2 pa, revente 2 pa 60 pc, gain 21 pc, repère Horde 3 pa", r1 and r1.buyUnit == 200 and r1.sellUnit == 260
            and r1.gain == 21 and r1.ref == 300 and r1.buySrc == "api", r1 and r1.gain)
        ns.UI.Show("opp")
        local opp = ns.UI.pages.opp
        opp.SetDirection("cross")
        check("Onglet Opportunités, HDV » HDV : lignes issues de l'API", #opp.cross.list.data > 0, #opp.cross.list.data)
        -- Onglet Marchés : ligne API de chaque HDV
        ns.UI.Show("markets")
        local mp = ns.UI.pages.markets
        local txt = ""
        for _, fr in ipairs(M.allFrames) do
            if fr.__type == "FontString" and fr:GetParent() and (fr:GetParent() == mp or fr:GetParent():GetParent() == mp) and type(fr.__text) == "string" then txt = txt .. strip(fr.__text) .. "\n" end
        end
        check("Onglet Marchés : « API Blizzard : 32 objets » et état du module", txt:find("API Blizzard : 32 objets", 1, true) ~= nil
            and txt:find("Prix API Blizzard : EU PvP", 1, true) ~= nil, txt)
        -- Source Forever AH (mode simple de l'application) : nom et mention du site
        ShadsunGoldLensExternal.source = "Forever AH"
        MK.LoadExternal()
        check("Source Forever AH : nom de la source repris", MK.ExternalName() == "Forever AH" and MK.External("H").char == "Forever AH")
        M.ProcessItem(GameTooltip, 7005)
        local txf = strip(joined(GameTooltip))
        check("Infobulle : « (1 en vente · Forever AH, il y a 1 h) »", txf:find("(1 en vente · Forever AH, il y a 1 h)", 1, true) ~= nil, txf)
        mp.OnActivate()
        local txt2 = ""
        for _, fr in ipairs(M.allFrames) do
            if fr.__type == "FontString" and fr:GetParent() and (fr:GetParent() == mp or fr:GetParent():GetParent() == mp) and type(fr.__text) == "string" then txt2 = txt2 .. strip(fr.__text) .. "\n" end
        end
        check("Onglet Marchés : « Forever AH : 32 objets » et mention « Prix : Forever AH (forever-ah.com) »",
            txt2:find("Forever AH : 32 objets", 1, true) ~= nil and txt2:find("Prix : Forever AH (forever-ah.com), données de l'API Battle.net", 1, true) ~= nil, txt2)
        ShadsunGoldLensExternal.source = nil
        MK.LoadExternal()
        check("Module sans source (ancien outil) : « API Blizzard » par défaut", MK.ExternalName() == "API Blizzard")
        -- Région différente : prix ignorés
        M.region = "US"
        MK.LoadExternal()
        check("Client US, prix EU : prix API ignorés avec explication", MK.External("H") == nil and MK.extStatus:find("région EU", 1, true) ~= nil, MK.extStatus)
        M.region = "EU"
        ShadsunGoldLensExternal.version = 2
        MK.LoadExternal()
        check("Format inconnu : prix API ignorés", MK.External("A") == nil and MK.extStatus == "format inconnu")
        ShadsunGoldLensExternal = nil
        MK.LoadExternal()
        check("Module absent : aucune erreur, état « absent »", MK.extStatus == "absent" and MK.Snap("H") == nil)
        check("Aucune erreur interne (bloc v0.9.0)", ns.Diag.counters.errors == 0, ns.Diag.errors[1] and ns.Diag.errors[1].err)
        _G.GetCurrentRegionName = nil
        _G.time = savedTime
    end
end

-- =============================================================================
-- 8. v0.10.0 : listes d'achats, avis HDV » HDV, rechargement
-- =============================================================================
do
    M.alt, M.reloads = false, 0
    _G.IsAltKeyDown = function() return M.alt end
    _G.IsShiftKeyDown = function() return false end
    _G.IsControlKeyDown = function() return false end
    _G.HandleModifiedItemClick = function() return false end
    _G.ReloadUI = function() M.reloads = M.reloads + 1 end
    local G = {}
    local ns = boot({}, G, {})
    local LS, U, W, MK = ns.Lists, ns.U, ns.W, ns.Market
    local function strip2(t) return strip(t or "") end

    -- --- Listes : données ------------------------------------------------------
    check("Listes : une liste « Ma liste » créée au départ, active", #LS.All() == 1 and LS.Active().name == "Ma liste" and type(G.lists) == "table")
    local ok1 = LS.Add(6325, 5)
    local ok2, msg2 = LS.Add(6325, 1)
    check("Ajout répété : quantité augmentée (5 + 1 = 6), message avec la quantité", ok1 and ok2 and LS.Entry(LS.ActiveId(), 6325).qty == 6 and msg2:find("6 dans « Ma liste »", 1, true) ~= nil, msg2)
    local lid2 = LS.Create("Couture")
    check("Nouvelle liste « Couture » créée et active", LS.ActiveId() == lid2 and LS.Active().name == "Couture" and #LS.All() == 2)
    LS.Add(2589, 20)
    LS.SetMax(lid2, 2589, 120)
    LS.SetQty(lid2, 2589, 40)
    local e = LS.Entry(lid2, 2589)
    check("Quantité et prix maximum modifiés", e and e.qty == 40 and e.max == 120)
    check("Renommer", LS.Rename(lid2, "Couture et tissus") and LS.Active().name == "Couture et tissus")
    local dup = LS.Duplicate(lid2)
    check("Dupliquer : copie avec les articles", LS.Get(dup).name == "Couture et tissus (copie)" and #LS.Get(dup).items == 1)
    LS.Delete(dup)
    check("Supprimer", LS.Get(dup) == nil and #LS.All() == 2)
    local first = LS.All()[1].id
    LS.Delete(first); LS.Delete(lid2)
    check("Supprimer la dernière liste : une liste vide est recréée", #LS.All() == 1 and LS.Active() ~= nil and #LS.Active().items == 0)
    -- Reconstruction : deux listes pour la suite
    local main = LS.ActiveId()
    LS.Rename(main, "Ma liste")
    LS.Add(6325, 5)
    LS.Add(2589, 20)
    M.owned = { [6325] = { 3, 0 }, [2589] = { 25, 0 } }
    local owned, want, done = LS.Progress(LS.Entry(main, 6325))
    check("Progression : 3 / 5 (personnages du serveur)", owned == 3 and want == 5 and not done)
    check("Progression : 25 / 20 terminé", select(3, LS.Progress(LS.Entry(main, 2589))) == true)
    M.ProcessItem(GameTooltip, 6325)
    check("Infobulle : « Liste | Ma liste 3 / 5 »", strip(joined(GameTooltip)):find("Liste | Ma liste 3 / 5", 1, true) ~= nil, strip(joined(GameTooltip)))

    -- --- Alt+clic --------------------------------------------------------------
    MerchantFrame:Hide()
    M.alt = true
    HandleModifiedItemClick("|cffffffff|Hitem:159::::::::1:::::::|h[Eau fraîche]|h|r")
    check("Alt+clic sur un objet : ajouté à la liste active", LS.Entry(main, 159) ~= nil)
    LS.Remove(main, 159)
    MerchantFrame:Show()
    HandleModifiedItemClick("|cffffffff|Hitem:159::::::::1:::::::|h[Eau fraîche]|h|r")
    check("Alt+clic dans la fenêtre du marchand : rien n'est ajouté", LS.Entry(main, 159) == nil)
    MerchantFrame:Hide()
    M.alt = false
    HandleModifiedItemClick("|cffffffff|Hitem:159::::::::1:::::::|h[Eau fraîche]|h|r")
    check("Clic modifié sans Alt : rien n'est ajouté", LS.Entry(main, 159) == nil)

    -- --- Icône + dans les tableaux ---------------------------------------------
    ns.UI.Show("opp")
    local opp = ns.UI.pages.opp
    opp.forward.Compute()
    local r1 = opp.forward.list.rows[1]
    check("Onglet Opportunités : icône + sur chaque ligne", r1 and r1.add ~= nil and r1.add.icon ~= nil)
    local addID = r1.data.id
    LS.Remove(main, addID)
    r1.add:Click()
    check("Icône + : objet ajouté à la liste active", LS.Entry(main, addID) ~= nil)
    if not LS.Entry(main, 6325) then LS.Add(6325, 5) end
    LS.SetQty(main, 6325, 5)

    -- --- Onglet Listes ------------------------------------------------------------
    ns.UI.Show("lists")
    local lp = ns.UI.pages.lists
    check("Onglet « Listes » présent", lp:IsShown() and ns.UI.tabs.lists ~= nil)
    G.markets.Forever = { A = { time = time(), total = 2, char = "Aurelia", d = { [6325] = MK.Pack(150, 2), [2589] = MK.Pack(110, 50) } },
                          N = { time = time(), total = 2, char = "Kael", d = { [6325] = MK.Pack(120, 1), [2589] = MK.Pack(90, 9) } } }
    lp.Refresh()
    local rowRecipe
    for _, r in ipairs(lp.itemsList.rows) do if r.data and r.data.id == 6325 then rowRecipe = r end end
    check("Liste : colonne PNJ (40 pc), le moins cher en vert ; prix par HDV (Alliance 1 pa 50, neutre 1 pa 20)",
        rowRecipe and strip2(rowRecipe.cells[6].__text) == "40\194\160pc" and rowRecipe.cells[6].__text:find("7beb96", 1, true) ~= nil
        and strip2(rowRecipe.cells[7].__text) == "1\194\160pa 50\194\160pc" and strip2(rowRecipe.cells[9].__text) == "1\194\160pa 20\194\160pc"
        and not rowRecipe.cells[9].__text:find("7beb96", 1, true), rowRecipe and rowRecipe.cells[6].__text)
    check("Liste : progression « 3 / 5 » affichée", rowRecipe and strip2(rowRecipe.cells[3].__text) == "3 / 5", rowRecipe and rowRecipe.cells[3].__text)
    check("Fenêtre principale : icônes Aller et Copier vers le marchand (pas de loupe)", rowRecipe and rowRecipe.search == nil
        and rowRecipe.go and rowRecipe.go:GetAlpha() == 1 and rowRecipe.copy:GetAlpha() == 1)
    M.tomtom = nil
    rowRecipe.go:Click()
    check("Icône Aller : point TomTom vers le marchand", M.tomtom ~= nil and M.tomtom.m ~= nil)
    rowRecipe.copy:Click()
    local cl = _G.ShadsunGoldLensCopyLine
    check("Icône Copier : commande /tway présélectionnée", cl and cl:IsShown() and (cl.edit and (cl.edit:GetText() or ""):find("^/tway #") ~= nil), cl and cl.edit and cl.edit:GetText())
    if cl then cl:Hide() end
    -- Prix maximum : au-dessus = grisé, pas de vert
    LS.SetMax(main, 6325, 100)
    lp.Refresh()
    check("Prix max 1 pa : HDV grisés, seul le PNJ (40 pc) reste en vert", not (rowRecipe.cells[9].__text or ""):find("7beb96", 1, true)
        and not (rowRecipe.cells[7].__text or ""):find("7beb96", 1, true) and (rowRecipe.cells[6].__text or ""):find("7beb96", 1, true) ~= nil)
    -- Édition par clic sur la ligne
    rowRecipe:Click()
    check("Clic sur un article : champs Quantité et Prix max affichés", lp.qtyEdit:IsShown() and lp.qtyEdit:GetText() == "5" and lp.maxEdit:GetText() == "0,01", tostring(lp.qtyEdit:IsShown()) .. "|" .. tostring(lp.qtyEdit:GetText()))
    lp.qtyEdit:SetText("8"); lp.qtyEdit.__scripts.OnEnterPressed(lp.qtyEdit)
    check("Quantité modifiée depuis l'onglet", LS.Entry(main, 6325).qty == 8)
    -- Ajout par le champ
    lp.addEdit:SetText("7005"); lp.addEdit.__scripts.OnEnterPressed(lp.addEdit)
    check("Champ « Ajouter » : par ID", LS.Entry(main, 7005) ~= nil)
    -- HDV ouvert : loupe et recherche groupée
    local terms
    Auctionator.API.v1.MultiSearch = function(caller, t) terms = t; M.atrSearch = t[1] end
    M.FireEvent("AUCTION_HOUSE_SHOW")
    M.RunTimers()
    lp.Refresh()
    check("HDV ouvert : « Rechercher toute la liste » actif", lp.searchAllButton:IsEnabled())
    ShadsunGoldLensAuctionPanel.tabs:Find("lists"):Click()
    local ahRow
    for _, r in ipairs(ShadsunGoldLensAuctionPanel.lists.itemsList.rows) do if r.data and r.data.id == 6325 then ahRow = r end end
    check("Panneau de l'HDV : loupe active (pas d'icône Aller)", ahRow and ahRow.search:GetAlpha() == 1 and ahRow.go == nil)
    ahRow.search:Click()
    check("Loupe d'un article : recherche Auctionator", M.atrSearch == "Recette : Goujon brillant", M.atrSearch)
    lp.searchAllButton:Click()
    local names = terms and table.concat(terms, ",") or ""
    check("Rechercher toute la liste : articles non obtenus seulement (pas l'étoffe déjà obtenue)", terms and #terms >= 2
        and names:find("Recette : Goujon brillant", 1, true) ~= nil and not names:find("Étoffe de lin", 1, true), names)
    M.FireEvent("AUCTION_HOUSE_CLOSED")
    -- Retrait par l'icône
    rowRecipe = nil
    for _, r in ipairs(lp.itemsList.rows) do if r.data and r.data.id == 7005 then rowRecipe = r end end
    rowRecipe.remove:Click()
    check("Icône de retrait : article retiré", LS.Entry(main, 7005) == nil)
    -- Persistance (commun au compte)
    local ns2 = boot({}, G, {})
    check("Rechargement : listes conservées (communes au compte)", ns2.Lists.Active().name == "Ma liste" and ns2.Lists.Entry(ns2.Lists.ActiveId(), 6325).qty == 8)
    ns, LS, W, MK = ns2, ns2.Lists, ns2.W, ns2.Market
    main = LS.ActiveId()

    -- --- Bordure chez le marchand -----------------------------------------------
    M.merchant = {
        { id = 2589, info = { price = 10, stackCount = 1, numAvailable = -1, isPurchasable = true } },
        { id = 5441, info = { price = 2000, stackCount = 1, numAvailable = -1, isPurchasable = true } },
    }
    rawset(MerchantFrame, "selectedTab", 1); rawset(MerchantFrame, "page", 1)
    ns.MerchantOverlay.Update()
    local function border(i)
        local btn = _G["MerchantItem" .. i .. "ItemButton"]
        for _, f in ipairs(M.allFrames) do
            if f:GetParent() == btn and f.__backdrop and f:IsShown() then return f end
        end
    end
    local b1 = border(1)
    check("Marchand : article d'une liste entouré en bleu", b1 and b1.__border and b1.__border[3] == 1 and b1.__border[1] == 0.35)
    check("Marchand : article hors liste et non rentable non entouré", not border(2))
    ns.settings.ah.listBorder = false
    ns.MerchantOverlay.Update()
    check("Option désactivée : plus de bordure bleue", not border(1) or border(1).__border[1] ~= 0.35)
    ns.settings.ah.listBorder = true
    M.merchant = nil

    -- --- Avis HDV » HDV ----------------------------------------------------------
    local XA = ns.CrossUI.Assess
    local a1, g1 = XA({ ref = 300, sellUnit = 260, buyUnit = 200, sellQty = 5 }, "FN", 3, 0.15)
    local a2, g2 = XA({ ref = 75, sellUnit = 200, buyUnit = 50, sellQty = 5 }, "FN", 3, 0.15)
    local a3 = XA({ sellUnit = 200, buyUnit = 50, sellQty = 5 }, "FN", 3, 0.15)
    local a4 = XA({ ref = 300, sellUnit = 260, buyUnit = 200, sellQty = 1 }, "FN", 3, 0.15)
    local a5 = XA({ sellUnit = 600, buyUnit = 200, sellQty = 4 }, "NF", 3, 0.05)
    local a6 = XA({ sellUnit = 600, buyUnit = 200, sellQty = 2 }, "NF", 3, 0.05)
    check("Avis Faction » Neutre : autre faction plus chère, 5 en vente = Favorable (gain 21 pc)", a1 == "fav" and g1 == 21, a1 .. " " .. g1)
    check("Avis Faction » Neutre : autre faction moins chère = Défavorable, gain réaliste au repère (75 - 12 - 50 = 13 pc)", a2 == "def" and g2 == 13, a2 .. " " .. g2)
    check("Avis Faction » Neutre : sans repère = À vérifier ; 1 seul en vente = À vérifier", a3 == "chk" and a4 == "chk")
    check("Avis Neutre » Faction : 4 en vente = Favorable ; 2 en vente = À vérifier", a5 == "fav" and a6 == "chk")
    -- Interface : colonne et filtre
    G.markets.Forever = {
        A = { time = time(), total = 3, char = "Aurelia", d = { [7005] = MK.Pack(50, 5), [2589] = MK.Pack(10, 40), [159] = MK.Pack(100, 2) } },
        N = { time = time(), total = 3, char = "Kael", d = { [7005] = MK.Pack(200, 5), [2589] = MK.Pack(40, 1), [159] = MK.Pack(300, 6) } },
        H = { time = time(), total = 3, char = "Grok", d = { [7005] = MK.Pack(75, 1), [159] = MK.Pack(400, 3) } },
    }
    ns.UI.Show("opp")
    local opp2 = ns.UI.pages.opp
    opp2.SetDirection("cross")
    local cp = opp2.cross
    cp.Compute()
    local byId = {}
    for _, d in ipairs(cp.list.data) do byId[d.id] = d end
    check("HDV » HDV : avis calculés (eau Favorable, couteau Défavorable, étoffe À vérifier)",
        byId[159] and byId[159].avis == "fav" and byId[7005] and byId[7005].avis == "def" and byId[2589] and byId[2589].avis == "chk",
        (byId[159] and byId[159].avis or "?") .. (byId[7005] and byId[7005].avis or "?") .. (byId[2589] and byId[2589].avis or "?"))
    local avisCell
    for _, r in ipairs(cp.list.rows) do if r.data and r.data.id == 159 then avisCell = r.cells[9] end end
    check("Colonne Avis : « Favorable » en vert", avisCell and strip(avisCell.__text) == "Favorable" and avisCell.__text:find("|c", 1, true) ~= nil)
    cp.avisSelector:Click()
    W.Menu.Find("Favorable"):Click()
    local onlyFav = #cp.list.data > 0
    for _, d in ipairs(cp.list.data) do if d.avis ~= "fav" then onlyFav = false end end
    check("Filtre Avis « Favorable »", onlyFav and #cp.list.data == 1, #cp.list.data)
    cp.avisSelector:Click()
    W.Menu.Find("Tous"):Click()
    cp.minQtyEdit:SetText("7"); cp.minQtyEdit.__scripts.OnEnterPressed(cp.minQtyEdit)
    byId = {}
    for _, d in ipairs(cp.list.data) do byId[d.id] = d end
    check("Qté min. (avis) portée à 7 : l'eau (6 en vente au neutre) passe « À vérifier »", ns.settings.economy.avisMinQty == 7 and byId[159].avis == "chk")
    cp.minQtyEdit:SetText("3"); cp.minQtyEdit.__scripts.OnEnterPressed(cp.minQtyEdit)

    -- --- Ordre des onglets et onglet Listes du panneau de l'HDV --------------------
    local order = {}
    for _, b in ipairs(ns.UI.tabBar.buttons) do order[#order + 1] = b.__text end
    check("Onglets : Objet, Listes, Opportunités, Marchés, Paramètres, Base & diagnostic",
        table.concat(order, ",") == "Objet,Listes,Opportunités,Marchés,Paramètres,Base & diagnostic", table.concat(order, ","))
    check("Montant compact : 490 po 99 pa 12 pc -> 490 po ; 15 po 90 pa 12 pc -> 15 po 90 pa ; 99 pc inchangé",
        strip(U.MoneyShort(4909912)) == "490\194\160po" and strip(U.MoneyShort(159012)) == "15\194\160po 90\194\160pa" and strip(U.MoneyShort(99)) == "99\194\160pc",
        strip(U.MoneyShort(4909912)))
    check("Pourcentage compact : 2 528,6 % -> >999 % ; 177,5 % -> 178 %", strip(U.PercentShort(2528.6)) == ">999\194\160%" and strip(U.PercentShort(177.5)) == "178\194\160%")
    local lid3 = LS.Create("Pour Kael")
    LS.Add(159, 4)
    LS.SetActive(main)
    M.FireEvent("AUCTION_HOUSE_SHOW"); M.RunTimers()
    local fr3 = ShadsunGoldLensAuctionPanel
    fr3.tabs:Find("lists"):Click()
    local shop = fr3.lists
    check("Panneau HDV, onglet Listes : articles de la liste active affichés", shop:IsShown() and #shop.itemsList.data >= 1, #shop.itemsList.data)
    local srow = shop.itemsList.rows[1]
    check("Onglet Listes de l'HDV : loupe active par article", srow.search:GetAlpha() == 1)
    M.atrSearch = nil
    srow.search:Click()
    check("Loupe : recherche de l'article", M.atrSearch ~= nil)
    check("« Rechercher toute la liste » actif à l'HDV", shop.searchAllButton:IsEnabled())
    shop.selector:Click()
    W.Menu.Find("Pour Kael  (0/1)"):Click()
    check("Sélecteur de liste : « Pour Kael » affichée et active", LS.ActiveId() == lid3 and #shop.itemsList.data == 1 and shop.itemsList.data[1].id == 159)
    LS.SetActive(main)
    M.FireEvent("AUCTION_HOUSE_CLOSED")

    -- --- Rechargement de l'interface ----------------------------------------------
    ns.UI.Show("markets")
    ns.UI.pages.markets.reloadButton:Click()
    M.FireEvent("AUCTION_HOUSE_SHOW"); M.RunTimers()
    ShadsunGoldLensAuctionPanel.scan.reloadButton:Click()
    check("Boutons Recharger (onglet Marchés, barre de scan) : ReloadUI appelé", M.reloads == 2, M.reloads)
    M.FireEvent("AUCTION_HOUSE_CLOSED")
    local okCmd = pcall(SlashCmdList.SHADSUNGOLDLENS, "listes")
    check("/sgl listes ouvre l'onglet Listes", okCmd and ns.UI.current == "lists")

    local badGlyph
    for _, f in ipairs(M.allFrames) do
        if type(f.__text) == "string" then
            for seq in f.__text:gmatch("[\226-\239][\128-\191][\128-\191]") do
                if seq ~= "\226\128\148" and seq ~= "\226\128\166" then badGlyph = f.__text end
            end
        end
    end
    check("Interface v0.10.0 : aucun caractère absent de la police du jeu", not badGlyph, badGlyph)
    check("Aucune erreur interne (bloc v0.10.0)", ns.Diag.counters.errors == 0, ns.Diag.errors[1] and ns.Diag.errors[1].err)
    M.owned = nil
    _G.HandleModifiedItemClick = nil
end

-- =============================================================================
-- 9. v0.11.0 : boutons + et -, quantités possédées, enchères en cours
-- =============================================================================
do
    M.shift = false
    _G.IsAltKeyDown = function() return false end
    _G.IsShiftKeyDown = function() return M.shift end
    _G.IsControlKeyDown = function() return false end
    _G.HandleModifiedItemClick = function() return false end
    _G.ERR_AUCTION_SOLD_S = "Un acheteur a été trouvé pour votre vente aux enchères : %s."
    _G.ERR_AUCTION_EXPIRED_S = "Votre vente aux enchères de %s a expiré."
    local G = {}
    local ns = boot({}, G, {})
    local LS, U, W, AU = ns.Lists, ns.U, ns.W, ns.Auctions
    Enum.ItemCommodityStatus = { Unknown = 0, Item = 1, Commodity = 2 }
    Enum.AuctionStatus = { Active = 0, Sold = 1 }
    M.owned = { [6325] = { 2, 5 } }
    local main = LS.ActiveId()

    -- --- Données : + et - -------------------------------------------------------------
    local ok, msg = LS.Step(6325, 1)
    check("Bouton + (données) : objet ajouté avec 1 exemplaire", ok and LS.ActiveQty(6325) == 1)
    check("Message : quantité dans la liste et possédé (« 1 dans « Ma liste » — sacs 2 · banque 5 »)",
        msg:find("1 dans « Ma liste » — sacs 2 · banque 5", 1, true) ~= nil, msg)
    LS.Step(6325, 1); LS.Step(6325, 5)
    check("+ répété puis +5 : 1 + 1 + 5 = 7", LS.ActiveQty(6325) == 7)
    LS.Step(6325, -5)
    check("-5 : 7 - 5 = 2", LS.ActiveQty(6325) == 2)
    local _, msgOut = LS.Step(6325, -5)
    check("Sous 1 : l'objet quitte la liste, message « retiré de »", LS.Entry(main, 6325) == nil and msgOut:find("retiré de « Ma liste »", 1, true) ~= nil, msgOut)
    local okNo, msgNo = LS.Step(6325, -1)
    check("- sur un objet absent : refusé avec message", not okNo and msgNo:find("n'est pas dans", 1, true) ~= nil, msgNo)

    -- --- Boutons des tableaux ---------------------------------------------------------
    local holder = M.CreateFrame("Frame", nil, UIParent)
    holder.data = { id = 159 }
    local plus = W.AddButton(holder, function(self) return self:GetParent().data.id end)
    check("Bouton - placé à gauche du +", plus.minus ~= nil and plus.minus:GetParent() == holder)
    plus:Refresh()
    check("Objet absent : bouton - grisé, pas de badge", plus.minus:GetAlpha() < 1 and (plus.badge:GetText() or "") == "")
    M.printed = {}
    plus:Click()
    check("Clic sur + : 1 exemplaire, badge « 1 », - actif", LS.ActiveQty(159) == 1 and plus.badge:GetText() == "1" and plus.minus:GetAlpha() == 1)
    plus:Click()
    check("Deuxième clic sur + : 2 exemplaires (plus de message « déjà dans la liste »)", LS.ActiveQty(159) == 2
        and not table.concat(M.printed, "\n"):find("déjà dans", 1, true), table.concat(M.printed, " / "))
    M.shift = true
    plus:Click()
    check("Maj+clic sur + : +5 (7)", LS.ActiveQty(159) == 7 and plus.badge:GetText() == "7")
    plus.minus:Click()
    M.shift = false
    check("Maj+clic sur - : -5 (2)", LS.ActiveQty(159) == 2)
    plus.minus:Click(); plus.minus:Click()
    check("- jusqu'à 0 : objet retiré, - grisé", LS.Entry(main, 159) == nil and plus.minus:GetAlpha() < 1)
    plus.__scripts.OnEnter(plus)
    check("Survol du + : liste active, quantité, sacs", GameTooltip:IsShown() and strip(joined(GameTooltip)):find("Dans la liste : 0", 1, true) ~= nil, strip(joined(GameTooltip)))

    -- --- Enchères en cours --------------------------------------------------------------
    M.ownedAuctions = {
        { auctionID = 1, itemKey = { itemID = 6325 }, quantity = 1, status = 0 },
        { auctionID = 2, itemKey = { itemID = 6325 }, quantity = 1, status = 0 },
        { auctionID = 3, itemKey = { itemID = 2589 }, quantity = 20, status = 0 },
        { auctionID = 4, itemKey = { itemID = 7005 }, quantity = 1, status = 1 },
    }
    M.queries = 0
    C_AuctionHouse.QueryOwnedAuctions = function() M.queries = M.queries + 1 end
    C_AuctionHouse.GetOwnedAuctions = function() return M.ownedAuctions end
    C_AuctionHouse.GetItemCommodityStatus = function(id) return id == 2589 and 2 or 1 end
    M.FireEvent("AUCTION_HOUSE_SHOW"); M.RunTimers()
    check("Ouverture de l'HDV : vos enchères demandées au jeu", M.queries == 1)
    M.FireEvent("OWNED_AUCTIONS_UPDATED")
    check("Relevé : 2 recettes et 20 étoffes en vente ; enchère vendue ignorée", AU.Total(6325) == 2 and AU.Total(2589) == 20 and AU.Total(7005) == 0)
    M.ProcessItem(GameTooltip, 6325)
    check("Infobulle : « En vente | 2 » sous « Possédé »", strip(joined(GameTooltip)):find("Possédé | 2 (sacs) · 5 (banque)\nEn vente | 2", 1, true) ~= nil, strip(joined(GameTooltip)))
    local _, msgSale = LS.Step(6325, 1)
    check("Message de liste : « en vente 2 »", msgSale:find("sacs 2 · banque 5 · en vente 2", 1, true) ~= nil, msgSale)
    M.FireEvent("AUCTION_HOUSE_AUCTION_CREATED"); M.RunTimers()
    check("Après une mise en vente : nouveau relevé demandé", M.queries == 2)
    M.FireEvent("AUCTION_HOUSE_CLOSED")
    -- Hors HDV : vendu, expiré
    M.FireEvent("CHAT_MSG_SYSTEM", "Un acheteur a été trouvé pour votre vente aux enchères : Recette : Goujon brillant.")
    check("Message « acheteur trouvé » hors HDV : une recette de moins (1)", AU.Total(6325) == 1)
    M.FireEvent("CHAT_MSG_SYSTEM", "Votre vente aux enchères de Recette : Goujon brillant a expiré.")
    check("Message « a expiré » : plus de recette en vente", AU.Total(6325) == 0)
    M.FireEvent("CHAT_MSG_SYSTEM", "Un acheteur a été trouvé pour votre vente aux enchères : Étoffe de lin.")
    check("Marchandise vendue en partie : 19 au plus (« ~19 »)", AU.Total(2589) == 19 and AU.Short(2589) == "~19")
    M.ProcessItem(GameTooltip, 2589)
    check("Infobulle : « (au plus) » et âge du relevé hors HDV", strip(joined(GameTooltip)):find("En vente | 19 (au plus) · ", 1, true) ~= nil, strip(joined(GameTooltip)))
    M.FireEvent("CHAT_MSG_SYSTEM", "Bienvenue dans World of Warcraft !")
    check("Autre message système : rien ne change", AU.Total(2589) == 19)
    -- Autre personnage : relevé pris en compte
    G.chars.Forever.Kael = G.chars.Forever.Kael or { bags = {} }
    G.chars.Forever.Kael.ah = { time = time() - 7200, list = { { id = 2589, q = 6 } } }
    check("Enchères de tous les personnages du serveur additionnées (19 + 6)", AU.Total(2589) == 25)
    M.ProcessItem(GameTooltip, 2589)
    check("Infobulle : détail par personnage", strip(joined(GameTooltip)):find("En vente | 25 : ", 1, true) ~= nil and strip(joined(GameTooltip)):find("Kael 6", 1, true) ~= nil, strip(joined(GameTooltip)))
    ns.settings.tooltip.showAuctions = false
    M.ProcessItem(GameTooltip, 2589)
    check("Option désactivée : plus de ligne « En vente »", not strip(joined(GameTooltip)):find("En vente", 1, true))
    ns.settings.tooltip.showAuctions = true

    -- --- Tableaux : colonnes « Sacs » et « Vente »
    local dS = ns.Inventory.Stock({ id = 2589 })
    M.owned = { [2589] = { 7, 40 } }
    local dB = ns.Inventory.Stock({ id = 2589 })
    check("Tableaux : « Sacs » = sacs du personnage (7, sans la banque), « Vente » = ~25",
        dB.bags == 7 and dB.sale == 25 and strip(W.SaleText(dB)) == "~25" and strip(W.BagsText(dB)) == "7", dB.bags .. " " .. tostring(dB.saleText))
    check("Tableaux : rien en vente = « - », sacs vides = « 0 »", strip(W.SaleText({})) == "-" and strip(W.BagsText({})) == "0" and dS.bags == 0)
    M.owned = { [6325] = { 2, 5 } }
    local labels = {}
    for _, f in ipairs(M.allFrames) do if type(f.__text) == "string" then labels[f.__text] = (labels[f.__text] or 0) + 1 end end
    check("En-têtes « Sacs » et « Vente » dans les 5 tableaux (fenêtre et panneau de l'HDV), plus de « Poss. »",
        (labels["Sacs"] or 0) >= 1 and (labels["Vente"] or 0) >= 1 and not labels["Poss."], (labels["Sacs"] or 0) .. "/" .. (labels["Vente"] or 0))

    -- --- Onglet Listes : colonne « Vente » ------------------------------------------------
    LS.Add(2589, 30)
    ns.UI.Show("lists")
    local lp = ns.UI.pages.lists
    lp.Refresh()
    local rowCloth
    for _, r in ipairs(lp.itemsList.rows) do if r.data and r.data.id == 2589 then rowCloth = r end end
    check("Onglet Listes : colonne « Vente » = ~25", rowCloth and strip(rowCloth.cells[4].__text or "") == "~25", rowCloth and rowCloth.cells[4].__text)
    check("Onglet Listes : la progression ne compte pas les objets en vente", rowCloth and strip(rowCloth.cells[3].__text or "") == "0 / 30", rowCloth and rowCloth.cells[3].__text)
    -- Rechargement : relevé conservé
    local ns2 = boot({}, G, {})
    check("Rechargement : enchères conservées", ns2.Auctions.Total(2589) == 25)

    local badGlyph
    for _, f in ipairs(M.allFrames) do
        if type(f.__text) == "string" then
            for seq in f.__text:gmatch("[\226-\239][\128-\191][\128-\191]") do
                if seq ~= "\226\128\148" and seq ~= "\226\128\166" then badGlyph = f.__text end
            end
        end
    end
    for _, t in ipairs(M.printed) do
        for seq in t:gmatch("[\226-\239][\128-\191][\128-\191]") do
            if seq ~= "\226\128\148" and seq ~= "\226\128\166" then badGlyph = t end
        end
    end
    check("Interface v0.11.0 : aucun caractère absent de la police du jeu", not badGlyph, badGlyph)
    check("Aucune erreur interne (bloc v0.11.0)", ns.Diag.counters.errors == 0 and ns2.Diag.counters.errors == 0, ns.Diag.errors[1] and ns.Diag.errors[1].err)
    M.owned = nil
    _G.HandleModifiedItemClick = nil
end

-- =============================================================================
-- 10. v0.13.0 : filtre « Meilleur achat », tri des listes, surbrillance, logo
-- =============================================================================
do
    local G = {}
    local ns = boot({}, G, {})
    local LS, MK, W = ns.Lists, ns.Market, ns.W
    local main = LS.ActiveId()
    for _, id in ipairs({ 6325, 2589, 50001, 50002 }) do LS.Add(id, 1) end
    G.markets.Forever = {
        A = { time = time(), total = 2, char = "Aurelia", d = { [6325] = MK.Pack(150, 2), [2589] = MK.Pack(110, 50) } },
        N = { time = time(), total = 2, char = "Kael", d = { [6325] = MK.Pack(120, 1), [2589] = MK.Pack(90, 9) } },
        H = { time = time(), total = 1, char = "Grosh", d = { [50001] = MK.Pack(75, 3) } } }
    ns.UI.Show("lists")
    local lp = ns.UI.pages.lists
    local v = lp.shopView
    local function ids()
        local t = {}
        for _, d in ipairs(v.itemsList.data) do t[#t + 1] = d.id end
        return table.concat(t, ",")
    end
    v.Refresh()
    check("Listes : filtre « Meilleur achat » et case « Seulement là où ce personnage peut acheter » présents",
        v.filterBox ~= nil and v.buyableCheck ~= nil and not v.buyableCheck:GetChecked())
    check("Filtre « Tous » : les 4 articles", ids() == "6325,2589,50001,50002", ids())
    local function setF(f) ns.settings.lists.bestFilter = f; v.Refresh() end
    setF("pnj")
    check("Filtre PNJ : la recette (40 pc chez le marchand)", ids() == "6325", ids())
    setF("N")
    check("Filtre HDV neutre : l'étoffe (90 pc au neutre)", ids() == "2589", ids())
    setF("H")
    check("Filtre HDV Horde : l'objet vendu seulement à la Horde", ids() == "50001", ids())
    setF("none")
    check("Filtre « Aucune offre sous le prix max » : l'objet sans prix", ids() == "50002", ids())
    setF("A")
    check("Filtre HDV Alliance : aucun article, message explicite", ids() == "" , ids())
    -- Seulement là où ce personnage (Alliance) peut acheter : HDV Horde ignoré
    ns.settings.lists.buyableOnly = true
    setF("H")
    check("Case cochée : plus rien « au meilleur prix » à la Horde", ids() == "", ids())
    setF("none")
    check("Case cochée : l'objet Horde passe dans « Aucune offre »", ids() == "50001,50002", ids())
    setF("all")
    local r50001
    for _, r in ipairs(v.itemsList.rows) do if r.data and r.data.id == 50001 then r50001 = r end end
    check("Case cochée : prix Horde affiché mais pas en vert", r50001 and strip(r50001.cells[8].__text or "") == "75\194\160pc"
        and not (r50001.cells[8].__text or ""):find("7beb96", 1, true), r50001 and r50001.cells[8].__text)
    ns.settings.lists.buyableOnly = false
    v.Refresh()
    check("Case décochée : prix Horde de nouveau en vert", r50001 and (r50001.cells[8].__text or ""):find("7beb96", 1, true) ~= nil)
    -- Tri sur les colonnes
    v.SortBy("m3")
    check("Tri par prix neutre croissant ; sans prix en bas", ids() == "2589,6325,50001,50002", ids())
    v.SortBy("m3", true)
    check("Tri par prix neutre décroissant ; sans prix toujours en bas", ids() == "6325,2589,50001,50002", ids())
    v.SortBy("pnj")
    check("Tri par prix PNJ", ids():sub(1, 4) == "6325", ids())
    v.SortBy("name")
    check("Tri par nom (accents ignorés)", ids():find("2589", 1, true) == 1, ids())
    local arrowShown = false
    for _, h in ipairs(v.header.cells) do if h.key == "name" and h.arrow:IsShown() then arrowShown = true end end
    check("Flèche de tri sur la colonne triée", arrowShown)
    v.header.cells[2].__scripts.OnClick(v.header.cells[2])
    check("Clic sur l'en-tête « Voulu » : tri par quantité", v.itemsList.data[1] ~= nil)
    -- Surbrillance de la ligne au survol des boutons
    local row = v.itemsList.rows[1]
    row.remove.__scripts.OnEnter(row.remove)
    check("Survol du X : la ligne reste en surbrillance", row.__locked == true)
    row.remove.__scripts.OnLeave(row.remove)
    check("Sortie du X : surbrillance rendue", row.__locked == false)
    ns.UI.Show("opp")
    local opp = ns.UI.pages.opp
    opp.SetDirection("forward")
    local orow = opp.fwd and opp.fwd.list and opp.fwd.list.rows[1]
    if orow and orow.add then
        orow.add.__scripts.OnEnter(orow.add)
        check("Survol du + dans PNJ » HDV : ligne en surbrillance", orow.__locked == true)
        orow.add.__scripts.OnLeave(orow.add)
    end
    -- Logo et icônes
    local mf = _G.ShadsunGoldLensMainFrame
    check("Fenêtre principale : grand médaillon (0.14)", mf and mf.logo and mf.logo.__tex == "Interface\\AddOns\\ShadsunGoldLens\\Media\\medaillon")
    local toc = io.open(ADDON .. "/ShadsunGoldLens.toc"):read("*a")
    check("Icône de l'add-on dans la liste des add-ons (TOC)", toc:find("## IconTexture: Interface\\AddOns\\ShadsunGoldLens\\Media\\icon", 1, true) ~= nil)
    local function tgaSize(path)
        local f = io.open(path, "rb")
        if not f then return nil end
        local h = f:read(18); f:close()
        return h:byte(13) + h:byte(14) * 256, h:byte(15) + h:byte(16) * 256, h:byte(17), h:byte(3)
    end
    local lw, lh, lbpp, ltype = tgaSize(ADDON .. "/Media/logo.tga")
    local iw, ih, ibpp = tgaSize(ADDON .. "/Media/icon.tga")
    check("Logo et icône en TGA 32 bits, tailles puissances de 2 (256, 64), non compressés",
        lw == 256 and lh == 256 and lbpp == 32 and ltype == 2 and iw == 64 and ih == 64 and ibpp == 32, tostring(lw) .. "x" .. tostring(lh) .. " " .. tostring(lbpp))
    check("Bouton de la mini-carte : icône de l'add-on", ns.Minimap and ns.Minimap.ICON == "Interface\\AddOns\\ShadsunGoldLens\\Media\\icon"
        or (ns.MM and ns.MM.ICON == "Interface\\AddOns\\ShadsunGoldLens\\Media\\icon"))
    check("Icônes de faction du jeu à côté des noms d'HDV", MK.IconLabel("A"):find("PlusManz-Alliance", 1, true) ~= nil
        and MK.IconLabel("H"):find("PlusManz-Horde", 1, true) ~= nil and MK.Icon("N"):find("INV_Misc_Coin_01", 1, true) ~= nil)
    M.ProcessItem(GameTooltip, 6325)
    check("Infobulle : icône de faction devant « HDV Alliance »", joined(GameTooltip):find("PlusManz-Alliance", 1, true) ~= nil)
    check("Aucune erreur interne (bloc v0.13.0)", ns.Diag.counters.errors == 0, ns.Diag.errors[1] and ns.Diag.errors[1].err)
end

-- =============================================================================
-- 11. v0.14.0 : fusion scan / API par objet (armes et armures), variantes, médaillon
-- =============================================================================
do
    local G = {}
    local ns = boot({}, G, {})
    local MK, T = ns.Market, ns.Tooltip
    local now = time()
    -- Votre scan d'hier (contient une arme 60001) ; API d'il y a 1 h, plus récente,
    -- sans cette arme mais avec une variante seule (60002).
    G.markets.Forever = { A = { time = now - 86400, total = 2, char = "Aurelia",
        d = { [60001] = MK.Pack(25000, 1), [2589] = MK.Pack(120, 10) } } }
    MK.ext = { A = { time = now - 3600, total = 3, char = "API Blizzard", source = "api", house = 113,
        d = { [2589] = MK.Pack(95, 30) }, v = { [60002] = MK.Pack(40000, 2) } } }
    MK.InvalidateSnap()
    local p1, q1, t1 = MK.Price(60001, "A")
    check("Arme absente de l'API plus récente : prix de votre scan conservé (avant : aucun prix)", p1 == 25000 and q1 == 1 and t1 == now - 86400, p1)
    local p2, _, t2 = MK.Price(2589, "A")
    check("Objet présent des deux côtés : donnée la plus récente (API, 95 pc)", p2 == 95 and t2 == now - 3600, p2)
    check("Photo fusionnée : source et heure de la plus récente", MK.Snap("A").source == "api" and MK.Snap("A").time == now - 3600)
    local lines = {}
    T.MarketLines(function(l, r) lines[#lines + 1] = strip((l or "") .. " | " .. (r or "")) end, 60001)
    check("Infobulle de l'arme : prix du scan avec son âge (« scan, il y a 1 j »)", lines[1] and lines[1]:find("HDV Alliance | 2\194\160po 50\194\160pa", 1, true)
        and lines[1]:find("scan, il y a 1 j", 1, true), lines[1])
    lines = {}
    T.MarketLines(function(l, r) lines[#lines + 1] = strip((l or "") .. " | " .. (r or "")) end, 60002)
    check("Infobulle : objet vendu seulement en variantes → « dès 4 po (variantes seulement · 2 en vente · API…) »",
        lines[1] and lines[1]:find("dès 4\194\160po", 1, true) and lines[1]:find("variantes seulement · 2 en vente · API", 1, true), lines[1])
    -- Le scan change (MK.Set : prix d'équipement ajouté après la lecture) : la fusion suit.
    MK.Set("A", 60003, 5000, 1, now - 86400)
    check("Prix d'équipement ajouté au scan après coup : visible dans la photo fusionnée", MK.Price(60003, "A") == 5000)
    -- HDV » HDV : la fusion profite aussi aux comparaisons
    G.markets.Forever.N = { time = now - 600, total = 1, char = "Kael", d = { [60001] = MK.Pack(40000, 1) } }
    local found
    for _, r in ipairs(MK.Cross("A>N")) do if r.id == 60001 then found = r end end
    check("HDV » HDV : l'arme du scan Alliance est comparée au neutre", found and found.buyUnit == 25000 and found.sellUnit == 40000, found and found.gain)
    -- Médaillon de la fenêtre principale, gemme dans le panneau de l'HDV
    ns.UI.Show("detail")
    local mf = _G.ShadsunGoldLensMainFrame
    local pt = mf.logo.__point
    check("Fenêtre principale : médaillon 76 px qui déborde en haut à gauche, zone d'écran élargie",
        mf.logo.__tex:find("medaillon", 1, true) and mf.logo.__w == 76 and pt and pt[2] == -22 and pt[3] == 34
        and mf.__clampInsets and mf.__clampInsets[1] == -22 and mf.__clampInsets[3] == 34, pt and (tostring(pt[2]) .. "," .. tostring(pt[3])))
    check("Titre décalé à droite du médaillon", mf.title.__point and mf.title.__point[2] == 62, mf.title.__point and mf.title.__point[2])
    M.FireEvent("AUCTION_HOUSE_SHOW")
    M.RunTimers()
    local ap = _G.ShadsunGoldLensAuctionPanel
    check("Panneau de l'HDV : gemme seule (version simple du logo)", ap and ap.logo and ap.logo.__tex:find("Media\\icon", 1, true) ~= nil
        and ap.logo.__w == 28, ap and ap.logo and ap.logo.__tex)
    local f = io.open(ADDON .. "/Media/medaillon.tga", "rb")
    local h = f and f:read(18)
    if f then f:close() end
    check("Médaillon : TGA 128×128, 32 bits, non compressé", h and h:byte(13) + h:byte(14) * 256 == 128 and h:byte(15) + h:byte(16) * 256 == 128
        and h:byte(17) == 32 and h:byte(3) == 2)
    check("Aucune erreur interne (bloc v0.14.0)", ns.Diag.counters.errors == 0, ns.Diag.errors[1] and ns.Diag.errors[1].err)
end

rprint("")
for _, l in ipairs(results) do rprint(l) end
rprint("")
rprint(string.format("Résultat : %d réussis, %d échoués", passed, failed))
os.exit(failed == 0 and 0 or 1)
