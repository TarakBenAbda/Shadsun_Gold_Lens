-- =============================================================================
-- Shadsun Gold Lens — UI/AuctionPanel.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Fenêtre « Gold Lens » accolée à l'hôtel des ventes (à droite), avec un
--      bouton de bascule au-dessus de la fenêtre Blizzard. Si un autre add-on
--      remplace la fenêtre de l'HDV, le panneau s'ouvre seul au centre.
-- EN : Side panel docked to the Auction House window, with a toggle button.
-- =============================================================================
local _, ns = ...
local U, W = ns.U, ns.W
local AP = {}
ns.AuctionPanel = AP

local frame, toggle
AP.MIN_SCALE, AP.MAX_SCALE = 0.6, 1.2

-- Échelle automatique : le panneau prend la place libre à droite de l'HDV
-- sans la recouvrir (en pixels écran, quelle que soit l'échelle de l'interface).
-- Auto scale: fit the free space right of the AH window (screen pixels).
function AP.AutoScale()
    if not (AuctionHouseFrame and AuctionHouseFrame.GetRight and UIParent.GetRight) then return 1 end
    local ahRight, screenRight = AuctionHouseFrame:GetRight(), UIParent:GetRight()
    if not ahRight or not screenRight then return 1 end
    local uiEff = UIParent:GetEffectiveScale()
    local availPx = screenRight * uiEff - ahRight * AuctionHouseFrame:GetEffectiveScale() - 8 * uiEff
    local scale = availPx / (frame:GetWidth() * uiEff)
    return math.min(1, math.max(AP.MIN_SCALE, scale))
end

local function currentScale()
    local s = tonumber(ns.settings.ah.scale)
    if s then return math.min(AP.MAX_SCALE, math.max(AP.MIN_SCALE, s)) end
    return AP.AutoScale()
end

local function anchor()
    local scale = currentScale()
    frame:SetScale(scale)
    frame:ClearAllPoints()
    local saved = ns.settings.windows.ahpanel
    if saved and saved.point then
        frame:SetPoint(saved.point, UIParent, saved.relPoint or saved.point, saved.x or 0, saved.y or 0)
    elseif AuctionHouseFrame then
        local uiEff = UIParent:GetEffectiveScale()
        local fits = (AuctionHouseFrame:GetRight() or 0) * AuctionHouseFrame:GetEffectiveScale()
            + (frame:GetWidth() + 6) * uiEff * scale <= (UIParent:GetRight() or 0) * uiEff
        if fits then
            frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 6, 0)
        else
            -- Pas assez de place même réduit : collé au bord droit de l'écran,
            -- aligné sur le haut de l'HDV. Not enough room: right screen edge.
            local top = (AuctionHouseFrame:GetTop() or 0) * AuctionHouseFrame:GetEffectiveScale()
            local y = (top - (UIParent:GetTop() or 0) * uiEff) / (uiEff * scale)
            frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -4, y)
        end
    else
        frame:SetPoint("CENTER")
    end
end
AP.Anchor = function() if frame then anchor() end end

AP.HEIGHT = 650
AP.MODES = {
    { "reverse", "HDV » PNJ", "Acheter à l'HDV, revendre à un marchand (prix de rachat du jeu)." },
    { "forward", "PNJ » HDV", "Acheter chez un marchand, revendre à l'HDV." },
    { "cross", "HDV » HDV", "Acheter sur un HDV, revendre sur un autre HDV du serveur, d'après vos scans." },
    { "lists", "Listes", "Vos listes d'achats : loupe par article et recherche de toute la liste." },
}

local function create()
    if frame then return frame end
    frame = W.Window("ShadsunGoldLensAuctionPanel", ns.ArbUI.WIDTH + 28, AP.HEIGHT, ns.title, "ahpanel")
    local sub = W.Text(frame, "GameFontDisableSmall", "Hôtel des ventes")
    sub:SetPoint("LEFT", frame.title, "RIGHT", 8, -1)
    local credit = W.Text(frame, "GameFontDisableSmall", ns.signature)
    credit:SetPoint("BOTTOMRIGHT", -14, 10)

    -- Barre de scan commune aux trois sens / shared scan bar
    local scan = ns.ScanBar.Build(frame, ns.ArbUI.WIDTH)
    scan:SetPoint("TOPLEFT", 14, -42)
    frame.scan = scan

    -- Sens d'arbitrage : onglets / direction tabs
    local pages = {}
    local function applyDirection()
        local d = ns.settings.ah.direction or "reverse"
        if not pages[d] then d = "reverse" end
        for k, p in pairs(pages) do p:SetShown(k == d) end
        -- Vue des listes : rafraîchie à chaque affichage (liste active à jour).
        if pages[d] and pages[d].Refresh and d == "lists" then pages[d].Refresh() end
    end
    local tabs = W.Segmented(frame, AP.MODES, function() return ns.settings.ah.direction or "reverse" end,
        function(v) ns.settings.ah.direction = v; applyDirection() end, { 150, 150, 150, 150 }, 24, "GameFontNormal")
    tabs:SetPoint("TOPLEFT", 14, -98)
    frame.tabs = tabs
    local tabRule = frame:CreateTexture(nil, "ARTWORK")
    tabRule:SetHeight(1)
    tabRule:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, 0)
    tabRule:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    tabRule:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.5)

    local top = -132
    local panel = ns.ArbUI.Build(frame, 17, { embedded = true })
    panel:SetPoint("TOPLEFT", 14, top)
    frame.panel, pages.reverse = panel, panel
    -- Sens PNJ » HDV : même liste que l'onglet Opportunités, avec la loupe.
    local fwd = ns.OppUI.Build(frame, "ah")
    fwd:SetPoint("TOPLEFT", 14, top)
    fwd:SetScript("OnShow", function() if #fwd.Rows() == 0 then fwd.Compute() end end)
    frame.fwd, pages.forward = fwd, fwd
    local cross = ns.CrossUI.Build(frame, "ah")
    cross:SetPoint("TOPLEFT", 14, top)
    frame.cross, pages.cross = cross, cross
    local shop = ns.ShopUI.Build(frame, "ah")
    shop:SetPoint("TOPLEFT", 14, top)
    frame.lists, pages.lists = shop, shop
    applyDirection()
    tabs:Refresh()
    frame:HookScript("OnShow", applyDirection)

    -- Le panneau suit l'HDV ; si vous le déplacez, il reste où vous l'avez mis.
    -- Ce bouton n'apparaît qu'après un déplacement et le remet contre l'HDV.
    local redock = W.Button(frame, "Replacer à côté de l'HDV", 190, 20, function(self)
        ns.settings.windows.ahpanel = nil
        anchor()
        self:Hide()
    end)
    redock:SetPoint("BOTTOMLEFT", 14, 8)
    redock:SetShown(ns.settings.windows.ahpanel ~= nil)
    frame:HookScript("OnDragStop", function() redock:Show() end)
    frame.redock = redock

    -- Taille : « - » / « + » (pas de 5 %), « Auto » = ajustement à l'espace libre.
    local function setScale(delta)
        local s = currentScale()
        ns.settings.ah.scale = math.floor(math.min(AP.MAX_SCALE, math.max(AP.MIN_SCALE, s + delta)) * 100 + 0.5) / 100
        anchor()
    end
    local auto = W.Button(frame, "Auto", 50, 20, function()
        ns.settings.ah.scale = nil
        anchor()
    end)
    auto:SetPoint("TOPRIGHT", -36, -10)
    local plus = W.Button(frame, "+", 24, 20, function() setScale(0.05) end)
    plus:SetPoint("RIGHT", auto, "LEFT", -4, 0)
    local minus = W.Button(frame, "-", 24, 20, function() setScale(-0.05) end)
    minus:SetPoint("RIGHT", plus, "LEFT", -4, 0)
    local sizeLbl = W.Text(frame, "GameFontDisableSmall", "Taille")
    sizeLbl:SetPoint("RIGHT", minus, "LEFT", -6, 0)
    anchor()
    ns.On("UI_RESET", function() if frame then anchor(); frame.redock:Hide() end end)
    return frame
end

function AP.Show()
    create()
    anchor()
    frame.redock:SetShown(ns.settings.windows.ahpanel ~= nil)
    frame:Show()
end

function AP.Toggle()
    if frame and frame:IsShown() then frame:Hide() else AP.Show() end
end

local function ensureToggle()
    if toggle or not AuctionHouseFrame then return end
    toggle = W.Button(AuctionHouseFrame, "Gold Lens", 100, 22, function() AP.Toggle() end)
    toggle:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "TOPRIGHT", -8, 2)
    toggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ns.title)
        GameTooltip:AddLine("Scan de l'HDV et opportunités d'arbitrage : HDV » PNJ, PNJ » HDV et HDV » HDV.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

ns.On("AH_SHOW", function()
    local ok, err = pcall(function()
        ensureToggle()
        if ns.settings.ah.autoShow then AP.Show() end
    end)
    if not ok then ns.Diag.Error("ahpanel", err) end
end)
ns.On("AH_CLOSED", function()
    if frame and not ns.settings.windows.ahpanel then frame:Hide() end
end)
