-- =============================================================================
-- Shadsun Gold Lens — UI/MarketsTab.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Onglet « Marchés » : scans enregistrés pour chaque hôtel des ventes du
--      serveur (partagés par tous vos personnages), marché de revente,
--      HDV visé par les scans de ce personnage, personnages connus et leur
--      inventaire. Effacement d'un scan ou d'un personnage avec confirmation.
-- EN : Markets tab: per-AH snapshots, sell market, characters overview.
-- =============================================================================
local _, ns = ...
local U, W = ns.U, ns.W

-- Bouton à double clic de confirmation / two-step confirm button
local function confirmButton(parent, label, w, onConfirm)
    local b
    local armed = false
    b = W.Button(parent, label, w, 20, function()
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

ns.UI.RegisterTab("markets", "Marchés", function(page)
    local MK, INV = ns.Market, ns.Inventory
    local controls = {}

    -- --- Colonne gauche : HDV du serveur / left: realm auction houses -------------
    local h1 = W.Section(page, "Hôtels des ventes · " .. MK.Realm(), 396)
    h1:SetPoint("TOPLEFT", 2, -4)

    local cards = {}
    local function card(i)
        local c = W.Panel(page, 400, 80)
        c:SetPoint("TOPLEFT", 0, -26 - (i - 1) * 86)
        c.title = W.Text(c, "GameFontNormal", "")
        c.title:SetPoint("TOPLEFT", 10, -8)
        c.badge = W.Text(c, "GameFontNormalSmall", "")
        c.badge:SetPoint("LEFT", c.title, "RIGHT", 10, 0)
        c.line1 = W.Text(c, "GameFontHighlightSmall", "", "LEFT", 290)
        c.line1:SetPoint("TOPLEFT", 10, -28)
        c.line2 = W.Text(c, "GameFontHighlightSmall", "", "LEFT", 290)
        c.line2:SetPoint("TOPLEFT", 10, -43)
        c.line3 = W.Text(c, "GameFontHighlightSmall", "", "LEFT", 290)
        c.line3:SetPoint("TOPLEFT", 10, -60)
        c.del = confirmButton(c, "Effacer", 84, function()
            if c.key then
                MK.Delete(c.key)
                U.Print(MK.Label(c.key) .. " : scan effacé.")
                page.OnActivate()
            end
        end)
        c.del:SetPoint("BOTTOMRIGHT", -8, 8)
        c.del:SetScript("OnEnter", function(self) W.ShowTip(self, "Effacer ce scan", "Supprime votre scan de cet HDV pour ce serveur (deux clics). Les autres HDV et les prix de l'API ne sont pas touchés.") end)
        c.del:SetScript("OnLeave", function() GameTooltip:Hide() end)
        cards[i] = c
        return c
    end
    for i = 1, 3 do card(i) end

    local y = -26 - 3 * 86 - 4
    local sell = W.Cycle(page, 400, "Marché de revente (PNJ » HDV) : ",
        { { "faction", "HDV de ma faction" }, { "neutral", "HDV neutre" } },
        function() return ns.settings.economy.market end,
        function(v) ns.settings.economy.market = v; ns.Fire("SETTINGS_CHANGED"); page.OnActivate() end,
        "HDV où vous revendez : son scan fournit le prix HDV et sa commission est déduite du bénéfice.")
    sell:SetPoint("TOPLEFT", 0, y)
    controls[#controls + 1] = sell
    local choice = W.Cycle(page, 400, "Scans de ce personnage : ",
        { { "zone", "selon la zone" }, { "faction", "HDV de ma faction" }, { "neutral", "HDV neutre" } },
        function() return MK.Choice() or "zone" end,
        function(v) MK.SetChoice(v ~= "zone" and v or nil); page.OnActivate() end,
        "HDV auquel les scans de ce personnage sont attribués. « Selon la zone » : Baie-du-Butin, Gadgetzan et Long-guet = HDV neutre, ailleurs = HDV de votre faction.")
    choice:SetPoint("TOPLEFT", 0, y - 28)
    controls[#controls + 1] = choice
    local c1 = W.Check(page, "Infobulle : prix des HDV scannés", function() return ns.settings.tooltip.showMarkets end,
        function(v) ns.settings.tooltip.showMarkets = v end, "Une ligne par HDV scanné : prix le plus bas, quantité en vente, âge du scan.")
    c1:SetPoint("TOPLEFT", 0, y - 58)
    controls[#controls + 1] = c1
    local c2 = W.Check(page, "Infobulle : inclure l'HDV de l'autre faction", function() return ns.settings.tooltip.showOtherFaction end,
        function(v) ns.settings.tooltip.showOtherFaction = v end, "Utile si vous avez des personnages des deux factions sur ce serveur.")
    c2:SetPoint("TOPLEFT", 0, y - 82)
    controls[#controls + 1] = c2

    -- --- Colonne droite : personnages / right: characters --------------------------
    local x2 = 414
    local h2 = W.Section(page, "Vos personnages sur ce serveur", 396)
    h2:SetPoint("TOPLEFT", x2, -4)
    local list = W.List(page, 398, {
        rows = 8, rowHeight = 34,
        empty = "Aucun personnage enregistré pour l'instant.",
        create = function(row)
            row.name = W.Text(row, "GameFontNormal", "", "LEFT", 200)
            row.name:SetPoint("TOPLEFT", 6, -3)
            row.money = W.Text(row, "GameFontHighlightSmall", "", "RIGHT", 120)
            row.money:SetPoint("TOPRIGHT", -96, -4)
            row.sub = W.Text(row, "GameFontDisableSmall", "", "LEFT", 290)
            row.sub:SetPoint("TOPLEFT", 6, -19)
            row.forget = confirmButton(row, "Oublier", 76, function()
                if row.data then INV.Forget(row.data.name); page.OnActivate() end
            end)
            row.forget:SetPoint("RIGHT", -4, 0)
            row.forget:SetScript("OnEnter", function(self) W.ShowTip(self, "Oublier ce personnage", "Retire son inventaire du nombre possédé (deux clics). Il sera de nouveau enregistré à sa prochaine connexion.") end)
            row.forget:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end,
        update = function(row, d)
            local rec = d.rec
            local col = rec.side == "H" and U.colors.horde or U.colors.alliance
            row.name:SetText(U.Color(col, d.name) .. (d.me and U.Color(U.colors.dim, "  (connecté)") or ""))
            row.money:SetText(rec.money and U.Money(rec.money) or "")
            local items = 0
            for _ in pairs(rec.bags or {}) do items = items + 1 end
            local bank = rec.bankTime and ("banque vue " .. U.Ago(rec.bankTime)) or "banque jamais ouverte"
            row.sub:SetText(string.format("%d objets en sac · sacs %s · %s", items, rec.time and U.Ago(rec.time) or "?", bank))
            row.forget:SetShown(not d.me)
        end,
    })
    list:SetPoint("TOPLEFT", x2, -28)
    page.charList = list
    local others = W.Text(page, "GameFontDisableSmall", "", "LEFT", 396)
    others:SetPoint("TOPLEFT", x2, -28 - 8 * 34 - 8)

    local reloadBtn = W.Button(page, "Recharger l'interface (/reload)", 220, 22, function() ReloadUI() end)
    reloadBtn:SetPoint("TOPLEFT", others, "BOTTOMLEFT", 0, -10)
    reloadBtn:SetScript("OnEnter", function(self)
        W.ShowTip(self, "Recharger l'interface", "Charge les prix des trois HDV mis à jour par l'application Shadsun Gold Lens (toutes les heures) et enregistre vos scans sur le disque.")
    end)
    reloadBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    page.reloadButton = reloadBtn

    local help = W.Text(page, "GameFontDisableSmall",
        "Fonctionnement : chaque « Lire les annonces » enregistre une photo du marché pour l'HDV choisi (prix le plus bas et quantité par objet), "
        .. "commune à vos personnages du serveur. Les prix des trois HDV viennent de l'application Shadsun Gold Lens (module ShadsunGoldLens_Prix), lus à la connexion ou après /reload. "
        .. "Pour chaque HDV, la donnée la plus récente des deux est utilisée. Données supprimées après " .. MK.RETENTION_DAYS .. " jours.", "LEFT", 810)
    help:SetPoint("BOTTOMLEFT", 0, 0)
    help:SetSpacing(2)

    page.OnActivate = function()
        local realm = MK.Realm()
        local mine = MK.PlayerKey()
        local order = { mine, "N", mine == "A" and "H" or "A" }
        local sellKey = MK.SellKey()
        local nextKey = MK.Current()
        for i, key in ipairs(order) do
            local c = cards[i]
            c.key = key
            c.title:SetText(MK.IconLabel(key, false, 16))
            local badges = {}
            if key == sellKey then badges[#badges + 1] = "marché de revente" end
            if key == nextKey then badges[#badges + 1] = "prochain scan de ce personnage" end
            c.badge:SetText(#badges > 0 and U.Color(U.colors.dim, "· " .. table.concat(badges, " · ")) or "")
            local s = MK.Get(key)
            local x = MK.External(key)
            if x then
                c.line3:SetText(string.format("%s : %s objets · %s%s", MK.ExternalName(), U.Group(MK.ItemCount(x)), date("%d/%m à %H:%M", x.time),
                    U.Color(MK.IsStale(x.time) and U.colors.warn or U.colors.dim, " (" .. U.Ago(x.time) .. ")")))
            else
                c.line3:SetText(U.Color(U.colors.dim, MK.ExternalName() .. " : " .. (MK.extStatus == "ok" and "pas de prix pour cet HDV" or "non importée")))
            end
            if s then
                c.line1:SetText(string.format("%s annonces · %s objets différents", U.Group(s.total or 0), U.Group(MK.ItemCount(s))))
                local age = U.Ago(s.time)
                if MK.IsStale(s.time) then age = U.Color(U.colors.warn, age .. ", ancien") end
                c.line2:SetText(string.format("Scanné par %s le %s (%s)", tostring(s.char or "?"), date("%d/%m à %H:%M", s.time), age))
                c.del:Show()
            else
                c.line1:SetText(U.Color(U.colors.dim, "Aucun scan enregistré par vos personnages."))
                c.line2:SetText(U.Color(U.colors.dim, key == "N" and "Lisez les annonces à Baie-du-Butin, Gadgetzan ou Long-guet."
                    or (key == mine and "Lisez les annonces à l'HDV d'une capitale de votre faction." or "Scan possible avec un personnage de cette faction.")))
                c.del:Hide()
            end
        end
        for _, ctl in ipairs(controls) do if ctl.Refresh then ctl:Refresh() end end
        list:SetData(INV.Characters())
        -- Autres serveurs / other realms
        local g = ns.DB.G
        local nChars, nScans, nRealms = 0, 0, 0
        for r, chars in pairs(g.chars) do
            if r ~= realm then nRealms = nRealms + 1; for _ in pairs(chars) do nChars = nChars + 1 end end
        end
        for r, markets in pairs(g.markets) do
            if r ~= realm then for _ in pairs(markets) do nScans = nScans + 1 end end
        end
        local apiTxt
        if MK.extStatus == "ok" and MK.extInfo then
            apiTxt = string.format("Prix %s : %s %s, générés %s.", MK.ExternalName(), tostring(MK.extInfo.region or "?"):upper(), tostring(MK.extInfo.ruleset or ""),
                MK.extInfo.generated and U.Ago(MK.extInfo.generated) or "?")
            if MK.ExternalName() == "Forever AH" then apiTxt = apiTxt .. "\n" .. MK.FAH_CREDIT end
        elseif MK.extStatus == "absent" then
            apiTxt = "Prix des trois HDV : module ShadsunGoldLens_Prix absent (lancez l'application Shadsun Gold Lens)."
        else
            apiTxt = "Prix externes ignorés : " .. MK.extStatus .. "."
        end
        others:SetText(apiTxt .. (nRealms > 0 and string.format("\nAutres serveurs : %d personnage(s), %d scan(s), non utilisés ici.", nChars, nScans) or ""))
    end
    ns.On("MARKET_CHANGED", function() if page:IsVisible() then page.OnActivate() end end)
    ns.On("INVENTORY_CHANGED", function() if page:IsVisible() then page.OnActivate() end end)
end)
