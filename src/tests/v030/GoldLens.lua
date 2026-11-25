-- Created by Tarak Ben Abda
local addonName, addon = ...
local title = "Shadsun Gold Lens"
local commission = 5
local untradeable = { [1] = true, [4] = true, [7] = true, [8] = true, [9] = true }
local offersByItem = addon.offers
local vendors = addon.vendors
local prices = {}
local lastPriceRefresh = 0
local offerCache = {}
local db, faction, mapId
local merchantOpen = false

local function itemID(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

local function coin(value)
    local rounded = math.floor(math.abs(value) + 0.5)
    if rounded == 0 and value ~= 0 then
        return (value < 0 and "−" or "+") .. string.format("%.2f pc", math.abs(value))
    end
    return (value < 0 and "−" or "") .. GetCoinTextureString(rounded)
end

local function auctionPrice(id, link)
    local now = GetTime()
    if now >= lastPriceRefresh + 3 then
        prices = {}
        lastPriceRefresh = now
    end
    local key = link or id
    local known = prices[key]
    if known then return known.price, known.age end

    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    local price, age
    if api then
        local ok, result
        if type(api.GetAuctionPriceByItemID) == "function" then
            ok, result = pcall(api.GetAuctionPriceByItemID, addonName, id)
            if ok and type(result) == "number" and result > 0 then price = result end
        end
        if not price and link and type(api.GetAuctionPriceByItemLink) == "function" then
            ok, result = pcall(api.GetAuctionPriceByItemLink, addonName, link)
            if ok and type(result) == "number" and result > 0 then price = result end
        end
        if price and type(api.GetAuctionAgeByItemID) == "function" then
            local ageOk, days = pcall(api.GetAuctionAgeByItemID, addonName, id)
            if ageOk and type(days) == "number" and days >= 0 then age = days end
        end
    end
    prices[key] = { price = price, age = age }
    return price, age
end

local function recordMerchant()
    if not (db and merchantOpen and C_MerchantFrame and C_MerchantFrame.GetItemInfo) then return end
    local guid = UnitGUID("npc")
    local npc = guid and tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    local name = npc and UnitName("npc")
    if not name then return end
    local map = C_Map.GetBestMapForUnit("player")
    local point = map and C_Map.GetPlayerMapPosition(map, "player")
    local now = time()
    for index = 1, GetMerchantNumItems() do
        local info = C_MerchantFrame.GetItemInfo(index)
        local id = itemID(GetMerchantItemLink(index))
        if id and info and info.stackCount and info.stackCount > 0 then
            local extra = info.hasExtendedCost or (info.currencyID or 0) > 0
            if (info.price and info.price > 0) or extra then
                local item = db.offers[id] or {}
                db.offers[id] = item
                local key = npc .. ":" .. info.stackCount .. ":" .. tostring(not not extra)
                item[key] = {
                    npc = npc, knownSide = true,
                    name = name, map = map, x = point and point.x * 100,
                    y = point and point.y * 100, price = info.price or 0,
                    quantity = info.stackCount, extra = extra,
                    stock = info.numAvailable, available = info.isPurchasable, seen = now,
                }
            end
        end
    end
    offerCache = {}
end

local function accessible(side)
    return side == faction or side == "AH" or side == "N"
end

local function priority(row)
    if row.enemy then return 6 end
    if row.extra or row.price <= 0 then return 5 end
    if row.condition and row.condition > 0 then return 4 end
    if row.stock == 0 or row.available == false then return 3 end
    if not row.knownSide then return 2 end
    return 1
end

local function better(row, previous)
    local rank, oldRank = priority(row), priority(previous)
    if rank ~= oldRank then return rank < oldRank end
    if (row.map == mapId) ~= (previous.map == mapId) then return row.map == mapId end
    if (row.seen ~= nil) ~= (previous.seen ~= nil) then return row.seen ~= nil end
    local price, oldPrice = row.price / row.quantity, previous.price / previous.quantity
    if price ~= oldPrice then return price < oldPrice end
    if row.name ~= previous.name then return row.name < previous.name end
    return row.npc < previous.npc
end

local function getOffers(id)
    if offerCache[id] then return offerCache[id] end
    local combined = {}
    local function insert(entries, catalog)
        for _, entry in ipairs(entries or {}) do
            local npc = entry[1]
            local vendor = catalog[npc]
            if vendor then
                local ref = addon.referenceVendors[npc]
                local side = (ref and ref[2]) or vendor[2]
                local key = npc .. ":" .. entry[3] .. ":" .. tostring(entry[5])
                local name = GetLocale and GetLocale() == "frFR" and ref and ref[6] or vendor[1]
                combined[key] = {
                    npc = npc, name = name, map = vendor[3], x = vendor[4], y = vendor[5],
                    price = entry[2], quantity = entry[3], limited = entry[4],
                    extra = entry[5], build = entry[6], knownSide = accessible(side),
                    enemy = side and side ~= "?" and not accessible(side), side = side,
                    condition = entry[7],
                }
            end
        end
    end
    insert(addon.referenceOffers[id], addon.referenceVendors)
    insert(offersByItem[id], vendors)
    for key,row in pairs(db.offers[id] or {}) do combined[key] = row end
    local rows = {}
    for _,row in pairs(combined) do rows[#rows+1] = row end
    table.sort(rows, better)
    if #rows > 0 then offerCache[id] = rows end
    return rows
end

local function noVendorText(id)
    if addon.knownItems[id] then return "Vente PNJ · aucun vendeur répertorié dans les bases" end
    return "Vente PNJ · objet absent des bases disponibles"
end
addon.noVendorText = noVendorText

local function location(offer)
    local info = offer.map and C_Map.GetMapInfo(offer.map)
    local name = info and info.name
    local xy = offer.x and offer.y and string.format("%.1f, %.1f", offer.x, offer.y)
    return name, xy
end

local function source(offer)
    if offer.seen then return "Prix vu par ce personnage · " .. date("%Y-%m-%d", offer.seen) end
    if offer.build == "Classic" or offer.build == "QuestieDB" then
        return "QuestieDB Forever · tarif Classic de référence"
    end
    return "Prix communautaire · remise à vérifier"
end

local function costText(offer)
    if offer.extra then return "Devise ou objet requis" end
    if offer.price <= 0 then return "Tarif inconnu" end
    return coin(offer.price) .. (offer.quantity > 1 and " / " .. offer.quantity or "")
end

local function evaluate(id, offer, price)
    if not (offer and price and priority(offer) <= 2) then return end
    local bind = C_Item and C_Item.GetItemInfo and select(14, C_Item.GetItemInfo(id))
    if not bind then return nil, "Type de liaison en attente" end
    if untradeable[bind] then return nil, "Achat lié · revente HV impossible" end
    local revenue = math.floor(price * offer.quantity * (100 - commission) / 100 + 0.000001)
    local profit = revenue - offer.price
    local roi = profit / offer.price * 100
    local result = (profit > 0 and "+" or "") .. coin(profit) .. string.format("  (%+.1f%%)", roi)
    return { text = result, profit = profit, revenue = revenue,
        threshold = math.ceil(offer.price * 100 / ((100 - commission) * offer.quantity)) }
end

addon.getOffers, addon.auctionPrice = getOffers, auctionPrice
addon.location, addon.source, addon.costText = location, source, costText
addon.coin, addon.evaluate, addon.itemID = coin, evaluate, itemID

-- Defer rendering until the game's nested recipe tooltips have finished.
-- Explicit bag/link contexts take precedence over the crafted-item hyperlink.
local states = setmetatable({}, { __mode = "k" })
local watched = setmetatable({}, { __mode = "k" })

local function linesFor(id, link)
    local lines = {}
    local function line(left, right, color)
        lines[#lines+1] = {left, right, color}
    end
    local rows = getOffers(id)
    local offer = rows[1]
    if not offer and not db.options.showMissing then return lines end
    line(title, nil, {0.91, 0.74, 0.39})
    if not offer then
        line(noVendorText(id), nil, {0.72,0.75,0.8})
        return lines
    end
    line(offer.seen and "Achat PNJ · ton prix relevé" or "Achat PNJ · référence", costText(offer))
    line(offer.name, (#rows > 1 and ("+" .. (#rows-1) .. " vendeurs") or nil))
    local zone, xy = location(offer)
    line(zone or "Zone inconnue", xy)
    if offer.enemy then
        line("Vendeur de la faction opposée", nil, {1,.6,.35})
    elseif not offer.knownSide then
        line("Accès au vendeur à vérifier", nil, {1,.8,.45})
    end
    if offer.condition and offer.condition > 0 then
        line("Achat soumis à conditions", nil, {1,.8,.45})
    end
    if offer.stock == 0 or offer.available == false then
        line("Indisponible lors de la dernière visite", nil, {1,.6,.35})
    elseif offer.limited or (offer.stock and offer.stock > 0) then
        line("Stock limité", nil, {1,.8,.45})
    end
    local price, age = auctionPrice(id, itemID(link) == id and link or ("item:" .. id))
    local estimate, reason = evaluate(id, offer, price)
    if estimate then
        local color = estimate.profit >= 0 and {.48,.92,.59} or {1,.48,.43}
        line(offer.quantity > 1 and "Gain / lot · rendement" or "Gain / unité · rendement", estimate.text, color)
    elseif reason then
        line(reason)
    elseif not price then
        line("Prix HV absent du dernier scan", nil, {.72,.75,.8})
    end
    if IsShiftKeyDown() then
        line(source(offer), nil, {.72,.75,.8})
        if price then line("HV par unité · " .. (age and (age .. " j") or "âge inconnu"), coin(price)) end
        if estimate then
            line("Seuil HV par unité", coin(estimate.threshold))
            if estimate.revenue > 0 then
                line("Marge sur vente nette", string.format("%+.1f%%",estimate.profit/estimate.revenue*100))
            end
        end
        line("ID " .. id .. " · commission estimée 5 %", nil, {.72,.75,.8})
    end
    line("Minicarte · vendeurs et carte", nil, {.68,.70,.75})
    return lines
end
addon.linesFor = linesFor

local function reportError(message)
    addon.lastError = tostring(message)
    if not addon.errorPrinted then
        addon.errorPrinted = true
        print(title .. " · Une erreur a été détectée. /sgl diagnostic pour le détail.")
    end
end

local function watchTooltip(tooltip)
    if watched[tooltip] then return end
    watched[tooltip] = true
    local function reset() states[tooltip] = nil end
    if tooltip.ClearLines then hooksecurefunc(tooltip, "ClearLines", reset) end
    tooltip:HookScript("OnHide", reset)
end

local function queueTooltip(tooltip, id, link, explicit)
    if not db or type(id) ~= "number" or id <= 0 then return end
    if not tooltip.AddLine or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
    watchTooltip(tooltip)
    local old = states[tooltip]
    if old and old.explicit and not explicit then return end
    if old and old.done and old.id == id then return end
    local state = {id=id,link=link,explicit=explicit}
    states[tooltip] = state
    addon.hoverCount = (addon.hoverCount or 0)+1
    if tooltip ~= ShoppingTooltip1 and tooltip ~= ShoppingTooltip2 then
        addon.lastItem,addon.lastLink = id,itemID(link)==id and link or ("item:"..id)
    end
    if not db.options.tooltip or (db.options.shiftOnly and not IsShiftKeyDown()) then return end
    C_Timer.After(0, function()
        if states[tooltip] ~= state or not tooltip:IsShown() then return end
        local ok, lines = pcall(linesFor, state.id, state.link)
        if not ok then reportError(lines); return end
        local success, err = pcall(function()
            for _, row in ipairs(lines) do
                local c = row[3] or {.93,.93,.93}
                if row[2] then
                    tooltip:AddDoubleLine(row[1], row[2], c[1],c[2],c[3],c[1],c[2],c[3])
                else
                    tooltip:AddLine(row[1],c[1],c[2],c[3],true)
                end
            end
            state.done = true
            tooltip:Show()
        end)
        if not success then reportError(err) end
    end)
end

local function identify(tooltip, data)
    local context = tooltip.GetPrimaryTooltipInfo and tooltip:GetPrimaryTooltipInfo()
    local args = context and context.getterArgs
    if args and context.getterName == "GetBagItem" and C_Container then
        return C_Container.GetContainerItemID(args[1],args[2]),
            C_Container.GetContainerItemLink(args[1],args[2]), true
    end
    if args and (context.getterName == "GetHyperlink" or context.getterName == "GetItemByID") then
        local id = tonumber(args[1]) or itemID(args[1])
        if id then return id, type(args[1]) == "string" and args[1] or ("item:"..id), true end
    end
    local primary = tooltip.GetPrimaryTooltipData and tooltip:GetPrimaryTooltipData()
    if primary and primary.type and primary.type ~= Enum.TooltipDataType.Item then return end
    local info = primary or data
    if info and type(info.id) == "number" and info.id > 0 then return info.id,info.hyperlink end
    if tooltip.GetItem then
        local _,link = tooltip:GetItem()
        return itemID(link),link
    end
end

local function installTooltips()
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip,data)
        local ok,id,link,explicit = pcall(identify,tooltip,data)
        if ok then queueTooltip(tooltip,id,link,explicit) else reportError(id) end
    end)
    for _,tooltip in pairs({GameTooltip,ItemRefTooltip}) do
        watchTooltip(tooltip)
        if tooltip.SetHyperlink then
            hooksecurefunc(tooltip,"SetHyperlink",function(frame,link)
                queueTooltip(frame,itemID(link),link,true)
            end)
        end
    end
    for _,tooltip in pairs({GameTooltip,ItemRefTooltip}) do
        if tooltip.SetItemByID then
            hooksecurefunc(tooltip,"SetItemByID",function(frame,id)
                queueTooltip(frame,id,"item:"..id,true)
            end)
        end
    end
    if GameTooltip.SetMerchantItem and GetMerchantItemLink then
        hooksecurefunc(GameTooltip,"SetMerchantItem",function(frame,index)
            local link=GetMerchantItemLink(index)
            queueTooltip(frame,itemID(link),link,true)
        end)
    end
    if GameTooltip.SetBagItem and C_Container then
        hooksecurefunc(GameTooltip,"SetBagItem",function(tooltip,bag,slot)
            queueTooltip(tooltip,C_Container.GetContainerItemID(bag,slot),
                C_Container.GetContainerItemLink(bag,slot),true)
        end)
    end
    addon.tooltipMethod = "Infobulle différée + identifiant de l’objet du sac"
end

local events = CreateFrame("Frame")
for _, event in ipairs({"ADDON_LOADED", "PLAYER_LOGIN", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED"}) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, loaded)
    if event == "ADDON_LOADED" and loaded == addonName then
        ShadsunGoldLensDB = ShadsunGoldLensDB or {}
        db = ShadsunGoldLensDB
        db.offers = db.offers or {}
        db.options = db.options or {}
        if db.options.tooltip == nil then db.options.tooltip = true end
        if db.options.showMissing == nil then db.options.showMissing = true end
        addon.db = db
        installTooltips()
    elseif event == "PLAYER_LOGIN" then
        local side = UnitFactionGroup("player")
        faction = side and side:sub(1, 1)
        mapId = C_Map.GetBestMapForUnit("player")
        addon.initUI()
        print("|cffe8bd64" .. title .. " v0.3.0|r · Créé par Tarak Ben Abda · /sgl")
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" then
        local current = C_Map.GetBestMapForUnit("player")
        if current ~= mapId then
            mapId = current
            offerCache = {}
        end
    elseif event == "MERCHANT_CLOSED" then
        merchantOpen = false
    elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
        if event == "MERCHANT_SHOW" then merchantOpen = true end
        recordMerchant()
    end
end)

function addon.status()
    local seen = 0
    for _ in pairs(db.offers) do seen = seen + 1 end
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    local active = api and (type(api.GetAuctionPriceByItemID) == "function" or type(api.GetAuctionPriceByItemLink) == "function")
    return "Auctionator " .. (active and "détecté" or "indisponible")
        .. "  ·  " .. addon.catalogStats()
end

function addon.catalogStats()
    if not addon.catalogCount then
        local items, shops = {}, {}
        for id,rows in pairs(addon.referenceOffers) do
            items[id] = true
            for _,row in ipairs(rows) do shops[row[1]] = true end
        end
        for id,rows in pairs(offersByItem) do
            items[id] = true
            for _,row in ipairs(rows) do shops[row[1]] = true end
        end
        local count, shopCount = 0, 0
        for _ in pairs(items) do count = count + 1 end
        for _ in pairs(shops) do shopCount = shopCount + 1 end
        addon.catalogCount = count .. " objets vendus · " .. shopCount .. " PNJ"
    end
    return addon.catalogCount
end
