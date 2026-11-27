-- =============================================================================
-- Shadsun Gold Lens — Core/Database.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : SavedVariables, paramètres par défaut, migration depuis la v0.3.0.
--      ShadsunGoldLensGlobal (compte) : paramètres, observations marchandes.
--      ShadsunGoldLensDB (personnage) : conservé pour la migration v0.3.0.
-- EN : SavedVariables, defaults, migration from v0.3.0.
-- =============================================================================
local _, ns = ...
local U = ns.U
local DB = {}
ns.DB = DB

DB.SCHEMA = 4

DB.defaults = {
    tooltip = {
        enabled = true, showBuy = true, showSell = true, showAH = true, showProfit = true,
        showVendor = true, showFaction = true, showStatus = true, showProfession = true,
        showNoVendorLine = true, showReverse = true, showOwned = true, showMarkets = true, showOtherFaction = true, showLists = true, showAuctions = true,
        maxLines = 12, shiftOnly = false, hideInCombat = false,
    },
    economy = {
        market = "faction",        -- "faction" | "neutral"
        commissionFaction = 5.0,   -- % (règle Classic, à vérifier sur Forever)
        commissionNeutral = 15.0,  -- %
        repDiscount = 0.0,         -- % appliqué aux prix de référence
        minROI = 20.0,             -- % sous lequel la marge est « faible »
        staleDays = 7,             -- âge (jours) au-delà duquel un prix HDV est « ancien »
        depositEstimate = false,   -- afficher le risque de dépôt perdu (estimation)
        depositPct = 15.0,         -- % du prix de vente PNJ par annonce (paramétrable)
        avisMinQty = 3,            -- HDV » HDV : quantité en vente minimale pour un avis « Favorable »
        avisMinSales = 0.3,        -- ventes par jour sous lesquelles l'avis devient « À vérifier » (0.16)
        adviceDays = 3,            -- quantité conseillée : jours de ventes (0.16)
    },
    ah = { autoShow = true, speed = "normal", direction = "reverse", merchantBorder = true, borderColor = { 0.2, 1, 0.3 }, listBorder = true, listBorderColor = { 0.35, 0.65, 1 } },
    minimap = { hide = false, minimapPos = 205 },
    windows = {},
    opportunities = { sortKey = "profit", sortDesc = true },
    lists = { altClick = true, bestFilter = "all", buyableOnly = false },
    columns = {},              -- colonnes affichées par tableau (0.16)
    display = { coinIcons = true, mainScale = 1 },
    debug = false,
}

-- Fusion récursive des valeurs par défaut sans écraser l'existant.
local function applyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            applyDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

-- Migration v0.3.0 → v0.4.0 (SavedVariablesPerCharacter « ShadsunGoldLensDB »)
-- v0.3.0 : db.offers[itemID][clé] = {npc, name, map, x, y, price, quantity, extra,
--          stock, available, seen, knownSide}; db.options; db.minimap
local function migrateLegacy(G, C)
    if type(C) ~= "table" or C.migrated040 then return 0 end
    local moved = 0
    local charName = (UnitName and UnitName("player")) or "?"
    if type(C.offers) == "table" then
        for itemID, entries in pairs(C.offers) do
            if type(itemID) == "number" and type(entries) == "table" then
                for _, o in pairs(entries) do
                    if type(o) == "table" and o.npc and o.price then
                        local qty = o.quantity or 1
                        local key = o.npc .. ":" .. qty .. ":" .. (o.extra and 1 or 0)
                        G.observations[itemID] = G.observations[itemID] or {}
                        if not G.observations[itemID][key] then
                            G.observations[itemID][key] = {
                                npc = o.npc, name = o.name, map = o.map, x = o.x, y = o.y,
                                price = o.price, qty = qty, ext = o.extra and true or nil,
                                stock = o.stock, avail = o.available, seen = o.seen,
                                char = charName, build = "v0.3.0",
                            }
                            moved = moved + 1
                        end
                    end
                end
            end
        end
    end
    if type(C.options) == "table" then
        if C.options.tooltip == false then G.settings.tooltip.enabled = false end
        if C.options.showMissing == false then G.settings.tooltip.showNoVendorLine = false end
        if C.options.shiftOnly == true then G.settings.tooltip.shiftOnly = true end
    end
    if type(C.minimap) == "table" then
        if C.minimap.minimapPos then G.settings.minimap.minimapPos = C.minimap.minimapPos end
        if C.minimap.hide ~= nil then G.settings.minimap.hide = C.minimap.hide end
    end
    -- Sauvegarde de l'ancien contenu pour une version (retour arrière possible).
    C.legacy030 = { offers = C.offers, options = C.options, minimap = C.minimap }
    C.offers, C.options, C.minimap = nil, nil, nil
    C.migrated040 = true
    return moved
end

ns.OnInit(function()
    ShadsunGoldLensGlobal = type(ShadsunGoldLensGlobal) == "table" and ShadsunGoldLensGlobal or {}
    ShadsunGoldLensDB = type(ShadsunGoldLensDB) == "table" and ShadsunGoldLensDB or {}
    local G, C = ShadsunGoldLensGlobal, ShadsunGoldLensDB

    local oldSchema = G.schema
    G.settings = type(G.settings) == "table" and G.settings or {}
    G.observations = type(G.observations) == "table" and G.observations or {}
    G.observedNPCs = type(G.observedNPCs) == "table" and G.observedNPCs or {}
    G.stats = type(G.stats) == "table" and G.stats or {}
    G.markets = type(G.markets) == "table" and G.markets or {}   -- [royaume][A|H|N] = photo du marché
    G.chars = type(G.chars) == "table" and G.chars or {}         -- [royaume][personnage] = inventaire
    local fresh = next(G.settings) == nil
    applyDefaults(G.settings, DB.defaults)
    -- v0.8.0 : lignes d'HDV supplémentaires dans l'infobulle (9 → 11 lignes).
    if not fresh and (oldSchema or 1) < 2 and G.settings.tooltip.maxLines == 9 then G.settings.tooltip.maxLines = 11 end
    -- v0.9.0 : HDV de l'autre faction affiché par défaut (prix de l'API Blizzard).
    if not fresh and (oldSchema or 1) < 3 then G.settings.tooltip.showOtherFaction = true end
    -- v0.11.0 : ligne « En vente » (vos enchères en cours) : 11 → 12 lignes.
    if not fresh and (oldSchema or 1) < 4 and G.settings.tooltip.maxLines == 11 then G.settings.tooltip.maxLines = 12 end
    G.schema = DB.SCHEMA

    -- Bornes de sécurité sur les valeurs saisies / sanity bounds
    local e = G.settings.economy
    e.commissionFaction = math.min(math.max(tonumber(e.commissionFaction) or 5, 0), 50)
    e.commissionNeutral = math.min(math.max(tonumber(e.commissionNeutral) or 15, 0), 50)
    e.repDiscount = math.min(math.max(tonumber(e.repDiscount) or 0, 0), 30)
    G.settings.tooltip.maxLines = math.min(math.max(tonumber(G.settings.tooltip.maxLines) or 9, 3), 20)

    DB.migratedRows = migrateLegacy(G, C)
    C.schema = DB.SCHEMA

    DB.G, DB.C = G, C
    DB.settings = G.settings
    ns.settings = G.settings
end)

function DB.ResetSettings()
    local keepMinimap = DB.settings.minimap
    for k in pairs(DB.settings) do DB.settings[k] = nil end
    applyDefaults(DB.settings, DB.defaults)
    DB.settings.minimap.minimapPos = keepMinimap and keepMinimap.minimapPos or DB.defaults.minimap.minimapPos
    ns.Fire("SETTINGS_CHANGED")
end

function DB.ResetUI()
    DB.settings.windows = {}
    DB.settings.minimap.minimapPos = DB.defaults.minimap.minimapPos
    DB.settings.minimap.hide = false
    ns.Fire("UI_RESET")
end

function DB.PurgeObservations()
    wipe(DB.G.observations)
    wipe(DB.G.observedNPCs)
    ns.Fire("DATA_CHANGED")
end

function DB.CountObservations()
    local items, rows = 0, 0
    for _, entries in pairs(DB.G.observations) do
        items = items + 1
        for _ in pairs(entries) do rows = rows + 1 end
    end
    local npcs = 0
    for _ in pairs(DB.G.observedNPCs) do npcs = npcs + 1 end
    return items, rows, npcs
end

-- Valeur numérique de paramètre (avec repli) / numeric setting helper
function DB.Num(section, key)
    local v = DB.settings[section] and tonumber(DB.settings[section][key])
    if v == nil then v = DB.defaults[section][key] end
    return v
end

U.applyDefaults = applyDefaults
