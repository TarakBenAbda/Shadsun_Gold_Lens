-- =============================================================================
-- Shadsun Gold Lens — UI/OptionsTab.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Paramètres (sauvegardés dans ShadsunGoldLensGlobal.settings).
--      Un raccourci est aussi ajouté dans Options > AddOns du jeu.
-- EN : Settings tab; a shortcut is registered in the game's AddOns options.
-- =============================================================================
local _, ns = ...
local U, W = ns.U, ns.W

ns.UI.RegisterTab("options", "Paramètres", function(page)
    local controls = {}
    local function add(c) controls[#controls + 1] = c; return c end
    local function check(label, section, key, x, y, tip)
        local c = add(W.Check(page, label, function() return ns.settings[section][key] end,
            function(v) ns.settings[section][key] = v end, tip))
        c:SetPoint("TOPLEFT", x, y)
        return c
    end

    local h1 = W.Text(page, "GameFontNormal", "Infobulle")
    h1:SetPoint("TOPLEFT", 4, -4)
    local y = -24
    local items = {
        { "Activer les informations au survol", "enabled" },
        { "Prix d'achat auprès du PNJ", "showBuy" },
        { "Prix de vente au PNJ", "showSell" },
        { "Prix HDV (scans de vos HDV, sinon Auctionator)", "showAH" },
        { "Bénéfice et rentabilité", "showProfit" },
        { "Nom et position du marchand", "showVendor" },
        { "Faction et exclusivité", "showFaction" },
        { "Statut de fiabilité", "showStatus" },
        { "Métier (recettes et composants)", "showProfession" },
        { "Ligne pour les objets sans vendeur connu", "showNoVendorLine" },
        { "Arbitrage HDV » PNJ (si rentable)", "showReverse" },
        { "Nombre possédé (tous vos personnages du serveur)", "showOwned" },
        { "Nombre en vente à l'HDV (vos enchères en cours)", "showAuctions" },
        { "Afficher seulement avec Maj enfoncée", "shiftOnly" },
        { "Masquer en combat", "hideInCombat" },
    }
    for _, it in ipairs(items) do
        check(it[1], "tooltip", it[2], 4, y)
        y = y - 24
    end
    local fs, e = W.NumberSetting(page, "Nombre maximal de lignes (3-20)", "tooltip", "maxLines", 3, 20)
    fs:SetPoint("TOPLEFT", 8, y - 6)
    add(e)

    -- --- Économie / economy -----------------------------------------------
    local x2 = 420
    local h2 = W.Text(page, "GameFontNormal", "Calculs économiques")
    h2:SetPoint("TOPLEFT", x2, -4)
    local market = add(W.Cycle(page, 330, "Marché de revente : ",
        { { "faction", "HDV de faction" }, { "neutral", "HDV neutre" } },
        function() return ns.settings.economy.market end,
        function(v) ns.settings.economy.market = v; ns.Fire("SETTINGS_CHANGED") end))
    market:SetPoint("TOPLEFT", x2, -26)
    local nums = {
        { "Commission HDV de faction (%)", "commissionFaction", 0, 50 },
        { "Commission HDV neutre (%)", "commissionNeutral", 0, 50 },
        { "Remise de réputation appliquée (%)", "repDiscount", 0, 30 },
        { "Rentabilité minimale « intéressante » (%)", "minROI", 0, 10000 },
        { "Prix HDV considéré ancien après (jours)", "staleDays", 0, 365 },
        { "Dépôt estimé (% du prix de vente PNJ)", "depositPct", 0, 100 },
    }
    local yy = -58
    for _, n in ipairs(nums) do
        local l, ed = W.NumberSetting(page, n[1], "economy", n[2], n[3], n[4])
        l:SetPoint("TOPLEFT", x2 + 4, yy)
        add(ed)
        yy = yy - 28
    end
    check("Afficher le risque de dépôt perdu (Maj)", "economy", "depositEstimate", x2, yy)
    yy = yy - 30
    local note = W.Text(page, "GameFontDisableSmall",
        "Règles Classic de référence : 5 % (faction), 15 % (neutre). Les règles exactes de Forever sont à vérifier en jeu ; ajustez ces valeurs si besoin. La remise de réputation ne s'applique qu'aux prix de référence (vos prix relevés l'incluent déjà).",
        "LEFT", 390)
    note:SetPoint("TOPLEFT", x2 + 4, yy)

    -- --- Interface / UI ------------------------------------------------------
    local yb = -330
    local h3 = W.Text(page, "GameFontNormal", "Interface")
    h3:SetPoint("TOPLEFT", x2, yb)
    local mm = add(W.Check(page, "Afficher l'icône de minicarte",
        function() return not ns.settings.minimap.hide end,
        function(v) ns.settings.minimap.hide = not v; if ns.Minimap then ns.Minimap.Apply() end end))
    mm:SetPoint("TOPLEFT", x2, yb - 20)
    local dbg = add(W.Check(page, "Messages de diagnostic dans le chat",
        function() return ns.settings.debug end, function(v) ns.settings.debug = v end))
    dbg:SetPoint("TOPLEFT", x2, yb - 44)
    local resetUI = W.Button(page, "Réinitialiser l'interface", 190, 22, function()
        ns.DB.ResetUI()
        if ns.Minimap then ns.Minimap.Apply() end
        U.Print("positions des fenêtres et de l'icône réinitialisées.")
    end)
    resetUI:SetPoint("TOPLEFT", x2, yb - 124)
    local armed = false
    local resetAll
    resetAll = W.Button(page, "Paramètres par défaut", 190, 22, function()
        if not armed then
            armed = true
            resetAll:SetText("Confirmer ?")
            C_Timer.After(3, function() armed = false; resetAll:SetText("Paramètres par défaut") end)
            return
        end
        armed = false
        resetAll:SetText("Paramètres par défaut")
        ns.DB.ResetSettings()
        for _, c in ipairs(controls) do if c.Refresh then c:Refresh() end end
        U.Print("paramètres réinitialisés.")
    end)
    resetAll:SetPoint("LEFT", resetUI, "RIGHT", 8, 0)
    local ahAuto = add(W.Check(page, "Ouvrir le panneau Gold Lens avec l'HDV",
        function() return ns.settings.ah.autoShow end, function(v) ns.settings.ah.autoShow = v end))
    ahAuto:SetPoint("TOPLEFT", x2, yb - 68)
    local speedBtn = add(W.Cycle(page, 300, "Vitesse d'analyse HDV : ",
        { { "slow", "Lente (jeu prioritaire)" }, { "normal", "Normale" }, { "fast", "Rapide" } },
        function() return ns.settings.ah.speed end,
        function(v) ns.settings.ah.speed = v end))
    speedBtn:SetPoint("TOPLEFT", x2, yb - 96)
    local dbBtn = W.Button(page, "État de la base de données", 190, 22, function() ns.UI.Show("db") end)
    dbBtn:SetPoint("TOPLEFT", 4, -460)

    -- Fenêtre du marchand : bordure des objets rentables à revendre à l'HDV
    local coins = add(W.Check(page, "Montants avec icônes de pièces",
        function() return ns.settings.display.coinIcons ~= false end,
        function(v) ns.settings.display.coinIcons = v end,
        "Affiche les montants avec les icônes or, argent et cuivre du jeu au lieu de « po », « pa », « pc »."))
    coins:SetPoint("TOPLEFT", 220, -460)
    local mb = add(W.Check(page, "Bordure des objets rentables chez le marchand",
        function() return ns.settings.ah.merchantBorder end, function(v) ns.settings.ah.merchantBorder = v end,
        "Entoure d'une couleur, dans la fenêtre du marchand, les objets dont la revente à l'HDV dépasse la rentabilité minimale."))
    mb:SetPoint("TOPLEFT", 4, -398)
    local colors = {
        { "vert", "Vert", { 0.2, 1, 0.3 } }, { "or", "Or", { 1, 0.82, 0 } },
        { "bleu", "Bleu", { 0.25, 0.65, 1 } }, { "violet", "Violet", { 0.75, 0.35, 1 } },
    }
    local function colorKey()
        local c = ns.settings.ah.borderColor or colors[1][3]
        for _, o in ipairs(colors) do
            if math.abs(o[3][1] - c[1]) < 0.01 and math.abs(o[3][2] - c[2]) < 0.01 and math.abs(o[3][3] - c[3]) < 0.01 then return o[1] end
        end
        return "vert"
    end
    local opts = {}
    for _, o in ipairs(colors) do opts[#opts + 1] = { o[1], o[2] } end
    local colorBtn = add(W.Cycle(page, 230, "Couleur de la bordure : ", opts, colorKey, function(v)
        for _, o in ipairs(colors) do if o[1] == v then ns.settings.ah.borderColor = { o[3][1], o[3][2], o[3][3] } end end
        ns.Fire("SETTINGS_CHANGED")
    end))
    colorBtn:SetPoint("TOPLEFT", 4, -428)

    page.OnActivate = function()
        for _, c in ipairs(controls) do if c.Refresh then c:Refresh() end end
    end
end)

-- Raccourci dans Options > AddOns (API Settings du client moderne)
ns.OnLogin(function()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local canvas = CreateFrame("Frame")
    local t = W.Text(canvas, "GameFontNormalLarge", ns.title .. " " .. ns.version)
    t:SetPoint("TOPLEFT", 16, -16)
    local d = W.Text(canvas, "GameFontHighlight", "Les paramètres complets se trouvent dans la fenêtre de l'add-on.", "LEFT", 500)
    d:SetPoint("TOPLEFT", 16, -48)
    local b = W.Button(canvas, "Ouvrir les paramètres", 200, 24, function()
        if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel and not InCombatLockdown() then HideUIPanel(SettingsPanel) end
        ns.UI.Show("options")
    end)
    b:SetPoint("TOPLEFT", 16, -80)
    local c = W.Text(canvas, "GameFontDisableSmall", ns.signature)
    c:SetPoint("TOPLEFT", 16, -116)
    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, canvas, ns.title)
    if ok and category then
        pcall(Settings.RegisterAddOnCategory, category)
        ns.settingsCategory = category
    end
end)
