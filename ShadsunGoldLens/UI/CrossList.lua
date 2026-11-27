-- =============================================================================
-- Shadsun Gold Lens — UI/CrossList.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Liste « HDV » HDV » : acheter sur un hôtel des ventes, revendre sur un
--      autre, d'après vos scans et les prix de l'API Blizzard. Deux sens,
--      choisis par un commutateur :
--        - Faction » Neutre : acheter à l'HDV de votre faction, revendre au neutre ;
--        - Neutre » Faction : acheter au neutre, revendre à l'HDV de votre faction.
--      Gain = prix de revente - commission de l'HDV de revente - prix d'achat.
--      Colonne « repère » : prix sur l'HDV de l'autre faction, c'est-à-dire ce
--      que ses joueurs paient chez eux (utile pour fixer un prix au neutre).
--      Mode "window" (onglet Opportunités) et "ah" (panneau de l'HDV).
-- EN : Cross-market list with two directions and other-faction reference.
-- =============================================================================
local _, ns = ...
local U, W = ns.U, ns.W
local XUI = {}
ns.CrossUI = XUI

local LAYOUTS = {
    window = {
        width = 812, rows = 15, bar = { 220, 150, 170 },
        x = { name = 0, buy = 148, sell = 218, ref = 288, gain = 358, real = 424, roi = 490, qty = 542, avis = 586, bags = 658, sale = 696 },
        w = { name = 146, buy = 68, sell = 68, ref = 68, gain = 64, real = 64, roi = 50, qty = 42, avis = 70, bags = 36, sale = 36 },
    },
    ah = {
        width = 730, rows = 17, bar = { 200, 140, 150 },
        x = { name = 0, buy = 114, sell = 178, ref = 242, gain = 306, real = 368, roi = 430, qty = 478, avis = 516, bags = 582, sale = 618 },
        w = { name = 112, buy = 62, sell = 62, ref = 62, gain = 60, real = 60, roi = 46, qty = 36, avis = 64, bags = 34, sale = 34 },
    },
}

-- Avis : libellés, couleurs et rang de tri / verdict labels
XUI.PRESETS = {
    { "ess", "Essentiel", { "name", "buyUnit", "sellUnit", "realGain", "roi", "avisRank" } },
    { "std", "Standard", { "name", "buyUnit", "sellUnit", "ref", "realGain", "roi", "qty", "sales", "gainDay", "avisRank", "bags" } },
    { "fast", "Revente rapide", { "name", "buyUnit", "sellUnit", "realGain", "sales", "gainDay", "advice", "value", "avisRank" } },
    { "all", "Complet" },
}

local AVIS = {
    fav = { "Favorable", "good", 3 },
    chk = { "À vérifier", "warn", 2 },
    def = { "Défavorable", "bad", 1 },
}
XUI.AVIS = AVIS

-- Âge maximal d'un prix pour un avis « Favorable » (les prix d'HDV bougent vite).
XUI.AVIS_MAX_AGE = 24 * 3600

-- Avis, gain réaliste et raison d'une ligne. dir = "FN" (faction » neutre)
-- ou "NF" (neutre » faction). Ordre des règles :
--  1. un des deux prix a plus de 24 h → À vérifier (prix ancien) ;
--  2. FN : l'autre faction achète aussi au neutre ; son prix chez elle (repère)
--     plafonne ce qu'elle paiera. Gain réaliste = revente au plus bas entre
--     votre prix et le repère. Sans repère → À vérifier. Gain réaliste nul ou
--     négatif → Défavorable. Sinon, moins de minQty objets en vente au neutre
--     → À vérifier (prix peut-être isolé), sinon Favorable, éventuellement
--     « au prix repère » s'il faut descendre au repère ;
--  3. NF : seuls les joueurs de votre faction achètent à son HDV : Favorable si
--     au moins minQty objets y sont en vente (vrai prix de marché), sinon À vérifier.
-- Avant 0.15 : un repère plus bas que la revente donnait « Défavorable » même
-- quand la revente au repère restait rentable, et l'âge des prix était ignoré.
-- Returns verdict, realistic gain, reason key.
function XUI.Assess(r, dir, minQty, rate, now)
    local sellQty = r.sellQty or 0
    local realSell = r.sellUnit
    if dir == "FN" and r.ref then realSell = math.min(r.sellUnit, r.ref) end
    local realGain = realSell - math.ceil(realSell * rate - 1e-9) - r.buyUnit
    now = now or time()
    local oldest = math.min(r.buyTime or r.time or now, r.sellTime or r.time or now)
    if now - oldest > XUI.AVIS_MAX_AGE then return "chk", realGain, "old" end
    -- 0.16 : vente trop lente à l'HDV de revente (estimation Forever AH) → À vérifier
    local minSales = ns.DB and ns.DB.Num("economy", "avisMinSales") or 0.3
    local slow = r.sales ~= nil and r.sales < minSales
    if dir == "FN" then
        if not r.ref then return "chk", realGain, "noref" end
        if realGain <= 0 then return "def", realGain, "refcheap" end
        if slow then return "chk", realGain, "slow" end
        if sellQty < minQty then return "chk", realGain, "few" end
        return "fav", realGain, (r.ref < r.sellUnit) and "atref" or "ok"
    end
    if slow then return "chk", realGain, "slow" end
    if sellQty < minQty then return "chk", realGain, "few" end
    return "fav", realGain, "ok"
end

-- Explication d'un avis (infobulle) / verdict explanation
function XUI.Reason(d)
    local q = tostring(d.sellQty or 0)
    local R = {
        old = "un des prix date de plus de 24 h : relisez les annonces avant d'acheter.",
        slow = "se vend très peu à l'HDV de revente (" .. ns.Market.SalesText(d.sales) .. ") : l'objet risque de rester en vente.",
        noref = "aucun prix connu pour l'autre faction : impossible de savoir si elle achètera au neutre.",
        refcheap = "l'autre faction paie moins cher chez elle ; même en revendant à son prix, il n'y a plus de gain.",
        few = "seulement " .. q .. " objet(s) en vente à l'HDV de revente : prix peut-être isolé.",
        atref = "rentable en revendant au prix repère de l'autre faction (plus bas que l'annonce actuelle).",
        ok = (d.dir == "FN") and ("l'autre faction paie au moins ce prix chez elle et " .. q .. " objets sont en vente au neutre.")
            or (q .. " objets en vente à l'HDV de revente : vrai prix de marché."),
    }
    return R[d.why] or ""
end

local function shortAgo(ts)
    return (U.Ago(ts):gsub("^il y a ", ""))
end

function XUI.Build(parent, mode)
    local layout = LAYOUTS[mode] or LAYOUTS.window
    local MK = ns.Market
    local page = CreateFrame("Frame", nil, parent)
    page:SetSize(layout.width, 120 + layout.rows * 20)
    local f = { dir = "FN", minGain = nil, minROI = nil, maxBuy = nil, avis = "ALL" }
    local filt = ns.Filters.New()
    local rows = {}
    local list, header
    local sortKey, sortDesc = "realGain", true

    local function otherKey() return MK.PlayerKey() == "A" and "H" or "A" end

    -- --- Sens : Faction » Neutre / Neutre » Faction ----------------------------
    local dirs = W.Segmented(page, {
        { "FN", "Faction » Neutre", "Acheter à l'HDV de votre faction, revendre à l'HDV neutre (commission 15 %)." },
        { "NF", "Neutre » Faction", "Acheter à l'HDV neutre, revendre à l'HDV de votre faction (commission 5 %)." },
    }, function() return f.dir end, function(v) f.dir = v; page.Compute() end, { 140, 140 })
    dirs:SetPoint("TOPLEFT", 0, 0)
    page.directions = dirs
    local dirHint = W.Text(page, "GameFontDisableSmall", "", "LEFT", layout.width - 300)
    dirHint:SetPoint("LEFT", dirs, "RIGHT", 12, 0)

    -- --- Filtres / filters -------------------------------------------------------
    local fbar = ns.Filters.Bar(page, filt, function() page.Compute() end, layout.bar)
    fbar:SetPoint("TOPLEFT", 0, -28)
    page.filters = fbar
    local refreshBtn = W.Button(page, "Actualiser", 100, 22, function() page.Compute() end)
    refreshBtn:SetPoint("TOPRIGHT", -14, 0)

    local function numEdit(label, key, anchor, tip)
        local fs = W.Text(page, "GameFontNormalSmall", label)
        if anchor then fs:SetPoint("LEFT", anchor, "RIGHT", 12, 0) else fs:SetPoint("TOPLEFT", 0, -60) end
        local e = W.Edit(page, 46, function(self) f[key] = U.ParseNumber(self:GetText()); page.Compute() end)
        e:SetPoint("LEFT", fs, "RIGHT", 6, 0)
        if tip then
            e:SetScript("OnEnter", function(self) W.ShowTip(self, label:gsub(" :$", ""), tip) end)
            e:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        return e
    end
    -- Budget : prix d'achat unitaire maximal, comme « Achat max » de PNJ » HDV.
    local e0 = numEdit("Achat max (po) :", "maxBuy", nil,
        "Prix d'achat maximal par unité sur l'HDV d'achat, en pièces d'or (ex. 2,5). Vide : pas de limite.")
    page.maxBuyEdit = e0
    local e1 = numEdit("Gain min. (po) :", "minGain", e0, "Gain réaliste minimal par unité, en pièces d'or.")
    local e2 = numEdit("Rentab. min (%) :", "minROI", e1)
    local qLbl = W.Text(page, "GameFontNormalSmall", "Qté min. :")
    qLbl:SetPoint("LEFT", e2, "RIGHT", 12, 0)
    local qEdit = W.Edit(page, 34, function(self)
        local v = math.max(1, math.floor(U.ParseNumber(self:GetText()) or 3))
        ns.settings.economy.avisMinQty = v
        self:SetText(tostring(v))
        page.Compute()
    end)
    qEdit:SetPoint("LEFT", qLbl, "RIGHT", 6, 0)
    qEdit:SetText(tostring(ns.settings.economy.avisMinQty or 3))
    qEdit:SetScript("OnEnter", function(self)
        W.ShowTip(self, "Quantité minimale pour l'avis", "Nombre d'objets en vente à l'HDV de revente en dessous duquel le prix peut être une annonce isolée : avis « À vérifier ».")
    end)
    qEdit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    page.minQtyEdit = qEdit
    local avisSel = W.Cycle(page, 150, "Avis : ", {
        { "ALL", "Tous" }, { "fav", "Favorable", U.colors.good }, { "chk", "À vérifier", U.colors.warn }, { "def", "Défavorable", U.colors.bad },
    }, function() return f.avis end, function(v) f.avis = v; page.Compute() end,
        "Faction » Neutre : l'autre faction paie-t-elle autant chez elle ? Neutre » Faction : assez d'objets en vente à l'HDV de revente ?")
    avisSel:SetPoint("TOPRIGHT", -14, -56)
    page.avisSelector = avisSel

    local summary = W.Text(page, "GameFontHighlightSmall", "", "LEFT", layout.width - 110)
    summary:SetPoint("TOPLEFT", 0, -84)
    summary:SetWordWrap(false)

    -- --- Colonnes (libellés selon le sens) / columns -------------------------------
    local X, Wd = layout.x, layout.w
    local cols = {
        { key = "name", label = "Objet", x = X.name, w = Wd.name },
        { key = "buyUnit", label = "Achat", x = X.buy, w = Wd.buy, right = true, tip = "Annonce la moins chère sur l'HDV d'achat." },
        { key = "sellUnit", label = "Revente", x = X.sell, w = Wd.sell, right = true, tip = "Annonce la moins chère sur l'HDV de revente." },
        { key = "ref", label = "Repère", x = X.ref, w = Wd.ref, right = true,
            tip = "Prix sur l'HDV de l'autre faction : ce que ses joueurs paient chez eux." },
        { key = "gain", label = "Gain / u.", x = X.gain, w = Wd.gain, right = true, tip = "Prix de revente, moins la commission, moins le prix d'achat." },
        { key = "realGain", label = "Gain réal.", x = X.real, w = Wd.real, right = true,
            tip = "Faction » Neutre : gain calculé sur le plus bas entre votre prix de revente et le repère de l'autre faction. Neutre » Faction : identique au gain." },
        { key = "roi", label = "Rentab.", x = X.roi, w = Wd.roi, right = true },
        { key = "qty", label = "Dispo", x = X.qty, w = Wd.qty, right = true, tip = "Quantité totale en vente sur l'HDV d'achat (tous prix confondus)." },
        { key = "avisRank", label = "Avis", x = X.avis, w = Wd.avis, tip = "Favorable, À vérifier ou Défavorable : détail au survol de la ligne." },
        { key = "bags", label = "Sacs", x = X.bags, w = Wd.bags, right = true, tip = W.TIP_BAGS },
        { key = "sale", label = "Vente", x = X.sale, w = Wd.sale, right = true, tip = W.TIP_SALE },
        -- 0.16 : indicateurs de marché
        { key = "sales", label = "Ventes/j", w = 52, right = true, tip = "Ventes estimées par jour à l'HDV de revente (Forever AH : annonces disparues entre deux relevés, achetées ou annulées)." },
        { key = "gainDay", label = "Gain/j", w = 64, right = true, tip = "Gain par jour estimé : gain réaliste par unité × ventes par jour à l'HDV de revente." },
        { key = "advice", label = "Conseil", w = 46, right = true, menuLabel = "Quantité conseillée", tip = "Quantité conseillée : environ 3 jours de ventes à l'HDV de revente, sans dépasser la quantité disponible." },
        { key = "value", label = "Valeur", w = 50, right = true, menuLabel = "Écart à la valeur habituelle", tip = "Prix d'achat comparé à la valeur habituelle de l'HDV d'achat (moyenne sur 14 jours). Vert : vraie bonne affaire." },
    }
    local ORDER = { name = 1, buyUnit = 2, sellUnit = 3, ref = 4, gain = 5, realGain = 6, roi = 7, qty = 8, sales = 9, gainDay = 10,
        advice = 11, value = 12, avisRank = 13, bags = 14, sale = 15 }
    for _, c in ipairs(cols) do c.order = ORDER[c.key]; if c.key == "name" then c.flex = true end end
    local cs = W.ColumnSet("cross_" .. (mode == "ah" and "ah" or "window"), cols, { width = layout.width - 14,
        locked = { name = true, realGain = true }, presets = XUI.PRESETS, default = "std", iconPad = 20 })
    page.columns = cs

    local function sortRows()
        table.sort(rows, function(a, b)
            local va, vb = a[sortKey], b[sortKey]
            if sortKey == "name" then va, vb = U.Fold(a.name or ""), U.Fold(b.name or "") end
            if va == vb or va == nil or vb == nil then
                if va == nil and vb ~= nil then return false end
                if vb == nil and va ~= nil then return true end
                return a.id < b.id
            end
            if sortDesc then return va > vb end
            return va < vb
        end)
        header:Update(sortKey, sortDesc)
    end
    header = W.Header(page, cols, -100, layout.width - 14, function(key)
        if sortKey == key then sortDesc = not sortDesc
        else sortKey, sortDesc = key, key ~= "name" end
        sortRows()
        list:SetData(rows, true)
    end, function(anchor) cs.Menu(anchor) end)
    page.header = header
    page.SortBy = function(key, desc) sortKey, sortDesc = key, desc; sortRows(); list:SetData(rows, true) end

    -- Libellés des colonnes de prix selon le sens / price headers per direction
    local function updateHeaders()
        local buyKey, sellKey = MK.DirectionPair(f.dir)
        header.cells[2].text:SetText("Achat " .. MK.Short(buyKey):lower())
        header.cells[3].text:SetText("Revente " .. MK.Short(sellKey):lower())
        header.cells[4].text:SetText("Repère " .. MK.Short(otherKey()))
        dirHint:SetText(string.format("Faction = %s pour ce personnage.", MK.Label(MK.PlayerKey())))
    end

    -- --- Tableau / table -------------------------------------------------------------
    list = W.List(page, layout.width, {
        rows = layout.rows, rowHeight = 20,
        create = function(row)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(16, 16)
            row.icon:SetPoint("LEFT", 0, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.cells = {}
            for i, c in ipairs(cols) do
                local fs = W.Text(row, "GameFontHighlightSmall", "", c.right and "RIGHT" or "LEFT", i == 1 and (c.w - 20) or c.w)
                fs:SetPoint("LEFT", i == 1 and 20 or c.x, 0)
                fs:SetWordWrap(false)
                row.cells[i] = fs
            end
            row.search = W.IconButton(row, W.ICON_SEARCH, "Rechercher dans l'HDV",
                "Lance la recherche de l'objet dans l'hôtel des ventes ouvert (à utiliser sur l'HDV d'achat).", function(self)
                    local _, msg = ns.Arbitrage.Search(self:GetParent().data.id)
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
                GameTooltip:AddLine(" ")
                local function src(s) return s == "api" and " · API" or " · scan" end
                GameTooltip:AddDoubleLine("Acheter sur " .. MK.Label(d.buy), U.Money(d.buyUnit) .. "  (" .. U.Group(d.qty or 0) .. " en vente" .. src(d.buySrc) .. ")", 1, 0.82, 0, 1, 1, 1)
                GameTooltip:AddDoubleLine("Revendre sur " .. MK.Label(d.sell), U.Money(d.sellUnit) .. "  (" .. U.Group(d.sellQty or 0) .. " en vente" .. src(d.sellSrc) .. ")", 1, 0.82, 0, 1, 1, 1)
                GameTooltip:AddDoubleLine("Commission de l'HDV de revente", U.Money(d.cut), 1, 0.82, 0, 1, 1, 1)
                GameTooltip:AddDoubleLine("Gain par unité", U.Money(d.gain, true, true) .. "  (" .. U.Percent(d.roi, true) .. ")", 1, 0.82, 0, 0.48, 0.92, 0.59)
                if d.ref then
                    GameTooltip:AddDoubleLine("Repère " .. MK.Label(d.refKey), U.Money(d.ref) .. "  (" .. U.Group(d.refQty or 0) .. " en vente)", 1, 0.82, 0, 1, 1, 1)
                end
                local a = AVIS[d.avis]
                if a then
                    GameTooltip:AddLine("Avis : " .. a[1] .. " — " .. XUI.Reason(d), 1, 1, 1, true)
                    if d.dir == "FN" and d.ref and d.ref < d.sellUnit then
                        GameTooltip:AddDoubleLine("Gain en revendant au repère", U.Money(d.realGain, true, true), 1, 0.82, 0, 1, 1, 1)
                    end
                    GameTooltip:AddDoubleLine("Âge des prix (achat / revente)", shortAgo(d.buyTime or d.time) .. " / " .. shortAgo(d.sellTime or d.time),
                        1, 0.82, 0, 1, 1, 1)
                end
                if d.sales or d.buyUsual or d.sellUsual then
                    GameTooltip:AddDoubleLine("Ventes à l'HDV de revente", MK.SalesText(d.sales)
                        .. (d.gainDay and ("  ·  " .. U.Money(math.floor(d.gainDay + 0.5), true, true) .. "/j") or ""), 1, 0.82, 0, 1, 1, 1)
                    if d.advice then GameTooltip:AddDoubleLine("Quantité conseillée", tostring(d.advice), 1, 0.82, 0, 1, 1, 1) end
                    if d.value then GameTooltip:AddDoubleLine("Prix d'achat", MK.DeltaText(d.value), 1, 0.82, 0, 1, 1, 1) end
                    if d.sellValue then GameTooltip:AddDoubleLine("Prix de revente", MK.DeltaText(d.sellValue), 1, 0.82, 0, 1, 1, 1) end
                end
                GameTooltip:AddLine("Prix au moment des relevés : vérifiez dans l'HDV avant d'acheter. Revendre suppose de rester sous l'annonce la moins chère.", 0.63, 0.66, 0.71, true)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end,
        update = function(row, d)
            local info = U.ItemInfo(d.id)
            if info then d.name = info.name end
            local inst = U.ItemInstant(d.id)
            row.icon:SetTexture((info and info.icon) or (inst and inst.icon) or "Interface\\Icons\\INV_Misc_QuestionMark")
            local c = row.cells
            c[1]:SetText(U.QualityName(d.id, d.name) or ("Objet n° " .. d.id))
            c[2]:SetText(U.MoneyShort(d.buyUnit))
            c[3]:SetText(U.MoneyShort(d.sellUnit))
            if d.ref then
                local warn = (d.sell == "N" and d.ref < d.sellUnit)
                c[4]:SetText(warn and U.Color(U.colors.warn, U.MoneyShort(d.ref, true)) or U.MoneyShort(d.ref))
            else
                c[4]:SetText(U.Color(U.colors.dim, "-"))
            end
            c[5]:SetText(U.Color(U.colors.good, U.MoneyShort(d.gain, true, true)))
            c[6]:SetText(U.Color(d.realGain > 0 and U.colors.good or U.colors.bad, U.MoneyShort(d.realGain, true, true)))
            c[7]:SetText(U.Color(U.colors.good, U.PercentShort(d.roi)))
            c[8]:SetText(U.Group(d.qty or 0))
            local a = AVIS[d.avis]
            c[9]:SetText(a and U.Color(U.colors[a[2]], a[1]) or "")
            c[10]:SetText(W.BagsText(d))
            c[11]:SetText(W.SaleText(d))
            c[12]:SetText(d.sales and (MK.SalesText(d.sales):gsub(" ventes?/j", "")) or U.Color(U.colors.dim, "-"))
            c[13]:SetText(d.gainDay and U.Color(d.gainDay > 0 and U.colors.good or U.colors.bad, U.MoneyShort(math.floor(d.gainDay + 0.5), true, true))
                or U.Color(U.colors.dim, "-"))
            c[14]:SetText(d.advice and tostring(d.advice) or U.Color(U.colors.dim, "-"))
            c[15]:SetText(d.value and MK.DeltaText(d.value, true) or U.Color(U.colors.dim, "-"))
            row.search:SetUsable(ns.Arbitrage.ahOpen)
        end,
    })
    list:SetPoint("TOPLEFT", 0, -120)
    page.list = list
    cs.Bind(header, list, 20)
    cs.Apply()
    local colBtn = cs.Button(page)
    colBtn:SetPoint("TOPRIGHT", -14, -80)
    page.columnsButton = colBtn

    -- --- Calcul / computation -------------------------------------------------------------
    function page.Compute()
        updateHeaders()
        wipe(rows)
        local INV = ns.Inventory
        local buyKey, sellKey = MK.DirectionPair(f.dir)
        local minQty = ns.settings.economy.avisMinQty or 3
        local rate = MK.Rate(sellKey)
        local Bs, Ss = MK.Snap(buyKey), MK.Snap(sellKey)
        for _, r in ipairs(MK.Cross(buyKey .. ">" .. sellKey)) do
            r.dir = f.dir
            -- Indicateurs (0.16) : ventes à l'HDV de revente, écarts à la valeur habituelle
            local spd, sellUsual = MK.Stats(Ss, r.id)
            local _, buyUsual = MK.Stats(Bs, r.id)
            r.sales, r.buyUsual, r.sellUsual = spd, buyUsual, sellUsual
            r.value, r.sellValue = MK.ValueDelta(r.buyUnit, buyUsual), MK.ValueDelta(r.sellUnit, sellUsual)
            r.avis, r.realGain, r.why = XUI.Assess(r, f.dir, minQty, rate)
            r.gainDay = spd and r.realGain * spd or nil
            r.advice = MK.Advice(spd)
            if r.advice and r.qty then r.advice = math.min(r.advice, r.qty) end
            r.avisRank = AVIS[r.avis][3]
            local keep = (f.avis == "ALL" or f.avis == r.avis)
            if f.maxBuy and r.buyUnit > f.maxBuy * 10000 then keep = false end
            if keep and f.minGain and r.realGain < f.minGain * 10000 then keep = false end
            if keep and f.minROI and (r.roi or -1e9) < f.minROI then keep = false end
            if keep then
                local info = U.ItemInfo(r.id)
                r.name = (info and info.name) or ns.Data.names[r.id]
                if not r.name then U.RequestItem(r.id) end
                if ns.Filters.Match(filt, r.id, r.name) then
                    INV.Stock(r)
                    rows[#rows + 1] = r
                end
            end
        end
        sortRows()
        local B, S = MK.Snap(buyKey), MK.Snap(sellKey)
        if not B or not S then
            local missing = (not B) and buyKey or sellKey
            list:SetEmptyText("Aucun prix pour " .. MK.Label(missing) .. ".\nLisez les annonces à cet HDV (barre de scan du panneau de l'HDV),\n"
                .. "ou importez les prix des trois HDV avec l'application Shadsun Gold Lens. Vos personnages partagent ces données.")
        else
            list:SetEmptyText("Aucun écart rentable dans ce sens avec ces filtres.")
        end
        list:SetData(rows, true)
        local parts = {}
        for _, key in ipairs({ buyKey, sellKey, otherKey() }) do
            local s = MK.Snap(key)
            if s then
                local _, pct = MK.Rate(key)
                parts[#parts + 1] = MK.ColorLabel(key) .. U.Color(MK.IsStale(s.time) and U.colors.warn or U.colors.dim,
                    " (" .. MK.SourceText(s) .. (key == sellKey and (", commission " .. tostring(pct) .. " %") or "") .. ")")
            end
        end
        summary:SetText(U.Color(U.colors.title, #rows .. " ligne(s)") .. " · "
            .. (#parts > 0 and table.concat(parts, " · ") or U.Color(U.colors.dim, "aucune donnée")))
    end

    ns.On("MARKET_CHANGED", function() if page:IsVisible() then page.Compute() end end)
    ns.On("SETTINGS_CHANGED", function() if page:IsVisible() then page.Compute() end end)
    local function updateOwned()
        if not page:IsVisible() or #rows == 0 then return end
        ns.Inventory.StockAll(rows)
        if sortKey == "bags" or sortKey == "sale" then sortRows() end
        list:SetData(rows, true)
    end
    ns.RegisterEvent("BAG_UPDATE_DELAYED", updateOwned)
    ns.On("INVENTORY_CHANGED", updateOwned)
    ns.On("AUCTIONS_CHANGED", updateOwned)
    local pendingRefresh = false
    ns.RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
        if not page:IsVisible() or pendingRefresh then return end
        pendingRefresh = true
        C_Timer.After(0.5, function() pendingRefresh = false; if page:IsVisible() then list:Refresh() end end)
    end)
    page:SetScript("OnShow", function() page.Compute() end)
    page.Rows = function() return rows end
    sortRows()
    return page
end
