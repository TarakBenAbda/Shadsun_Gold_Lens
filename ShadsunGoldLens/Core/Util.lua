-- =============================================================================
-- Shadsun Gold Lens — Core/Util.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Fonctions utilitaires : monnaie (cuivre → po/pa/pc), pourcentages,
--      identifiants d'objets, accès protégés aux API du client.
-- EN : Helpers: money formatting, percentages, item IDs, guarded API access.
-- =============================================================================
local _, ns = ...
local U = {}
ns.U = U

local floor, abs, tostring, tonumber, type = math.floor, math.abs, tostring, tonumber, type
local NBSP = "\194\160" -- espace insécable / non-breaking space

U.colors = {
    title = "ffe8bd64", gold = "ffffd100", silver = "ffc7c7cf", copper = "ffeda55f",
    good = "ff7beb96", bad = "ffff7b6e", warn = "ffffcc66", dim = "ffa0a8b4",
    text = "ffeeeeee", alliance = "ff4a9eff", horde = "ffff4a4a", neutral = "ffe0c060",
}

function U.Color(hex, text)
    return "|c" .. hex .. tostring(text) .. "|r"
end

-- Séparateur de milliers français / French thousands separator
local function group(n)
    local out, k = tostring(n), 1
    while k > 0 do
        out, k = out:gsub("^(%d+)(%d%d%d)", "%1" .. NBSP .. "%2")
    end
    return out
end
U.Group = group

-- Monnaie : entier en cuivre. Par défaut avec les icônes de pièces du jeu
-- (« 38 [argent] 77 [cuivre] », comme l'infobulle Blizzard) ; en texte
-- « 1 po 22 pa 50 pc » si l'option est désactivée ou si textOnly (chat copiable).
-- plain : chiffres sans couleur propre (pour colorer tout le montant).
-- Money: integer copper, with game coin icons by default. Pure integer math.
local COIN_ICONS = {
    po = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
    pa = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
    pc = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}
U.COIN_ICONS = COIN_ICONS
function U.Money(copper, plain, signed, textOnly)
    if copper == nil then return "—" end
    copper = floor(copper + 0.5)
    local neg = copper < 0
    local c = abs(copper)
    local g, s, cp = floor(c / 10000), floor((c % 10000) / 100), c % 100
    local icons = not textOnly and not (ns.settings and ns.settings.display and ns.settings.display.coinIcons == false)
    local parts = {}
    local function add(value, unit, color)
        local txt
        if icons then
            txt = group(value)
            if not plain then txt = U.Color(U.colors.text, txt) end
            txt = txt .. COIN_ICONS[unit]
        else
            txt = group(value) .. NBSP .. unit
            if not plain then txt = U.Color(color, txt) end
        end
        parts[#parts + 1] = txt
    end
    if g > 0 then add(g, "po", U.colors.gold) end
    if s > 0 then add(s, "pa", U.colors.silver) end
    if cp > 0 or (g == 0 and s == 0) then add(cp, "pc", U.colors.copper) end
    local sign = ""
    if neg then sign = "-" elseif signed and copper > 0 then sign = "+" end
    return sign .. table.concat(parts, " ")
end

-- Montant compact pour les tableaux étroits : sans cuivre au-delà de 1 po,
-- sans argent au-delà de 100 po (arrondi à l'unité inférieure affichée).
-- Compact amount for narrow table cells.
function U.MoneyShort(copper, plain, signed)
    if copper == nil then return "—" end
    copper = floor(copper + 0.5)
    local c = abs(copper)
    if c >= 1000000 then c = floor(c / 10000) * 10000
    elseif c >= 10000 then c = floor(c / 100) * 100 end
    return U.Money(copper < 0 and -c or c, plain, signed)
end

-- Pourcentage compact : sans décimale au-delà de 100 %, « >999 % » au-delà.
function U.PercentShort(value, signed)
    if value == nil or value ~= value then return "—" end
    local a = abs(value)
    local sign = ""
    if value < 0 then sign = "-" elseif signed and value > 0 then sign = "+" end
    if a >= 1000 then return sign .. ">999" .. NBSP .. "%" end
    if a >= 100 then return sign .. string.format("%d", floor(a + 0.5)) .. NBSP .. "%" end
    return U.Percent(value, signed)
end

-- Pourcentage au format français : « +612,5 % »
function U.Percent(value, signed)
    if value == nil or value ~= value then return "—" end
    local int, dec = string.format("%.1f", abs(value)):match("^(%d+)%.(%d)$")
    local txt = (int and (group(tonumber(int)) .. "," .. dec)) or string.format("%.1f", abs(value))
    local sign = ""
    if value < 0 then sign = "-" elseif signed and value > 0 then sign = "+" end
    return sign .. txt .. NBSP .. "%"
end

function U.Coord(v)
    -- Format TomTom/Wowhead (point décimal) pour éviter la confusion avec la virgule séparatrice.
    if not v then return "?" end
    return string.format("%.1f", v)
end

-- Extraction d'un itemID depuis un lien, une chaîne « item:123 » ou un nombre.
function U.ItemID(value)
    if type(value) == "number" then return value > 0 and floor(value) or nil end
    if type(value) ~= "string" then return nil end
    local id = value:match("item:(%d+)")
    if id then return tonumber(id) end
    if value:match("^%s*%d+%s*$") then return tonumber(value) end
    return nil
end

-- Protection contre les « valeurs secrètes » du client Midnight (12.x).
-- Guard against Midnight-client "secret values".
function U.IsSecret(v)
    if issecretvalue then
        local ok, res = pcall(issecretvalue, v)
        return ok and res or false
    end
    return false
end

-- -----------------------------------------------------------------------------
-- Accès protégés aux informations d'objet / guarded item info
-- -----------------------------------------------------------------------------
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

-- Retourne une table normalisée ou nil si l'objet n'est pas en cache.
function U.ItemInfo(id)
    if not id or not GetItemInfo then return nil end
    local ok, name, link, quality, _, _, _, _, stack, _, icon, sellPrice, classID, subClassID, bindType = pcall(GetItemInfo, id)
    if not ok or not name then return nil end
    return {
        name = name, link = link, quality = quality, stack = stack, icon = icon,
        sellPrice = sellPrice, classID = classID, subClassID = subClassID, bindType = bindType,
    }
end

-- Informations instantanées (sans cache serveur) / instant info (no server cache)
function U.ItemInstant(id)
    if not id or not GetItemInfoInstant then return nil end
    local ok, itemID, _, _, equipLoc, icon, classID, subClassID = pcall(GetItemInfoInstant, id)
    if not ok or not itemID then return nil end
    return { icon = icon, classID = classID, subClassID = subClassID, equipLoc = equipLoc }
end

-- Exemplaires possédés par le personnage : sacs, et banque (connue après
-- une ouverture de la banque dans la session). Owned counts: bags and bank.
local GetItemCountFn = (C_Item and C_Item.GetItemCount) or GetItemCount
function U.Owned(id)
    if not id or not GetItemCountFn then return 0, 0 end
    local ok1, bags = pcall(GetItemCountFn, id, false)
    local ok2, total = pcall(GetItemCountFn, id, true)
    bags = (ok1 and type(bags) == "number") and bags or 0
    total = (ok2 and type(total) == "number") and total or bags
    return bags, math.max(0, total - bags)
end

function U.OwnedText(id)
    local bags, bank = U.Owned(id)
    if bags + bank == 0 then return nil end
    local parts = {}
    if bags > 0 then parts[#parts + 1] = bags .. " (sacs)" end
    if bank > 0 then parts[#parts + 1] = bank .. " (banque)" end
    return table.concat(parts, " · ")
end

function U.RequestItem(id)
    if id and C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, id)
    end
end

-- Nom de profession d'une recette (classe 9) / recipe profession name
local RECIPE_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Recipe) or 9
U.RECIPE_CLASS = RECIPE_CLASS
local fallbackProfessions = {
    [0] = "Livre", [1] = "Travail du cuir", [2] = "Couture", [3] = "Ingénierie",
    [4] = "Forge", [5] = "Cuisine", [6] = "Alchimie", [7] = "Secourisme",
    [8] = "Enchantement", [9] = "Pêche", [10] = "Joaillerie", [11] = "Calligraphie",
}
function U.SubClassName(classID, subClassID)
    if classID == nil or subClassID == nil then return nil end
    local fn = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo
    if fn then
        local ok, name = pcall(fn, classID, subClassID)
        if ok and name and name ~= "" then return name end
    end
    if classID == RECIPE_CLASS then return fallbackProfessions[subClassID] end
    return nil
end

-- Métiers utilisant un composant d'artisanat, d'après la sous-catégorie que le
-- jeu attribue à l'objet (classe Artisanat). Sous-catégories génériques
-- (« Artisanat », « Autre », « Matériaux ») : aucun métier affiché, plutôt
-- qu'une supposition. Professions using a trade good, from its game subclass.
local TRADEGOODS_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods) or 7
U.TRADEGOODS_CLASS = TRADEGOODS_CLASS
local TRADEGOODS_PROFESSIONS = {
    [1] = "Ingénierie",                    -- Pièces
    [2] = "Ingénierie",                    -- Explosifs
    [3] = "Ingénierie",                    -- Appareils
    [4] = "Joaillerie",
    [5] = "Couture, Secourisme",           -- Tissu (bandages en Secourisme)
    [6] = "Travail du cuir",
    [7] = "Forge, Ingénierie",             -- Métal et pierre
    [8] = "Cuisine",                       -- Viande / cuisine
    [9] = "Alchimie",                      -- Herbe
    [10] = "Plusieurs métiers (élémentaire)",
    [12] = "Enchantement",
    [16] = "Calligraphie",
}
function U.TradeProfessions(classID, subClassID)
    if classID ~= TRADEGOODS_CLASS then return nil end
    return TRADEGOODS_PROFESSIONS[subClassID]
end

-- Nom d'objet coloré selon sa qualité (gris, blanc, vert, bleu, violet…).
-- Item name colored by quality.
local QUALITY_FALLBACK = { [0] = "ff9d9d9d", [1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd",
    [4] = "ffa335ee", [5] = "ffff8000", [6] = "ffe6cc80", [7] = "ff00ccff" }
function U.QualityHex(quality)
    if quality == nil then return nil end
    if C_Item and C_Item.GetItemQualityColor then
        local ok, _, _, _, hex = pcall(C_Item.GetItemQualityColor, quality)
        if ok and type(hex) == "string" and #hex == 8 then return hex end
    end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if c and type(c.hex) == "string" then
        local h = c.hex:gsub("^|c", "")
        if #h == 8 then return h end
    end
    return QUALITY_FALLBACK[quality]
end

function U.QualityName(id, name)
    local info = U.ItemInfo(id)
    name = (info and info.name) or name
    if not name then return nil end
    local hex = info and U.QualityHex(info.quality)
    return hex and ("|c" .. hex .. name .. "|r") or name
end

function U.ClassName(classID)
    local fn = (C_Item and C_Item.GetItemClassInfo) or GetItemClassInfo
    if fn and classID then
        local ok, name = pcall(fn, classID)
        if ok and name then return name end
    end
    return nil
end

-- Sort enseigné par une recette (distinct de l'objet recette) / taught spell
function U.ItemSpell(id)
    local fn = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if not fn or not id then return nil end
    local ok, spellName, spellID = pcall(fn, id)
    if ok and spellName then return spellName, spellID end
    return nil
end

-- Nom de zone à partir d'un uiMapID / zone name from uiMapID
local mapNameCache = {}
function U.MapName(mapID)
    if not mapID then return nil end
    local cached = mapNameCache[mapID]
    if cached ~= nil then return cached or nil end
    local info = C_Map and C_Map.GetMapInfo and select(2, pcall(C_Map.GetMapInfo, mapID))
    local name = type(info) == "table" and info.name or false
    mapNameCache[mapID] = name
    return name or nil
end

function U.PlayerSide()
    local side = UnitFactionGroup and UnitFactionGroup("player")
    if side == "Alliance" then return "A" elseif side == "Horde" then return "H" end
    return "?"
end

function U.SideText(side)
    local L = ns.L
    if side == "A" then return U.Color(U.colors.alliance, L.SIDE_A) end
    if side == "H" then return U.Color(U.colors.horde, L.SIDE_H) end
    if side == "N" then return U.Color(U.colors.neutral, L.SIDE_N) end
    return U.Color(U.colors.dim, L.SIDE_U)
end

function U.Print(msg)
    print("|c" .. U.colors.title .. ns.title .. "|r · " .. tostring(msg))
end

function U.CopyTable(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = U.CopyTable(v) end
    return out
end

function U.Trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Âge lisible d'un horodatage : « à l'instant », « il y a 12 min », « il y a 3 h »,
-- « il y a 2 j ». Readable age of a timestamp.
function U.Ago(ts)
    if not ts then return "?" end
    local d = math.max(0, time() - ts)
    if d < 60 then return "à l'instant" end
    if d < 3600 then return string.format("il y a %d min", floor(d / 60)) end
    if d < 86400 then return string.format("il y a %d h", floor(d / 3600)) end
    return string.format("il y a %d j", floor(d / 86400))
end

-- Texte replié pour la recherche : minuscules et sans accents (« Épée » → « epee »).
-- Folded text for searching: lower case, accents removed.
local FOLD = {
    ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["À"] = "a", ["Â"] = "a", ["Ä"] = "a",
    ["ç"] = "c", ["Ç"] = "c",
    ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e",
    ["î"] = "i", ["ï"] = "i", ["Î"] = "i", ["Ï"] = "i",
    ["ô"] = "o", ["ö"] = "o", ["Ô"] = "o", ["Ö"] = "o",
    ["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["Ù"] = "u", ["Û"] = "u", ["Ü"] = "u",
    ["œ"] = "oe", ["Œ"] = "oe", ["æ"] = "ae", ["Æ"] = "ae", ["’"] = "'",
}
function U.Fold(s)
    if type(s) ~= "string" then return "" end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("[\195\197\226][\128-\191]+", function(ch) return FOLD[ch] end)
    return s:lower()
end

-- Nom du serveur (royaume) du personnage / character realm name
function U.Realm()
    local fn = GetNormalizedRealmName or GetRealmName
    local ok, r = pcall(fn or function() return nil end)
    if ok and type(r) == "string" and r ~= "" then return r end
    return "?"
end

-- Nombre saisi au format français (virgule) / French-formatted number input
function U.ParseNumber(s)
    s = U.Trim(s):gsub(",", ".")
    return tonumber(s)
end
