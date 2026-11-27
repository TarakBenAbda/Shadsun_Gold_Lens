-- =============================================================================
-- Shadsun Gold Lens — Core/Economy.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Calculs de rentabilité, intégralement en cuivre (entiers).
--   Revenu lot     = q × prixHDV − commission, commission = ⌈q × prixHDV × taux⌉
--                    (arrondi défavorable : estimation prudente)
--   Bénéfice       = revenu − coût du lot PNJ
--   Rentabilité %  = bénéfice / coût × 100
--   Seuil HDV / u. = ⌈coût / (q × (1 − taux))⌉
--   Marge %        = bénéfice / (q × prixHDV) × 100
--   Le dépôt n'est pas soustrait (restitué si la vente aboutit) ; il est
--   présenté séparément comme risque d'invendu si l'option est activée.
-- EN : Profitability math in integer copper.
-- =============================================================================
local _, ns = ...
local L = ns.L
local E = {}
ns.Economy = E

local floor, ceil = math.floor, math.ceil

-- Taux de commission (fraction) selon le marché choisi / commission rate
function E.Rate()
    local s = ns.DB.settings.economy
    local pct = (s.market == "neutral") and ns.DB.Num("economy", "commissionNeutral") or ns.DB.Num("economy", "commissionFaction")
    return pct / 100, pct, s.market
end

-- Objets non revendables à l'HDV : liés quand ramassés (1), quête (4), compte (7/8/9)
local UNTRADEABLE_BIND = { [1] = true, [4] = true, [7] = true, [8] = true, [9] = true }
local QUEST_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12

-- Calcul pur, testable hors jeu / pure computation
-- lotCost : coût du lot PNJ ; qty : unités par lot ; ahUnit : prix HDV unitaire ; rate : 0..1
function E.Compute(lotCost, qty, ahUnit, rate)
    qty = qty or 1
    local gross = qty * ahUnit
    local cut = ceil(gross * rate - 1e-9)
    local revenue = gross - cut
    local profit = revenue - lotCost
    local roi = lotCost > 0 and (profit / lotCost * 100) or nil
    local breakEven = ceil(lotCost / (qty * (1 - rate)) - 1e-9)
    local margin = gross > 0 and (profit / gross * 100) or nil
    return { gross = gross, cut = cut, revenue = revenue, profit = profit, roi = roi,
        breakEven = breakEven, margin = margin, lotCost = lotCost, qty = qty, ahUnit = ahUnit, rate = rate }
end

-- Évaluation complète pour une offre et un prix HDV / full evaluation
-- Retourne result | nil, raison
function E.Evaluate(itemID, offer, ahUnit, ageDays, itemInfo, rateOverride)
    if not offer then return nil, L.REASON_NO_VENDOR end
    if offer.ext then return nil, L.REASON_EXTCOST end
    if not offer.price or offer.price <= 0 then return nil, L.REASON_NO_PRICE end
    if not ahUnit then return nil, L.REASON_NO_AH end
    itemInfo = itemInfo or ns.U.ItemInfo(itemID)
    if itemInfo and (UNTRADEABLE_BIND[itemInfo.bindType or 0] or itemInfo.classID == QUEST_CLASS) then
        return nil, L.REASON_BOUND
    end
    local rate = rateOverride or E.Rate()
    local r = E.Compute(offer.price, offer.qty, ahUnit, rate)
    r.bindUnknown = itemInfo == nil
    r.age = ageDays
    r.stale = ageDays ~= nil and ageDays > (ns.DB.Num("economy", "staleDays") or 7)
    local minROI = ns.DB.Num("economy", "minROI") or 20
    if r.profit <= 0 then r.verdict = "BAD"
    elseif (r.roi or 0) < minROI then r.verdict = "LOW"
    else r.verdict = "GOOD" end
    if ns.DB.settings.economy.depositEstimate and itemInfo and itemInfo.sellPrice and itemInfo.sellPrice > 0 then
        r.depositRisk = ceil(itemInfo.sellPrice * offer.qty * ns.DB.Num("economy", "depositPct") / 100)
    end
    return r
end

function E.VerdictText(r)
    local t = (r.verdict == "GOOD" and L.VERDICT_GOOD) or (r.verdict == "LOW" and L.VERDICT_LOW) or L.VERDICT_BAD
    if r.stale then t = t .. " · " .. L.VERDICT_STALE end
    return t
end

function E.VerdictColor(r)
    local c = ns.U.colors
    if r.verdict == "GOOD" then return c.good elseif r.verdict == "LOW" then return c.warn end
    return c.bad
end
