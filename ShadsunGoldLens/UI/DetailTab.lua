-- =============================================================================
-- Shadsun Gold Lens — UI/DetailTab.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Onglet « Objet » : recherche (ID, lien, nom), prix, rentabilité,
--      liste complète des marchands, navigation TomTom / carte, statut et
--      provenance des données.
-- EN : Item detail tab: search, prices, all vendors, navigation, provenance.
-- =============================================================================
local _, ns = ...
local U, L, W = ns.U, ns.L, ns.W
local C = ns.Catalog

ns.UI.RegisterTab("detail", "Objet", function(page)
    local current, currentLink, selectedOffer

    -- --- Recherche / search -------------------------------------------------
    local lbl = W.Text(page, "GameFontNormal", "Objet (ID, lien Maj+clic ou nom) :")
    lbl:SetPoint("TOPLEFT", 4, -4)
    local search = W.Edit(page, 200)
    search:SetPoint("LEFT", lbl, "RIGHT", 12, 0)
    page.search = search
    local results -- liste des correspondances / matches list

    local select -- forward
    local function lookup()
        local q = U.Trim(search:GetText())
        if q == "" then return end
        local id = U.ItemID(q)
        if id then
            results:Hide()
            select(id, q:find("item:") and q or nil)
            return
        end
        local found = C.SearchByName(q, 40)
        if #found == 1 then
            results:Hide()
            select(found[1].id)
        elseif #found > 1 then
            results.list:SetData(found)
            results:Show()
        else
            results:Hide()
            page.nameText:SetText(U.Color(U.colors.warn, "Aucun objet du catalogue ne correspond. Essayez l'ID ou un lien (Maj+clic)."))
        end
    end
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus(); lookup() end)
    local go = W.Button(page, "Chercher", 90, 22, lookup)
    go:SetPoint("LEFT", search, "RIGHT", 8, 0)
    local last = W.Button(page, "Dernier survol", 120, 22, function()
        if ns.lastItem then select(ns.lastItem, ns.lastLink) end
    end)
    last:SetPoint("LEFT", go, "RIGHT", 6, 0)

    -- Insertion d'un lien par Maj+clic quand le champ a le focus.
    W.AcceptLinks(search, function(box, link)
        box:SetText(link)
        lookup()
    end)

    -- Ajout à la liste d'achats active (Maj+clic : +5) / add to the active list
    local addList = W.Button(page, "Ajouter à la liste", 150, 22, function()
        if not current then U.Print("choisissez d'abord un objet.") return end
        local _, msg = ns.Lists.Step(current, (IsShiftKeyDown and IsShiftKeyDown()) and 5 or 1)
        U.Print(msg)
    end)
    addList:SetPoint("LEFT", last, "RIGHT", 6, 0)
    addList:SetScript("OnEnter", function(self)
        local l = ns.Lists.Active()
        W.ShowTip(self, "Ajouter à la liste d'achats", "Ajoute 1 exemplaire de l'objet affiché à la liste active"
            .. (l and (" (« " .. l.name .. " »)") or "") .. ". Maj+clic : +5. Choix de la liste et quantités : onglet Listes.")
    end)
    addList:SetScript("OnLeave", function() GameTooltip:Hide() end)
    page.addListButton = addList
    -- Le libellé indique la quantité déjà dans la liste active.
    local function refreshListState()
        local q = (current and ns.Lists) and ns.Lists.ActiveQty(current) or 0
        addList:SetText(q > 0 and ("Ajouter (" .. q .. " en liste)") or "Ajouter à la liste")
    end
    ns.On("LISTS_CHANGED", function() if page:IsVisible() then refreshListState() end end)

    -- --- En-tête objet / item header ----------------------------------------
    local icon = page:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36)
    icon:SetPoint("TOPLEFT", 4, -36)
    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    local iconBtn = CreateFrame("Button", nil, page)
    iconBtn:SetAllPoints(icon)
    iconBtn:SetScript("OnEnter", function(self)
        if current then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(current)
            GameTooltip:Show()
        end
    end)
    iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    page.nameText = W.Text(page, "GameFontNormalLarge", "Survolez un objet puis cliquez sur « Dernier survol », ou saisissez un ID.")
    page.nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
    page.nameText:SetWidth(740)
    local subText = W.Text(page, "GameFontHighlightSmall", "")
    subText:SetPoint("TOPLEFT", page.nameText, "BOTTOMLEFT", 0, -4)
    subText:SetWidth(740)

    -- --- Panneau prix / price panel -----------------------------------------
    local pricePanel = W.Panel(page, 400, 150)
    pricePanel:SetPoint("TOPLEFT", 0, -82)
    local priceRows = {}
    local labels = { "Achat PNJ (meilleur pour vous)", "Vente PNJ (prix reçu)", "HDV", "Bénéfice net",
        "Rentabilité", "Seuil de rentabilité HDV / u.", "Marge sur prix de vente" }
    for i, t in ipairs(labels) do
        local l = W.Text(pricePanel, "GameFontNormalSmall", t)
        l:SetPoint("TOPLEFT", 10, -8 - (i - 1) * 18)
        local v = W.Text(pricePanel, "GameFontHighlightSmall", "—", "RIGHT", 200)
        v:SetPoint("TOPRIGHT", -10, -8 - (i - 1) * 18)
        priceRows[i] = v
    end
    local verdict = W.Text(pricePanel, "GameFontHighlightSmall", "", "LEFT", 380)
    verdict:SetPoint("BOTTOMLEFT", 10, 8)

    local infoPanel = W.Panel(page, 400, 150)
    infoPanel:SetPoint("TOPLEFT", pricePanel, "TOPRIGHT", 12, 0)
    local infoText = W.Text(infoPanel, "GameFontHighlightSmall", "", "LEFT", 380)
    infoText:SetPoint("TOPLEFT", 10, -8)
    infoText:SetSpacing(3)

    -- --- Liste des vendeurs / vendor list -----------------------------------
    local header = W.Text(page, "GameFontNormal", "Marchands connus")
    header:SetPoint("TOPLEFT", pricePanel, "BOTTOMLEFT", 2, -10)
    local cols = { { "Marchand", 0, 168 }, { "Faction", 170, 62 }, { "Zone et coordonnées", 234, 196 },
        { "Prix", 432, 120 }, { "Remarques", 554, 104 }, { "", 660, 140 } }
    for _, c in ipairs(cols) do
        local h = W.Text(page, "GameFontNormalSmall", c[1])
        h:SetPoint("TOPLEFT", header, "BOTTOMLEFT", c[2], -6)
    end
    local list = W.List(page, 812, {
        rows = 7, rowHeight = 22,
        create = function(row)
            row.cells = {}
            for i = 1, 5 do
                local fs = W.Text(row, "GameFontHighlightSmall", "", "LEFT", cols[i][3])
                fs:SetPoint("LEFT", cols[i][2] + 2, 0)
                fs:SetWordWrap(false)
                row.cells[i] = fs
            end
            row.tomtom = W.Button(row, L.NAV_TOMTOM, 66, 18, function(self)
                local ok, msg = ns.Navigation.AddWaypoint(self:GetParent().data, page.itemName)
                U.Print(msg)
            end)
            row.tomtom:SetPoint("LEFT", 660, 0)
            row.map = W.Button(row, L.NAV_MAP, 60, 18, function(self)
                local ok, msg = ns.Navigation.ShowOnMap(self:GetParent().data)
                if not ok then U.Print(msg) end
            end)
            row.map:SetPoint("LEFT", row.tomtom, "RIGHT", 4, 0)
            row:SetScript("OnClick", function(self)
                page.list.selectedIndex = self.index
                page.list:Refresh()
                page.SelectOffer(self.data)
            end)
        end,
        update = function(row, o)
            local name = o.name
            if o.source == "PERSONAL" then name = name .. " " .. U.Color(U.colors.good, "(vu)") end
            row.cells[1]:SetText(name)
            row.cells[2]:SetText(U.SideText(o.side))
            row.cells[3]:SetText(C.LocationText(o))
            row.cells[4]:SetText(C.PriceText(o))
            local notes = {}
            if o.condText then notes[#notes + 1] = "Condition" end
            if o.unavailable then notes[#notes + 1] = "Indispo." elseif o.limited then notes[#notes + 1] = "Stock limité" end
            if o.moves then notes[#notes + 1] = "Itinérant" end
            if o.enemy then notes[#notes + 1] = "Adverse" end
            row.cells[5]:SetText(U.Color(U.colors.warn, table.concat(notes, ", ")))
            local valid = ns.Navigation.Validate(o)
            row.tomtom:SetEnabled(valid and true or false)
            row.map:SetEnabled(valid and true or false)
        end,
    })
    list:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -22)
    page.list = list

    -- --- Détail du vendeur sélectionné / selected vendor detail -------------
    local selText = W.Text(page, "GameFontHighlightSmall", "", "LEFT", 810)
    selText:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -6)
    selText:SetSpacing(2)
    local cmdLabel = W.Text(page, "GameFontNormalSmall", L.NAV_CMD)
    cmdLabel:SetPoint("BOTTOMLEFT", 4, 6)
    local cmdBox = W.CopyLine(page, 520)
    cmdBox:SetPoint("LEFT", cmdLabel, "RIGHT", 10, 0)

    function page.SelectOffer(o)
        selectedOffer = o
        if not o then selText:SetText(""); cmdBox:SetText(""); return end
        local parts = {
            U.Color(U.colors.title, o.name) .. " · PNJ n° " .. o.npc .. " · " .. U.SideText(o.side)
                .. " · " .. C.LocationText(o) .. " · " .. C.PriceText(o),
            "Source : " .. C.SourceText(o),
        }
        if o.condText then parts[#parts + 1] = "Condition : " .. o.condText end
        if o.stock and o.stock >= 0 then parts[#parts + 1] = "Stock observé : " .. o.stock
        elseif o.limited then parts[#parts + 1] = L.LIMITED end
        if o.moves then
            local alt = o.alt and U.MapName(o.alt.map)
            parts[#parts + 1] = L.MOVES .. (alt and (" · autre position connue : " .. alt .. " " .. U.Coord(o.alt.x) .. ", " .. U.Coord(o.alt.y)) or "")
        end
        selText:SetText(table.concat(parts, "\n"))
        cmdBox:SetText(ns.Navigation.Command(o) or L.NAV_CMD_NONE)
    end

    -- --- Rafraîchissement / refresh -----------------------------------------
    local function refresh()
        if not current then return end
        local view = C.GetView(current)
        local info = U.ItemInfo(current)
        local instant = U.ItemInstant(current)
        page.itemName = info and info.name or ns.Data.names[current]
        icon:SetTexture((info and info.icon) or (instant and instant.icon) or "Interface\\Icons\\INV_Misc_QuestionMark")
        local name = info and info.link or page.itemName or ("Objet n° " .. current)
        page.nameText:SetText(name)
        local sub = { "ID " .. current }
        if instant then
            sub[#sub + 1] = U.ClassName(instant.classID) or ("classe " .. tostring(instant.classID))
            if instant.classID == U.RECIPE_CLASS then
                sub[#sub + 1] = "Profession : " .. (U.SubClassName(instant.classID, instant.subClassID) or "?")
                local spell, spellID = U.ItemSpell(current)
                if spell then sub[#sub + 1] = "enseigne « " .. spell .. " »" .. (spellID and (" (sort " .. spellID .. ")") or "") end
            end
        end
        sub[#sub + 1] = U.Color(C.StatusColor(view.status), C.StatusText(view.status))
        subText:SetText(table.concat(sub, " · "))

        local best = view.best
        local price, age, state, liveTime, liveQty = ns.Prices.Best(current, info and info.link or currentLink)
        priceRows[1]:SetText(best and C.PriceText(best) or U.Color(U.colors.dim, view.status == "NONE" and "aucun vendeur connu" or "information non disponible"))
        priceRows[2]:SetText(info and ((info.sellPrice or 0) > 0 and U.Money(info.sellPrice) or L.UNSELLABLE) or L.UNKNOWN_YET)
        if price and state == "LIVE" then
            priceRows[3]:SetText(U.Money(price) .. U.Color(U.colors.dim, " (" .. ns.Market.Short(ns.Market.SellKey()) .. ", " .. ns.Market.SourceText(ns.Market.Snap(ns.Market.SellKey())) .. ")"))
        elseif price then
            priceRows[3]:SetText(U.Money(price) .. (age and (" (" .. (age == 0 and L.AH_TODAY or string.format(L.AH_AGE, age)) .. ")") or ""))
        elseif state == "VARIANTS" then
            priceRows[3]:SetText(U.Color(U.colors.dim, "indisponible — lire les annonces"))
        else
            priceRows[3]:SetText(U.Color(U.colors.dim, (state == "NO_ADDON" or state == "NO_API") and "Auctionator absent" or "indisponible — scan Auctionator"))
        end
        local r, reason = ns.Economy.Evaluate(current, best, price, age, info)
        if r then
            local col = ns.Economy.VerdictColor(r)
            priceRows[4]:SetText(U.Color(col, U.Money(r.profit, true, true)) .. (r.qty > 1 and (" / lot de " .. r.qty) or ""))
            priceRows[5]:SetText(U.Color(col, U.Percent(r.roi, true)))
            priceRows[6]:SetText(U.Money(r.breakEven))
            priceRows[7]:SetText(U.Percent(r.margin, true))
            local _, pct, market = ns.Economy.Rate()
            verdict:SetText(U.Color(col, ns.Economy.VerdictText(r)) .. U.Color(U.colors.dim,
                string.format(" · commission %s %% (%s)", tostring(pct), market == "neutral" and "HDV neutre" or "HDV de faction")))
        else
            priceRows[4]:SetText(U.Color(U.colors.dim, L.CALC_IMPOSSIBLE))
            for i = 5, 7 do priceRows[i]:SetText("—") end
            verdict:SetText(U.Color(U.colors.dim, tostring(reason or "")))
        end

        local info2 = {}
        info2[#info2 + 1] = U.Color(U.colors.title, "Statut : ") .. C.StatusText(view.status)
        info2[#info2 + 1] = U.Color(U.colors.title, "Possédé : ") .. (ns.Inventory.Text(current) or "aucun")
        if best then
            info2[#info2 + 1] = U.Color(U.colors.title, "Exclusivité : ") .. C.ExclusivityText(view.excl)
            local arb = C.ArbitrageText(view.excl)
            if arb then info2[#info2 + 1] = U.Color(U.colors.warn, arb) end
            info2[#info2 + 1] = U.Color(U.colors.title, "Vendeurs : ") .. #view.offers
                .. " · accessibles pour vous : " .. (function() local n = 0 for _, o in ipairs(view.offers) do if o.accessible then n = n + 1 end end return n end)()
            info2[#info2 + 1] = U.Color(U.colors.title, "Source du meilleur : ") .. C.SourceText(best)
        else
            info2[#info2 + 1] = view.status == "NONE" and L.NO_VENDOR_KNOWN or L.NO_DATA
            info2[#info2 + 1] = "Visitez un marchand qui le vend : l'add-on l'enregistrera automatiquement."
        end
        -- Prix sur chaque HDV scanné du serveur / price on each scanned AH
        local mparts = {}
        for _, key in ipairs(ns.Market.KEYS) do
            local s = ns.Market.Snap(key)
            if s then
                local unit, qty = ns.Market.Item(s, current)
                mparts[#mparts + 1] = ns.Market.ColorLabel(key, true) .. " " .. (unit and (U.Money(unit) .. U.Color(U.colors.dim, " (" .. U.Group(qty or 0) .. ", " .. ns.Market.SourceText(s) .. ")"))
                    or U.Color(U.colors.dim, "absent du scan"))
            end
        end
        info2[#info2 + 1] = U.Color(U.colors.title, "HDV scannés : ") .. (#mparts > 0 and table.concat(mparts, " · ") or U.Color(U.colors.dim, "aucun scan sur ce serveur"))
        infoText:SetText(table.concat(info2, "\n"))

        list:SetData(view.offers)
        list.selectedIndex = view.best and 1 or nil
        list:Refresh()
        page.SelectOffer(view.best)
    end
    page.Refresh = refresh

    select = function(id, link)
        current, currentLink = id, link
        search:SetText(tostring(id))
        U.RequestItem(id)
        refresh()
        refreshListState()
    end

    -- Liste des résultats de recherche par nom / name search results
    results = W.Panel(page, 420, 6 * 20 + 12)
    results:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -6, -2)
    results:SetFrameLevel(page:GetFrameLevel() + 20)
    results.list = W.List(results, 412, {
        rows = 6, rowHeight = 20,
        create = function(row)
            row.text = W.Text(row, "GameFontHighlightSmall", "", "LEFT", 380)
            row.text:SetPoint("LEFT", 6, 0)
            row:SetScript("OnClick", function(self) results:Hide(); select(self.data.id) end)
        end,
        update = function(row, d) row.text:SetText((U.QualityName(d.id, d.name) or d.name) .. U.Color(U.colors.dim, "  (" .. d.id .. ")")) end,
    })
    results.list:SetPoint("TOPLEFT", 4, -6)
    results:Hide()

    ns.RegisterEvent("GET_ITEM_INFO_RECEIVED", function(_, id)
        if id == current and page:IsVisible() then refresh() end
    end)
    ns.On("DATA_CHANGED", function() if page:IsVisible() then refresh() end end)
    ns.On("PRICES_CHANGED", function() if page:IsVisible() then refresh() end end)
    ns.On("SETTINGS_CHANGED", function() if page:IsVisible() then refresh() end end)
    ns.On("MARKET_CHANGED", function() if page:IsVisible() then refresh() end end)

    page.OnActivate = function(_, itemID)
        if itemID then select(itemID)
        elseif not current and ns.lastItem then select(ns.lastItem, ns.lastLink)
        elseif current then refresh() end
    end
end)
