-- =============================================================================
-- Shadsun Gold Lens — UI/OpportunitiesTab.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Onglet Opportunités, trois sens d'arbitrage :
--       - PNJ » HDV (liste partagée, icônes Aller et Copier) ;
--       - HDV » PNJ (liste d'arbitrage partagée) ;
--       - HDV » HDV (écarts entre les HDV scannés du serveur).
-- EN : Opportunities tab: vendor » AH, AH » vendor, AH » AH.
-- =============================================================================
local _, ns = ...
local W = ns.W

ns.UI.RegisterTab("opp", "Opportunités", function(root)
    local direction = "forward"
    local pages = {}
    local top = -32

    local tabs = W.Segmented(root, {
        { "forward", "PNJ » HDV", "Acheter chez un marchand, revendre à l'HDV." },
        { "reverse", "HDV » PNJ", "Acheter à l'HDV, revendre à un marchand (prix de rachat du jeu)." },
        { "cross", "HDV » HDV", "Acheter sur un HDV, revendre sur un autre HDV du serveur, d'après vos scans." },
    }, function() return direction end, function(v)
        direction = v
        for k, p in pairs(pages) do p:SetShown(k == v) end
        root.note:SetShown(v == "forward")
        if v == "forward" and #pages.forward.Rows() == 0 then pages.forward.Compute() end
    end, { 150, 150, 150 }, 24, "GameFontNormal")
    tabs:SetPoint("TOPLEFT", 0, 0)
    root.tabs = tabs
    local rule = root:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, 0)
    rule:SetPoint("RIGHT", root, "RIGHT", 0, 0)
    rule:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.5)

    local fwd = ns.OppUI.Build(root, "window")
    fwd:SetPoint("TOPLEFT", 0, top)
    pages.forward, root.forward = fwd, fwd
    local reverse = ns.ArbUI.Build(root, 15)
    reverse:SetPoint("TOPLEFT", 0, top)
    reverse:Hide()
    pages.reverse, root.reverse = reverse, reverse
    local cross = ns.CrossUI.Build(root, "window")
    cross:SetPoint("TOPLEFT", 0, top)
    cross:Hide()
    pages.cross, root.cross = cross, cross

    root.note = W.Text(root, "GameFontDisableSmall",
        "Prix HDV : scan du marché de revente (Marchés), sinon historique Auctionator (*). Vente non garantie. Clic sur une ligne : fiche de l'objet.", "LEFT", 800)
    root.note:SetPoint("BOTTOMLEFT", 0, 0)

    root.SetDirection = function(v) local b = tabs:Find(v); if b then b:Click() end end
    root.OnActivate = function()
        if direction == "forward" and #fwd.Rows() == 0 then fwd.Compute() end
    end
end)
