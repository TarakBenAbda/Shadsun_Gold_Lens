-- =============================================================================
-- Shadsun Gold Lens — Core/Diagnostics.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Compteurs, journal de débogage (/sgl debug), capture d'erreurs avec
--      pile d'appel, rapport complet copiable (/sgl diag).
-- EN : Counters, debug log, error capture, copyable diagnostic report.
-- =============================================================================
local _, ns = ...
local U = ns.U
local D = {}
ns.Diag = D

D.counters = {
    postCalls = 0, rendered = 0, skippedNested = 0, skippedDuplicate = 0, skippedReentrant = 0,
    skippedShopping = 0, skippedForbidden = 0, skippedSecret = 0, unresolved = 0, errors = 0,
}
D.errors = {}
D.log = {}
local MAX_LOG, MAX_ERR = 60, 10

function D.Count(key) D.counters[key] = (D.counters[key] or 0) + 1 end

function D.Log(msg)
    local line = date("%H:%M:%S") .. " " .. tostring(msg)
    D.log[#D.log + 1] = line
    if #D.log > MAX_LOG then table.remove(D.log, 1) end
    if ns.settings and ns.settings.debug then
        print("|c" .. U.colors.dim .. "[SGL debug]|r " .. tostring(msg))
    end
end

function D.Error(where, err)
    D.Count("errors")
    local entry = { where = where, err = tostring(err), stack = debugstack and debugstack(2, 6, 0) or "", time = date("%H:%M:%S") }
    D.errors[#D.errors + 1] = entry
    if #D.errors > MAX_ERR then table.remove(D.errors, 1) end
    if not D.announced then
        D.announced = true
        U.Print("une erreur interne a été interceptée. Tapez /sgl diag pour le rapport.")
    end
    D.Log("ERREUR " .. where .. " : " .. tostring(err))
end

-- Gestionnaire pour xpcall / xpcall handler
function D.Handler(err)
    return tostring(err) .. "\n" .. (debugstack and debugstack(2, 8, 0) or "")
end

local function yes(b) return b and "oui" or "non" end

function D.Report()
    local out = {}
    local function add(s) out[#out + 1] = s end
    local version, build, _, toc = GetBuildInfo()
    add(ns.title .. " " .. ns.version .. " — rapport de diagnostic (" .. date("%Y-%m-%d %H:%M") .. ")")
    add("Client : " .. tostring(version) .. " build " .. tostring(build) .. " · TOC " .. tostring(toc)
        .. " · projet " .. tostring(WOW_PROJECT_ID) .. " · langue " .. tostring(GetLocale()))
    add("Personnage : " .. tostring(UnitName("player")) .. " · faction " .. tostring(UnitFactionGroup("player"))
        .. " · carte " .. tostring(ns.Catalog.PlayerMap()))
    add("TooltipDataProcessor : " .. yes(TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall)
        .. " · hook installé : " .. yes(ns.Tooltip and ns.Tooltip.installed) .. " · méthode : " .. tostring(ns.Tooltip and ns.Tooltip.method))
    add("Auctionator : " .. ns.Prices.Describe())
    add("TomTom : " .. yes(ns.Navigation.HasTomTom()) .. " · C_Map.SetUserWaypoint : " .. yes(C_Map and C_Map.SetUserWaypoint))
    add("C_MerchantFrame.GetItemInfo : " .. yes(C_MerchantFrame and C_MerchantFrame.GetItemInfo)
        .. " · dernier relevé : " .. (ns.Merchant.lastScan and (tostring(ns.Merchant.lastScan.name) .. " (" .. ns.Merchant.lastScan.items .. " objets)") or "aucun"))
    if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
        pcall(UpdateAddOnMemoryUsage)
        local ok, kb = pcall(GetAddOnMemoryUsage, ns.name)
        if ok and type(kb) == "number" then
            add(string.format("Mémoire de l'add-on : %.1f Mo", kb / 1024))
        end
    end
    if ns.Arbitrage then
        local A = ns.Arbitrage
        add("HDV : scan complet API " .. yes(A.CanReplicate()) .. " · annonces en mémoire " .. (A.live and A.live.total or 0) .. " · demandes d'infos en attente " .. A.PendingPrices()
            .. " · opportunités HDV » PNJ " .. #A.liveResults .. " (direct) / " .. #A.histResults .. " (historique)")
    end
    if ns.Market then
        local MK = ns.Market
        local zone, mapID = MK.ZoneKey()
        add("Marchés (" .. MK.Realm() .. ") : carte " .. tostring(mapID) .. " = " .. MK.Label(zone) .. " · prochain scan : " .. MK.Label(MK.Current())
            .. " (" .. tostring(MK.Choice() or "selon la zone") .. ") · revente : " .. MK.Label(MK.SellKey()))
        for _, key in ipairs(MK.KEYS) do
            add("  " .. MK.Label(key) .. " : " .. (MK.Describe(key):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
        end
        add("Prix externes (" .. MK.ExternalName() .. ") : " .. tostring(MK.extStatus) .. (MK.extInfo and (" · " .. tostring(MK.extInfo.region) .. " " .. tostring(MK.extInfo.ruleset or "")
            .. " · générés " .. (MK.extInfo.generated and U.Ago(MK.extInfo.generated) or "?")) or "")
            .. " · région du client : " .. tostring(MK.ClientRegion() or "inconnue"))
        local chars = ns.Inventory.Characters()
        local names = {}
        for _, c in ipairs(chars) do names[#names + 1] = c.name end
        add("Personnages du serveur : " .. (#names > 0 and table.concat(names, ", ") or "aucun"))
        if ns.Auctions then
            local na, ta, qa = ns.Auctions.Mine()
            add("Vos enchères (ce personnage) : " .. na .. " annonce(s), " .. (qa or 0) .. " objet(s) · relevé " .. (ta and U.Ago(ta) or "jamais (ouvrez l'HDV)"))
        end
    end
    local m = ns.Data.meta
    add(string.format("Base intégrée %s : %d objets · %d PNJ · %d associations · %d objets connus",
        tostring(m.version), m.items or 0, m.npcs_used or 0, m.pairs or 0, m.known_items or 0))
    local oi, orows, onpc = ns.DB.CountObservations()
    add(string.format("Vos observations : %d objets · %d relevés · %d PNJ · migrées depuis v0.3.0 : %d",
        oi, orows, onpc, ns.DB.migratedRows or 0))
    local c = D.counters
    add(string.format("Infobulles : appels %d · rendus %d · imbriqués ignorés %d · doublons ignorés %d · réentrées %d · comparaison %d · protégées %d · secrètes %d · non résolus %d · erreurs %d",
        c.postCalls, c.rendered, c.skippedNested, c.skippedDuplicate, c.skippedReentrant, c.skippedShopping,
        c.skippedForbidden, c.skippedSecret, c.unresolved, c.errors))
    local t = ns.Tooltip and ns.Tooltip.last
    if t then
        add(string.format("Dernier survol : objet %s via %s (%s) · primaire %s · %d lignes · %.2f ms",
            tostring(t.id), tostring(t.tooltip), tostring(t.how), tostring(t.primary), t.lines or 0, t.ms or 0))
    end
    local s = ns.settings
    add(string.format("Paramètres : infobulle %s · marché %s · commission %s/%s %% · remise %s %% · lignes max %s",
        yes(s.tooltip.enabled), s.economy.market, s.economy.commissionFaction, s.economy.commissionNeutral,
        s.economy.repDiscount, s.tooltip.maxLines))
    if #D.errors > 0 then
        add("Erreurs récentes :")
        for i = #D.errors, math.max(1, #D.errors - 4), -1 do
            local e = D.errors[i]
            add("  [" .. e.time .. "] " .. e.where .. " : " .. e.err)
            if e.stack ~= "" then add("    " .. e.stack:gsub("\n", "\n    ")) end
        end
    else
        add("Aucune erreur enregistrée.")
    end
    if #D.log > 0 then
        add("Journal (dernières lignes) :")
        for i = math.max(1, #D.log - 12), #D.log do add("  " .. D.log[i]) end
    end
    return table.concat(out, "\n")
end
