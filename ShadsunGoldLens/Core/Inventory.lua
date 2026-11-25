-- =============================================================================
-- Shadsun Gold Lens — Core/Inventory.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Inventaire de chaque personnage du compte (sacs et banque), rangé par
--      serveur, pour connaître le nombre possédé sur tous vos personnages.
--      - Personnage connecté : nombre exact donné par le jeu (GetItemCount).
--      - Autres personnages : dernier relevé enregistré (sacs à chaque
--        changement, banque à chaque visite de la banque).
--      Seuls les personnages du même serveur sont additionnés : un objet ne
--      peut pas passer d'un serveur à l'autre.
-- EN : Account-wide per-character bag/bank snapshots, summed per realm.
-- =============================================================================
local _, ns = ...
local U = ns.U
local INV = {}
ns.Inventory = INV

local function G() return ns.DB and ns.DB.G end

function INV.Me() return (UnitName and UnitName("player")) or "?" end

local function realmChars(realm, create)
    local g = G()
    if not g then return nil end
    realm = realm or U.Realm()
    local r = g.chars[realm]
    if not r and create then r = {}; g.chars[realm] = r end
    return r
end
INV.RealmChars = realmChars

local function myRecord()
    local r = realmChars(nil, true)
    if not r then return nil end
    local me = INV.Me()
    local rec = r[me]
    if type(rec) ~= "table" then rec = {}; r[me] = rec end
    rec.side = U.PlayerSide()
    rec.bags = type(rec.bags) == "table" and rec.bags or {}
    return rec
end
INV.MyRecord = myRecord

-- -----------------------------------------------------------------------------
-- Relevé des conteneurs / container scan
-- -----------------------------------------------------------------------------
local function scanContainers(bagIDs)
    local out = {}
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return out end
    for _, bag in ipairs(bagIDs) do
        local ok, n = pcall(C_Container.GetContainerNumSlots, bag)
        if ok and type(n) == "number" then
            for slot = 1, n do
                local ok2, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
                if ok2 and type(info) == "table" and type(info.itemID) == "number" then
                    out[info.itemID] = (out[info.itemID] or 0) + (info.stackCount or 1)
                end
            end
        end
    end
    return out
end

-- Sacs : sac à dos (0), sacs 1-4, sac de composants (5).
INV.BAGS = { 0, 1, 2, 3, 4, 5 }

-- Banque du personnage (pas la banque de bataillon, commune au compte).
-- Character bank only (account/warband bank excluded).
function INV.BankBags()
    local out, seen = {}, {}
    local B = Enum and Enum.BagIndex
    if type(B) == "table" then
        for k, v in pairs(B) do
            if type(v) == "number" and type(k) == "string" and not seen[v]
                and (k == "Bank" or k == "Reagentbank" or k:match("^BankBag_%d") or k:match("^CharacterBankTab_%d")) then
                out[#out + 1] = v; seen[v] = true
            end
        end
    end
    if #out == 0 then out = { -1, -3, 6, 7, 8, 9, 10, 11 } end
    table.sort(out)
    return out
end

function INV.ScanBags()
    local rec = myRecord()
    if not rec then return end
    rec.bags = scanContainers(INV.BAGS)
    rec.time = time()
    if GetMoney then
        local ok, m = pcall(GetMoney)
        if ok and type(m) == "number" then rec.money = m end
    end
end

function INV.ScanBank()
    local rec = myRecord()
    if not rec then return end
    rec.bank = scanContainers(INV.BankBags())
    rec.bankTime = time()
end

-- -----------------------------------------------------------------------------
-- Nombre possédé / owned counts
-- -----------------------------------------------------------------------------
-- Total sur tous les personnages du serveur, et détail { {nom, n, moi}, ... }.
function INV.Count(itemID)
    local me = INV.Me()
    local bags, bank = U.Owned(itemID)
    local total = bags + bank
    local list
    if total > 0 then list = { { name = me, n = total, me = true, bags = bags, bank = bank } } end
    local r = realmChars()
    if r then
        for name, rec in pairs(r) do
            if name ~= me and type(rec) == "table" then
                local n = ((rec.bags and rec.bags[itemID]) or 0) + ((rec.bank and rec.bank[itemID]) or 0)
                if n > 0 then
                    list = list or {}
                    list[#list + 1] = { name = name, n = n }
                    total = total + n
                end
            end
        end
    end
    if list and #list > 1 then
        table.sort(list, function(a, b)
            if a.me ~= b.me then return a.me and true or false end
            if a.n ~= b.n then return a.n > b.n end
            return a.name < b.name
        end)
    end
    return total, list
end

-- Détail pour un message : sacs et banque du personnage connecté, autres
-- personnages du serveur. Breakdown: my bags, my bank, other characters.
function INV.Breakdown(itemID)
    local bags, bank = U.Owned(itemID)
    local total = INV.Total(itemID)
    return bags, bank, math.max(0, total - bags - bank)
end

-- Colonnes « Sacs » et « Vente » des tableaux : sacs du personnage connecté,
-- objets en vente (tous vos personnages du serveur). Columns for tables.
function INV.Bags(itemID)
    return (U.Owned(itemID))
end

function INV.Stock(d)
    d.bags = INV.Bags(d.id)
    local AU = ns.Auctions
    d.sale = AU and AU.Total(d.id) or 0
    d.saleText = AU and AU.Short(d.id) or nil
    return d
end

function INV.StockAll(rows)
    for _, d in ipairs(rows) do INV.Stock(d) end
end

function INV.Total(itemID)
    return (INV.Count(itemID))
end

-- Texte de l'infobulle : « 2 (sacs) · 1 (banque) » pour le seul personnage
-- connecté, sinon « 12 : Aurelia 8 · Kael 4 ».
function INV.Text(itemID)
    local total, list = INV.Count(itemID)
    if total == 0 or not list then return nil end
    if #list == 1 and list[1].me then return U.OwnedText(itemID) end
    local parts = {}
    for i = 1, math.min(#list, 4) do parts[#parts + 1] = list[i].name .. " " .. list[i].n end
    if #list > 4 then parts[#parts + 1] = "+" .. (#list - 4) end
    return total .. " : " .. table.concat(parts, " · ")
end

-- Personnages connus du serveur / known characters on this realm
function INV.Characters(realm)
    local out = {}
    local r = realmChars(realm)
    if not r then return out end
    for name, rec in pairs(r) do
        if type(rec) == "table" then out[#out + 1] = { name = name, rec = rec, me = (name == INV.Me()) and (realm == nil or realm == U.Realm()) } end
    end
    table.sort(out, function(a, b)
        if a.me ~= b.me then return a.me and true or false end
        return a.name < b.name
    end)
    return out
end

function INV.Forget(name, realm)
    local r = realmChars(realm)
    if r and name ~= INV.Me() then r[name] = nil end
    ns.Fire("INVENTORY_CHANGED")
end

-- -----------------------------------------------------------------------------
-- Événements / events (relevés regroupés, jamais à chaque emplacement)
-- -----------------------------------------------------------------------------
local bankOpen = false
local pending = false
local function scheduleScan()
    if pending then return end
    pending = true
    C_Timer.After(1, function()
        pending = false
        INV.ScanBags()
        if bankOpen then INV.ScanBank() end
        ns.Fire("INVENTORY_CHANGED")
    end)
end

ns.OnLogin(function() INV.ScanBags() end)
ns.RegisterEvent("BAG_UPDATE_DELAYED", scheduleScan)
ns.RegisterEvent("PLAYER_MONEY", function()
    local rec = myRecord()
    if rec and GetMoney then
        local ok, m = pcall(GetMoney)
        if ok and type(m) == "number" then rec.money = m end
    end
end)
ns.RegisterEvent("BANKFRAME_OPENED", function()
    bankOpen = true
    C_Timer.After(0.5, function() INV.ScanBank(); ns.Fire("INVENTORY_CHANGED") end)
end)
ns.RegisterEvent("BANKFRAME_CLOSED", function() bankOpen = false end)
ns.RegisterEvent("PLAYERBANKSLOTS_CHANGED", function() if bankOpen then scheduleScan() end end)
ns.RegisterEvent("PLAYER_LOGOUT", function()
    pcall(INV.ScanBags)
    if bankOpen then pcall(INV.ScanBank) end
end)
