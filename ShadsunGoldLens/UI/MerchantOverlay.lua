-- =============================================================================
-- Shadsun Gold Lens — UI/MerchantOverlay.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Bordure de couleur autour des objets de la fenêtre du marchand qui
--      sont rentables à revendre à l'HDV (prix réellement demandé par ce
--      marchand, lot, prix Auctionator, commission). Aucun texte sur l'icône.
--      Critère : bénéfice > 0 et rentabilité ≥ « rentabilité minimale ».
--      Objets payés en devise ou liés : jamais marqués.
-- EN : Colored border on merchant items profitable to resell on the AH.
-- =============================================================================
local _, ns = ...
local U = ns.U
local MO = {}
ns.MerchantOverlay = MO

local borders = {}

local function perPage()
    return MERCHANT_ITEMS_PER_PAGE or 10
end

local function getBorder(button)
    local b = borders[button]
    if b then return b end
    b = CreateFrame("Frame", nil, button, "BackdropTemplate")
    b:SetPoint("TOPLEFT", -2, 2)
    b:SetPoint("BOTTOMRIGHT", 2, -2)
    b:SetFrameLevel(button:GetFrameLevel() + 5)
    b:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    b:Hide()
    borders[button] = b
    return b
end

-- Prix et lot affichés par le marchand pour l'emplacement / slot price and lot
local function slotPrice(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local ok, info = pcall(C_MerchantFrame.GetItemInfo, index)
        if ok and type(info) == "table" then
            return info.price, info.stackCount, info.hasExtendedCost or ((info.currencyID or 0) > 0)
        end
    end
    if GetMerchantItemInfo then
        local ok, _, _, price, quantity, _, _, _, ext = pcall(GetMerchantItemInfo, index)
        if ok then return price, quantity, ext end
    end
    return nil
end

-- Évaluation d'un emplacement (pure, testable) / slot evaluation
function MO.Evaluate(index)
    local itemID = U.ItemID(GetMerchantItemLink and GetMerchantItemLink(index))
    if not itemID then return false end
    local price, qty, ext = slotPrice(index)
    if ext or not price or price <= 0 or not qty or qty <= 0 then return false end
    local ah, age = ns.Prices.Best(itemID)
    if not ah then return false end
    local r = ns.Economy.Evaluate(itemID, { price = price, qty = qty }, ah, age)
    if not r then return false end
    return r.profit > 0 and (r.roi or 0) >= (ns.DB.Num("economy", "minROI") or 0), r
end

-- Article d'une liste d'achats ? / is the slot item in a shopping list?
function MO.InList(index, set)
    local itemID = U.ItemID(GetMerchantItemLink and GetMerchantItemLink(index))
    return itemID and set[itemID] or false
end

function MO.Update()
    local enabled = ns.settings and ns.settings.ah.merchantBorder
    local listOn = ns.settings and ns.settings.ah.listBorder and ns.Lists
    local listSet = listOn and ns.Lists.ItemSet() or {}
    local lc = ns.settings and ns.settings.ah.listBorderColor or { 0.35, 0.65, 1 }
    local onBuyTab = not MerchantFrame or (MerchantFrame.selectedTab or 1) == 1
    local page = (MerchantFrame and MerchantFrame.page) or 1
    local c = ns.settings and ns.settings.ah.borderColor or { 0.2, 1, 0.3 }
    local total = GetMerchantNumItems and GetMerchantNumItems() or 0
    for i = 1, perPage() do
        local button = _G["MerchantItem" .. i .. "ItemButton"]
        if button then
            local show, col = false, c
            local index = (page - 1) * perPage() + i
            if onBuyTab and index <= total and button:IsShown() then
                -- Article d'une liste : bordure bleue, prioritaire sur « rentable ».
                if listOn and MO.InList(index, listSet) then
                    show, col = true, lc
                elseif enabled then
                    local ok, good = pcall(MO.Evaluate, index)
                    show = ok and good or false
                end
            end
            if show then
                local b = getBorder(button)
                b:SetBackdropBorderColor(col[1], col[2], col[3], 1)
                b:Show()
            elseif borders[button] then
                borders[button]:Hide()
            end
        end
    end
end

local function safeUpdate()
    local ok, err = pcall(MO.Update)
    if not ok then ns.Diag.Error("merchantBorder", err) end
end

ns.OnLogin(function()
    -- Fonctions de rafraîchissement de la fenêtre du marchand (pages, onglets).
    for _, fn in ipairs({ "MerchantFrame_UpdateMerchantInfo", "MerchantFrame_Update" }) do
        if type(_G[fn]) == "function" then hooksecurefunc(fn, safeUpdate) end
    end
end)
ns.RegisterEvent("MERCHANT_SHOW", function() C_Timer.After(0.1, safeUpdate) end)
ns.On("LISTS_CHANGED", function() if MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown() then safeUpdate() end end)
ns.RegisterEvent("MERCHANT_UPDATE", function() safeUpdate() end)
ns.On("PRICES_CHANGED", function() if MerchantFrame and MerchantFrame:IsShown() then safeUpdate() end end)
ns.On("SETTINGS_CHANGED", function() if MerchantFrame and MerchantFrame:IsShown() then safeUpdate() end end)
