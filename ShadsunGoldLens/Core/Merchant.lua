-- =============================================================================
-- Shadsun Gold Lens — Core/Merchant.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Couche B — observation des marchands. À l'ouverture d'une fenêtre
--      marchande, enregistre (lecture seule, aucune action automatisée) :
--      objet, prix payé par vous, taille du lot, stock, devise éventuelle,
--      PNJ (ID, nom, faction), zone et position du personnage.
-- EN : Layer B — read-only merchant observation recorder.
-- =============================================================================
local _, ns = ...
local U = ns.U
local M = {}
ns.Merchant = M

M.open = false
M.lastScan = nil
local pending = false

local function npcInfo()
    local guid = UnitGUID and UnitGUID("npc")
    if not guid or U.IsSecret(guid) then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    local npcID = tonumber(id)
    if not npcID then return nil end
    local name = UnitName("npc")
    local fac = UnitFactionGroup and UnitFactionGroup("npc")
    local side = (fac == "Alliance" and "A") or (fac == "Horde" and "H") or nil
    if not side and UnitReaction then
        -- Réaction amicale envers le joueur sans faction : PNJ neutre (gobelins, etc.)
        local reaction = UnitReaction("npc", "player")
        if reaction and reaction >= 4 then side = "N" end
    end
    return npcID, name, side
end

local function playerPosition()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return nil end
    local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return map end
    local x, y = pos.x, pos.y
    if pos.GetXY then x, y = pos:GetXY() end
    if not x or not y or (x == 0 and y == 0) then return map end
    return map, math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10
end

-- Informations d'un emplacement marchand (API 11.x+ puis repli historique).
local function slotInfo(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local ok, info = pcall(C_MerchantFrame.GetItemInfo, index)
        if ok and type(info) == "table" then
            return info.price, info.stackCount, info.numAvailable, info.isPurchasable,
                info.hasExtendedCost or ((info.currencyID or 0) > 0)
        end
    end
    if GetMerchantItemInfo then
        local ok, _, _, price, quantity, numAvailable, isPurchasable, _, extendedCost = pcall(GetMerchantItemInfo, index)
        if ok then return price, quantity, numAvailable, isPurchasable, extendedCost end
    end
    return nil
end

function M.Scan()
    pending = false
    if not M.open or not ns.DB.G then return 0 end
    local npcID, npcName, side = npcInfo()
    if not npcID then return 0 end
    local map, x, y = playerPosition()
    local now = time()
    local charName = UnitName("player")
    local build = select(2, GetBuildInfo())
    local version = GetBuildInfo()
    local count = 0
    local touched = {}
    local n = GetMerchantNumItems and GetMerchantNumItems() or 0
    for i = 1, n do
        local link = GetMerchantItemLink and GetMerchantItemLink(i)
        local itemID = U.ItemID(link)
        local price, qty, numAvailable, purchasable, ext = slotInfo(i)
        if itemID and qty and qty > 0 and (price or ext) then
            local key = npcID .. ":" .. qty .. ":" .. (ext and 1 or 0)
            local G = ns.DB.G
            G.observations[itemID] = G.observations[itemID] or {}
            G.observations[itemID][key] = {
                npc = npcID, name = npcName, side = side, map = map, x = x, y = y,
                price = price or 0, qty = qty, ext = ext and true or nil,
                stock = numAvailable, avail = purchasable ~= false, seen = now,
                char = charName, build = tostring(version) .. "." .. tostring(build),
            }
            touched[#touched + 1] = itemID
            count = count + 1
        end
    end
    if count > 0 then
        ns.DB.G.observedNPCs[npcID] = { name = npcName, side = side, map = map, x = x, y = y, seen = now }
        ns.DB.G.stats.merchantScans = (ns.DB.G.stats.merchantScans or 0) + 1
        for _, id in ipairs(touched) do ns.Catalog.Invalidate(id) end
        ns.Fire("DATA_CHANGED")
    end
    M.lastScan = { npc = npcID, name = npcName, items = count, side = side, map = map, x = x, y = y, time = now }
    if ns.Diag then ns.Diag.Log("Marchand " .. tostring(npcName) .. " (" .. npcID .. ") : " .. count .. " objets relevés") end
    return count
end

-- Regroupement des événements rapprochés / coalesce bursts of updates
local function schedule()
    if pending then return end
    pending = true
    C_Timer.After(0.3, function()
        local ok, err = pcall(M.Scan)
        if not ok and ns.Diag then ns.Diag.Error("merchant", err) end
    end)
end

ns.RegisterEvent("MERCHANT_SHOW", function() M.open = true; schedule() end)
ns.RegisterEvent("MERCHANT_UPDATE", function() if M.open then schedule() end end)
ns.RegisterEvent("MERCHANT_CLOSED", function() M.open = false end)
