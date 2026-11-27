-- =============================================================================
-- Shadsun Gold Lens — Core/Tooltip.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Ajout des informations aux infobulles d'objets.
--
--  Cause du clignotement en v0.3.0 (corrigée ici) :
--   v0.3.0 différait l'ajout des lignes d'une image (C_Timer.After(0)) puis
--   appelait tooltip:Show(). Or le client moderne reconstruit périodiquement
--   les infobulles (RefreshData : ClearLines → lignes Blizzard → post-calls).
--   À chaque reconstruction, l'infobulle s'affichait d'abord SANS nos lignes
--   (rétrécissement), puis l'image suivante AVEC (agrandissement) : cycle
--   visible de redimensionnement. Les hooks SetHyperlink / SetBagItem /
--   SetItemByID / SetMerchantItem doublaient en outre le post-call.
--
--  Solution :
--   1. Un seul point d'entrée : TooltipDataProcessor.AddTooltipPostCall(Item).
--   2. Ajout SYNCHRONE dans le post-call : chaque reconstruction produit
--      exactement le même contenu dans la même image → taille stable.
--   3. Garde « une fois par passe » remise à zéro par OnTooltipCleared/OnHide :
--      pas de lignes dupliquées, même si le post-call est appelé deux fois.
--   4. Garde de réentrance (busy) : aucun traitement récursif.
--   5. Infobulles imbriquées (objet créé d'une recette) ignorées : seul
--      l'objet primaire (la recette elle-même) est décrit.
--   6. Calculs mis en cache (vue catalogue + prix) : coût négligeable même si
--      le client rafraîchit l'infobulle plusieurs fois par seconde.
--   Aucun OnUpdate, aucun minuteur, aucun Hide/SetOwner de notre part.
-- EN : Synchronous TooltipDataProcessor post-call with per-pass and
--      re-entrancy guards; nested (recipe product) tooltips ignored.
-- =============================================================================
local _, ns = ...
local U, L = ns.U, ns.L
local T = {}
ns.Tooltip = T

local passState = setmetatable({}, { __mode = "k" }) -- infobulle → itemID rendu dans la passe
local hooked = setmetatable({}, { __mode = "k" })
local busy = false
local SKIP = {}

T.installed = false
T.method = "aucune"
T.last = nil
ns.lastItem, ns.lastLink = nil, nil

local function resetPass(tt) passState[tt] = nil end

local function ensureHooks(tt)
    if hooked[tt] then return end
    hooked[tt] = true
    if tt.HookScript then
        pcall(tt.HookScript, tt, "OnTooltipCleared", resetPass)
        pcall(tt.HookScript, tt, "OnHide", resetPass)
    end
end

-- Présence effective de notre en-tête dans les lignes de l'infobulle.
-- Retourne true/false, ou nil si l'infobulle n'expose pas ses lignes.
local function hasOurBlock(tt)
    local name = tt.GetName and tt:GetName()
    if not name or not tt.NumLines then return nil end
    local ok, n = pcall(tt.NumLines, tt)
    if not ok or type(n) ~= "number" then return nil end
    for i = 1, n do
        local fs = _G[name .. "TextLeft" .. i]
        local text = fs and fs.GetText and fs:GetText()
        if type(text) == "string" and not U.IsSecret(text) and text:find(ns.title, 1, true) then return true end
    end
    return false
end
T.HasOurBlock = hasOurBlock

local function itemType()
    return Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
end

-- -----------------------------------------------------------------------------
-- Identification de l'objet / item resolution
-- Retourne itemID, mode, primaryID ; itemID nil si l'appel concerne une
-- infobulle imbriquée (ex. objet fabriqué affiché dans une recette).
-- -----------------------------------------------------------------------------
function T.Resolve(tt, data)
    local id = data and data.id
    if id ~= nil and U.IsSecret(id) then return nil, "secret" end
    if type(id) ~= "number" or id <= 0 then id = nil end
    local how = "data"

    local primary = tt.GetPrimaryTooltipData and tt:GetPrimaryTooltipData()
    local primaryID
    if type(primary) == "table" and primary ~= data then
        if primary.type ~= nil and primary.type ~= itemType() then
            return nil, "nested-nonitem"
        end
        primaryID = type(primary.id) == "number" and primary.id or nil
        if primaryID and id and primaryID ~= id then
            return nil, "nested", primaryID
        end
    end

    -- Contexte explicite du sac : l'ID réel de l'emplacement fait foi.
    local info = tt.GetPrimaryTooltipInfo and tt:GetPrimaryTooltipInfo()
    if type(info) == "table" and info.getterName == "GetBagItem" and type(info.getterArgs) == "table"
        and C_Container and C_Container.GetContainerItemID then
        local ok, bagID = pcall(C_Container.GetContainerItemID, info.getterArgs[1], info.getterArgs[2])
        if ok and type(bagID) == "number" then
            if id and bagID ~= id then return nil, "nested", bagID end
            id, how = bagID, "bag"
        end
    end

    if not id and data and type(data.hyperlink) == "string" then
        id, how = U.ItemID(data.hyperlink), "hyperlink"
    end
    if not id and tt.GetItem then
        local ok, _, link = pcall(tt.GetItem, tt)
        if ok then id, how = U.ItemID(link), "GetItem" end
    end
    return id, how, primaryID
end

-- -----------------------------------------------------------------------------
-- Construction des lignes (pure, testable) / line building
-- Chaque ligne : { gauche, droite|nil }  (couleurs intégrées au texte)
-- -----------------------------------------------------------------------------
local function ahText(price, age, state, liveTime, liveQty)
    if state == "NO_ADDON" or state == "NO_API" then return U.Color(U.colors.dim, L.AH_NO_ADDON) end
    if state == "VARIANTS" then return U.Color(U.colors.dim, L.AH_VARIANTS) end
    if not price then return U.Color(U.colors.dim, L.AH_NONE) end
    local t = U.Money(price)
    if state == "LIVE" and liveTime then
        return t .. " " .. U.Color(U.colors.dim, "(" .. string.format(L.AH_LIVE, date("%H:%M", liveTime), U.Group(liveQty or 0)) .. ")")
    end
    if age then
        local ageTxt = (age == 0) and L.AH_TODAY or string.format(L.AH_AGE, age)
        local stale = age > (ns.DB.Num("economy", "staleDays") or 7)
        t = t .. " " .. U.Color(stale and U.colors.warn or U.colors.dim, "(" .. ageTxt .. (stale and (", " .. L.AH_STALE) or "") .. ")")
    end
    return t
end

-- Lignes des HDV scannés (faction, neutre, autre faction en option) :
-- « HDV Alliance | 1 po 20 · 35 en vente · il y a 3 h ». Rien si l'objet n'a
-- pas été vu au scan. Retourne le nombre de lignes ajoutées.
-- Market lines from the account's scans of this realm.
local function marketLines(add, itemID)
    local MK = ns.Market
    if not MK or not ns.settings.tooltip.showMarkets then return 0 end
    local n = 0
    for _, key in ipairs(MK.TooltipKeys()) do
        local snap = MK.Snap(key)
        local unit, qty = MK.Item(snap, itemID)
        local s = MK.ItemSnap(snap, itemID)
        local prefix = ""
        if not unit then
            -- Seules des variantes (suffixe, bonus) sont en vente : prix « dès ».
            unit, qty = MK.Variant(snap, itemID)
            s, prefix = snap, L.MARKET_FROM
        end
        if unit then
            local stale = MK.IsStale(s.time)
            local extra = string.format(L.MARKET_DETAIL, U.Group(qty or 0), MK.SourceText(s))
            if prefix ~= "" then extra = L.MARKET_VARIANTS .. " · " .. extra end
            if stale then extra = extra .. ", " .. L.AH_STALE end
            -- Indicateurs (0.16) : ventes par jour et écart à la valeur habituelle
            local spd, usual = MK.Stats(snap, itemID)
            local ind = ""
            if spd or usual then
                ind = "  " .. U.Color(U.colors.dim, MK.SalesText(spd))
                local dt = prefix == "" and MK.DeltaText(MK.ValueDelta(unit, usual), true) or ""
                if dt ~= "" then ind = ind .. U.Color(U.colors.dim, " · ") .. dt .. U.Color(U.colors.dim, " vs habituel") end
            end
            add(MK.IconLabel(key), prefix .. U.Money(unit) .. " " .. U.Color(stale and U.colors.warn or U.colors.dim, "(" .. extra .. ")") .. ind)
            n = n + 1
        end
    end
    return n
end
T.MarketLines = marketLines

local function sellText(info)
    if not info then return U.Color(U.colors.dim, L.UNKNOWN_YET) end
    if not info.sellPrice or info.sellPrice <= 0 then return U.Color(U.colors.dim, L.UNSELLABLE) end
    return U.Money(info.sellPrice)
end

-- Ligne d'arbitrage inverse : seulement si un achat HDV < rachat PNJ existe.
local function reverseLine(itemID, info)
    if not ns.settings.tooltip.showReverse or not ns.Arbitrage then return nil end
    -- Historique Auctionator : toutes variantes confondues (même prix de rachat PNJ).
    local price = ns.Prices.Get(itemID, info and info.link)
    local live = ns.Arbitrage.LiveFor(itemID)
    if live and live.gain > 0 and live.minUnit then
        return U.Color(U.colors.good, string.format(L.REVERSE_LIVE, U.Money(live.sell - live.minUnit, true), live.qty, U.Money(live.minUnit, true)))
    end
    local sell = info and info.sellPrice
    if price and sell and sell > price then
        return U.Color(U.colors.good, string.format(L.REVERSE_HIST, U.Money(sell - price, true), U.Money(price, true)))
    end
    return nil
end
T.ReverseLine = reverseLine

function T.BuildLines(itemID, shift)
    local s = ns.settings.tooltip
    local C, E, P = ns.Catalog, ns.Economy, ns.Prices
    local lines = {}
    local function add(left, right) lines[#lines + 1] = { left, right } end

    local view = C.GetView(itemID)
    local info = U.ItemInfo(itemID)
    if not info then U.RequestItem(itemID) end
    local best = view.best

    if not best and not s.showNoVendorLine then return lines end

    add(U.Color(U.colors.title, ns.title), s.showStatus and U.Color(C.StatusColor(view.status), C.StatusText(view.status, true)) or nil)

    local instant = U.ItemInstant(itemID)
    if s.showProfession and instant then
        if instant.classID == U.RECIPE_CLASS then
            add(L.PROFESSION, U.SubClassName(instant.classID, instant.subClassID) or "?")
        else
            local trades = U.TradeProfessions(instant.classID, instant.subClassID)
            if trades then add(L.USED_IN, trades) end
        end
    end

    local price, age, state, liveTime, liveQty = P.Best(itemID, info and info.link)

    if s.showOwned then
        local owned = ns.Inventory and ns.Inventory.Text(itemID) or U.OwnedText(itemID)
        if owned then add(L.OWNED, owned) end
    end
    if s.showAuctions and ns.Auctions then
        local sale = ns.Auctions.Text(itemID)
        if sale then add(L.ON_SALE, sale) end
    end
    if s.showLists and ns.Lists then
        local lt = ns.Lists.TooltipText(itemID)
        if lt then add(L.LIST, lt) end
    end

    if not best then
        add(U.Color(U.colors.dim, view.status == "NONE" and L.NO_VENDOR_KNOWN or L.NO_DATA))
        if s.showSell then add(L.SELL, sellText(info)) end
        if s.showAH and marketLines(add, itemID) == 0 then add(L.AH, ahText(price, age, state, liveTime, liveQty)) end
        do local rv = reverseLine(itemID, info); if rv then add(L.REVERSE, rv) end end
    else
        if s.showBuy then add(L.BUY, C.PriceText(best)) end
        if s.showSell then add(L.SELL, sellText(info)) end
        if s.showAH and marketLines(add, itemID) == 0 then add(L.AH, ahText(price, age, state, liveTime, liveQty)) end
        do local rv = reverseLine(itemID, info); if rv then add(L.REVERSE, rv) end end
        local result, reason
        if s.showProfit then
            result, reason = E.Evaluate(itemID, best, price, age, info)
            if result then
                local col = E.VerdictColor(result)
                add(L.PROFIT, U.Color(col, U.Money(result.profit, true, true) .. " (" .. U.Percent(result.roi, true) .. ")")
                    .. (state == "LIVE" and ns.Market and (" " .. U.Color(U.colors.dim, ns.Market.Short(ns.Market.SellKey()))) or ""))
            else
                add(L.PROFIT, U.Color(U.colors.dim, L.CALC_IMPOSSIBLE .. " — " .. tostring(reason)))
            end
        end
        if s.showVendor then
            local name = best.name
            if s.showFaction then name = name .. " · " .. U.SideText(best.side) end
            if #view.offers > 1 then name = name .. " " .. U.Color(U.colors.dim, string.format(L.OTHERS, #view.offers - 1)) end
            add(name, U.Color(U.colors.dim, C.LocationText(best)))
        end
        if s.showFaction then
            local ex = C.ExclusivityText(view.excl)
            local arb = C.ArbitrageText(view.excl)
            if arb then ex = ex .. " · " .. arb end
            add(U.Color(view.excl.code == "BOTH" and U.colors.dim or U.colors.warn, ex))
        end
        local notes = {}
        if best.enemy then notes[#notes + 1] = L.ENEMY end
        if best.condText then notes[#notes + 1] = best.condText end
        if best.unavailable then notes[#notes + 1] = L.UNAVAILABLE
        elseif best.limited then notes[#notes + 1] = L.LIMITED end
        if best.moves then notes[#notes + 1] = L.MOVES end
        if #notes > 0 then add(U.Color(U.colors.warn, table.concat(notes, " · "))) end

        if shift then
            add(U.Color(U.colors.dim, C.SourceText(best)))
            if result then
                add(L.BREAKEVEN, U.Money(result.breakEven))
                add(L.MARGIN, U.Percent(result.margin, true))
                add(U.Color(E.VerdictColor(result), E.VerdictText(result)))
                if result.depositRisk then add("Dépôt perdu si invendu (estim.)", U.Money(result.depositRisk)) end
            end
            local _, rate = E.Rate()
            add(U.Color(U.colors.dim, string.format("Commission %s %% (%s)", tostring(rate),
                ns.settings.economy.market == "neutral" and "HDV neutre" or "HDV de faction")))
        end
    end
    if shift then
        local spell, spellID = U.ItemSpell(itemID)
        if spell and instant and instant.classID == U.RECIPE_CLASS then
            add(U.Color(U.colors.dim, L.RECIPE_TEACHES .. " : " .. spell .. (spellID and (" (sort " .. spellID .. ")") or "")))
        end
        add(U.Color(U.colors.dim, string.format(L.ITEM_ID, itemID)))
    end

    local maxLines = ns.DB.Num("tooltip", "maxLines") or 9
    if shift then maxLines = maxLines + 6 end
    while #lines > maxLines do table.remove(lines) end
    return lines
end

-- -----------------------------------------------------------------------------
-- Post-call
-- -----------------------------------------------------------------------------
local function render(tt, itemID)
    local t0 = debugprofilestop and debugprofilestop() or 0
    local lines = T.BuildLines(itemID, IsShiftKeyDown() and true or false)
    for i = 1, #lines do
        local l, r = lines[i][1], lines[i][2]
        if r then
            tt:AddDoubleLine(l, r, 0.93, 0.93, 0.93, 0.93, 0.93, 0.93)
        else
            tt:AddLine(l, 0.93, 0.93, 0.93, true)
        end
    end
    -- Redimensionnement dans la MÊME image (aucun cycle visible).
    if #lines > 0 and tt:IsShown() then tt:Show() end
    local ms = debugprofilestop and (debugprofilestop() - t0) or 0
    return #lines, ms
end

local function onPostCall(tt, data)
    local Diag = ns.Diag
    Diag.Count("postCalls")
    if busy then Diag.Count("skippedReentrant"); return end
    local s = ns.settings
    if not s or not s.tooltip.enabled or not tt then return end
    if tt.IsForbidden and tt:IsForbidden() then Diag.Count("skippedForbidden"); return end
    if SKIP[tt] then Diag.Count("skippedShopping"); return end
    if s.tooltip.hideInCombat and InCombatLockdown() then return end
    if s.tooltip.shiftOnly and not IsShiftKeyDown() then return end
    ensureHooks(tt)
    if passState[tt] then
        -- Bloc déjà rendu dans cette passe… sauf si le client a reconstruit les
        -- lignes sans déclencher OnTooltipCleared (bloc absent) : on le remet.
        if hasOurBlock(tt) ~= false then Diag.Count("skippedDuplicate"); return end
        passState[tt] = nil
    end

    busy = true
    local ok, err = xpcall(function()
        local id, how, primaryID = T.Resolve(tt, data)
        if not id then
            if how == "nested" or how == "nested-nonitem" then Diag.Count("skippedNested")
            elseif how == "secret" then Diag.Count("skippedSecret")
            else Diag.Count("unresolved") end
            return
        end
        local n, ms = render(tt, id)
        passState[tt] = id
        Diag.Count("rendered")
        local name = tt.GetName and tt:GetName() or "?"
        local changed = not T.last or T.last.id ~= id or T.last.tooltip ~= name
        T.last = { id = id, how = how, primary = primaryID, tooltip = name, lines = n, ms = ms }
        if name ~= "ItemRefTooltip" then
            ns.lastItem = id
            ns.lastLink = data and type(data.hyperlink) == "string" and data.hyperlink or nil
        end
        if changed then Diag.Log(string.format("Infobulle %s : objet %d (%s) · %d lignes · %.2f ms", name, id, how, n, ms)) end
    end, Diag.Handler)
    busy = false
    if not ok then Diag.Error("tooltip", err) end
end
T.OnPostCall = onPostCall

function T.Install()
    if T.installed then return end
    for _, name in ipairs({ "ShoppingTooltip1", "ShoppingTooltip2", "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" }) do
        if _G[name] then SKIP[_G[name]] = true end
    end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and itemType() then
        TooltipDataProcessor.AddTooltipPostCall(itemType(), onPostCall)
        T.method = "TooltipDataProcessor.AddTooltipPostCall(Item), synchrone"
    else
        -- Repli pour un client sans TooltipDataProcessor (non attendu sur Forever).
        for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
            if tt and tt.HookScript then
                tt:HookScript("OnTooltipSetItem", function(self) onPostCall(self, nil) end)
            end
        end
        T.method = "OnTooltipSetItem (repli)"
    end
    T.installed = true
end

ns.OnInit(T.Install)

-- Note : aucune reconstruction forcée sur Maj (RefreshData depuis un add-on
-- pourrait « contaminer » l'infobulle sécurisée). Les détails Maj apparaissent
-- à la reconstruction suivante effectuée par le client ou au prochain survol.
