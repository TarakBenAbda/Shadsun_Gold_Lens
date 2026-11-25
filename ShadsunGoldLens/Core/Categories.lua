-- =============================================================================
-- Shadsun Gold Lens — Core/Categories.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Catégories d'objets organisées comme l'onglet « Acheter » de l'hôtel
--      des ventes : catégorie » sous-catégorie » emplacement (armures).
--      Tous les noms viennent du jeu (GetItemClassInfo, GetItemSubClassInfo,
--      noms d'emplacement du client) : ils suivront la langue du client.
--      L'arbre ne montre que les catégories réellement présentes dans les
--      données connues (catalogue des marchands et scans de l'HDV).
-- EN : Auction-house-like category tree (class » subclass » slot), names
--      from the game client, built from known items only.
-- =============================================================================
local _, ns = ...
local U = ns.U
local K = {}
ns.Categories = K

-- Ordre de l'hôtel des ventes / auction house order
K.ORDER = { 2, 4, 1, 0, 7, 6, 11, 9, 5, 3, 15, 12 }
K.SLOT_CLASS = 4   -- Armure : niveau « emplacement » / armor gets a slot level

-- Emplacements, dans l'ordre de l'HDV. INVTYPE_ROBE est rangé avec le torse.
K.SLOTS = { "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK", "INVTYPE_CHEST", "INVTYPE_BODY",
    "INVTYPE_TABARD", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET",
    "INVTYPE_FINGER", "INVTYPE_TRINKET", "INVTYPE_HOLDABLE", "INVTYPE_SHIELD", "INVTYPE_RELIC" }
local SLOT_ALIAS = { INVTYPE_ROBE = "INVTYPE_CHEST" }
local SLOT_FALLBACK = {
    INVTYPE_HEAD = "Tête", INVTYPE_NECK = "Cou", INVTYPE_SHOULDER = "Épaules", INVTYPE_CLOAK = "Dos",
    INVTYPE_CHEST = "Torse", INVTYPE_BODY = "Chemise", INVTYPE_TABARD = "Tabard", INVTYPE_WRIST = "Poignets",
    INVTYPE_HAND = "Mains", INVTYPE_WAIST = "Taille", INVTYPE_LEGS = "Jambes", INVTYPE_FEET = "Pieds",
    INVTYPE_FINGER = "Doigt", INVTYPE_TRINKET = "Bijou", INVTYPE_HOLDABLE = "Tenu(e) en main gauche",
    INVTYPE_SHIELD = "Bouclier", INVTYPE_RELIC = "Relique",
}
local SLOT_RANK = {}
for i, s in ipairs(K.SLOTS) do SLOT_RANK[s] = i end

function K.SlotName(loc)
    local v = _G[loc]
    if type(v) == "string" and v ~= "" then return v end
    return SLOT_FALLBACK[loc] or loc
end

local function normSlot(loc)
    if type(loc) ~= "string" or loc == "" then return nil end
    return SLOT_ALIAS[loc] or loc
end

-- Un objet correspond-il au filtre { class, sub, slot } (champs facultatifs) ?
function K.Match(f, itemID)
    if not f then return true end
    local inst = U.ItemInstant(itemID)
    if not inst then return false end
    if f.class ~= nil and inst.classID ~= f.class then return false end
    if f.sub ~= nil and inst.subClassID ~= f.sub then return false end
    if f.slot ~= nil and normSlot(inst.equipLoc) ~= f.slot then return false end
    return true
end

-- Libellé d'un filtre : « Armure » Tissu » Tête » / filter label
function K.Label(f)
    if not f or f.class == nil then return "Toutes" end
    local parts = { U.ClassName(f.class) or ("Catégorie " .. f.class) }
    if f.sub ~= nil then parts[#parts + 1] = U.SubClassName(f.class, f.sub) or ("#" .. f.sub) end
    if f.slot ~= nil then parts[#parts + 1] = K.SlotName(f.slot) end
    return table.concat(parts, " » ")
end

-- -----------------------------------------------------------------------------
-- Arbre construit à partir des objets connus / tree from known items
-- -----------------------------------------------------------------------------
local cache, dirty = nil, true
ns.On("MARKET_CHANGED", function() dirty = true end)
ns.On("DATA_CHANGED", function() dirty = true end)

local function knownIDs()
    local ids, seen = {}, {}
    local function add(id) if not seen[id] then seen[id] = true; ids[#ids + 1] = id end end
    if ns.Catalog and ns.Catalog.AllItemIDs then for _, id in ipairs(ns.Catalog.AllItemIDs()) do add(id) end end
    if ns.Market then
        for _, key in ipairs(ns.Market.KEYS) do
            local s = ns.Market.Snap(key)
            if s then for id in pairs(s.d) do add(id) end end
        end
    end
    local A = ns.Arbitrage
    if A then for _, r in ipairs(A.Results("all")) do add(r.id) end end
    return ids
end

-- Retourne { {class, name, subs = { {sub, name, slots = { {slot, name}, … }}, … }}, … }
function K.Tree()
    if cache and not dirty then return cache end
    local present = {}
    for _, id in ipairs(knownIDs()) do
        local inst = U.ItemInstant(id)
        if inst and inst.classID then
            local c = present[inst.classID]
            if not c then c = {}; present[inst.classID] = c end
            local sub = inst.subClassID or 0
            local s = c[sub]
            if not s then s = {}; c[sub] = s end
            if inst.classID == K.SLOT_CLASS then
                local loc = normSlot(inst.equipLoc)
                if loc and SLOT_RANK[loc] then s[loc] = true end
            end
        end
    end
    local tree = {}
    local function addClass(classID)
        local c = present[classID]
        if not c then return end
        local node = { class = classID, name = U.ClassName(classID) or ("Catégorie " .. classID), subs = {} }
        local subs = {}
        for sub in pairs(c) do subs[#subs + 1] = sub end
        table.sort(subs)
        for _, sub in ipairs(subs) do
            local sn = { sub = sub, name = U.SubClassName(classID, sub) or ("#" .. sub), slots = {} }
            local locs = {}
            for loc in pairs(c[sub]) do locs[#locs + 1] = loc end
            table.sort(locs, function(a, b) return SLOT_RANK[a] < SLOT_RANK[b] end)
            if #locs > 1 then
                for _, loc in ipairs(locs) do sn.slots[#sn.slots + 1] = { slot = loc, name = K.SlotName(loc) } end
            end
            node.subs[#node.subs + 1] = sn
        end
        tree[#tree + 1] = node
    end
    local listed = {}
    for _, classID in ipairs(K.ORDER) do addClass(classID); listed[classID] = true end
    local rest = {}
    for classID in pairs(present) do if not listed[classID] then rest[#rest + 1] = classID end end
    table.sort(rest)
    for _, classID in ipairs(rest) do addClass(classID) end
    cache, dirty = tree, false
    return tree
end

function K.Invalidate() dirty = true end
