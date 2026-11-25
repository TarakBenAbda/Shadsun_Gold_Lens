-- =============================================================================
-- Shadsun Gold Lens — Core/Prices.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Lecture des prix HDV via l'API publique d'Auctionator (v1) :
--      GetAuctionPriceByItemID / GetAuctionPriceByItemLink / GetAuctionAgeByItemID
--      et RegisterForDBUpdate pour invalider le cache. Aucun scan propre,
--      aucun prix inventé : absence de donnée = nil.
-- EN : Auctionator public API v1 wrapper with cache; no own scanning.
-- =============================================================================
local _, ns = ...
local P = {}
ns.Prices = P

local cache = {}
local cacheSize = 0
local TTL = 120          -- secondes / seconds (filet de sécurité)
P.version = 0
P.registered = false

local function api()
    local a = Auctionator and Auctionator.API and Auctionator.API.v1
    if type(a) == "table" then return a end
    return nil
end

-- État d'Auctionator : "OK", "NO_ADDON", "NO_API"
function P.State()
    local a = api()
    if not a then
        local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Auctionator")
        return loaded and "NO_API" or "NO_ADDON"
    end
    if type(a.GetAuctionPriceByItemID) ~= "function" and type(a.GetAuctionPriceByItemLink) ~= "function" then
        return "NO_API"
    end
    return "OK"
end

function P.Invalidate()
    wipe(cache)
    cacheSize = 0
    P.version = P.version + 1
    ns.Fire("PRICES_CHANGED")
end

local function register()
    if P.registered then return end
    local a = api()
    if a and type(a.RegisterForDBUpdate) == "function" then
        local ok = pcall(a.RegisterForDBUpdate, ns.callerID, function() P.Invalidate() end)
        P.registered = ok
    end
end

ns.OnLogin(register)
ns.RegisterEvent("ADDON_LOADED", function(_, name)
    if name == "Auctionator" then register() end
end)
-- Filet de sécurité : fermeture de l'HDV = nouveau scan possible.
ns.RegisterEvent("AUCTION_HOUSE_CLOSED", function() P.Invalidate() end)

-- Lecture directe sans mise en cache (analyses en masse : pas de milliers
-- d'entrées gardées en mémoire). Uncached read for bulk scans.
local fetch
function P.Peek(itemID)
    if not itemID then return nil, nil, "NONE" end
    return fetch(itemID, nil)
end

-- Retourne prixUnitaire (cuivre) | nil, âge (jours) | nil, état
-- Returns unitPrice (copper) | nil, age (days) | nil, state
function P.Get(itemID, link)
    if not itemID then return nil, nil, "NONE" end
    local now = GetTime()
    local c = cache[itemID]
    if c and now - c.t < TTL then return c.p, c.age, c.state end
    local price, age, state = fetch(itemID, link)
    -- Plafond de mémoire : au-delà de 2 000 entrées, le cache repart de zéro.
    cacheSize = cacheSize + 1
    if cacheSize > 2000 then wipe(cache); cacheSize = 1 end
    cache[itemID] = { p = price, age = age, state = state, t = now }
    return price, age, state
end

fetch = function(itemID, link)

    local state = P.State()
    local price, age
    if state == "OK" then
        local a = api()
        if type(a.GetAuctionPriceByItemID) == "function" then
            local ok, res = pcall(a.GetAuctionPriceByItemID, ns.callerID, itemID)
            if ok and type(res) == "number" and res > 0 then price = res end
        end
        if not price and type(link) == "string" and link:find("item:") and type(a.GetAuctionPriceByItemLink) == "function" then
            local ok, res = pcall(a.GetAuctionPriceByItemLink, ns.callerID, link)
            if ok and type(res) == "number" and res > 0 then price = res end
        end
        if price and type(a.GetAuctionAgeByItemID) == "function" then
            local ok, days = pcall(a.GetAuctionAgeByItemID, ns.callerID, itemID)
            if ok and type(days) == "number" and days >= 0 then age = days end
        end
        if not price then state = "NONE" end
    end
    return price, age, state
end

-- Meilleur prix HDV disponible pour revendre un objet (sens PNJ » HDV).
--  1. Photo du marché de revente (paramètre « Marché de revente ») de ce
--     serveur, si elle n'est pas ancienne : prix réel du scan et quantité ;
--     pour les armes et armures : version simple uniquement.
--  2. Sinon historique Auctionator — sauf armes et armures, dont l'historique
--     mélange la version simple et les variantes à suffixe (plus chères).
--  3. Sinon photo ancienne, s'il en existe une.
-- Retourne prix, âge (jours), état ("LIVE", "OK", "NONE", "VARIANTS"…), heure du scan, quantité, HDV.
-- Best AH price for reselling: market snapshot first, Auctionator otherwise.
function P.Best(itemID, link)
    local A, MK = ns.Arbitrage, ns.Market
    local key = MK and MK.SellKey()
    local snap = MK and MK.Snap(key)
    local unit, qty, t
    if snap then unit, qty = MK.Item(snap, itemID); t = MK.ItemSnap(snap, itemID).time end
    if unit and not MK.IsStale(t) then
        return unit, MK.AgeDays(t), "LIVE", t, qty, key
    end
    local gear = A and A.IsGear(itemID)
    if not gear then
        local price, age, state = P.Get(itemID, link)
        if price then return price, age, state end
        if unit then return unit, MK.AgeDays(t), "LIVE", t, qty, key end
        return price, age, state
    end
    if unit then return unit, MK.AgeDays(t), "LIVE", t, qty, key end
    if snap and P.State() == "OK" then return nil, nil, "NONE" end
    return nil, nil, (P.State() == "OK") and "VARIANTS" or P.State()
end

-- Prix de vente au marchand (ce que le PNJ vous paie) — via les infos d'objet.
-- Vendor sell price (what the NPC pays you).
function P.VendorSell(itemID)
    -- Uniquement le jeu : GetVendorPriceByItemID d'Auctionator est un prix d'achat.
    local info = ns.U.ItemInfo(itemID)
    return info and info.sellPrice or nil
end

function P.Describe()
    local a = api()
    if not a then return P.State() end
    local fns = {}
    for _, f in ipairs({ "GetAuctionPriceByItemID", "GetAuctionPriceByItemLink", "GetAuctionAgeByItemID", "RegisterForDBUpdate" }) do
        fns[#fns + 1] = f .. (type(a[f]) == "function" and "=oui" or "=non")
    end
    return P.State() .. " (" .. table.concat(fns, ", ") .. ")" .. (P.registered and " · abonné aux mises à jour" or "")
end
