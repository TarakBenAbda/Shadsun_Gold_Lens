-- =============================================================================
-- Shadsun Gold Lens — Core/Market.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Marchés de l'hôtel des ventes, par serveur et par HDV.
--      Chaque lecture des annonces (scan complet) est enregistrée comme une
--      « photo » compacte du marché : prix unitaire le plus bas et quantité
--      totale en vente, par objet, avec l'heure du scan et le personnage.
--      Données communes à tout le compte (ShadsunGoldLensGlobal.markets),
--      rangées par serveur puis par HDV :
--        "A" = HDV Alliance · "H" = HDV Horde · "N" = HDV neutre
--      L'HDV visé par un scan est choisi par le joueur (mémorisé pour chaque
--      personnage), prérempli d'après la zone : Baie-du-Butin, Gadgetzan et
--      Long-guet = HDV neutre ; toute autre zone = HDV de la faction.
--      Rien n'est inventé : sans scan, aucun prix de marché.
-- EN : Per-realm, per-auction-house market snapshots shared by the account.
-- =============================================================================
local _, ns = ...
local U = ns.U
local MK = {}
ns.Market = MK

MK.KEYS = { "A", "H", "N" }
MK.RETENTION_DAYS = 30          -- photos plus anciennes supprimées au démarrage

-- Cartes des HDV neutres (identifiants Classic et identifiants du client moderne).
-- Neutral auction house maps (Classic and modern uiMapIDs).
MK.NEUTRAL_MAPS = {
    [1434] = "Strangleronce (Baie-du-Butin)", [1446] = "Tanaris (Gadgetzan)", [1452] = "Berceau-de-l'Hiver (Long-guet)",
    [210] = "Cap Strangleronce (Baie-du-Butin)", [224] = "Strangleronce (Baie-du-Butin)",
    [71] = "Tanaris (Gadgetzan)", [83] = "Berceau-de-l'Hiver (Long-guet)",
}

local function G() return ns.DB and ns.DB.G end
local function C() return ns.DB and ns.DB.C end

-- -----------------------------------------------------------------------------
-- Libellés / labels
-- -----------------------------------------------------------------------------
local NAMES = { A = "Alliance", H = "Horde", N = "neutre" }
local COLORS = { A = "alliance", H = "horde", N = "neutral" }

function MK.Label(key) return "HDV " .. (NAMES[key] or "?") end
function MK.Short(key) return key == "N" and "Neutre" or (NAMES[key] or "?") end
function MK.ColorLabel(key, short)
    return U.Color(U.colors[COLORS[key] or "dim"], short and MK.Short(key) or MK.Label(key))
end

-- Icônes de faction fournies par le jeu (aucun fichier copié) / in-game faction icons
MK.ICONS = {
    A = "Interface\\FriendsFrame\\PlusManz-Alliance",
    H = "Interface\\FriendsFrame\\PlusManz-Horde",
    N = "Interface\\Icons\\INV_Misc_Coin_01",
}
function MK.Icon(key, size)
    local tex = MK.ICONS[key]
    if not tex then return "" end
    size = size or 14
    return "|T" .. tex .. ":" .. size .. ":" .. size .. "|t "
end
function MK.IconLabel(key, short, size)
    return MK.Icon(key, size) .. MK.ColorLabel(key, short)
end

-- Faction du personnage connecté ("A" ou "H") / player faction key
function MK.PlayerKey()
    local s = U.PlayerSide()
    return (s == "A" or s == "H") and s or "A"
end

-- Commission de vente de l'HDV (fraction) / auction cut of a market
function MK.Rate(key)
    local pct = key == "N" and ns.DB.Num("economy", "commissionNeutral") or ns.DB.Num("economy", "commissionFaction")
    return (pct or 0) / 100, pct
end

-- -----------------------------------------------------------------------------
-- Choix de l'HDV : zone + bouton / which auction house a scan belongs to
-- -----------------------------------------------------------------------------
-- Suggestion d'après la zone (carte du joueur et cartes parentes).
-- Returns key, mapID.
function MK.ZoneKey()
    local mapID
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
        if ok and type(m) == "number" then mapID = m end
    end
    local id, depth = mapID, 0
    while id and depth < 4 do
        if MK.NEUTRAL_MAPS[id] then return "N", mapID end
        local info = C_Map and C_Map.GetMapInfo and select(2, pcall(C_Map.GetMapInfo, id))
        id = type(info) == "table" and info.parentMapID or nil
        depth = depth + 1
    end
    return MK.PlayerKey(), mapID
end

-- Choix mémorisé du personnage : "faction", "neutral" ou nil (selon la zone).
function MK.Choice() local c = C(); return c and c.ahMarket or nil end

function MK.SetChoice(v)
    local c = C()
    if not c then return end
    local before = MK.Current()
    c.ahMarket = (v == "faction" or v == "neutral") and v or nil
    local after = MK.Current()
    -- Scan de la visite en cours (HDV encore ouvert) attribué au mauvais HDV :
    -- on le déplace. Un scan d'une visite précédente n'est jamais déplacé.
    -- Scan of the current AH visit filed under the wrong market: move it.
    local A = ns.Arbitrage
    if A and A.ahOpen and A.live and A.liveKey and A.liveKey == before and before ~= after and A.liveTime and MK.lastCommit
        and MK.lastCommit.key == before and MK.lastCommit.time == A.liveTime then
        MK.Move(before, after)
        A.liveKey = after
        U.Print(string.format("dernier scan déplacé vers %s.", MK.Label(after)))
    end
    ns.Fire("MARKET_CHANGED")
end

-- HDV visé par le prochain scan / market of the next scan
function MK.Current()
    local v = MK.Choice()
    if v == "neutral" then return "N" end
    if v == "faction" then return MK.PlayerKey() end
    return (MK.ZoneKey())
end

-- Vrai si le choix du joueur contredit la zone (avertissement, sans blocage).
function MK.Mismatch()
    if not MK.Choice() then return false end
    local zone = MK.ZoneKey()
    local cur = MK.Current()
    if zone ~= cur then return true, zone end
    return false
end

-- HDV de revente pour les calculs PNJ » HDV (paramètre « Marché de revente »).
function MK.SellKey()
    return (ns.settings and ns.settings.economy.market == "neutral") and "N" or MK.PlayerKey()
end

-- -----------------------------------------------------------------------------
-- Stockage / storage
-- -----------------------------------------------------------------------------
function MK.Realm() return U.Realm() end

local function realmStore(realm, create)
    local g = G()
    if not g then return nil end
    realm = realm or MK.Realm()
    local r = g.markets[realm]
    if not r and create then r = {}; g.markets[realm] = r end
    return r
end

-- Photo d'un HDV / market snapshot: { time, total, char, d = { [itemID] = valeur } }
-- Prix et quantité tiennent dans un seul nombre (mémoire et SavedVariables
-- divisées par deux) : valeur = prix × 100 000 + quantité. Toutes les valeurs
-- restent sous 10^14, donc exactes même écrites avec 14 chiffres significatifs.
-- Price and quantity packed in one number below 1e14: price * 1e5 + qty.
local QBITS = 100000             -- quantité max 99 999
local PMAX = 999999999           -- prix max ≈ 99 999 po (plafonné au-delà)
MK.QBITS, MK.PMAX = QBITS, PMAX

function MK.Pack(price, qty)
    price = math.min(math.max(math.floor(price + 0.5), 0), PMAX)
    qty = math.min(math.max(math.floor(qty or 0), 0), QBITS - 1)
    return price * QBITS + qty
end

function MK.Unpack(v)
    if not v then return nil end
    local q = v % QBITS
    return (v - q) / QBITS, q
end
local unpackV = MK.Unpack

function MK.Get(key, realm)
    local r = realmStore(realm)
    return r and r[key] or nil
end

-- -----------------------------------------------------------------------------
-- Prix externes : API Blizzard ou Forever AH / external prices
-- Le module facultatif « ShadsunGoldLens_Prix », écrit hors du jeu par
-- l'application Shadsun Gold Lens (ou l'outil sgl_prix_api.py), définit la
-- globale ShadsunGoldLensExternal (source = « API Blizzard » ou « Forever AH ») :
--   { version = 1, generated, source, region = "eu", rulesetName,
--     markets = { A = { time, total, house, d = { [itemID] = valeur } }, H = …, N = … } }
-- Ces prix concernent le marché pour lequel l'outil a été configuré (région,
-- type de serveur). Un add-on ne peut pas accéder à Internet : ils ne sont
-- mis à jour qu'au chargement (connexion ou /reload).
-- -----------------------------------------------------------------------------
MK.ext = nil
MK.extStatus = "absent"

-- Région du client (« EU », « US »…), si le jeu la fournit.
function MK.ClientRegion()
    if GetCurrentRegionName then
        local ok, r = pcall(GetCurrentRegionName)
        if ok and type(r) == "string" and r ~= "" then return r:upper() end
    end
    return nil
end

function MK.LoadExternal()
    MK.ext, MK.extStatus = nil, "absent"
    local x = rawget(_G, "ShadsunGoldLensExternal")
    if type(x) ~= "table" then return end
    if x.version ~= 1 or type(x.markets) ~= "table" then MK.extStatus = "format inconnu"; return end
    local region = MK.ClientRegion()
    if region and type(x.region) == "string" and x.region:upper() ~= region then
        MK.extStatus = "région " .. x.region:upper() .. " différente du client (" .. region .. ")"
        return
    end
    local limit = time() - MK.RETENTION_DAYS * 86400
    local out = {}
    -- Source : « API Blizzard » (clé de l'utilisateur) ou « Forever AH » (sans compte)
    local srcName = (type(x.source) == "string" and x.source ~= "") and x.source or "API Blizzard"
    for _, key in ipairs(MK.KEYS) do
        local m = x.markets[key]
        if type(m) == "table" and type(m.d) == "table" and type(m.time) == "number" and m.time >= limit then
            out[key] = { time = m.time, total = m.total or 0, char = srcName, d = m.d, source = "api", house = m.house,
                         v = type(m.v) == "table" and m.v or nil, s = type(m.s) == "table" and m.s or nil }
        end
    end
    MK.ext = out
    MK.extStatus = "ok"
    MK.extInfo = { generated = x.generated, region = x.region, ruleset = x.rulesetName, source = srcName }
end
ns.OnLogin(function() MK.LoadExternal(); ns.Fire("MARKET_CHANGED") end)

-- Prix externes d'un HDV (serveur du personnage) / external snapshot
function MK.External(key) return MK.ext and MK.ext[key] or nil end

-- Photo d'un HDV pour le serveur actuel : votre scan et l'API fusionnés.
-- Pour chaque objet, la donnée la plus récente qui le contient : un objet
-- absent de la photo la plus récente (ex. une arme que l'API n'a pas retenue)
-- garde le prix de l'autre photo, avec l'âge et la source de celle-ci.
-- Avant 0.14 : tout ou rien (la photo la plus récente masquait l'autre).
-- Merged snapshot: per item, the freshest source that has it.
local mergeCache = {}
function MK.Snap(key)
    local own, ext = MK.Get(key), MK.External(key)
    if not (own and ext) then return own or ext end
    local c = mergeCache[key]
    if c and c.own == own and c.ext == ext and c.ot == own.time and c.et == ext.time then return c.snap end
    local new, old = own, ext
    if ext.time > own.time then new, old = ext, own end
    local d, fromOld = {}, {}
    for id, v in pairs(old.d) do d[id] = v; fromOld[id] = true end
    for id, v in pairs(new.d) do d[id] = v; fromOld[id] = nil end
    local snap = { time = new.time, total = new.total, char = new.char, source = new.source, house = new.house,
                   d = d, v = ext.v, s = ext.s, older = old, fromOld = fromOld }
    mergeCache[key] = { own = own, ext = ext, ot = own.time, et = ext.time, snap = snap }
    return snap
end
function MK.InvalidateSnap(key) if key then mergeCache[key] = nil else mergeCache = {} end end

-- Photo d'où vient le prix d'un objet (pour l'âge et la source affichés).
function MK.ItemSnap(s, itemID)
    if s and s.fromOld and s.fromOld[itemID] then return s.older end
    return s
end

-- -----------------------------------------------------------------------------
-- Indicateurs de marché (Forever AH, via l'application) / market indicators
--   ventes par jour (estimation) et valeur habituelle (moyenne pondérée sur
--   14 jours du 10e centile). Seuils de l'écart à la valeur habituelle :
--   ≥ 15 % en dessous = bonne affaire ; ≥ 25 % au-dessus = prix gonflé.
-- -----------------------------------------------------------------------------
MK.DEAL_PCT, MK.HIGH_PCT = -15, 25

-- Ventes par jour (nombre, décimales) et valeur habituelle (pc) d'un objet.
function MK.Stats(s, itemID)
    if not s or not s.s or not itemID then return nil end
    local mv, spd10 = unpackV(s.s[itemID])
    if not mv then return nil end
    return (spd10 or 0) / 10, (mv and mv > 0) and mv or nil
end
function MK.KeyStats(key, itemID) return MK.Stats(MK.Snap(key), itemID) end

-- Écart (%) d'un prix à la valeur habituelle / deviation from usual value
function MK.ValueDelta(unit, usual)
    if not unit or not usual or usual <= 0 then return nil end
    return (unit / usual - 1) * 100
end

function MK.SalesText(spd)
    if not spd then return U.Color(U.colors.dim, "ventes inconnues") end
    local n = (spd >= 10) and tostring(math.floor(spd + 0.5)) or (string.format("%.1f", spd):gsub("%.0$", ""):gsub("%.", ","))
    return n .. (spd >= 2 and " ventes/j" or " vente/j")
end

-- Texte de l'écart : vert (bonne affaire), orange (gonflé), gris (habituel)
function MK.DeltaText(pct, short)
    if not pct then return "" end
    local n = math.floor(math.abs(pct) + 0.5)
    if pct <= MK.DEAL_PCT then
        return U.Color(U.colors.good, short and ("-" .. n .. " %") or (n .. " % sous la valeur habituelle"))
    elseif pct >= MK.HIGH_PCT then
        return U.Color(U.colors.warn, short and ("+" .. n .. " %") or (n .. " % au-dessus de la valeur habituelle"))
    end
    return U.Color(U.colors.dim, short and ((pct >= 0 and "+" or "-") .. n .. " %") or "au prix habituel")
end

-- Quantité conseillée : environ N jours de ventes (paramètre « adviceDays »)
function MK.Advice(spd)
    if not spd or spd <= 0 then return nil end
    local days = ns.DB and ns.DB.Num("economy", "adviceDays") or 3
    return math.max(1, math.floor(spd * days + 0.5))
end

-- Prix « dès » des variantes (suffixe, bonus) d'un objet sans version simple
-- en vente (prix API uniquement). Variant-only price.
function MK.Variant(s, itemID)
    if not s or not s.v or not itemID then return nil end
    return unpackV(s.v[itemID])
end

-- Nom de la source des prix externes (« API Blizzard », « Forever AH »)
function MK.ExternalName()
    return (MK.extInfo and MK.extInfo.source) or "API Blizzard"
end

-- Mention à afficher quand les prix viennent de Forever AH (demandée par le site)
MK.FAH_CREDIT = "Prix : Forever AH (forever-ah.com), données de l'API Battle.net de Blizzard."

-- Libellé de la source d'une photo / source label
function MK.SourceText(s)
    if not s then return "" end
    local lab = "scan"
    if s.source == "api" then lab = (s.char == "Forever AH") and "Forever AH" or "API" end
    return lab .. ", " .. U.Ago(s.time)
end

-- Prix unitaire le plus bas et quantité d'un objet dans une photo.
function MK.Item(s, itemID)
    if not s or not itemID then return nil end
    return unpackV(s.d[itemID])
end

-- Prix unitaire le plus bas, quantité en vente, heure du scan.
function MK.Price(itemID, key, realm)
    local s = realm and MK.Get(key, realm) or MK.Snap(key)
    if not s or not itemID then return nil end
    local p, q = unpackV(s.d[itemID])
    return p, q, MK.ItemSnap(s, itemID).time
end

-- Ajoute ou corrige un objet de la photo (prix d'équipement évalués après la
-- lecture, une fois le nom de l'objet chargé). Late gear prices.
function MK.Set(key, itemID, price, qty, readAt)
    local s = MK.Get(key)
    if not s or (readAt and s.time ~= readAt) then return end
    if price then s.d[itemID] = MK.Pack(price, qty) else s.d[itemID] = nil end
    MK.InvalidateSnap(key)
end

-- Âge en jours (entier) / age in whole days
function MK.AgeDays(t) return t and math.floor(math.max(0, time() - t) / 86400) or nil end

function MK.IsStale(t)
    local days = ns.DB.Num("economy", "staleDays") or 7
    return t and (time() - t) > days * 86400 or false
end

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

MK.prev = {}        -- photo remplacée pendant la session (pour un déplacement)
MK.lastCommit = nil

-- Enregistre le résultat d'une lecture (prix unitaires p, quantités q).
-- Stores a read: unit prices p and quantities q, packed.
function MK.Commit(key, p, q, readAt, total)
    local r = realmStore(nil, true)
    if not r or not key then return end
    local d = {}
    for id, price in pairs(p) do d[id] = MK.Pack(price, q[id]) end
    MK.prev[key] = r[key] or false
    r[key] = { time = readAt or time(), total = total or 0, char = UnitName and UnitName("player") or "?", d = d }
    MK.lastCommit = { key = key, time = readAt }
    ns.Diag.Log(string.format("Marché enregistré : %s · %s annonces", MK.Label(key), U.Group(total or 0)))
    ns.Fire("MARKET_CHANGED")
end

-- Déplace la photo d'un HDV vers un autre (choix corrigé après le scan) et
-- rétablit la photo précédente de l'HDV d'origine.
function MK.Move(from, to)
    local r = realmStore(nil, true)
    if not r or not r[from] or from == to then return false end
    MK.prev[to] = r[to] or false
    r[to] = r[from]
    r[from] = MK.prev[from] or nil
    MK.prev[from] = nil
    MK.lastCommit = { key = to, time = r[to].time }
    return true
end

function MK.Delete(key, realm)
    local r = realmStore(realm)
    if r then r[key] = nil end
    MK.prev[key] = nil
    ns.Fire("MARKET_CHANGED")
end

-- Nombre d'objets distincts d'une photo (mis en cache) / distinct items
local countCache = setmetatable({}, { __mode = "k" })
function MK.ItemCount(s)
    if not s then return 0 end
    local c = countCache[s]
    if not c or c.t ~= s.time then
        c = { t = s.time, n = count(s.d) }
        countCache[s] = c
    end
    return c.n
end

-- Description d'une photo pour l'interface / snapshot summary text
function MK.Describe(key, realm)
    local s = MK.Get(key, realm)
    if not s then return U.Color(U.colors.dim, "aucun scan enregistré") end
    local age = U.Ago(s.time)
    if MK.IsStale(s.time) then age = U.Color(U.colors.warn, age .. ", ancien") end
    return string.format("%s annonces · %s objets · %s · %s (%s)", U.Group(s.total or 0), U.Group(MK.ItemCount(s)),
        tostring(s.char or "?"), date("%d/%m %H:%M", s.time), age)
end

-- HDV affichés dans l'infobulle : faction du personnage, neutre, et
-- (option) l'autre faction si elle a été scannée sur ce serveur.
function MK.TooltipKeys()
    local mine = MK.PlayerKey()
    local keys = { mine, "N" }
    if ns.settings and ns.settings.tooltip.showOtherFaction then
        keys[#keys + 1] = (mine == "A") and "H" or "A"
    end
    return keys
end

-- Nettoyage des SavedVariables : clés internes et photos trop anciennes.
local function cleanup()
    local g = G()
    if not g then return end
    local limit = time() - MK.RETENTION_DAYS * 86400
    for _, markets in pairs(g.markets) do
        for key, s in pairs(markets) do
            if type(s) ~= "table" or type(s.d) ~= "table" or (s.time or 0) < limit then
                markets[key] = nil
            end
        end
    end
end
ns.OnInit(cleanup)

-- -----------------------------------------------------------------------------
-- Arbitrage HDV » HDV / cross-market arbitrage
-- -----------------------------------------------------------------------------
-- Paires d'HDV disponibles (scan ou API). Le transfert Alliance <-> Horde ne
-- passe pas par le courrier : opération marquée « indirecte ».
function MK.Pairs()
    local out = {}
    for _, b in ipairs(MK.KEYS) do
        for _, s in ipairs(MK.KEYS) do
            if b ~= s and MK.Snap(b) and MK.Snap(s) then
                out[#out + 1] = { buy = b, sell = s, direct = not ((b == "A" and s == "H") or (b == "H" and s == "A")) }
            end
        end
    end
    return out
end

-- Calcul pur pour un objet / pure computation for one item
-- Gain unitaire = prix de revente - commission (arrondie au supérieur) - prix d'achat.
function MK.CrossUnit(buyUnit, sellUnit, rate)
    local cut = math.ceil(sellUnit * rate - 1e-9)
    local gain = sellUnit - cut - buyUnit
    return gain, cut, buyUnit > 0 and (gain / buyUnit * 100) or nil
end

-- Sens d'arbitrage du personnage : "FN" = faction » neutre, "NF" = neutre » faction.
function MK.DirectionPair(dir)
    local mine = MK.PlayerKey()
    if dir == "NF" then return "N", mine end
    return mine, "N"
end

-- Toutes les opportunités HDV » HDV (gain > 0). pairFilter : nil (toutes) ou
-- "A>N", "N>A", etc. Chaque ligne porte aussi le prix de l'autre faction
-- (repère : ce que ses joueurs paient chez eux), s'il est connu.
function MK.Cross(pairFilter)
    local rows = {}
    for _, pr in ipairs(MK.Pairs()) do
        local tag = pr.buy .. ">" .. pr.sell
        if not pairFilter or pairFilter == tag then
            local B, S = MK.Snap(pr.buy), MK.Snap(pr.sell)
            local mine = MK.PlayerKey()
            local refKey = (mine == "A") and "H" or "A"
            local R = (pr.buy ~= refKey and pr.sell ~= refKey) and MK.Snap(refKey) or nil
            local RD = R and R.d
            local rate = MK.Rate(pr.sell)
            local oldest = math.min(B.time or 0, S.time or 0)
            local SD = S.d
            for id, bv in pairs(B.d) do
                local sv = SD[id]
                -- Préfiltre rapide : le prix domine la valeur emballée.
                if sv and sv > bv then
                    local buyUnit, qty = unpackV(bv)
                    local sellUnit, sellQty = unpackV(sv)
                    local gain, cut, roi = MK.CrossUnit(buyUnit, sellUnit, rate)
                    if gain > 0 then
                        local ref, refQty
                        if RD and RD[id] then ref, refQty = unpackV(RD[id]) end
                        -- Âge et source réels de chaque prix (photos fusionnées scan / API)
                        local bs, ss = MK.ItemSnap(B, id), MK.ItemSnap(S, id)
                        rows[#rows + 1] = { id = id, buy = pr.buy, sell = pr.sell, pair = tag, direct = pr.direct,
                            buyUnit = buyUnit, sellUnit = sellUnit, cut = cut, gain = gain, roi = roi,
                            qty = qty, sellQty = sellQty, time = oldest, ref = ref, refQty = refQty, refKey = R and refKey or nil,
                            buySrc = bs.source, sellSrc = ss.source, buyTime = bs.time, sellTime = ss.time }
                    end
                end
            end
        end
    end
    return rows
end
