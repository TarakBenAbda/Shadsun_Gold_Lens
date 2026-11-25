-- =============================================================================
-- Shadsun Gold Lens — Core/Lists.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Listes d'achats, communes à tous les personnages du compte
--      (ShadsunGoldLensGlobal.lists). Plusieurs listes ; une liste « active »
--      reçoit les ajouts (icônes + et - des tableaux, Alt+clic sur un
--      objet ; un objet déjà présent voit sa quantité augmenter).
--      Chaque article : objet, quantité voulue, prix maximum facultatif.
--      Le suivi (« 8 / 20 ») utilise le nombre possédé par vos personnages
--      du serveur. Aucun achat automatique : la recherche et l'achat restent
--      manuels.
-- EN : Account-wide shopping lists (multiple lists, one active list).
-- =============================================================================
local _, ns = ...
local U = ns.U
local LS = {}
ns.Lists = LS

LS.DEFAULT_NAME = "Ma liste"

local function store()
    local g = ns.DB and ns.DB.G
    if not g then return nil end
    local s = g.lists
    if type(s) ~= "table" then s = {}; g.lists = s end
    s.byId = type(s.byId) == "table" and s.byId or {}
    s.order = type(s.order) == "table" and s.order or {}
    s.nextId = tonumber(s.nextId) or 1
    return s
end

local function changed() ns.Fire("LISTS_CHANGED") end

-- Vérifie la structure et garde au moins une liste / sanity + one list minimum
local function normalize()
    local s = store()
    if not s then return end
    local seen, order = {}, {}
    for _, lid in ipairs(s.order) do
        if type(s.byId[lid]) == "table" and not seen[lid] then seen[lid] = true; order[#order + 1] = lid end
    end
    for lid, l in pairs(s.byId) do
        if type(l) == "table" and not seen[lid] then seen[lid] = true; order[#order + 1] = lid end
    end
    s.order = order
    for _, lid in ipairs(order) do
        local l = s.byId[lid]
        l.name = (type(l.name) == "string" and l.name ~= "") and l.name or LS.DEFAULT_NAME
        local items = {}
        for _, e in ipairs(type(l.items) == "table" and l.items or {}) do
            if type(e) == "table" and type(e.id) == "number" then
                e.qty = math.max(1, math.floor(tonumber(e.qty) or 1))
                e.max = tonumber(e.max)
                items[#items + 1] = e
            end
        end
        l.items = items
    end
    if #order == 0 then
        local lid = tostring(s.nextId)
        s.nextId = s.nextId + 1
        s.byId[lid] = { name = LS.DEFAULT_NAME, items = {} }
        s.order = { lid }
    end
    if not s.byId[s.active or ""] then s.active = s.order[1] end
end
ns.OnInit(normalize)

-- Listes dans l'ordre / lists in order: { {id, name, items}, … }
function LS.All()
    local s = store()
    if not s then return {} end
    local out = {}
    for _, lid in ipairs(s.order) do
        local l = s.byId[lid]
        if l then out[#out + 1] = { id = lid, name = l.name, items = l.items } end
    end
    return out
end

function LS.Get(lid)
    local s = store()
    return s and s.byId[lid] or nil
end

function LS.ActiveId() local s = store(); return s and s.active end
function LS.Active() return LS.Get(LS.ActiveId()) end

function LS.SetActive(lid)
    local s = store()
    if s and s.byId[lid] then s.active = lid; changed() end
end

local function cleanName(name)
    name = U.Trim(tostring(name or "")):gsub("[|\n\r]", "")
    if name == "" then return nil end
    return name:sub(1, 40)
end

function LS.Create(name)
    local s = store()
    if not s then return nil end
    local lid = tostring(s.nextId)
    s.nextId = s.nextId + 1
    s.byId[lid] = { name = cleanName(name) or ("Liste " .. lid), items = {} }
    s.order[#s.order + 1] = lid
    s.active = lid
    changed()
    return lid
end

function LS.Rename(lid, name)
    local l = LS.Get(lid)
    local n = cleanName(name)
    if l and n then l.name = n; changed(); return true end
    return false
end

function LS.Duplicate(lid)
    local l = LS.Get(lid)
    if not l then return nil end
    local new = LS.Create(l.name .. " (copie)")
    local d = LS.Get(new)
    for _, e in ipairs(l.items) do d.items[#d.items + 1] = { id = e.id, qty = e.qty, max = e.max } end
    changed()
    return new
end

function LS.Delete(lid)
    local s = store()
    if not s or not s.byId[lid] then return false end
    s.byId[lid] = nil
    for i, v in ipairs(s.order) do if v == lid then table.remove(s.order, i); break end end
    normalize()
    changed()
    return true
end

-- Article d'une liste / list entry
function LS.Entry(lid, itemID)
    local l = LS.Get(lid)
    if not l then return nil end
    for i, e in ipairs(l.items) do if e.id == itemID then return e, i end end
    return nil
end

local function itemName(itemID)
    local info = U.ItemInfo(itemID)
    if not info then U.RequestItem(itemID) end
    return (info and info.name) or (ns.Data.names and ns.Data.names[itemID]) or ("objet n° " .. itemID)
end

-- Ce que vous avez déjà : « sacs 2 · banque 5 · autres persos 3 · en vente 6 »
-- What you already have (bags, bank, other characters, on sale).
function LS.HaveText(itemID)
    local parts = {}
    local INV = ns.Inventory
    if INV and INV.Breakdown then
        local bags, bank, others = INV.Breakdown(itemID)
        parts[#parts + 1] = "sacs " .. bags
        if bank > 0 then parts[#parts + 1] = "banque " .. bank end
        if others > 0 then parts[#parts + 1] = "autres persos " .. others end
    end
    local sale = ns.Auctions and ns.Auctions.Short(itemID)
    if sale then parts[#parts + 1] = "en vente " .. sale end
    return table.concat(parts, " · ")
end

-- Message après un ajout / retrait : « Fil de soie : 4 dans « Ma liste » — sacs 2 · … »
function LS.Message(itemID, lid)
    lid = lid or LS.ActiveId()
    local l = LS.Get(lid)
    local e = LS.Entry(lid, itemID)
    local head = itemName(itemID) .. " : " .. (e and (e.qty .. " dans « " .. l.name .. " »") or ("retiré de « " .. (l and l.name or "?") .. " »"))
    local have = LS.HaveText(itemID)
    return have ~= "" and (head .. " — " .. have) or head
end

-- Ajoute qty exemplaires à la liste (active par défaut). Un objet déjà
-- présent voit sa quantité augmenter. Retourne ok, message.
-- Adds qty (existing entry: quantity increased). Returns ok, message.
function LS.Add(itemID, qty, lid)
    itemID = tonumber(itemID)
    lid = lid or LS.ActiveId()
    local l = LS.Get(lid)
    if not itemID or not l then return false, "liste introuvable." end
    qty = math.max(1, math.floor(tonumber(qty) or 1))
    local e = LS.Entry(lid, itemID)
    if e then
        e.qty = e.qty + qty
    else
        l.items[#l.items + 1] = { id = itemID, qty = qty }
    end
    changed()
    return true, LS.Message(itemID, lid)
end

-- Ajoute (delta > 0) ou retire (delta < 0) des exemplaires. Sous 1, l'objet
-- quitte la liste. Retourne ok, message.
-- Step the quantity; below 1 the entry is removed.
function LS.Step(itemID, delta, lid)
    itemID = tonumber(itemID)
    delta = math.floor(tonumber(delta) or 0)
    lid = lid or LS.ActiveId()
    local l = LS.Get(lid)
    if not itemID or not l or delta == 0 then return false, "liste introuvable." end
    if delta > 0 then return LS.Add(itemID, delta, lid) end
    local e, i = LS.Entry(lid, itemID)
    if not e then return false, itemName(itemID) .. " n'est pas dans « " .. l.name .. " »." end
    if e.qty + delta < 1 then
        table.remove(l.items, i)
    else
        e.qty = e.qty + delta
    end
    changed()
    return true, LS.Message(itemID, lid)
end

-- Quantité dans la liste active (0 si absent) / quantity in the active list
function LS.ActiveQty(itemID)
    local e = LS.Entry(LS.ActiveId(), itemID)
    return e and e.qty or 0
end

function LS.Remove(lid, itemID)
    local _, i = LS.Entry(lid, itemID)
    if i then table.remove(LS.Get(lid).items, i); changed(); return true end
    return false
end

function LS.SetQty(lid, itemID, qty)
    local e = LS.Entry(lid, itemID)
    if e then e.qty = math.max(1, math.floor(tonumber(qty) or 1)); changed() end
end

-- Prix maximum en cuivre (nil = aucun) / max price in copper
function LS.SetMax(lid, itemID, copper)
    local e = LS.Entry(lid, itemID)
    if e then e.max = (copper and copper > 0) and math.floor(copper) or nil; changed() end
end

-- Listes contenant l'objet : { {list = {id, name}, entry}, … }
function LS.Find(itemID)
    local out = {}
    for _, l in ipairs(LS.All()) do
        for _, e in ipairs(l.items) do
            if e.id == itemID then out[#out + 1] = { list = l, entry = e }; break end
        end
    end
    return out
end

-- Progression : possédé (personnages du serveur), voulu, terminé ?
function LS.Progress(e)
    local owned = ns.Inventory and ns.Inventory.Total(e.id) or 0
    return owned, e.qty, owned >= e.qty
end

-- Ensemble des objets de toutes les listes (bordure chez le marchand)
function LS.ItemSet()
    local set = {}
    for _, l in ipairs(LS.All()) do for _, e in ipairs(l.items) do set[e.id] = true end end
    return set
end

-- Texte de l'infobulle : « Ma liste 8 / 20 · Couture 0 / 5 »
function LS.TooltipText(itemID)
    local found = LS.Find(itemID)
    if #found == 0 then return nil end
    local parts = {}
    for i = 1, math.min(#found, 3) do
        local f = found[i]
        local owned, want, done = LS.Progress(f.entry)
        parts[#parts + 1] = f.list.name .. " " .. U.Color(done and U.colors.good or U.colors.title, owned .. " / " .. want)
    end
    if #found > 3 then parts[#parts + 1] = "+" .. (#found - 3) end
    return table.concat(parts, " · ")
end

-- -----------------------------------------------------------------------------
-- Alt+clic sur un objet (sacs, liens du chat, HDV…) : ajout à la liste active.
-- Jamais dans la fenêtre du marchand, où un clic modifié peut acheter.
-- Alt+click adds to the active list (never inside the merchant window).
-- -----------------------------------------------------------------------------
LS.lastAlt = nil
function LS.OnModifiedClick(link)
    if not (ns.settings and ns.settings.lists and ns.settings.lists.altClick) then return end
    if not (IsAltKeyDown and IsAltKeyDown()) then return end
    if (IsShiftKeyDown and IsShiftKeyDown()) or (IsControlKeyDown and IsControlKeyDown()) then return end
    if MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown() then return end
    local id = U.ItemID(link)
    if not id then return end
    local now = GetTime and GetTime() or 0
    if LS.lastAlt and LS.lastAlt.id == id and now - LS.lastAlt.t < 0.3 then return end
    LS.lastAlt = { id = id, t = now }
    local _, msg = LS.Add(id, 1)
    U.Print(msg)
end

ns.OnLogin(function()
    if type(HandleModifiedItemClick) == "function" and hooksecurefunc then
        hooksecurefunc("HandleModifiedItemClick", function(link) pcall(LS.OnModifiedClick, link) end)
    end
end)
