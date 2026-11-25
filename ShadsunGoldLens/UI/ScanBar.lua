-- =============================================================================
-- Shadsun Gold Lens — UI/ScanBar.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Barre de scan affichée en tête du panneau de l'hôtel des ventes,
--      commune aux trois sens d'arbitrage :
--       - choix de l'HDV qui recevra le scan (prérempli selon la zone,
--         mémorisé pour chaque personnage, avertissement si la zone ne
--         concorde pas) ;
--       - « Lire les annonces » (scan complet) et « Tout arrêter » ;
--       - progression et état du dernier scan.
-- EN : Scan bar: target market selector, full scan, stop, progress.
-- =============================================================================
local _, ns = ...
local U, W = ns.U, ns.W
local SB = {}
ns.ScanBar = SB

function SB.Build(parent, width)
    local A, MK = ns.Arbitrage, ns.Market
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(width, 50)

    local function choiceValue()
        local c = MK.Choice()
        if c then return c end
        return (MK.ZoneKey() == "N") and "neutral" or "faction"
    end
    local function options()
        local mine = MK.PlayerKey()
        return { { "faction", MK.Label(mine), U.colors[mine == "A" and "alliance" or "horde"] }, { "neutral", MK.Label("N"), U.colors.neutral } }
    end
    local market = W.Cycle(bar, 210, "Scan pour : ", options(), choiceValue, function(v) MK.SetChoice(v) end,
        "HDV auquel le prochain scan sera attribué. Prérempli d'après la zone ; votre choix est mémorisé pour ce personnage. Les scans sont partagés par tous vos personnages du serveur.\n\nChanger ce choix juste après un scan, HDV encore ouvert, réattribue ce scan au bon HDV.")
    market:SetPoint("TOPLEFT", 0, 0)
    bar.market = market

    local scanBtn = W.Button(bar, "Lire les annonces", 150, 22, function()
        local ok, msg = A.RequestFullScan()
        if not ok and A.CanReplicate() and A.ahOpen and A.ReadReplicate(true) then
            msg = "Scan complet indisponible pour l'instant : relecture des annonces déjà chargées."
        end
        U.Print(msg)
        bar.Update()
    end)
    scanBtn:SetPoint("LEFT", market, "RIGHT", 8, 0)
    scanBtn:SetScript("OnEnter", function(self)
        W.ShowTip(self, "Lire les annonces", "Scan complet de l'hôtel des ventes (une fois toutes les 15 minutes, limite du jeu). "
            .. "Le résultat est enregistré pour l'HDV choisi à gauche, avec l'heure du scan.")
    end)
    scanBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar.scanButton = scanBtn

    local stopBtn = W.Button(bar, "Tout arrêter", 110, 22, function()
        local stopped = A.StopAll()
        U.Print(#stopped > 0 and ("arrêté : " .. table.concat(stopped, ", ") .. ". Résultats déjà obtenus conservés.")
            or "aucune activité en cours.")
        bar.Update()
    end)
    stopBtn:SetPoint("LEFT", scanBtn, "RIGHT", 6, 0)
    stopBtn:SetScript("OnEnter", function(self)
        W.ShowTip(self, "Tout arrêter", "Arrête immédiatement la lecture des annonces, l'analyse de l'historique et les demandes d'informations au serveur. Les résultats déjà obtenus restent affichés. Équivalent : /sgl stop.")
    end)
    stopBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar.stopButton = stopBtn

    -- Recharger l'interface : charge les prix de l'API écrits par l'outil.
    local reload = W.IconButton(bar, W.ICON_RELOAD, "Recharger l'interface (/reload)",
        "Charge les prix des trois HDV mis à jour par l'application Shadsun Gold Lens et enregistre vos scans sur le disque. La fenêtre de l'HDV se fermera : reparlez au commissaire-priseur.",
        function() ReloadUI() end, 22, false)
    reload:SetPoint("TOPRIGHT", 0, 0)
    bar.reloadButton = reload

    local status = W.Text(bar, "GameFontHighlightSmall", "", "LEFT", width - 4)
    status:SetPoint("TOPLEFT", 2, -28)
    status:SetWordWrap(false)
    bar.status = status
    local hint = W.Text(bar, "GameFontHighlightSmall", "", "LEFT", width - 520)
    hint:SetPoint("LEFT", stopBtn, "RIGHT", 10, 0)
    hint:SetWordWrap(true)
    bar.hint = hint

    function bar.Update()
        market:SetOptions(options())
        local cur = MK.Current()
        -- Choix mémorisé ou zone ; avertissement si la zone ne concorde pas.
        local mismatch, zone = MK.Mismatch()
        if mismatch then
            hint:SetText(U.Color(U.colors.warn, "La zone indique " .. MK.Label(zone) .. " : vérifiez avant de lire."))
        elseif MK.Choice() then
            hint:SetText(U.Color(U.colors.dim, "Choix mémorisé pour " .. ns.Inventory.Me() .. "."))
        else
            hint:SetText(U.Color(U.colors.dim, "Déterminé par la zone."))
        end
        local txt
        if A.processing and A.progress then
            txt = string.format("Lecture en cours pour %s : %s / %s annonces", MK.ColorLabel(A.readingKey or cur),
                U.Group(A.progress.done), U.Group(A.progress.total))
        else
            txt = MK.ColorLabel(cur) .. " : " .. MK.Describe(cur)
            if not A.ahOpen then txt = txt .. U.Color(U.colors.dim, " · ouvrez l'HDV pour scanner") end
        end
        local cd = A.CooldownLeft()
        if cd > 0 and not A.processing then txt = txt .. U.Color(U.colors.dim, string.format(" · prochain scan complet dans %d min", math.ceil(cd / 60))) end
        local q = A.QueueSize()
        if q > 0 then txt = txt .. U.Color(U.colors.dim, string.format(" · %s infos en attente", U.Group(q))) end
        status:SetText(txt)
        scanBtn:SetEnabled((A.ahOpen and not A.processing) and true or false)
        stopBtn:SetEnabled(A.IsBusy() and true or false)
    end

    ns.On("ARBITRAGE_PROGRESS", function() if bar:IsVisible() then bar.Update() end end)
    ns.On("ARBITRAGE_CHANGED", function() if bar:IsVisible() then bar.Update() end end)
    ns.On("MARKET_CHANGED", function() if bar:IsVisible() then bar.Update() end end)
    ns.On("AH_SHOW", function() if bar:IsVisible() then bar.Update() end end)
    ns.On("AH_CLOSED", function() if bar:IsVisible() then bar.Update() end end)
    bar:SetScript("OnShow", function() bar.Update() end)
    local ticker = 0
    bar:SetScript("OnUpdate", function(_, elapsed)
        if not A.IsBusy() then return end
        ticker = ticker + elapsed
        if ticker >= 0.5 then ticker = 0; bar.Update() end
    end)
    bar.Update()
    return bar
end
