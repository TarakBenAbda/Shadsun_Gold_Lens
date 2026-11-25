-- =============================================================================
-- Shadsun Gold Lens — Core/Auctions.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Vos enchères en cours (objets mis en vente, pas encore vendus), par
--      personnage du serveur.
--      - Relevé exact : le jeu ne donne la liste de vos enchères que quand
--        l'HDV est ouvert. Relevé à l'ouverture, après chaque mise en vente
--        et après chaque annulation.
--      - Entre deux visites : les messages « Un acheteur a été trouvé pour
--        votre enchère… » et « Votre enchère … a expiré » retirent l'annonce
--        concernée. Pour une marchandise (vendue par morceaux), la quantité
--        restante n'est pas connue : le nombre est alors marqué « ~ »
--        (maximum possible).
--      Relevé stocké dans l'inventaire du personnage (ShadsunGoldLensGlobal).
-- EN : Your active auctions per character (exact at the AH, adjusted by the
--      sold / expired system messages in between).
-- =============================================================================
local _, ns = ...
local U = ns.U
local AU = {}
ns.Auctions = AU

local ACTIVE = (Enum and Enum.AuctionStatus and Enum.AuctionStatus.Active) or 0

local function record()
    return ns.Inventory and ns.Inventory.MyRecord and ns.Inventory.MyRecord()
end

-- Enregistrement { time, list = { {id, q, c}, … }, approx } ; c = marchandise
local function ahData(rec, create)
    if type(rec) ~= "table" then return nil end
    if type(rec.ah) ~= "table" then
        if not create then return nil end
        rec.ah = {}
    end
    rec.ah.list = type(rec.ah.list) == "table" and rec.ah.list or {}
    return rec.ah
end

-- -----------------------------------------------------------------------------
-- Relevé à l'HDV / owned auctions scan (AH open)
-- -----------------------------------------------------------------------------
local function ownedList()
    local CA = C_AuctionHouse
    if not CA then return nil end
    if CA.GetOwnedAuctions then
        local ok, t = pcall(CA.GetOwnedAuctions)
        if ok and type(t) == "table" then return t end
    end
    if CA.GetNumOwnedAuctions and CA.GetOwnedAuctionInfo then
        local ok, n = pcall(CA.GetNumOwnedAuctions)
        if ok and type(n) == "number" then
            local t = {}
            for i = 1, n do
                local ok2, info = pcall(CA.GetOwnedAuctionInfo, i)
                if ok2 and type(info) == "table" then t[#t + 1] = info end
            end
            return t
        end
    end
    return nil
end

local function isCommodity(id)
    local CA, E = C_AuctionHouse, Enum and Enum.ItemCommodityStatus
    if CA and CA.GetItemCommodityStatus and E then
        local ok, st = pcall(CA.GetItemCommodityStatus, id)
        if ok and st == E.Commodity then return true end
        if ok and st == E.Item then return false end
    end
    local info = U.ItemInfo(id)
    return (info and info.stack and info.stack > 1) and true or false
end

-- Lit la liste donnée par le jeu et remplace le relevé du personnage.
function AU.Read()
    local t = ownedList()
    if not t then return false end
    local rec = record()
    local d = ahData(rec, true)
    if not d then return false end
    local list = {}
    for _, a in ipairs(t) do
        local id = a.itemKey and a.itemKey.itemID or a.itemID
        local status = a.status or ACTIVE
        if type(id) == "number" and status == ACTIVE then
            list[#list + 1] = { id = id, q = math.max(1, tonumber(a.quantity) or 1), c = isCommodity(id) or nil }
        end
    end
    d.list, d.time, d.approx = list, time(), nil
    ns.Fire("AUCTIONS_CHANGED")
    return true
end

function AU.Query()
    local CA = C_AuctionHouse
    if not (CA and CA.QueryOwnedAuctions) then AU.Read() return end
    pcall(CA.QueryOwnedAuctions, {})
end

local queued = false
local function queueQuery(delay)
    if queued then return end
    queued = true
    C_Timer.After(delay or 1, function()
        queued = false
        if ns.Arbitrage and ns.Arbitrage.ahOpen then AU.Query() end
    end)
end

ns.RegisterEvent("AUCTION_HOUSE_SHOW", function() queueQuery(0.5) end)
ns.RegisterEvent("OWNED_AUCTIONS_UPDATED", function() AU.Read() end)
ns.RegisterEvent("AUCTION_HOUSE_AUCTION_CREATED", function() queueQuery(1) end)
ns.RegisterEvent("AUCTION_CANCELED", function() queueQuery(1) end)

-- -----------------------------------------------------------------------------
-- Vendu ou expiré hors HDV / sold or expired while away
-- -----------------------------------------------------------------------------
-- Motif tiré d'une chaîne du jeu (« … %s. ») / pattern from a game string
local function pattern(fmt)
    if type(fmt) ~= "string" or not fmt:find("%%s") then return nil end
    local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "%%d+")
    return "^" .. p .. "$"
end
AU.Pattern = pattern

local function itemName(id)
    local info = U.ItemInfo(id)
    return (info and info.name) or (ns.Data.names and ns.Data.names[id])
end

-- Retire une annonce de l'objet nommé. Pour une marchandise, l'annonce peut
-- n'être vendue qu'en partie : le total devient un maximum (« ~ »).
function AU.OnGone(name, sold)
    local d = ahData(record())
    if not d or not name then return false end
    name = U.Trim(tostring(name)):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local linkId = U.ItemID(name)
    for i, a in ipairs(d.list) do
        if (linkId and a.id == linkId) or itemName(a.id) == name then
            if a.c and sold then
                d.approx = true
                if a.q > 1 then a.q = a.q - 1 else table.remove(d.list, i) end
            else
                table.remove(d.list, i)
            end
            ns.Fire("AUCTIONS_CHANGED")
            return true
        end
    end
    return false
end

ns.RegisterEvent("CHAT_MSG_SYSTEM", function(_, msg)
    if type(msg) ~= "string" then return end
    local ps, pe = pattern(ERR_AUCTION_SOLD_S), pattern(ERR_AUCTION_EXPIRED_S)
    local name = ps and msg:match(ps)
    if name then AU.OnGone(name, true) return end
    name = pe and msg:match(pe)
    if name then AU.OnGone(name, false) end
end)

-- -----------------------------------------------------------------------------
-- Lecture / queries
-- -----------------------------------------------------------------------------
-- Nombre en vente pour un personnage (enregistrement) / count for a record
local function countIn(rec, itemID)
    local d = ahData(rec)
    if not d then return 0, nil, false end
    local n = 0
    for _, a in ipairs(d.list) do if a.id == itemID then n = n + a.q end end
    return n, d.time, d.approx and true or false
end

-- Total du serveur, détail { {name, n, me}, … }, relevé le plus ancien,
-- approximatif ? / realm total, per-character detail, oldest scan, approx.
function AU.Count(itemID)
    local INV = ns.Inventory
    local total, list, oldest, approx = 0, nil, nil, false
    if not INV then return 0 end
    local me = INV.Me()
    for _, c in ipairs(INV.Characters()) do
        local n, t, ap = countIn(c.rec, itemID)
        if n > 0 then
            list = list or {}
            list[#list + 1] = { name = c.name, n = n, me = c.me }
            total = total + n
            if t and (not oldest or t < oldest) then oldest = t end
            approx = approx or ap
        end
    end
    if list then
        table.sort(list, function(a, b)
            if a.me ~= b.me then return a.me and true or false end
            if a.n ~= b.n then return a.n > b.n end
            return a.name < b.name
        end)
    end
    return total, list, oldest, approx, me
end

function AU.Total(itemID) return (AU.Count(itemID)) end

-- Nombre court : « 6 » ou « ~6 » (maximum) / short count
function AU.Short(itemID)
    local n, _, _, approx = AU.Count(itemID)
    if n == 0 then return nil end
    return (approx and "~" or "") .. n
end

-- Ligne d'infobulle : « 6 · il y a 2 h », « 6 : Aurelia 4 · Kael 2 · il y a 2 h »,
-- « 6 (au plus) » après une vente partielle de marchandise.
function AU.Text(itemID)
    local total, list, oldest, approx = AU.Count(itemID)
    if total == 0 then return nil end
    local s = tostring(total)
    if #list > 1 or not list[1].me then
        local parts = {}
        for i = 1, math.min(#list, 4) do parts[#parts + 1] = list[i].name .. " " .. list[i].n end
        if #list > 4 then parts[#parts + 1] = "+" .. (#list - 4) end
        s = s .. " : " .. table.concat(parts, " · ")
    end
    if approx then s = s .. U.Color(U.colors.dim, " (au plus)") end
    if oldest and not (ns.Arbitrage and ns.Arbitrage.ahOpen) then
        s = s .. U.Color(U.colors.dim, " · " .. U.Ago(oldest))
    end
    return s
end

-- Relevé du personnage connecté (onglet Marchés, diagnostic)
function AU.Mine()
    local d = ahData(record())
    if not d then return 0, nil end
    local n = 0
    for _, a in ipairs(d.list) do n = n + a.q end
    return #d.list, d.time, n
end
