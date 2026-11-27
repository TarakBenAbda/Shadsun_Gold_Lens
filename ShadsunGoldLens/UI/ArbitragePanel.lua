-- =============================================================================
-- Shadsun Gold Lens — UI/ArbitragePanel.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Liste « HDV » PNJ » réutilisable (acheter à l'HDV, revendre au
--      marchand) : panneau de l'hôtel des ventes et onglet Opportunités.
--      - Sources : annonces du dernier scan (Direct) et historique Auctionator.
--      - Filtres : catégorie (arbre de l'HDV), qualité, nom, gain minimal.
--      - Liste figeable : aucune mise à jour automatique tant qu'elle est figée.
--      - Icône loupe : recherche de l'objet dans l'HDV ; achat manuel.
--      opts.embedded = true : le bouton « Tout arrêter » est fourni par la
--      barre de scan du panneau de l'HDV.
-- EN : Reusable AH » vendor list: sources, filters, freeze, search icon.
-- =============================================================================
local _, ns = ...
local U, W = ns.U, ns.W
local AUI = {}
ns.ArbUI = AUI

local COLS = {
    { key = "name", label = "Objet", x = 0, w = 152 },
    { key = "minUnit", label = "HDV / u.", x = 154, w = 74, right = true, tip = "Prix unitaire le plus bas à l'HDV." },
    { key = "sell", label = "PNJ / u.", x = 230, w = 74, right = true, tip = "Prix payé par un marchand (donné par le jeu)." },
    { key = "gainUnit", label = "Gain / u.", x = 306, w = 76, right = true },
    { key = "qty", label = "Qté", x = 384, w = 38, right = true, tip = "Unités rentables en vente au moment du scan." },
    { key = "gain", label = "Gain total", x = 424, w = 80, right = true },
    { key = "source", label = "Source", x = 506, w = 62 },
    { key = "bags", label = "Sacs", x = 570, w = 36, right = true, tip = W.TIP_BAGS },
    { key = "sale", label = "Vente", x = 608, w = 36, right = true, tip = W.TIP_SALE },
    -- 0.16 : écart du prix d'achat à la valeur habituelle de l'HDV
    { key = "value", label = "Valeur", w = 50, right = true, menuLabel = "Écart à la valeur habituelle",
        tip = "Prix d'achat comparé à la valeur habituelle de cet HDV (moyenne sur 14 jours). Vert : vraie bonne affaire ; orange : prix gonflé." },
}
do
    local ORDER = { name = 1, minUnit = 2, sell = 3, gainUnit = 4, qty = 5, gain = 6, value = 7, source = 8, bags = 9, sale = 10 }
    for _, c in ipairs(COLS) do c.order = ORDER[c.key]; if c.key == "name" then c.flex = true end end
end
AUI.PRESETS = {
    { "ess", "Essentiel", { "name", "minUnit", "sell", "gainUnit", "gain" } },
    { "std", "Standard", { "name", "minUnit", "sell", "gainUnit", "qty", "gain", "value", "bags", "sale" } },
    { "all", "Complet" },
}
AUI.WIDTH = 730

function AUI.Build(parent, rowsCount, opts)
    opts = opts or {}
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetSize(AUI.WIDTH, 132 + rowsCount * 20)
    local A = ns.Arbitrage
    local state = { mode = "all", minGain = 1, sortKey = "gain", sortDesc = true, frozen = false }
    local filt = ns.Filters.New()
    local rows = {}
    local list, header

    -- --- Ligne 1 : actions / actions -------------------------------------------
    local histBtn = W.Button(panel, "Analyser l'historique Auctionator", 220, 22, function()
        if ns.Prices.State() ~= "OK" then U.Print("Auctionator indisponible."); return end
        A.ComputeHistoric()
        panel.UpdateStatus()
    end)
    histBtn:SetPoint("TOPLEFT", 0, 0)
    histBtn:SetScript("OnEnter", function(self)
        W.ShowTip(self, "Analyser l'historique Auctionator", "Compare le dernier prix connu par Auctionator au prix de rachat des marchands, pour tous les objets connus. Quantité et disponibilité inconnues : vérifiez dans l'HDV.")
    end)
    histBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local stopBtn = W.Button(panel, "Tout arrêter", 110, 22, function()
        local stopped = A.StopAll()
        U.Print(#stopped > 0 and ("arrêté : " .. table.concat(stopped, ", ") .. ". Résultats déjà obtenus conservés.")
            or "aucune activité en cours.")
        panel.UpdateStatus()
    end)
    stopBtn:SetPoint("LEFT", histBtn, "RIGHT", 6, 0)
    stopBtn:SetScript("OnEnter", function(self)
        W.ShowTip(self, "Tout arrêter", "Arrête immédiatement la lecture des annonces, l'analyse de l'historique et les demandes d'informations au serveur. Les résultats déjà obtenus restent affichés. Équivalent : /sgl stop.")
    end)
    stopBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    stopBtn:SetShown(not opts.embedded)
    panel.stopButton = stopBtn

    local refreshBtn = W.Button(panel, "Actualiser", 96, 22, function() panel.Refresh(true) end)
    refreshBtn:SetPoint("TOPRIGHT", -14, 0)
    local freeze = W.Check(panel, "Figer la liste", function() return state.frozen end, function(v)
        state.frozen = v
        if not v then panel.Refresh(true) end
    end, "Arrête les mises à jour automatiques de la liste (les lignes ne bougent plus). Décochez ou cliquez sur « Actualiser » pour appliquer les nouvelles données.")
    freeze:SetPoint("RIGHT", refreshBtn, "LEFT", -96, 0)

    -- --- Ligne 2 : source, gain minimal / source, minimum gain -----------------
    local src = W.Segmented(panel, {
        { "all", "Toutes", "Annonces du dernier scan et historique Auctionator." },
        { "live", "Direct (annonces)", "Annonces présentes au dernier scan complet : prix et quantité réels au moment du scan." },
        { "hist", "Historique", "Dernier prix connu par Auctionator : quantité et disponibilité inconnues." },
    }, function() return state.mode end, function(v) state.mode = v; panel.Refresh(false) end, { 76, 132, 96 })
    src:SetPoint("TOPLEFT", 0, -28)
    panel.sourceButtons = src
    local minLbl = W.Text(panel, "GameFontNormalSmall", "Gain min. / u. (pc) :")
    minLbl:SetPoint("LEFT", src, "RIGHT", 18, 0)
    local minEdit = W.Edit(panel, 50, function(self)
        state.minGain = math.max(0, math.floor(U.ParseNumber(self:GetText()) or 1))
        self:SetText(tostring(state.minGain))
        panel.Refresh(false)
    end)
    minEdit:SetPoint("LEFT", minLbl, "RIGHT", 8, 0)
    minEdit:SetText("1")

    -- --- Ligne 3 : filtres / filters --------------------------------------------
    local fbar = ns.Filters.Bar(panel, filt, function() panel.Refresh(false) end, { 220, 160, 170 })
    fbar:SetPoint("TOPLEFT", 0, -56)
    panel.filters = fbar

    local status = W.Text(panel, "GameFontHighlightSmall", "", "LEFT", AUI.WIDTH - 110)
    status:SetPoint("TOPLEFT", 0, -84)
    status:SetSpacing(2)

    -- --- Tableau / table ---------------------------------------------------------
    local function sortRows()
        local key, desc = state.sortKey, state.sortDesc
        table.sort(rows, function(a, b)
            local va, vb = a[key], b[key]
            if key == "name" then va, vb = U.Fold(a.name or ""), U.Fold(b.name or "") end
            if va == vb or va == nil or vb == nil then
                if va == nil and vb ~= nil then return false end
                if vb == nil and va ~= nil then return true end
                return a.id < b.id
            end
            if desc then return va > vb end
            return va < vb
        end)
        header:Update(key, desc)
    end
    local cs = W.ColumnSet(opts.columnsKey or "arb", COLS, { width = AUI.WIDTH - 14, locked = { name = true, gainUnit = true },
        presets = AUI.PRESETS, default = "std", iconPad = 20 })
    panel.columns = cs
    header = W.Header(panel, COLS, -112, AUI.WIDTH - 14, function(key)
        if state.sortKey == key then state.sortDesc = not state.sortDesc
        else state.sortKey, state.sortDesc = key, (key ~= "name" and key ~= "source") end
        sortRows()
        list:SetData(rows, true)
    end, function(anchor) cs.Menu(anchor) end)
    panel.header = header

    list = W.List(panel, AUI.WIDTH, {
        rows = rowsCount, rowHeight = 20,
        create = function(row)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(16, 16)
            row.icon:SetPoint("LEFT", 0, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.cells = {}
            for i, c in ipairs(COLS) do
                local fs = W.Text(row, "GameFontHighlightSmall", "", c.right and "RIGHT" or "LEFT", i == 1 and (c.w - 20) or c.w)
                fs:SetPoint("LEFT", i == 1 and 20 or c.x, 0)
                fs:SetWordWrap(false)
                row.cells[i] = fs
            end
            row.search = W.IconButton(row, W.ICON_SEARCH, "Rechercher dans l'HDV",
                "Lance la recherche de l'objet dans l'hôtel des ventes (Auctionator si présent). L'achat reste manuel.", function(self)
                    local _, msg = A.Search(self:GetParent().data.id)
                    U.Print(msg)
                end, 18, false)
            row.search:SetPoint("RIGHT", -2, 0)
            row.add = W.AddButton(row, function(self) return self:GetParent().data.id end)
            row.add:SetPoint("RIGHT", -22, 0)
            row:SetScript("OnClick", function(self) ns.UI.ShowItem(self.data.id) end)
            row:SetScript("OnEnter", function(self)
                local d = self.data
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(d.id)
                if d.source == "LIVE" then
                    GameTooltip:AddLine(string.format("Annonces rentables : %d · coût %s · gain total %s",
                        d.deals or 0, U.Money(d.spend or 0, true), U.Money(d.gain or 0, true)), 0.5, 0.9, 0.6, true)
                else
                    GameTooltip:AddLine("Prix issu de l'historique Auctionator" .. (d.age and (" (il y a " .. d.age .. " j)") or "")
                        .. " : quantité et disponibilité inconnues.", 1, 0.8, 0.4, true)
                end
                GameTooltip:AddLine("Clic : fiche de l'objet.", 0.63, 0.66, 0.71)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end,
        update = function(row, d)
            local info = U.ItemInfo(d.id)
            if info then d.name = info.name end
            local inst = U.ItemInstant(d.id)
            row.icon:SetTexture((info and info.icon) or (inst and inst.icon) or "Interface\\Icons\\INV_Misc_QuestionMark")
            local cells = row.cells
            cells[1]:SetText(U.QualityName(d.id, d.name or ns.Data.names[d.id]) or ("Objet n° " .. d.id))
            cells[2]:SetText(U.MoneyShort(d.minUnit))
            cells[3]:SetText(U.MoneyShort(d.sell))
            cells[4]:SetText(U.Color(U.colors.good, U.MoneyShort(d.gainUnit, true, true)))
            cells[5]:SetText(d.source == "LIVE" and tostring(d.qty) or U.Color(U.colors.dim, "?"))
            cells[6]:SetText(d.source == "LIVE" and U.Color(U.colors.good, U.MoneyShort(d.gain, true, true)) or U.Color(U.colors.dim, "-"))
            cells[7]:SetText(d.source == "LIVE" and U.Color(U.colors.good, "Direct") or U.Color(U.colors.warn, "Historique"))
            cells[8]:SetText(W.BagsText(d))
            cells[9]:SetText(W.SaleText(d))
            cells[10]:SetText(d.value and ns.Market.DeltaText(d.value, true) or U.Color(U.colors.dim, "-"))
            row.search:SetUsable(A.ahOpen)
        end,
    })
    list:SetPoint("TOPLEFT", 0, -132)
    panel.list = list
    cs.Bind(header, list, 20)
    cs.Apply()
    local colBtn = cs.Button(panel)
    colBtn:SetPoint("TOPRIGHT", -14, -82)
    panel.columnsButton = colBtn

    -- --- Statut / status ---------------------------------------------------------
    function panel.UpdateStatus()
        local liveTxt
        if A.processing and A.progress then
            liveTxt = string.format("lecture en cours : %s / %s annonces", U.Group(A.progress.done), U.Group(A.progress.total))
        elseif A.liveTime then
            A.Results("live")
            liveTxt = string.format("%s annonces lues à %s%s, %d opportunités%s", U.Group(A.liveTotal or 0), date("%H:%M", A.liveTime),
                A.liveKey and (" (" .. ns.Market.ColorLabel(A.liveKey) .. ")") or "", #A.liveResults,
                A.live and "" or U.Color(U.colors.dim, " · HDV fermé : résultats conservés"))
        elseif not A.CanReplicate() then
            liveTxt = "API de scan complet absente"
        else
            liveTxt = U.Color(U.colors.dim, "aucune lecture dans cette session — lisez les annonces à l'HDV")
        end
        local pend = A.PendingPrices()
        if pend > 0 and not A.processing then liveTxt = liveTxt .. string.format(" · %d prix de rachat en chargement", pend) end
        local histTxt
        if A.histRunning then histTxt = "analyse en cours…"
        elseif A.histTime then histTxt = string.format("%d opportunités (calculé à %s)", #A.histResults, date("%H:%M", A.histTime))
        else histTxt = U.Color(U.colors.dim, "non calculé") end
        status:SetText("Annonces : " .. liveTxt .. "\nHistorique Auctionator : " .. histTxt
            .. " · " .. U.Color(U.colors.title, #rows .. " ligne(s)") .. (state.frozen and U.Color(U.colors.warn, " · liste figée") or ""))
        stopBtn:SetEnabled(A.IsBusy() and true or false)
        src:Refresh()
    end

    local function emptyText()
        if ns.Filters.Active(filt) or state.minGain > 1 then return "Aucune ligne avec ces filtres." end
        if not A.liveTime and not A.histTime then
            return "Lisez les annonces à l'hôtel des ventes ou analysez l'historique Auctionator\npour trouver des objets vendus moins cher que leur prix de rachat."
        end
        return "Aucun objet de l'HDV n'est actuellement moins cher que son prix de rachat."
    end

    -- keep = true : mise à jour en place (position de défilement conservée)
    function panel.Refresh(keep)
        wipe(rows)
        local INV = ns.Inventory
        local MK = ns.Market
        local key = A.liveKey or MK.Current()
        for _, r in ipairs(A.Results(state.mode)) do
            if (r.gainUnit or 0) >= state.minGain then
                r.name = r.name or ns.Data.names[r.id]
                local _, usual = MK.KeyStats(key, r.id)
                r.value = MK.ValueDelta(r.minUnit, usual)
                if ns.Filters.Match(filt, r.id, r.name) then
                    INV.Stock(r)
                    rows[#rows + 1] = r
                end
            end
        end
        sortRows()
        list:SetEmptyText(emptyText())
        list:SetData(rows, keep)
        panel.UpdateStatus()
    end

    -- Mises à jour automatiques : jamais pendant la lecture, jamais si figée.
    ns.On("ARBITRAGE_CHANGED", function()
        if not panel:IsVisible() then return end
        if state.frozen or A.processing then panel.UpdateStatus() else panel.Refresh(true) end
    end)
    ns.On("ARBITRAGE_PROGRESS", function() if panel:IsVisible() then panel.UpdateStatus() end end)
    ns.On("AH_SHOW", function() if panel:IsVisible() then panel.UpdateStatus() end end)
    ns.On("AH_CLOSED", function() if panel:IsVisible() then list:Refresh(); panel.UpdateStatus() end end)
    panel:SetScript("OnShow", function() panel.Refresh(false) end)
    local function updateStock()
        if not panel:IsVisible() then return end
        ns.Inventory.StockAll(rows)
        if state.sortKey == "bags" or state.sortKey == "sale" then sortRows() end
        list:SetData(rows, true)
    end
    ns.On("INVENTORY_CHANGED", updateStock)
    ns.On("AUCTIONS_CHANGED", updateStock)
    ns.RegisterEvent("BAG_UPDATE_DELAYED", updateStock)

    -- Progression de la lecture affichée sans toucher à la liste (2 fois / s).
    local ticker = 0
    panel:SetScript("OnUpdate", function(_, elapsed)
        if not A.IsBusy() then return end
        ticker = ticker + elapsed
        if ticker >= 0.5 then ticker = 0; panel.UpdateStatus() end
    end)
    panel.state = state
    sortRows()
    return panel
end
