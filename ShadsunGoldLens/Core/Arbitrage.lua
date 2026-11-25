-- =============================================================================
-- Shadsun Gold Lens — Core/Arbitrage.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Arbitrage inverse HDV » PNJ : acheter à l'hôtel des ventes moins cher
--      que le prix de rachat d'un marchand, puis vendre au marchand.
--      Gain = prix de vente PNJ − prix d'achat HDV (l'acheteur ne paie ni
--      commission ni dépôt).
--
--      Deux sources, sans scan propre à l'add-on :
--       1. Annonces en cours : lecture de la liste chargée par un scan complet
--          (C_AuctionHouse.ReplicateItems, lancé par Auctionator ou par le
--          bouton du panneau ; limite Blizzard : 1 scan / 15 min / compte).
--          Prix et quantités réels au moment du scan.
--       2. Historique Auctionator : dernier prix minimum connu par objet
--          (API publique v1), sans quantité ni garantie de disponibilité.
--      Lecture seule : aucun achat automatique.
-- EN : Reverse arbitrage AH → vendor from replicate listings or Auctionator.
-- =============================================================================
local _, ns = ...
local U = ns.U
local A = {}
ns.Arbitrage = A

-- Vitesse d'analyse (paramètre « Vitesse d'analyse ») : AUCUNE limite sur le
-- nombre d'annonces ou d'objets analysés, seulement sur le rythme de travail
-- par image et de demandes au serveur. Speed only paces work; volume is unlimited.
A.SPEEDS = {
    slow   = { chunk = 750,  hist = 400,  perTick = 10 },  -- 40 demandes / s
    normal = { chunk = 1500, hist = 800,  perTick = 20 },  -- 80 demandes / s
    fast   = { chunk = 4000, hist = 2000, perTick = 50 },  -- 200 demandes / s
}
local function speed()
    local s = ns.settings and ns.settings.ah and ns.settings.ah.speed
    return A.SPEEDS[s] or A.SPEEDS.normal
end
A.SCAN_COOLDOWN = 15 * 60   -- limite Blizzard documentée / documented throttle

A.live = nil                -- { time, total, items = { [id] = { units = {}, counts = {}, buyouts = {} } } }
A.liveResults = {}
A.histResults = {}
A.processing = false
A.lastScanRequest = nil
A.ahOpen = false

-- -----------------------------------------------------------------------------
-- Prix de vente au marchand / vendor sell price
-- -----------------------------------------------------------------------------
-- SEULE source fiable : le prix de vente au marchand fourni par le jeu
-- (11e valeur de C_Item.GetItemInfo, celle affichée « Prix de vente » dans
-- l'infobulle). NE PAS utiliser Auctionator GetVendorPriceByItemID : c'est le
-- prix d'ACHAT chez un marchand (coûts d'artisanat), pas le prix de rachat.
-- Objet non chargé : aucune valeur, chargement demandé, recalcul ensuite.
-- Only the game's vendor sell price; Auctionator's "vendor price" is a BUY price.
local pendingInfo = {}     -- objets dont on attend le prix de rachat / awaited items
local queue, queued = {}, {} -- demandes au jeu, envoyées au compte-gouttes / throttled requests
local pumping = false
local TICK = 0.25

-- Les demandes d'informations au serveur sont étalées : jamais des milliers
-- d'un coup (cause des saccades de la v0.5.2). Uniquement HDV ouvert ou
-- analyse de l'historique en cours ; tout est annulé à la fermeture de l'HDV.
local function pump()
    if #queue == 0 or not (A.ahOpen or A.histRunning) then
        pumping = false
        return
    end
    for _ = 1, speed().perTick do
        local id = table.remove(queue)
        if not id then break end
        queued[id] = nil
        if pendingInfo[id] then U.RequestItem(id) end
    end
    C_Timer.After(TICK, pump)
end

local function enqueue(itemID)
    pendingInfo[itemID] = true
    if queued[itemID] then return end
    queued[itemID] = true
    queue[#queue + 1] = itemID
    if not pumping then pumping = true; C_Timer.After(TICK, pump) end
end

function A.SellPrice(itemID)
    local info = U.ItemInfo(itemID)
    if info then return info.sellPrice or 0, info end
    enqueue(itemID)
    return nil, nil
end

-- Libère tout ce qui est volumineux (annonces brutes, files d'attente).
-- Releases bulky data; keeps only the compact results.
function A.ReleaseData()
    if A.processing then A.cancelRequested = true end
    A.live = nil
    wipe(queue); wipe(queued); wipe(pendingInfo)
    A.histPending = {}
end

-- Calcul pur pour une liste d'annonces / pure computation over listings
-- buyouts[i] = prix total de l'annonce i, counts[i] = quantité
function A.ComputeListings(sell, buyouts, counts)
    local gain, qty, spend, minUnit, deals = 0, 0, 0, nil, 0
    for i = 1, #buyouts do
        local b, c = buyouts[i], counts[i]
        local unit = b / c
        if not minUnit or unit < minUnit then minUnit = unit end
        local value = c * sell
        if b < value then
            gain, qty, spend, deals = gain + (value - b), qty + c, spend + b, deals + 1
        end
    end
    return { gain = gain, qty = qty, spend = spend, deals = deals,
        minUnit = minUnit and math.floor(minUnit + 0.5) or nil,
        roi = spend > 0 and (gain / spend * 100) or nil }
end

-- Calcul pour un prix unitaire unique (historique) / single unit price
function A.ComputeUnit(sell, ahUnit)
    local gain = sell - ahUnit
    return { gainUnit = gain, roi = ahUnit > 0 and (gain / ahUnit * 100) or nil }
end

-- -----------------------------------------------------------------------------
-- Source 1 : annonces en cours / live replicate listings
-- -----------------------------------------------------------------------------
local function api()
    return C_AuctionHouse
end

function A.CanReplicate()
    local a = api()
    return a and type(a.ReplicateItems) == "function" and type(a.GetNumReplicateItems) == "function"
        and type(a.GetReplicateItemInfo) == "function"
end

function A.CooldownLeft()
    if not A.lastScanRequest then return 0 end
    return math.max(0, A.SCAN_COOLDOWN - (GetTime() - A.lastScanRequest))
end

-- Demande un scan complet (même requête que le scan complet d'Auctionator).
function A.RequestFullScan()
    if not A.ahOpen then return false, "Ouvrez l'hôtel des ventes." end
    if not A.CanReplicate() then return false, "API de scan complet indisponible sur ce client." end
    local left = A.CooldownLeft()
    if left > 0 then return false, string.format("Scan complet possible dans %d min.", math.ceil(left / 60)) end
    local ok, err = pcall(C_AuctionHouse.ReplicateItems)
    if not ok then return false, tostring(err) end
    A.lastScanRequest = GetTime()
    return true, "Scan complet demandé : lecture des annonces dès réception."
end

A.liveMap = {}          -- résultats compacts par objet (conservés après fermeture de l'HDV)
A.liveDirty = false

-- Prix HDV « marché » d'un objet d'après les annonces lues (sens PNJ » HDV) :
-- prix unitaire le plus bas et quantité en vente. Pour les armes et armures,
-- uniquement les annonces de la version simple (nom identique au nom de base),
-- car le marchand vend la version simple. Compact, conservé après fermeture.
A.liveUnit, A.liveQty = {}, {}

function A.IsGear(itemID)
    local inst = U.ItemInstant(itemID)
    return inst and (inst.classID == 2 or inst.classID == 4) or false
end

local function evalMarket(id, it, baseName)
    local minUnit, qty = nil, 0
    for i = 1, #it.buyouts do
        if not it.gear or it.names[i] == baseName then
            local unit = it.buyouts[i] / it.counts[i]
            if not minUnit or unit < minUnit then minUnit = unit end
            qty = qty + it.counts[i]
        end
    end
    A.liveUnit[id] = minUnit and math.floor(minUnit + 0.5) or nil
    A.liveQty[id] = minUnit and qty or nil
end

local function evalLive(id)
    local it = A.live and A.live.items[id]
    if not it then return end
    local sell, info = A.SellPrice(id)
    if not it.gear then
        if not A.liveUnit[id] then evalMarket(id, it) end
    elseif info then
        evalMarket(id, it, info.name)
        -- Photo déjà enregistrée : prix de la version simple ajouté ensuite.
        if A.liveKey and ns.Market and not A.processing then
            ns.Market.Set(A.liveKey, id, A.liveUnit[id], A.liveQty[id], A.live and A.live.time)
        end
    end
    if not sell then return end
    local r = sell > 0 and A.ComputeListings(sell, it.buyouts, it.counts) or nil
    if r and r.gain > 0 then
        r.id, r.sell, r.source, r.time = id, sell, "LIVE", A.live.time
        r.gainUnit = sell - r.minUnit
        A.liveMap[id] = r
    else
        A.liveMap[id] = nil
    end
    A.liveDirty = true
end

local function buildLiveResults()
    A.liveMap = {}
    A.liveUnit, A.liveQty = {}, {}
    if A.live then
        for id in pairs(A.live.items) do evalLive(id) end
    end
    A.liveDirty = true
end

-- Lecture découpée en tranches (aucun gel du jeu), annulable.
-- Chunked, cancellable read of the replicate list.
A.cancelRequested = false
function A.ReadReplicate(force)
    if A.processing or not A.CanReplicate() then return false end
    local okN, total = pcall(C_AuctionHouse.GetNumReplicateItems)
    if not okN or type(total) ~= "number" or total <= 0 then return false end
    -- Même liste déjà lue : pas de relecture (sauf demande explicite).
    if not force and A.live and A.live.total == total and (time() - A.live.time) < A.SCAN_COOLDOWN then
        return false
    end
    A.processing, A.cancelRequested = true, false
    A.progress = { done = 0, total = total }
    -- HDV visé, figé au début de la lecture (choix du joueur ou zone).
    local marketKey = ns.Market and ns.Market.Current() or nil
    A.readingKey = marketKey
    local items, index, readAt = {}, 0, time()
    ns.Fire("ARBITRAGE_PROGRESS")
    local function step()
        if A.cancelRequested then
            A.processing, A.cancelRequested, A.progress, A.readingKey = false, false, nil, nil
            ns.Diag.Log("Lecture des annonces arrêtée par l'utilisateur.")
            ns.Fire("ARBITRAGE_CHANGED")
            return
        end
        local last = math.min(index + speed().chunk, total) - 1
        for i = index, last do
            local ok, name, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID =
                pcall(C_AuctionHouse.GetReplicateItemInfo, i)
            if ok and itemID and type(buyout) == "number" and buyout > 0 and type(count) == "number" and count > 0 then
                local it = items[itemID]
                if not it then
                    it = { buyouts = {}, counts = {}, gear = A.IsGear(itemID) }
                    if it.gear then it.names = {} end
                    items[itemID] = it
                end
                local n = #it.buyouts + 1
                it.buyouts[n] = buyout
                it.counts[n] = count
                -- Armes et armures : le nom complet distingue la version simple
                -- des variantes à suffixe (« … de l'aigle »).
                if it.gear then it.names[n] = name end
            end
        end
        index = last + 1
        A.progress.done = index
        if index < total then
            C_Timer.After(0, step)
        else
            A.live = { time = readAt, total = total, items = items }
            A.liveTime, A.liveTotal = readAt, total
            A.processing, A.progress, A.readingKey = false, nil, nil
            buildLiveResults()
            -- Photo du marché enregistrée pour l'HDV choisi (partagée par le compte).
            A.liveKey = marketKey
            if ns.Market and marketKey then ns.Market.Commit(marketKey, A.liveUnit, A.liveQty, readAt, total) end
            A.Results("live")
            ns.Diag.Log(string.format("Annonces lues : %d · %d opportunités HDV » PNJ", total, #A.liveResults))
            ns.Fire("ARBITRAGE_CHANGED")
        end
    end
    step()
    return true
end

-- Arrête TOUTE activité en arrière-plan : lecture des annonces, analyse de
-- l'historique, demandes d'infos au serveur. Les résultats déjà obtenus sont
-- conservés. Stops every background activity; results are kept.
function A.StopAll()
    local stopped = {}
    if A.processing then A.cancelRequested = true; stopped[#stopped + 1] = "lecture des annonces" end
    if A.histRunning then A.histCancel = true; stopped[#stopped + 1] = "analyse de l'historique" end
    local n = #queue
    for _ in pairs(pendingInfo) do n = math.max(n, 1) end
    if n > 0 then stopped[#stopped + 1] = "demandes d'informations au serveur" end
    wipe(queue); wipe(queued); wipe(pendingInfo)
    A.histPending = {}
    ns.Fire("ARBITRAGE_PROGRESS")
    return stopped
end

function A.IsBusy()
    return A.processing or A.histRunning or #queue > 0
end

function A.QueueSize() return #queue end

function A.CancelRead()
    if A.processing then A.cancelRequested = true; return true end
    return false
end

-- Prix de rachat arrivés plus tard : calcul de CET objet seulement
-- (plus de recalcul complet périodique), affichage regroupé toutes les 2 s.
-- Late sell price: evaluate only that item; batched UI notification.
local notifyPending = false
ns.RegisterEvent("GET_ITEM_INFO_RECEIVED", function(_, itemID)
    if not pendingInfo[itemID] then return end
    pendingInfo[itemID] = nil
    if A.live and not A.processing then evalLive(itemID) end
    A.ResolveHistPending(itemID)
    if notifyPending then return end
    notifyPending = true
    C_Timer.After(2, function()
        notifyPending = false
        ns.Fire("ARBITRAGE_CHANGED", "prices")
    end)
end)

-- Historique : objets dont le prix de rachat n'était pas encore chargé.
A.histPending = {}
function A.ResolveHistPending(onlyID)
    local function one(id, p)
        local info = U.ItemInfo(id)
        if not info then return end
        A.histPending[id] = nil
        local sell = info.sellPrice or 0
        if sell > p.price then
            local c = A.ComputeUnit(sell, p.price)
            A.histResults[#A.histResults + 1] = { id = id, sell = sell, minUnit = p.price, gainUnit = c.gainUnit,
                roi = c.roi, gain = c.gainUnit, age = p.age, source = "HIST" }
        end
    end
    if onlyID then
        local p = A.histPending[onlyID]
        if p then one(onlyID, p) end
    else
        for id, p in pairs(A.histPending) do one(id, p) end
    end
end

function A.PendingPrices()
    local n = 0
    for _ in pairs(pendingInfo) do n = n + 1 end
    return n
end

-- Le client signale la liste plusieurs fois pendant et après un scan :
-- on attend 2 s de calme, puis on lit une seule fois si la liste a changé.
-- The client fires this repeatedly: debounce, then read once if changed.
local replicateSeq = 0
ns.RegisterEvent("REPLICATE_ITEM_LIST_UPDATE", function()
    replicateSeq = replicateSeq + 1
    local mySeq = replicateSeq
    C_Timer.After(2, function()
        if mySeq == replicateSeq then A.ReadReplicate(false) end
    end)
end)
ns.RegisterEvent("AUCTION_HOUSE_SHOW", function() A.ahOpen = true; ns.Fire("AH_SHOW") end)
ns.RegisterEvent("AUCTION_HOUSE_CLOSED", function()
    A.ahOpen = false
    A.ReleaseData()
    ns.Fire("AH_CLOSED")
end)

-- Résultat « annonces » d'un objet (infobulle), conservé après fermeture.
function A.LiveFor(itemID)
    return A.liveMap[itemID]
end

-- -----------------------------------------------------------------------------
-- Source 2 : historique Auctionator / Auctionator history
-- Parcourt les objets connus de la base (≈ 15 000) + vos relevés, en tranches.
-- -----------------------------------------------------------------------------
function A.ComputeHistoric(onDone)
    local ids = {}
    local seen = {}
    local r = ns.Data.knownRanges
    for i = 1, #r - 1, 2 do
        for id = r[i], r[i] + r[i + 1] - 1 do ids[#ids + 1] = id; seen[id] = true end
    end
    if A.live then for id in pairs(A.live.items) do if not seen[id] then ids[#ids + 1] = id end end end
    seen = nil
    local out, idx = {}, 1
    A.histPending = {}
    A.histRunning, A.histCancel = true, false
    local function step()
        if A.histCancel then
            -- Arrêt demandé : les résultats précédents sont conservés.
            A.histRunning, A.histCancel = false, false
            ns.Diag.Log("Analyse de l'historique arrêtée par l'utilisateur.")
            ns.Fire("ARBITRAGE_CHANGED")
            return
        end
        local last = math.min(idx + speed().hist, #ids + 1) - 1
        for i = idx, last do
            local id = ids[i]
            local price, age = ns.Prices.Peek(id)
            if price then
                local sell = A.SellPrice(id)
                if sell == nil then A.histPending[id] = { price = price, age = age } end
                if sell and sell > price then
                    local c = A.ComputeUnit(sell, price)
                    out[#out + 1] = { id = id, sell = sell, minUnit = price, gainUnit = c.gainUnit, roi = c.roi,
                        gain = c.gainUnit, age = age, source = "HIST" }
                end
            end
        end
        idx = last + 1
        if idx <= #ids then
            C_Timer.After(0, step)
        else
            A.histResults = out
            A.histTime = time()
            A.histRunning = false
            ns.Fire("ARBITRAGE_CHANGED")
            if onDone then onDone(out) end
        end
    end
    step()
end

-- Résultats combinés : les annonces en cours priment sur l'historique.
function A.Results(mode)
    if A.liveDirty then
        local list = {}
        for _, r in pairs(A.liveMap) do list[#list + 1] = r end
        A.liveResults, A.liveDirty = list, false
    end
    local out, used = {}, {}
    if mode ~= "hist" then
        for _, r in ipairs(A.liveResults) do out[#out + 1] = r; used[r.id] = true end
    end
    if mode ~= "live" then
        for _, r in ipairs(A.histResults) do if not used[r.id] then out[#out + 1] = r end end
    end
    return out
end

-- -----------------------------------------------------------------------------
-- Recherche d'un objet dans l'HDV / AH search for an item
-- 1. API publique d'Auctionator (onglet Achats) ; 2. barre de recherche Blizzard.
-- -----------------------------------------------------------------------------
function A.Search(itemID)
    local info = U.ItemInfo(itemID)
    local name = info and info.name or ns.Data.names[itemID]
    if not name then U.RequestItem(itemID); return false, "Nom de l'objet en cours de chargement, réessayez." end
    if not A.ahOpen then return false, "Ouvrez l'hôtel des ventes." end
    -- Recherche NON exacte : affiche aussi les variantes à suffixe
    -- (« Bâtarde aiguisée de l'aigle »…), comme une recherche manuelle.
    local a = Auctionator and Auctionator.API and Auctionator.API.v1
    if a and type(a.MultiSearch) == "function" then
        local ok = pcall(a.MultiSearch, ns.callerID, { name })
        if ok then return true, "Recherche Auctionator : " .. name end
    end
    local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
    if bar and bar.SearchBox and bar.StartSearch then
        local ok = pcall(function()
            bar.SearchBox:SetText(name)
            bar:StartSearch()
        end)
        if ok then return true, "Recherche HDV : " .. name end
    end
    return false, "Recherche automatique indisponible : cherchez « " .. name .. " »."
end

-- Recherche de plusieurs objets d'un coup (liste d'achats). Auctionator :
-- une seule recherche groupée ; sans Auctionator, la barre de l'HDV ne peut
-- chercher qu'un nom à la fois (premier objet). Achat toujours manuel.
-- Multi-item search (shopping list).
function A.SearchMany(ids)
    if not A.ahOpen then return false, "Ouvrez l'hôtel des ventes." end
    local names, missing = {}, 0
    for _, id in ipairs(ids) do
        local info = U.ItemInfo(id)
        local name = info and info.name or ns.Data.names[id]
        if name then names[#names + 1] = name else missing = missing + 1; U.RequestItem(id) end
    end
    if #names == 0 then return false, "Noms des objets en cours de chargement, réessayez." end
    local extra = missing > 0 and string.format(" (%d nom(s) en chargement, relancez dans un instant)", missing) or ""
    local a = Auctionator and Auctionator.API and Auctionator.API.v1
    if a and type(a.MultiSearch) == "function" then
        local ok = pcall(a.MultiSearch, ns.callerID, names)
        if ok then return true, string.format("Recherche Auctionator : %d objet(s)%s.", #names, extra) end
    end
    local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
    if bar and bar.SearchBox and bar.StartSearch then
        local ok = pcall(function() bar.SearchBox:SetText(names[1]); bar:StartSearch() end)
        if ok then return true, "Sans Auctionator, l'HDV cherche un objet à la fois : " .. names[1] .. ". Utilisez les loupes pour les autres." end
    end
    return false, "Recherche automatique indisponible."
end

-- Diagnostic de l'API d'HDV (/sgl hdv) / AH API diagnostic
function A.Report()
    local L = {}
    local function add(s) L[#L + 1] = s end
    local function yes(v) return v and "oui" or "non" end
    add(ns.title .. " " .. ns.version .. " — diagnostic de l'hôtel des ventes (" .. date("%Y-%m-%d %H:%M") .. ")")
    add("HDV ouvert : " .. yes(A.ahOpen) .. " · AuctionHouseFrame : " .. yes(AuctionHouseFrame)
        .. " · barre de recherche : " .. yes(AuctionHouseFrame and AuctionHouseFrame.SearchBar and AuctionHouseFrame.SearchBar.StartSearch))
    local a = C_AuctionHouse
    add("C_AuctionHouse : " .. yes(a) .. " · ReplicateItems : " .. yes(a and a.ReplicateItems)
        .. " · GetNumReplicateItems : " .. yes(a and a.GetNumReplicateItems) .. " · GetReplicateItemInfo : " .. yes(a and a.GetReplicateItemInfo))
    if a and a.GetNumReplicateItems then
        local ok, n = pcall(a.GetNumReplicateItems)
        add("Annonces chargées dans le client : " .. tostring(ok and n or ("erreur " .. tostring(n))))
        if ok and type(n) == "number" and n > 0 then
            local vals = { pcall(a.GetReplicateItemInfo, 0) }
            local parts = {}
            for i = 2, #vals do parts[#parts + 1] = (i - 1) .. "=" .. type(vals[i]) .. ":" .. tostring(vals[i]) end
            add("Exemple d'annonce (index 0) : " .. table.concat(parts, " · "))
        end
    end
    local v1 = Auctionator and Auctionator.API and Auctionator.API.v1
    add("Auctionator MultiSearch : " .. yes(v1 and v1.MultiSearch) .. " · prix de rachat : C_Item.GetItemInfo (jeu) uniquement")
    A.Results("live")
    add("Dernière lecture : " .. (A.liveTime and (date("%H:%M:%S", A.liveTime) .. " · " .. (A.liveTotal or 0) .. " annonces · " .. #A.liveResults .. " opportunités"
        .. (A.live and "" or " · données brutes libérées")) or "aucune"))
    add("Historique : " .. #A.histResults .. " opportunités" .. (A.histTime and (" · calculé à " .. date("%H:%M:%S", A.histTime)) or ""))
    if ns.Market then
        local MK = ns.Market
        local zone, mapID = MK.ZoneKey()
        add("Serveur : " .. MK.Realm() .. " · carte " .. tostring(mapID) .. " · zone = " .. MK.Label(zone)
            .. " · choix du personnage : " .. tostring(MK.Choice() or "selon la zone") .. " · prochain scan : " .. MK.Label(MK.Current()))
        for _, key in ipairs(MK.KEYS) do add(MK.Label(key) .. " : " .. MK.Describe(key):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    end
    add("Scan demandé par Gold Lens : " .. (A.lastScanRequest and (math.floor(GetTime() - A.lastScanRequest) .. " s") or "jamais"))
    return table.concat(L, "\n")
end
