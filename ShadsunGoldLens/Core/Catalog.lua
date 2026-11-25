-- =============================================================================
-- Shadsun Gold Lens — Core/Catalog.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Accès indexé à la base intégrée (couche A) fusionnée avec les
--      observations faites en jeu (couche B). Calcule, pour un itemID :
--      les offres PNJ triées, le statut de fiabilité et l'exclusivité de faction.
--      Recherche O(1) par itemID ; résultats mis en cache et invalidés sur
--      changement de données, de zone ou de paramètres.
-- EN : Indexed catalog access merged with in-game observations; per-item view
--      (sorted offers, reliability status, faction exclusivity), cached.
-- =============================================================================
local _, ns = ...
local U, L = ns.U, ns.L
local C = {}
ns.Catalog = C

-- Drapeaux des lignes (identiques à tools/sgl_build_db.py) / row flags
local R_REF, R_EG, R_LIMITED, R_EXTCOST = 1, 2, 4, 8
local R_PRICE_FOREVER, R_PRICE_REF_ONLY, R_PRICE_EG_ONLY = 16, 32, 64
local R_QTY_CHANGED, R_PRICE_UNCERTAIN, R_MANUAL, R_OBS_LOWER, R_WEB = 128, 256, 512, 1024, 2048
-- Drapeaux des PNJ / NPC flags
local N_EG, N_MOVES, N_NOPOS = 2, 4, 8
C.flags = { R_REF = R_REF, R_EG = R_EG, R_LIMITED = R_LIMITED, R_EXTCOST = R_EXTCOST,
    R_PRICE_FOREVER = R_PRICE_FOREVER, R_PRICE_UNCERTAIN = R_PRICE_UNCERTAIN, R_MANUAL = R_MANUAL,
    R_WEB = R_WEB, R_OBS_LOWER = R_OBS_LOWER, N_MOVES = N_MOVES, N_NOPOS = N_NOPOS }

local function has(flags, bit)
    return flags % (bit * 2) >= bit
end
C.has = has

-- Conditions CMaNGOS identifiées d'après les objets concernés (déduction
-- documentée, à confirmer en jeu) / CMaNGOS conditions inferred from items.
local CONDITION_KIND = {
    [156] = "REP", [161] = "REP", [1535] = "REP", [1536] = "REP", [1537] = "REP", [1538] = "REP",
    [500] = "EVENT", [1368] = "EVENT", [1369] = "EVENT",
}

-- Index des objets connus (plages compactes → ensemble) / known-item set
local known
local function buildKnown()
    known = {}
    local r = ns.Data and ns.Data.knownRanges or {}
    for i = 1, #r - 1, 2 do
        local start, len = r[i], r[i + 1]
        for id = start, start + len - 1 do known[id] = true end
    end
end

local cache = {}
local cacheVersion = 0
function C.Invalidate(itemID)
    if itemID then cache[itemID] = nil else wipe(cache); cacheVersion = cacheVersion + 1 end
end
function C.Version() return cacheVersion end

ns.On("DATA_CHANGED", function(itemID) C.Invalidate(itemID) end)
ns.On("SETTINGS_CHANGED", function() C.Invalidate() end)
ns.On("ZONE_CHANGED", function() C.Invalidate() end)

local playerSide, playerMap = "?", nil
ns.OnLogin(function()
    playerSide = U.PlayerSide()
    playerMap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
    C.Invalidate()
end)
local function onZone()
    local m = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
    if m ~= playerMap then
        playerMap = m
        ns.Fire("ZONE_CHANGED")
    end
end
ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", onZone)
ns.RegisterEvent("ZONE_CHANGED", onZone)
ns.RegisterEvent("PLAYER_ENTERING_WORLD", onZone)
function C.PlayerSide() return playerSide end
function C.PlayerMap() return playerMap end

-- -----------------------------------------------------------------------------
-- Construction d'une offre / offer construction
-- -----------------------------------------------------------------------------
local function npcRecord(npcID)
    local n = ns.Data.npcs[npcID]
    local o = ns.DB.G and ns.DB.G.observedNPCs[npcID]
    local rec = {}
    if n then
        rec.nameEN, rec.nameFR, rec.side, rec.map, rec.x, rec.y, rec.nflags =
            n[1], n[2] or nil, n[3], n[4] or nil, n[5] or nil, n[6] or nil, n[7] or 0
        if n[8] then rec.alt = { map = n[8], x = n[9], y = n[10] } end
    else
        rec.nflags = 0
    end
    if o then
        -- Vos observations priment pour le nom localisé, la faction et la position.
        rec.nameLocal = o.name
        if o.side and o.side ~= "?" then rec.side = o.side end
        if o.map and o.x and o.y and not has(rec.nflags, N_MOVES) then
            rec.map, rec.x, rec.y = o.map, o.x, o.y
        end
        rec.observed = true
    end
    rec.side = rec.side or "?"
    return rec
end

local function displayName(rec, npcID)
    local isFR = GetLocale and GetLocale() == "frFR"
    return rec.nameLocal or (isFR and rec.nameFR) or rec.nameEN or ("PNJ n° " .. npcID)
end

local function conditionText(cond)
    if not cond or cond == 0 then return nil end
    local kind = CONDITION_KIND[cond]
    local base = (kind == "REP" and L.COND_REP) or (kind == "EVENT" and L.COND_EVENT) or L.COND_OTHER
    return base .. string.format(L.COND_REF, cond)
end

local function makeOffer(npcID, price, qty, flags, cond, obsPrice)
    local rec = npcRecord(npcID)
    local offer = {
        npc = npcID, name = displayName(rec, npcID), side = rec.side,
        map = rec.map, x = rec.x, y = rec.y, alt = rec.alt,
        basePrice = price or 0, price = price or 0, qty = qty or 1, flags = flags or 0,
        cond = cond or 0, condText = conditionText(cond), obsPrice = (obsPrice and obsPrice > 0) and obsPrice or nil,
    }
    offer.ext = has(offer.flags, R_EXTCOST)
    offer.limited = has(offer.flags, R_LIMITED)
    offer.moves = has(rec.nflags, N_MOVES)
    offer.nopos = not (offer.map and offer.x and offer.y)
    if has(offer.flags, R_MANUAL) then offer.source = "MANUAL"
    elseif has(offer.flags, R_EG) then offer.source = "EG"
    elseif has(offer.flags, R_WEB) then offer.source = "WEB"
    else offer.source = "REF" end
    return offer
end

-- Intègre une observation personnelle (couche B) / merge personal observation
local function applyObservation(offer, o)
    offer.personal = o
    offer.price = o.price or offer.price
    offer.qty = o.qty or offer.qty
    offer.ext = o.ext and true or offer.ext
    offer.source = "PERSONAL"
    if o.stock ~= nil then
        offer.stock = o.stock
        if o.stock >= 0 then offer.limited = true end
    end
    if o.avail == false then offer.unavailable = true end
    if o.map and o.x and o.y and not offer.moves then
        offer.map, offer.x, offer.y, offer.nopos = o.map, o.x, o.y, false
    end
    if (not offer.side or offer.side == "?") and o.side then offer.side = o.side end
    if o.name and o.name ~= "" then offer.name = o.name end
end

-- -----------------------------------------------------------------------------
-- Classement des offres pour le personnage courant / ranking for the player
-- -----------------------------------------------------------------------------
local function accessRank(o)
    if o.ext then return 4 end
    if o.side ~= "?" and o.side ~= "N" and o.side ~= playerSide then return 5 end
    if o.side == "?" then return 3 end
    if o.cond ~= 0 or o.unavailable then return 2 end
    return 1
end
local sourceRank = { PERSONAL = 1, MANUAL = 2, EG = 3, WEB = 4, REF = 5 }

local function better(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    local am, bm = (a.map == playerMap), (b.map == playerMap)
    if am ~= bm then return am end
    if a.nopos ~= b.nopos then return not a.nopos end
    local sa, sb = sourceRank[a.source] or 9, sourceRank[b.source] or 9
    if sa ~= sb then return sa < sb end
    local ua, ub = a.price / a.qty, b.price / b.qty
    if ua ~= ub then return ua < ub end
    if a.name ~= b.name then return a.name < b.name end
    return a.npc < b.npc
end

-- Exclusivité calculée sur l'ensemble des vendeurs connus, pas sur un seul.
-- Exclusivity is derived from all known vendors with a confidence level.
local function exclusivity(offers, status)
    local hasA, hasH, hasN, unknown, knownCount = false, false, false, 0, 0
    for _, o in ipairs(offers) do
        if o.side == "A" then hasA = true; knownCount = knownCount + 1
        elseif o.side == "H" then hasH = true; knownCount = knownCount + 1
        elseif o.side == "N" then hasN = true; knownCount = knownCount + 1
        else unknown = unknown + 1 end
    end
    local code
    if hasN or (hasA and hasH) then code = "BOTH"
    elseif hasA then code = "A"
    elseif hasH then code = "H"
    else code = "UNKNOWN" end
    local conf
    if code == "UNKNOWN" then conf = "LOW"
    elseif unknown > 0 then conf = (code == "BOTH") and "MED" or "LOW"
    elseif status == "CONFIRMED" and knownCount >= 2 then conf = "HIGH"
    else conf = "MED" end
    return { code = code, confidence = conf, unknown = unknown, count = knownCount }
end

-- -----------------------------------------------------------------------------
-- Vue d'un objet / per-item view (mise en cache)
-- -----------------------------------------------------------------------------
function C.GetView(itemID)
    if not itemID then return nil end
    local v = cache[itemID]
    if v then return v end
    if not known then buildKnown() end

    local offers, byKey = {}, {}
    local flat = ns.Data.items[itemID]
    if flat then
        for i = 1, #flat, 6 do
            local o = makeOffer(flat[i], flat[i + 1], flat[i + 2], flat[i + 3], flat[i + 4], flat[i + 5])
            byKey[o.npc .. ":" .. o.qty .. ":" .. (o.ext and 1 or 0)] = o
            offers[#offers + 1] = o
        end
    end
    local obs = ns.DB.G and ns.DB.G.observations[itemID]
    local personal = false
    if obs then
        for key, o in pairs(obs) do
            if type(o) == "table" and o.npc then
                local offer = byKey[key]
                if not offer then
                    -- Même PNJ mais quantité différente : on remplace la ligne de base.
                    for k2, existing in pairs(byKey) do
                        if existing.npc == o.npc and not existing.personal and k2 ~= key then
                            offer = existing
                            break
                        end
                    end
                end
                if not offer then
                    offer = makeOffer(o.npc, o.price, o.qty, o.ext and R_EXTCOST or 0, 0, 0)
                    offers[#offers + 1] = offer
                end
                byKey[key] = offer
                applyObservation(offer, o)
                personal = true
            end
        end
    end

    local status
    if #offers == 0 then
        status = known[itemID] and "NONE" or "NODATA"
    else
        status = "REFERENCE"
        for _, o in ipairs(offers) do
            if o.source == "PERSONAL" or o.source == "EG" or o.source == "MANUAL" then status = "CONFIRMED"; break end
        end
    end

    -- Armes et armures : vendues à l'unité sur Forever. La référence Classic
    -- indique parfois des lots de 200 (armes de jet) : prix compté pour 1 unité.
    -- Weapons/armor are sold one at a time on Forever: ignore reference lots.
    local inst = U.ItemInstant(itemID)
    if inst and (inst.classID == 2 or inst.classID == 4) then
        for _, o in ipairs(offers) do
            if o.qty > 1 and not o.personal then o.qty = 1; o.lotFixed = true end
        end
    end

    local repDiscount = ns.DB.Num("economy", "repDiscount") or 0
    for _, o in ipairs(offers) do
        if repDiscount > 0 and not o.personal and not o.ext and o.price > 0 then
            o.price = math.floor(o.basePrice * (100 - repDiscount) / 100 + 0.5)
            o.discounted = true
        end
        o.rank = accessRank(o)
        o.accessible = o.rank <= 2
        o.enemy = o.rank == 5
    end
    table.sort(offers, better)

    v = {
        id = itemID, offers = offers, best = offers[1], status = status, personal = personal,
        excl = exclusivity(offers, status), playerSide = playerSide,
    }
    cache[itemID] = v
    return v
end

function C.IsKnown(itemID)
    if not known then buildKnown() end
    return known[itemID] or false
end

-- Liste des itemIDs du catalogue + observations / all catalog item IDs
function C.AllItemIDs()
    local ids, seen = {}, {}
    for id in pairs(ns.Data.items) do ids[#ids + 1] = id; seen[id] = true end
    if ns.DB.G then
        for id in pairs(ns.DB.G.observations) do
            if not seen[id] then ids[#ids + 1] = id; seen[id] = true end
        end
    end
    table.sort(ids)
    return ids
end

-- Textes d'affichage / display helpers
function C.StatusText(status, short)
    local key = ({ CONFIRMED = "CONFIRMED", REFERENCE = "REFERENCE", NONE = "NONE", NODATA = "NODATA" })[status] or "NODATA"
    return L[(short and "STATUS_SHORT_" or "STATUS_") .. key]
end

function C.StatusColor(status)
    if status == "CONFIRMED" then return U.colors.good end
    if status == "REFERENCE" then return U.colors.warn end
    return U.colors.dim
end

function C.SourceText(o)
    if o.source == "PERSONAL" then
        local p = o.personal
        return string.format(L.SRC_PERSONAL, p.seen and date("%Y-%m-%d", p.seen) or "?", p.char or "?")
    end
    local t = (o.source == "EG" and L.SRC_EG) or (o.source == "WEB" and L.SRC_WEB)
        or (o.source == "MANUAL" and L.SRC_MANUAL) or L.SRC_REF
    if has(o.flags, R_PRICE_FOREVER) then t = t .. " · " .. L.PRICE_FOREVER end
    if has(o.flags, R_PRICE_UNCERTAIN) then t = t .. " · " .. L.PRICE_UNCERTAIN end
    if o.obsPrice then t = t .. " · " .. string.format(L.PRICE_DISCOUNT_SEEN, U.Money(o.obsPrice, true)) end
    return t
end

function C.ExclusivityText(excl)
    local base = (excl.code == "A" and L.EXCL_A) or (excl.code == "H" and L.EXCL_H)
        or (excl.code == "BOTH" and L.EXCL_BOTH) or L.EXCL_UNKNOWN
    local conf = (excl.confidence == "HIGH" and L.CONF_HIGH) or (excl.confidence == "MED" and L.CONF_MED) or L.CONF_LOW
    return base .. " (" .. conf .. ")"
end

function C.ArbitrageText(excl)
    if excl.code == playerSide and (excl.code == "A" or excl.code == "H") then return L.ARBITRAGE_OWN end
    if (excl.code == "A" or excl.code == "H") and excl.code ~= playerSide then return L.ARBITRAGE_ENEMY end
    return nil
end

function C.LocationText(o)
    if o.nopos then return L.NOPOS end
    local zone = U.MapName(o.map) or (L.ZONE_UNKNOWN .. " (" .. tostring(o.map) .. ")")
    return zone .. " " .. U.Coord(o.x) .. ", " .. U.Coord(o.y)
end

function C.PriceText(o, plain)
    if o.ext then
        if o.price and o.price > 0 then return U.Money(o.price, plain) .. " + " .. L.EXTCOST end
        return L.EXTCOST
    end
    if not o.price or o.price <= 0 then return L.PRICE_UNKNOWN end
    local t = U.Money(o.price, plain)
    if o.qty > 1 then t = t .. string.format(L.SOLD_BY_LOT, o.qty) end
    return t
end

-- Recherche par nom (anglais de référence + noms en cache du client)
-- Name search over English reference names and client-cached localized names.
function C.SearchByName(query, limit)
    query = U.Trim(query):lower()
    if query == "" then return {} end
    local results, seen = {}, {}
    local function consider(id, name)
        if not seen[id] and name and name:lower():find(query, 1, true) then
            seen[id] = true
            results[#results + 1] = { id = id, name = name }
        end
    end
    for _, id in ipairs(C.AllItemIDs()) do
        local info = U.ItemInfo(id)
        if info then consider(id, info.name) end
        consider(id, ns.Data.names[id])
        if #results >= (limit or 30) then break end
    end
    table.sort(results, function(a, b) return a.name < b.name end)
    return results
end
