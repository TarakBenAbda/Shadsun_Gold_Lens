-- =============================================================================
-- Shadsun Gold Lens — UI/ListsTab.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Onglet « Listes » : listes d'achats communes à tous vos personnages.
--       - à gauche : vos listes (nouvelle, renommer, dupliquer, supprimer) ;
--         un clic rend la liste active (elle reçoit les ajouts + et Alt+clic) ;
--       - à droite : les articles, avec quantité voulue, progression
--         (possédé par vos personnages du serveur), prix maximum, prix sur
--         chaque HDV (scan ou API), loupe (HDV ouvert) et retrait ;
--       - « Rechercher toute la liste » quand l'HDV est ouvert.
--      Achat toujours manuel.
-- EN : Shopping lists tab.
-- =============================================================================
local _, ns = ...
local U, W = ns.U, ns.W

local function confirmButton(parent, label, w, onConfirm)
    local b
    local armed = false
    b = W.Button(parent, label, w, 22, function()
        if not armed then
            armed = true
            b:SetText("Confirmer ?")
            C_Timer.After(3, function() armed = false; b:SetText(label) end)
            return
        end
        armed = false
        b:SetText(label)
        onConfirm()
    end)
    return b
end

ns.UI.RegisterTab("lists", "Listes", function(page)
    local LS = ns.Lists
    local LEFT_W, RIGHT_X = 196, 210
    local RIGHT_W = 812 - RIGHT_X

    -- =========================================================================
    -- Colonne gauche : listes / left: lists
    -- =========================================================================
    local h1 = W.Section(page, "Mes listes", LEFT_W - 4)
    h1:SetPoint("TOPLEFT", 2, -4)
    local listsList = W.List(page, LEFT_W, {
        rows = 11, rowHeight = 22,
        create = function(row)
            row.name = W.Text(row, "GameFontHighlight", "", "LEFT", LEFT_W - 60)
            row.name:SetPoint("LEFT", 4, 0)
            row.name:SetWordWrap(false)
            row.count = W.Text(row, "GameFontDisableSmall", "", "RIGHT", 34)
            row.count:SetPoint("RIGHT", -4, 0)
            row.mark = row:CreateTexture(nil, "BACKGROUND")
            row.mark:SetAllPoints()
            row.mark:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.16)
            row:SetScript("OnClick", function(self) LS.SetActive(self.data.id) end)
            row:SetScript("OnEnter", function(self)
                W.ShowTip(self, self.data.name, "Clic : afficher et rendre active (reçoit les ajouts « + » et Alt+clic).")
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end,
        update = function(row, d)
            local active = d.id == LS.ActiveId()
            row.mark:SetShown(active)
            row.name:SetText(active and U.Color("ffffffff", d.name) or d.name)
            local done = 0
            for _, e in ipairs(d.items) do if select(3, LS.Progress(e)) then done = done + 1 end end
            row.count:SetText(done .. "/" .. #d.items)
        end,
    })
    listsList:SetPoint("TOPLEFT", 0, -26)
    page.listsList = listsList

    -- Champ de nom (nouvelle liste, renommer) / name field
    local nameEdit = W.Edit(page, LEFT_W - 8)
    nameEdit:SetPoint("TOPLEFT", 6, -26 - 11 * 22 - 10)
    nameEdit:SetMaxLetters(40)
    local nameHint = W.Text(nameEdit, "GameFontDisableSmall", "Nom de la liste…")
    nameHint:SetPoint("LEFT", 2, 0)
    nameEdit:SetScript("OnTextChanged", function(self) nameHint:SetShown((self:GetText() or "") == "" and not self:HasFocus()) end)
    nameEdit:SetScript("OnEditFocusGained", function() nameHint:Hide() end)
    nameEdit:SetScript("OnEditFocusLost", function(self) nameHint:SetShown((self:GetText() or "") == "") end)
    page.nameEdit = nameEdit
    local function nameText() return U.Trim(nameEdit:GetText() or "") end
    local y0 = -26 - 11 * 22 - 38
    local newBtn = W.Button(page, "Nouvelle", 94, 22, function()
        local lid = LS.Create(nameText() ~= "" and nameText() or nil)
        nameEdit:SetText(""); nameEdit:ClearFocus(); nameHint:Show()
        U.Print("liste « " .. LS.Get(lid).name .. " » créée et active.")
    end)
    newBtn:SetPoint("TOPLEFT", 0, y0)
    local renBtn = W.Button(page, "Renommer", 94, 22, function()
        if nameText() == "" then U.Print("tapez le nouveau nom dans le champ, puis « Renommer ».") return end
        LS.Rename(LS.ActiveId(), nameText())
        nameEdit:SetText(""); nameEdit:ClearFocus(); nameHint:Show()
    end)
    renBtn:SetPoint("LEFT", newBtn, "RIGHT", 6, 0)
    local dupBtn = W.Button(page, "Dupliquer", 94, 22, function() LS.Duplicate(LS.ActiveId()) end)
    dupBtn:SetPoint("TOPLEFT", 0, y0 - 26)
    local delBtn = confirmButton(page, "Supprimer", 94, function()
        local l = LS.Active()
        local name = l and l.name or "?"
        LS.Delete(LS.ActiveId())
        U.Print("liste « " .. name .. " » supprimée.")
    end)
    delBtn:SetPoint("LEFT", dupBtn, "RIGHT", 6, 0)
    page.newButton, page.renameButton, page.deleteButton = newBtn, renBtn, delBtn

    -- Options des listes / list options
    local o1 = W.Check(page, "Alt+clic ajoute", function() return ns.settings.lists.altClick end,
        function(v) ns.settings.lists.altClick = v end,
        "Alt+clic sur un objet (sacs, liens du chat, HDV) l'ajoute à la liste active. Jamais dans la fenêtre du marchand.")
    o1:SetPoint("TOPLEFT", 0, y0 - 56)
    local o2 = W.Check(page, "Bordure chez le marchand", function() return ns.settings.ah.listBorder end,
        function(v) ns.settings.ah.listBorder = v end, "Entoure en bleu les articles de vos listes dans la fenêtre du marchand.")
    o2:SetPoint("TOPLEFT", 0, y0 - 80)
    local o3 = W.Check(page, "Ligne dans l'infobulle", function() return ns.settings.tooltip.showLists end,
        function(v) ns.settings.tooltip.showLists = v end, "Ligne « Liste » : nom de la liste et progression (8 / 20).")
    o3:SetPoint("TOPLEFT", 0, y0 - 104)

    -- =========================================================================
    -- Colonne droite : articles (vue partagée avec le panneau de l'HDV)
    -- =========================================================================
    local view = ns.ShopUI.Build(page, "window")
    view:SetPoint("TOPLEFT", RIGHT_X, 0)
    page.view = view
    page.itemsList, page.qtyEdit, page.maxEdit = view.itemsList, view.qtyEdit, view.maxEdit
    page.addEdit, page.searchAllButton = view.addEdit, view.searchAllButton
    page.shopView = view
    local help = W.Text(page, "GameFontDisableSmall",
        "Listes communes à tous vos personnages. Prix : annonce la moins chère de chaque HDV (scan ou API) ; en vert, le moins cher sous votre prix maximum. "
        .. "Possédé : vos personnages du serveur. Recherche et achat manuels.", "LEFT", RIGHT_W - 10)
    help:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", RIGHT_X, 0)
    help:SetSpacing(2)

    function page.Refresh()
        listsList:SetData(LS.All(), true)
        view.Refresh()
    end

    page.OnActivate = page.Refresh
    ns.On("LISTS_CHANGED", function() if page:IsVisible() then page.Refresh() end end)
    ns.On("INVENTORY_CHANGED", function() if page:IsVisible() then page.Refresh() end end)
    ns.RegisterEvent("BAG_UPDATE_DELAYED", function() if page:IsVisible() then listsList:SetData(LS.All(), true) end end)
end)
