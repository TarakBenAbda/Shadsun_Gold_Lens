-- =============================================================================
-- Shadsun Gold Lens — UI/OpportunityList.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Liste des opportunités PNJ » HDV (acheter chez un marchand, revendre à
--      l'HDV), partagée par :
--       - l'onglet Opportunités (mode "window") : icônes Aller (TomTom) et
--         Copier (commande /tway) devant chaque objet ;
--       - le panneau de l'hôtel des ventes (mode "ah") : icône loupe.
--      Mêmes filtres, colonnes et calculs dans les deux. Prix HDV : scan du
--      marché de revente (paramètre), sinon historique Auctionator (« * »).
--      Calcul à la demande (Actualiser) et après chaque lecture des annonces.
-- EN : Shared vendor » AH opportunity list (window and AH modes).
-- =============================================================================
local _, ns = ...
local U, W = ns.U, ns.W
local OUI = {}
ns.OppUI = OUI

local LAYOUTS = {
    window = {
        width = 812, rows = 15, nameX = 42,
        bar = { 220, 150, 170 },
        cols = {
            { key = "name", label = "Objet", x = 42, w = 104 },
            { key = "prof", label = "Profession", x = 148, w = 76 },
            { key = "vendor", label = "Vendeur", x = 226, w = 84 },
            { key = "zone", label = "Zone", x = 312, w = 72 },
            { key = "side", label = "Fac.", x = 386, w = 32, tip = "Faction du marchand." },
            { key = "cost", label = "Achat / u.", x = 420, w = 70, right = true },
            { key = "ah", label = "HDV / u.", x = 492, w = 72, right = true, tip = "Prix du scan du marché de revente ; « * » = historique Auctionator." },
            { key = "profit", label = "Bénéfice", x = 566, w = 74, right = true, tip = "Bénéfice net par lot, commission déduite." },
            { key = "roi", label = "Rentab.", x = 642, w = 46, right = true },
            { key = "bags", label = "Sacs", x = 690, w = 32, right = true, tip = W.TIP_BAGS },
            { key = "sale", label = "Vente", x = 724, w = 32, right = true, tip = W.TIP_SALE },
        },
    },
    ah = {
        width = 730, rows = 17, nameX = 0,
        bar = { 200, 140, 150 },
        cols = {
            { key = "name", label = "Objet", x = 0, w = 106 },
            { key = "prof", label = "Profession", x = 108, w = 56 },
            { key = "vendor", label = "Vendeur", x = 166, w = 76 },
            { key = "zone", label = "Zone", x = 244, w = 60 },
            { key = "side", label = "Fac.", x = 306, w = 32, tip = "Faction du marchand." },
            { key = "cost", label = "Achat / u.", x = 340, w = 62, right = true },
            { key = "ah", label = "HDV / u.", x = 404, w = 64, right = true, tip = "Prix du scan du marché de revente ; « * » = historique Auctionator." },
            { key = "profit", label = "Bénéfice", x = 470, w = 64, right = true, tip = "Bénéfice net par lot, commission déduite." },
            { key = "roi", label = "Rentab.", x = 536, w = 44, right = true },
            { key = "bags", label = "Sacs", x = 582, w = 34, right = true, tip = W.TIP_BAGS },
            { key = "sale", label = "Vente", x = 618, w = 34, right = true, tip = W.TIP_SALE },
        },
    },
}

function OUI.Build(parent, mode)
    local layout = LAYOUTS[mode] or LAYOUTS.window
    local cols = layout.cols
    local C, P, E = ns.Catalog, ns.Prices, ns.Economy
    local page = CreateFrame("Frame", nil, parent)
    page:SetSize(layout.width, 120 + layout.rows * 20)
    local f = { side = "all", excl = "all", ah = "with", zone = "all", status = "all",
        maxCost = nil, minProfit = nil, minROI = nil, onlyProfit = true }
    local filt = ns.Filters.New()
    local rows = {}
    local list, header
    local computed = false

    -- --- Filtres / filters ---------------------------------------------------
    local function cycle(prefix, w, opts, key)
        return W.Cycle(page, w, prefix, opts, function() return f[key] end, function(v) f[key] = v; page.Compute() end)
    end
    local fbar = ns.Filters.Bar(page, filt, function() page.Compute() end, layout.bar)
    fbar:SetPoint("TOPLEFT", 0, 0)
    page.filters = fbar
    local side = cycle("Vendeur : ", mode == "ah" and 196 or 200, { { "all", "Toutes factions" }, { "mine", "Accessible pour moi" },
        { "A", "Alliance", U.colors.alliance }, { "H", "Horde", U.colors.horde }, { "N", "Neutre", U.colors.neutral } }, "side")
    side:SetPoint("TOPRIGHT", -14, 0)
    local y2 = -28
    local excl = cycle("Exclusivité : ", mode == "ah" and 180 or 200, { { "all", "Toutes" }, { "A", "Alliance seule" }, { "H", "Horde seule" }, { "BOTH", "Deux factions" } }, "excl")
    excl:SetPoint("TOPLEFT", 0, y2)
    local ahc = cycle("HDV : ", mode == "ah" and 140 or 150, { { "with", "Avec prix" }, { "all", "Tous" }, { "without", "Sans prix" } }, "ah")
    ahc:SetPoint("LEFT", excl, "RIGHT", 6, 0)
    local zone = cycle("Zone : ", mode == "ah" and 160 or 170, { { "all", "Toutes" }, { "here", "Zone actuelle" } }, "zone")
    zone:SetPoint("LEFT", ahc, "RIGHT", 6, 0)
    local status = cycle("Données : ", mode == "ah" and 170 or 180, { { "all", "Toutes" }, { "CONFIRMED", "Confirmées" }, { "REFERENCE", "À vérifier" } }, "status")
    status:SetPoint("LEFT", zone, "RIGHT", 6, 0)

    local y3 = -56
    local function numEdit(label, key, anchor, w)
        local fs = W.Text(page, "GameFontNormalSmall", label)
        if anchor then fs:SetPoint("LEFT", anchor, "RIGHT", 16, 0) else fs:SetPoint("TOPLEFT", 0, y3 - 4) end
        local e = W.Edit(page, w or 46, function(self) f[key] = U.ParseNumber(self:GetText()); if computed then page.Compute() end end)
        e:SetPoint("LEFT", fs, "RIGHT", 8, 0)
        return e
    end
    local e1 = numEdit("Achat max (po) :", "maxCost")
    local e2 = numEdit("Bénéfice min (po) :", "minProfit", e1)
    local e3 = numEdit("Rentab. min (%) :", "minROI", e2)
    local chk = W.Check(page, "Bénéfice > 0", function() return f.onlyProfit end, function(v) f.onlyProfit = v; page.Compute() end)
    chk:SetPoint("LEFT", e3, "RIGHT", 16, 0)
    local summary = W.Text(page, "GameFontHighlightSmall", "Cliquez sur « Actualiser » pour calculer.", "LEFT", layout.width - 10)
    summary:SetPoint("TOPLEFT", 0, -82)
    summary:SetWordWrap(false)

    -- --- Tri / sorting ---------------------------------------------------------
    local sortKey = ns.settings.opportunities.sortKey or "profit"
    local sortDesc = ns.settings.opportunities.sortDesc ~= false
    local TEXT_KEYS = { name = true, vendor = true, zone = true, prof = true }
    local function sortRows()
        table.sort(rows, function(a, b)
            local va, vb = a[sortKey], b[sortKey]
            if TEXT_KEYS[sortKey] then va, vb = va and U.Fold(va), vb and U.Fold(vb) end
            if va == nil and vb == nil then return a.id < b.id end
            if va == nil then return false end
            if vb == nil then return true end
            if va == vb then return a.id < b.id end
            if sortDesc then return va > vb end
            return va < vb
        end)
        header:Update(sortKey, sortDesc)
    end
    header = W.Header(page, cols, -100, layout.width - 14, function(key)
        if sortKey == key then sortDesc = not sortDesc
        else sortKey, sortDesc = key, not TEXT_KEYS[key] end
        ns.settings.opportunities.sortKey, ns.settings.opportunities.sortDesc = sortKey, sortDesc
        sortRows()
        list:SetData(rows, true)
    end)
    page.SortBy = function(key, desc) sortKey, sortDesc = key, desc; sortRows(); list:SetData(rows, true) end

    -- --- Tableau / table ---------------------------------------------------------
    list = W.List(page, layout.width, {
        rows = layout.rows, rowHeight = 20,
        empty = "Cliquez sur « Actualiser » pour calculer les opportunités.",
        create = function(row)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(16, 16)
            row.icon:SetPoint("LEFT", layout.nameX, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.cells = {}
            for i, c in ipairs(cols) do
                local fs = W.Text(row, "GameFontHighlightSmall", "", c.right and "RIGHT" or "LEFT", i == 1 and (c.w - 20) or c.w)
                fs:SetPoint("LEFT", i == 1 and (c.x + 20) or c.x, 0)
                fs:SetWordWrap(false)
                row.cells[i] = fs
            end
            if mode == "ah" then
                row.search = W.IconButton(row, W.ICON_SEARCH, "Rechercher dans l'HDV",
                    "Lance la recherche de l'objet dans l'hôtel des ventes (Auctionator si présent).", function(self)
                        local _, msg = ns.Arbitrage.Search(self:GetParent().data.id)
                        U.Print(msg)
                    end, 18, false)
                row.search:SetPoint("RIGHT", -2, 0)
                row.add = W.AddButton(row, function(self) return self:GetParent().data.id end)
                row.add:SetPoint("RIGHT", -22, 0)
            else
                row.add = W.AddButton(row, function(self) return self:GetParent().data.id end)
                row.add:SetPoint("RIGHT", -2, 0)
                row.go = W.IconButton(row, W.ICON_MAP, "Aller", "Place un point TomTom vers le marchand (repère de la carte si TomTom est absent).", function(self)
                    local d = self:GetParent().data
                    local _, msg = ns.Navigation.AddWaypoint(d.offer, d.name)
                    U.Print(msg)
                end, 18)
                row.go:SetPoint("LEFT", 0, 0)
                row.copy = W.IconButton(row, W.ICON_COPY, "Copier la commande /tway", "Ouvre la commande déjà sélectionnée : Ctrl+C, puis collez-la dans le chat.", function(self)
                    local d = self:GetParent().data
                    local cmd = ns.Navigation.Command(d.offer)
                    if cmd then ns.UI.ShowCopyLine(cmd) else U.Print(ns.L.NAV_CMD_NONE) end
                end, 18)
                row.copy:SetPoint("LEFT", 20, 0)
            end
            row:SetScript("OnClick", function(self) ns.UI.ShowItem(self.data.id) end)
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(self.data.id)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end,
        update = function(row, d)
            local info = U.ItemInfo(d.id)
            if info then d.name = info.name else U.RequestItem(d.id) end
            local inst = U.ItemInstant(d.id)
            row.icon:SetTexture((info and info.icon) or (inst and inst.icon) or "Interface\\Icons\\INV_Misc_QuestionMark")
            local cells = row.cells
            cells[1]:SetText(U.QualityName(d.id, d.name) or d.name)
            cells[2]:SetText(d.prof or "")
            cells[3]:SetText(d.vendor)
            cells[4]:SetText(d.zone or "?")
            cells[5]:SetText(U.SideText(d.side))
            cells[6]:SetText(d.cost and U.MoneyShort(d.cost) or "-")
            if d.ah then
                cells[7]:SetText(U.MoneyShort(d.ah) .. (d.source == "LIVE" and "" or U.Color(U.colors.warn, "*")))
            else
                cells[7]:SetText(U.Color(U.colors.dim, "-"))
            end
            if d.profit then
                local col = d.profit > 0 and U.colors.good or U.colors.bad
                cells[8]:SetText(U.Color(col, U.MoneyShort(d.profit, true, true)))
                cells[9]:SetText(U.Color(col, U.PercentShort(d.roi)))
            else
                cells[8]:SetText(U.Color(U.colors.dim, "-"))
                cells[9]:SetText(U.Color(U.colors.dim, "-"))
            end
            cells[10]:SetText(W.BagsText(d))
            cells[11]:SetText(W.SaleText(d))
            if row.search then row.search:SetUsable(ns.Arbitrage.ahOpen) end
            if row.go then
                local valid = ns.Navigation.Validate(d.offer) and true or false
                row.go:SetUsable(valid)
                row.copy:SetUsable(valid)
            end
        end,
    })
    list:SetPoint("TOPLEFT", 0, -120)
    page.list = list

    -- --- Calcul / computation ---------------------------------------------------
    function page.Compute()
        computed = true
        wipe(rows)
        local playerMap = C.PlayerMap()
        local counted, withAH, live = 0, 0, 0
        local INV = ns.Inventory
        for _, id in ipairs(C.AllItemIDs()) do
            local view = C.GetView(id)
            local best = view.best
            if best then
                local ok = true
                if f.side ~= "all" then
                    if f.side == "mine" then ok = best.accessible
                    else
                        ok = false
                        for _, o in ipairs(view.offers) do if o.side == f.side then ok = true; break end end
                    end
                end
                if ok and f.excl ~= "all" and view.excl.code ~= f.excl then ok = false end
                if ok and f.zone == "here" and best.map ~= playerMap then ok = false end
                if ok and f.status ~= "all" and view.status ~= f.status then ok = false end
                if ok and not ns.Filters.Match(filt, id) then ok = false end
                if ok then
                    counted = counted + 1
                    local info = U.ItemInfo(id)
                    local instant = U.ItemInstant(id)
                    local isRecipe = instant and instant.classID == U.RECIPE_CLASS
                    local price, age, pstate = P.Best(id, info and info.link)
                    if price then withAH = withAH + 1 end
                    local r = E.Evaluate(id, best, price, age, info)
                    local unit = (not best.ext and best.price > 0) and math.floor(best.price / best.qty + 0.5) or nil
                    local d = {
                        id = id, name = (info and info.name) or ns.Data.names[id] or ("Objet n° " .. id),
                        prof = isRecipe and U.SubClassName(instant.classID, instant.subClassID) or (instant and U.ClassName(instant.classID)),
                        vendor = best.name, zone = U.MapName(best.map), side = best.side, offer = best,
                        cost = unit, ah = price, age = age, source = pstate,
                        profit = r and r.profit, roi = r and r.roi, status = view.status,
                    }
                    INV.Stock(d)
                    local keep = true
                    if f.ah == "with" and not price then keep = false end
                    if f.ah == "without" and price then keep = false end
                    if keep and f.onlyProfit and not (r and r.profit > 0) then keep = false end
                    if keep and f.maxCost and (not unit or unit > f.maxCost * 10000) then keep = false end
                    if keep and f.minProfit and (not r or r.profit < f.minProfit * 10000) then keep = false end
                    if keep and f.minROI and (not r or (r.roi or -1e9) < f.minROI) then keep = false end
                    if keep then
                        rows[#rows + 1] = d
                        if pstate == "LIVE" then live = live + 1 end
                    end
                end
            end
        end
        sortRows()
        list:SetEmptyText(counted == 0 and "Aucun objet ne correspond à ces filtres."
            or (withAH == 0 and "Aucun prix HDV connu : lisez les annonces à l'HDV (scan complet)\nou effectuez un scan Auctionator."
            or "Aucune opportunité avec ces filtres."))
        list:SetData(rows, true)
        local MK = ns.Market
        local sell = MK.SellKey()
        local snap = MK.Snap(sell)
        local state = P.State()
        summary:SetText(string.format("%s · %d objets filtrés · %d avec prix HDV · %d d'après %s%s",
            U.Color(U.colors.title, #rows .. " ligne(s)"), counted, withAH, live,
            MK.ColorLabel(sell) .. (snap and U.Color(U.colors.dim, " (" .. MK.SourceText(snap) .. ")") or U.Color(U.colors.dim, " (aucun)")),
            state == "OK" and "" or " · Auctionator indisponible"))
    end

    local refreshBtn = W.Button(page, "Actualiser", 100, 22, function() page.Compute() end)
    refreshBtn:SetPoint("TOPRIGHT", -14, y3)
    page.refreshButton = refreshBtn

    -- Possédé : mis à jour quand les sacs changent (tri par « Poss. » exact).
    local function updateOwned()
        if not page:IsVisible() or #rows == 0 then return end
        ns.Inventory.StockAll(rows)
        if sortKey == "bags" or sortKey == "sale" then sortRows() end
        list:SetData(rows, true)
    end
    ns.RegisterEvent("BAG_UPDATE_DELAYED", updateOwned)
    ns.On("INVENTORY_CHANGED", updateOwned)
    ns.On("AUCTIONS_CHANGED", updateOwned)
    -- Noms en cours de chargement (limité, sans recalcul).
    local pendingRefresh = false
    ns.RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
        if not page:IsVisible() or pendingRefresh then return end
        pendingRefresh = true
        C_Timer.After(0.5, function() pendingRefresh = false; if page:IsVisible() then list:Refresh() end end)
    end)
    -- Recalcul après une lecture complète des annonces (pas à chaque info reçue).
    ns.On("ARBITRAGE_CHANGED", function(reason)
        if reason == nil and computed and page:IsVisible() and not ns.Arbitrage.processing then page.Compute() end
    end)
    ns.On("SETTINGS_CHANGED", function() if computed and page:IsVisible() then page.Compute() end end)
    page.Rows = function() return rows end
    sortRows()
    return page
end
