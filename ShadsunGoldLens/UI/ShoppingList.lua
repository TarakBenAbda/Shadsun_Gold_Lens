-- =============================================================================
-- Shadsun Gold Lens — UI/ShoppingList.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Vue des articles d'une liste d'achats, réutilisable (icônes Aller et
--      Copier vers le marchand hors HDV, loupe à l'HDV) :
--       - onglet Listes de la fenêtre principale (mode "window") ;
--       - panneau de l'hôtel des ventes (mode "ah"), avec un sélecteur de
--         liste à la place du titre.
--      Pour chaque article : quantité voulue, progression (possédé par vos
--      personnages du serveur), exemplaires en vente à l'HDV, prix maximum,
--      prix sur chaque HDV (scan ou
--      API, le moins cher sous le maximum en vert), loupe (HDV ouvert) et
--      retrait. « Rechercher toute la liste » cherche les articles non
--      obtenus. Filtre « Meilleur achat » (où l'article est le moins cher sous
--      le prix maximum), case « Seulement là où ce personnage peut acheter »
--      (ignore l'HDV de l'autre faction), tri par clic sur chaque colonne.
--      Recherche et achat manuels.
-- EN : Reusable shopping-list items view (window and AH modes).
-- =============================================================================
local _, ns = ...
local U, W = ns.U, ns.W
local SUI = {}
ns.ShopUI = SUI

-- name = { x, largeur } ; nameX = décalage de l'icône d'objet (icônes Aller
-- et Copier devant le nom en mode "window").
local LAYOUTS = {
    window = { width = 602, rows = 12, nameX = 42,
        cols = { name = { 42, 110 }, qty = { 154, 36 }, prog = { 192, 54 }, sale = { 248, 36 }, max = { 286, 56 }, pnj = { 344, 54 },
            m1 = { 400, 54 }, m2 = { 456, 54 }, m3 = { 512, 54 } } },
    ah = { width = 730, rows = 15, nameX = 0,
        cols = { name = { 0, 166 }, qty = { 168, 44 }, prog = { 214, 62 }, sale = { 278, 40 }, max = { 320, 70 }, pnj = { 392, 68 },
            m1 = { 462, 68 }, m2 = { 532, 68 }, m3 = { 602, 66 } } },
}

-- Meilleure offre d'un marchand pour un objet : prix unitaire, offre.
-- Best vendor offer: unit price and offer (nil if paid in currency).
local function vendorOffer(id)
    local view = ns.Catalog.GetView(id)
    local best = view and view.best
    if not best then return nil, nil end
    if best.ext or not best.price or best.price <= 0 then return nil, best end
    return math.floor(best.price / math.max(1, best.qty or 1) + 0.5), best
end
SUI.VendorOffer = vendorOffer

function SUI.Build(parent, mode)
    local layout = LAYOUTS[mode] or LAYOUTS.window
    local LS, MK, A = ns.Lists, ns.Market, ns.Arbitrage
    local WIDTH = layout.width
    local view = CreateFrame("Frame", nil, parent)
    view:SetSize(WIDTH, 440)
    local selectedItem
    local mine = function() return MK.PlayerKey() end
    local other = function() return MK.PlayerKey() == "A" and "H" or "A" end

    -- --- En-tête : titre ou sélecteur de liste / header ---------------------------
    local title, selector
    if mode == "ah" then
        selector = W.Dropdown(view, 300, "Liste : ", function() local l = LS.Active(); return l and l.name or "?" end, function()
            local items, cur = {}, LS.ActiveId()
            for _, l in ipairs(LS.All()) do
                local done = 0
                for _, e in ipairs(l.items) do if select(3, LS.Progress(e)) then done = done + 1 end end
                items[#items + 1] = { text = l.name .. "  (" .. done .. "/" .. #l.items .. ")", value = l.id, checked = l.id == cur }
            end
            return items
        end, function(v) LS.SetActive(v) end, "Choisissez la liste à afficher. Création et gestion des listes : onglet Listes de la fenêtre principale (/sgl listes).")
        selector:SetPoint("TOPLEFT", 0, 0)
        view.selector = selector
    else
        title = W.Text(view, "GameFontNormalLarge", "", "LEFT", WIDTH - 230)
        title:SetPoint("TOPLEFT", 0, -2)
        title:SetWordWrap(false)
    end
    local searchAll = W.Button(view, "Rechercher toute la liste", 200, 22, function()
        local l = LS.Active()
        if not l or #l.items == 0 then U.Print("la liste est vide.") return end
        local ids = {}
        for _, e in ipairs(l.items) do
            if not select(3, LS.Progress(e)) then ids[#ids + 1] = e.id end
        end
        if #ids == 0 then U.Print("tous les articles sont déjà obtenus.") return end
        local _, msg = A.SearchMany(ids)
        U.Print(msg)
    end)
    searchAll:SetPoint("TOPRIGHT", -14, 0)
    searchAll:SetScript("OnEnter", function(self)
        W.ShowTip(self, "Rechercher toute la liste", "Lance la recherche de tous les articles non encore obtenus (Auctionator : une seule recherche groupée). HDV ouvert uniquement. Achat manuel.")
    end)
    searchAll:SetScript("OnLeave", function() GameTooltip:Hide() end)
    view.searchAllButton = searchAll

    -- --- Ajout par ID, lien ou nom / add by ID, link or name -----------------------
    local addLbl = W.Text(view, "GameFontNormalSmall", "Ajouter :")
    addLbl:SetPoint("TOPLEFT", 0, -34)
    local addEdit = CreateFrame("EditBox", nil, view, "InputBoxTemplate")
    addEdit:SetSize(mode == "ah" and 300 or 260, 20)
    addEdit:SetAutoFocus(false)
    addEdit:SetPoint("LEFT", addLbl, "RIGHT", 10, 0)
    view.addEdit = addEdit
    local function doAdd()
        local txt = U.Trim(addEdit:GetText() or "")
        if txt == "" then return end
        local id = U.ItemID(txt) or tonumber(txt)
        if not id then
            local found = ns.Catalog.SearchByName(txt, 1)
            id = found and found[1] and found[1].id
        end
        if not id then U.Print("objet introuvable : tapez son ID, Maj+clic sur l'objet, ou un nom connu.") return end
        local _, msg = LS.Add(id, 1)
        U.Print(msg)
        addEdit:SetText("")
        addEdit:ClearFocus()
    end
    addEdit:SetScript("OnEnterPressed", doAdd)
    addEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local addBtn = W.Button(view, "Ajouter", 80, 22, doAdd)
    addBtn:SetPoint("LEFT", addEdit, "RIGHT", 8, 0)
    local addHint = W.Text(view, "GameFontDisableSmall", "ID, nom, ou Maj+clic sur un objet", "LEFT", 220)
    addHint:SetPoint("LEFT", addBtn, "RIGHT", 10, 0)
    -- Maj+clic sur un objet pendant que le champ a le focus : ajout direct.
    W.AcceptLinks(addEdit, function(box, link)
        box:SetText(link)
        doAdd()
    end)

    -- --- Filtre « Meilleur achat » / best-buy filter -------------------------------------
    local FILTERS = { { "all", "Tous" }, { "pnj", "PNJ" }, { "A", "HDV Alliance" }, { "H", "HDV Horde" },
        { "N", "HDV neutre" }, { "none", "Aucune offre sous le prix max" } }
    local filterBox = W.Cycle(view, mode == "ah" and 300 or 250, "Meilleur achat : ", FILTERS,
        function() return ns.settings.lists.bestFilter or "all" end,
        function(v) ns.settings.lists.bestFilter = v; ns.Fire("LISTS_CHANGED") end,
        "N'affiche que les articles dont l'offre la moins chère (sous votre prix maximum) se trouve à cet endroit : la case verte du tableau. Clic droit ou molette : valeur suivante.")
    filterBox:SetPoint("TOPLEFT", 0, -60)
    view.filterBox = filterBox
    local buyable = W.Check(view, "Seulement là où ce personnage peut acheter",
        function() return ns.settings.lists.buyableOnly end,
        function(v) ns.settings.lists.buyableOnly = v; ns.Fire("LISTS_CHANGED") end,
        "Ignore l'HDV de l'autre faction (et les marchands qui ne vous vendent pas) pour la case verte et le filtre. Décochée : les quatre prix sont comparés, utile avec un personnage dans chaque faction.")
    buyable:SetPoint("LEFT", filterBox, "RIGHT", 12, 0)
    buyable:SetChecked(ns.settings.lists.buyableOnly and true or false)
    view.buyableCheck = buyable

    -- --- Tableau / table -------------------------------------------------------------
    local C = layout.cols
    local COLS = {
        { key = "name", label = "Objet", x = C.name[1], w = C.name[2] },
        { key = "qty", label = "Voulu", x = C.qty[1], w = C.qty[2], right = true },
        { key = "prog", label = "Possédé", x = C.prog[1], w = C.prog[2], right = true, tip = "Possédé par vos personnages du serveur (sacs et banque) / quantité voulue. Les objets mis en vente ne comptent pas." },
        { key = "sale", label = "Vente", x = C.sale[1], w = C.sale[2], right = true, tip = "Exemplaires mis en vente à l'HDV, pas encore vendus (tous vos personnages du serveur). Relevé exact à chaque visite de l'HDV, corrigé ensuite par les messages de vente et d'expiration ; « ~ » = au plus." },
        { key = "max", label = "Prix max", x = C.max[1], w = C.max[2], right = true, tip = "Prix unitaire maximum que vous acceptez (facultatif)." },
        { key = "pnj", label = "PNJ", x = C.pnj[1], w = C.pnj[2], right = true, tip = "Prix d'achat unitaire chez le meilleur marchand connu (base des marchands)." },
        { key = "m1", label = "Faction", x = C.m1[1], w = C.m1[2], right = true },
        { key = "m2", label = "Autre", x = C.m2[1], w = C.m2[2], right = true },
        { key = "m3", label = "Neutre", x = C.m3[1], w = C.m3[2], right = true },
    }
    local sortKey, sortDesc
    local header
    header = W.Header(view, COLS, -86, WIDTH - 14, function(key)
        if sortKey == key then sortDesc = not sortDesc else sortKey, sortDesc = key, false end
        view.Refresh()
    end)
    view.header = header
    local rows = {}
    local list
    function view.SortBy(key, desc) sortKey, sortDesc = key, desc and true or false; view.Refresh() end

    -- Prix de l'article sur un HDV (scan ou prix téléchargés) / price on an AH
    local function priceOn(key, id)
        local snap = MK.Snap(key)
        return snap and MK.Item(snap, id) or nil
    end

    -- Meilleure offre sous le prix maximum : (prix, "pnj" | "A" | "H" | "N") ou nil.
    -- buyableOnly : ignore l'HDV de l'autre faction et les marchands inaccessibles.
    local function bestOffer(d, buyableOnly)
        local best, key
        if d.pnj and ((not d.max) or d.pnj <= d.max) and d.offer and d.offer.accessible ~= false then
            best, key = d.pnj, "pnj"
        end
        for _, k in ipairs({ mine(), other(), "N" }) do
            local p = d.prices[k]
            if p and (not d.max or p <= d.max) and (not best or p < best) and not (buyableOnly and k == other()) then
                best, key = p, k
            end
        end
        return best, key
    end
    SUI.BestOffer = bestOffer

    -- Valeur de tri d'une ligne / sort value (nil = toujours en bas)
    local SORTERS = {
        name = function(d) return U.Fold(d.name or ("objet n° " .. d.id)) end,
        qty = function(d) return d.qty end,
        prog = function(d) return d.qty > 0 and d.owned / d.qty or 0 end,
        sale = function(d) return d.saleN end,
        max = function(d) return d.max end,
        pnj = function(d) return d.pnj end,
        m1 = function(d) return d.prices[mine()] end,
        m2 = function(d) return d.prices[other()] end,
        m3 = function(d) return d.prices.N end,
    }

    list = W.List(view, WIDTH, {
        rows = layout.rows, rowHeight = 20,
        empty = "Liste vide.\nAjoutez des objets avec l'icône « + » des tableaux, Alt+clic sur un objet,\nou le champ « Ajouter » ci-dessus.",
        create = function(row)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(16, 16)
            row.icon:SetPoint("LEFT", layout.nameX, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.cells = {}
            for i, c in ipairs(COLS) do
                local fs = W.Text(row, "GameFontHighlightSmall", "", c.right and "RIGHT" or "LEFT", i == 1 and (c.w - 20) or c.w)
                fs:SetPoint("LEFT", i == 1 and (c.x + 20) or c.x, 0)
                fs:SetWordWrap(false)
                row.cells[i] = fs
            end
            row.sel = row:CreateTexture(nil, "BACKGROUND")
            row.sel:SetAllPoints()
            row.sel:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.14)
            row.remove = W.IconButton(row, W.ICON_REMOVE, "Retirer de la liste", "Retire cet article de la liste.", function(self)
                LS.Remove(LS.ActiveId(), self:GetParent().data.id)
            end, 16, false)
            row.remove:SetPoint("RIGHT", -2, 0)
            if mode == "ah" then
                -- À l'HDV : loupe / at the AH: search icon
                row.search = W.IconButton(row, W.ICON_SEARCH, "Rechercher dans l'HDV",
                    "Lance la recherche de cet article dans l'hôtel des ventes (Auctionator si présent). Achat manuel.", function(self)
                        local _, msg = A.Search(self:GetParent().data.id)
                        U.Print(msg)
                    end, 18, false)
                row.search:SetPoint("RIGHT", -22, 0)
            else
                -- Hors HDV : aller au marchand (TomTom) ou copier la commande /tway
                row.go = W.IconButton(row, W.ICON_MAP, "Aller au marchand", "Place un point TomTom vers le meilleur marchand connu (repère de la carte si TomTom est absent).", function(self)
                    local d = self:GetParent().data
                    if not d.offer then return end
                    local _, msg = ns.Navigation.AddWaypoint(d.offer, d.name)
                    U.Print(msg)
                end, 18)
                row.go:SetPoint("LEFT", 0, 0)
                row.copy = W.IconButton(row, W.ICON_COPY, "Copier la commande /tway", "Ouvre la commande déjà sélectionnée : Ctrl+C, puis collez-la dans le chat.", function(self)
                    local d = self:GetParent().data
                    local cmd = d.offer and ns.Navigation.Command(d.offer)
                    if cmd then ns.UI.ShowCopyLine(cmd) else U.Print(ns.L.NAV_CMD_NONE) end
                end, 18)
                row.copy:SetPoint("LEFT", 20, 0)
            end
            row:SetScript("OnClick", function(self)
                selectedItem = self.data.id
                view.Refresh()
            end)
            row:SetScript("OnEnter", function(self)
                local d = self.data
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(d.id)
                if d.offer then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddDoubleLine("Marchand : " .. tostring(d.offer.name or "?"),
                        (d.pnj and U.Money(d.pnj) or U.Color(U.colors.warn, "devise")), 1, 0.82, 0, 1, 1, 1)
                    GameTooltip:AddLine(ns.Catalog.LocationText(d.offer), 0.8, 0.8, 0.8, true)
                end
                local sale = ns.Auctions and ns.Auctions.Text(d.id)
                if sale then GameTooltip:AddDoubleLine("En vente :", sale, 1, 0.82, 0, 1, 1, 1) end
                GameTooltip:AddLine("Clic : modifier la quantité et le prix maximum.", 0.63, 0.66, 0.71)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end,
        update = function(row, d)
            local info = U.ItemInfo(d.id)
            if not info then U.RequestItem(d.id) end
            local inst = U.ItemInstant(d.id)
            row.icon:SetTexture((info and info.icon) or (inst and inst.icon) or "Interface\\Icons\\INV_Misc_QuestionMark")
            local c = row.cells
            c[1]:SetText(U.QualityName(d.id, (info and info.name) or ns.Data.names[d.id]) or ("Objet n° " .. d.id))
            c[2]:SetText(tostring(d.qty))
            c[3]:SetText(U.Color(d.done and U.colors.good or U.colors.title, d.owned .. " / " .. d.qty))
            c[4]:SetText(d.sale and U.Color(U.colors.title, d.sale) or U.Color(U.colors.dim, "-"))
            c[5]:SetText(d.max and U.MoneyShort(d.max) or U.Color(U.colors.dim, "-"))
            -- PNJ puis les trois HDV ; le moins cher (sous le maximum) en vert.
            if d.pnj then
                local ok = (not d.max) or d.pnj <= d.max
                c[6]:SetText(ok and U.MoneyShort(d.pnj) or U.Color(U.colors.dim, U.MoneyShort(d.pnj, true)))
            else
                c[6]:SetText(U.Color(U.colors.dim, d.offer and "devise" or "-"))
            end
            for i, key in ipairs({ mine(), other(), "N" }) do
                local p = d.prices[key]
                if not p then c[6 + i]:SetText(U.Color(U.colors.dim, "-"))
                else
                    local ok = (not d.max) or p <= d.max
                    c[6 + i]:SetText(ok and U.MoneyShort(p) or U.Color(U.colors.dim, U.MoneyShort(p, true)))
                end
            end
            if d.bestKey and not d.done then
                local col = d.bestKey == "pnj" and 6 or (d.bestKey == mine() and 7 or (d.bestKey == other() and 8 or 9))
                c[col]:SetText(U.Color(U.colors.good, U.MoneyShort(d.best, true)))
            end
            row.sel:SetShown(d.id == selectedItem)
            if row.search then row.search:SetUsable(A.ahOpen) end
            if row.go then
                local valid = d.offer and ns.Navigation.Validate(d.offer) and true or false
                row.go:SetUsable(valid)
                row.copy:SetUsable(valid)
            end
        end,
    })
    list:SetPoint("TOPLEFT", 0, -106)
    view.itemsList = list

    -- --- Édition de l'article choisi / edit selected item ---------------------------
    local yEdit = -106 - layout.rows * 20 - 10
    local editLbl = W.Text(view, "GameFontNormalSmall", "", "LEFT", mode == "ah" and 300 or 200)
    editLbl:SetPoint("TOPLEFT", 0, yEdit - 4)
    editLbl:SetWordWrap(false)
    local qtyLbl = W.Text(view, "GameFontNormalSmall", "Quantité voulue :")
    qtyLbl:SetPoint("LEFT", editLbl, "RIGHT", 10, 0)
    local qtyEdit = W.Edit(view, 50, function(self)
        if selectedItem then LS.SetQty(LS.ActiveId(), selectedItem, U.ParseNumber(self:GetText())) end
    end)
    qtyEdit:SetPoint("LEFT", qtyLbl, "RIGHT", 8, 0)
    local maxLbl = W.Text(view, "GameFontNormalSmall", "Prix max (po) :")
    maxLbl:SetPoint("LEFT", qtyEdit, "RIGHT", 16, 0)
    local maxEdit = W.Edit(view, 60, function(self)
        if selectedItem then
            local v = U.ParseNumber(self:GetText())
            LS.SetMax(LS.ActiveId(), selectedItem, v and math.floor(v * 10000 + 0.5) or nil)
        end
    end)
    maxEdit:SetPoint("LEFT", maxLbl, "RIGHT", 8, 0)
    view.qtyEdit, view.maxEdit = qtyEdit, maxEdit
    local editWidgets = { qtyLbl, qtyEdit, maxLbl, maxEdit }

    local summary = W.Text(view, "GameFontHighlightSmall", "", "LEFT", WIDTH - 10)
    summary:SetPoint("TOPLEFT", 0, yEdit - 30)
    summary:SetWordWrap(false)
    -- Coût de la liste au meilleur prix connu (case verte) / list cost line
    local totalText = W.Text(view, "GameFontHighlightSmall", "", "LEFT", WIDTH - 10)
    totalText:SetPoint("TOPLEFT", 0, yEdit - 46)
    totalText:SetWordWrap(false)
    view.totalText = totalText

    -- --- Rafraîchissement / refresh ---------------------------------------------------
    function view.Refresh()
        local l = LS.Active()
        local lid = LS.ActiveId()
        if title then title:SetText(l and l.name or "") end
        if selector then selector:Refresh() end
        header.cells[7].text:SetText(MK.Short(mine()))
        header.cells[8].text:SetText(MK.Short(other()))
        wipe(rows)
        local done, total = 0, 0
        -- Totaux sur toute la liste (indépendants du filtre d'affichage) :
        -- cost = tout acheter, remain = ce qui manque encore, missing = sans prix.
        local T = { cost = 0, remain = 0, remainItems = 0, missing = 0 }
        local filter = ns.settings.lists.bestFilter or "all"
        local buyableOnly = ns.settings.lists.buyableOnly and true or false
        for _, e in ipairs(l and l.items or {}) do
            local owned, want, isDone = LS.Progress(e)
            local pnj, offer = vendorOffer(e.id)
            local info = U.ItemInfo(e.id)
            local d = { id = e.id, qty = want, owned = owned, done = isDone, max = e.max, pnj = pnj, offer = offer,
                sale = ns.Auctions and ns.Auctions.Short(e.id), saleN = ns.Auctions and ns.Auctions.Total(e.id) or 0,
                name = (info and info.name) or ns.Data.names[e.id], prices = {} }
            for _, k in ipairs({ "A", "H", "N" }) do d.prices[k] = priceOn(k, e.id) end
            d.best, d.bestKey = bestOffer(d, buyableOnly)
            if d.best then
                T.cost = T.cost + d.best * want
                local need = math.max(0, want - owned)
                if need > 0 then T.remain = T.remain + d.best * need; T.remainItems = T.remainItems + 1 end
            elseif not isDone then
                T.missing = T.missing + 1
            end
            total = total + 1
            if isDone then done = done + 1 end
            local keep = filter == "all" or (filter == "none" and d.bestKey == nil) or (filter ~= "none" and d.bestKey == filter)
            if keep then rows[#rows + 1] = d end
        end
        if sortKey and SORTERS[sortKey] then
            local get = SORTERS[sortKey]
            table.sort(rows, function(a, b)
                local va, vb = get(a), get(b)
                if va == nil and vb == nil then return a.id < b.id end
                if va == nil then return false end
                if vb == nil then return true end
                if va == vb then return a.id < b.id end
                if sortDesc then return va > vb end
                return va < vb
            end)
        end
        header:Update(sortKey, sortDesc)
        filterBox:Refresh()
        buyable:SetChecked(buyableOnly)
        local shownTxt = filter == "all" and "" or U.Color(U.colors.warn, string.format(" · filtre : %d / %d affichés", #rows, total))
        list:SetEmptyText(total == 0 and "Liste vide.\nAjoutez des objets avec l'icône « + » des tableaux, Alt+clic sur un objet,\nou le champ « Ajouter » ci-dessus."
            or "Aucun article ne correspond au filtre « Meilleur achat ».")
        list:SetData(rows, true)
        local e = selectedItem and LS.Entry(lid, selectedItem)
        if not e then selectedItem = nil end
        for _, wdg in ipairs(editWidgets) do wdg:SetShown(e ~= nil) end
        if e then
            local info = U.ItemInfo(e.id)
            editLbl:SetText("Article : " .. (U.QualityName(e.id, (info and info.name) or ns.Data.names[e.id]) or e.id))
            if not qtyEdit:HasFocus() then qtyEdit:SetText(tostring(e.qty)) end
            if not maxEdit:HasFocus() then
                local txt = ""
                if e.max then txt = (string.format("%.4f", e.max / 10000):gsub("0+$", ""):gsub("%.$", ""):gsub("%.", ",")) end
                maxEdit:SetText(txt)
            end
        else
            editLbl:SetText(U.Color(U.colors.dim, "Cliquez sur un article pour modifier sa quantité ou son prix maximum."))
            editLbl:SetWidth(WIDTH - 10)
        end
        if e then editLbl:SetWidth(mode == "ah" and 300 or 200) end
        summary:SetText(string.format("%s · %d / %d article(s) obtenu(s)%s%s", U.Color(U.colors.title, l and l.name or ""), done, total,
            shownTxt, A.ahOpen and "" or U.Color(U.colors.dim, " · ouvrez l'HDV pour rechercher")))
        searchAll:SetEnabled(A.ahOpen and total > done)
        view.totals = T
        if total == 0 then
            totalText:SetText("")
        else
            totalText:SetText(U.Color(U.colors.title, "Coût de la liste : ") .. U.Money(T.cost)
                .. U.Color(U.colors.title, "  ·  reste à acheter : ") .. (T.remain > 0 and U.Money(T.remain) or U.Color(U.colors.good, "rien"))
                .. (T.remainItems > 0 and U.Color(U.colors.dim, " (" .. T.remainItems .. " article(s))") or "")
                .. (T.missing > 0 and U.Color(U.colors.warn, "  ·  " .. T.missing .. " sans prix sous le maximum") or ""))
        end
    end

    ns.On("LISTS_CHANGED", function() if view:IsVisible() then view.Refresh() end end)
    ns.On("INVENTORY_CHANGED", function() if view:IsVisible() then view.Refresh() end end)
    ns.On("MARKET_CHANGED", function() if view:IsVisible() then view.Refresh() end end)
    ns.On("AUCTIONS_CHANGED", function() if view:IsVisible() then view.Refresh() end end)
    ns.On("AH_SHOW", function() if view:IsVisible() then view.Refresh() end end)
    ns.On("AH_CLOSED", function() if view:IsVisible() then view.Refresh() end end)
    ns.RegisterEvent("BAG_UPDATE_DELAYED", function() if view:IsVisible() then view.Refresh() end end)
    ns.RegisterEvent("GET_ITEM_INFO_RECEIVED", function() if view:IsVisible() then list:Refresh() end end)
    view:SetScript("OnShow", function() view.Refresh() end)
    return view
end
