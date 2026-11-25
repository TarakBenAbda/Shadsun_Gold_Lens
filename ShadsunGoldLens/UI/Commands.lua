-- =============================================================================
-- Shadsun Gold Lens — UI/Commands.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Commandes /sgl et message de démarrage.
-- EN : Slash commands and login banner.
-- =============================================================================
local _, ns = ...
local U = ns.U

local HELP = {
    "/sgl — ouvrir/fermer la fenêtre",
    "/sgl objet <ID | lien | nom> — détail d'un objet",
    "/sgl opp — tableau des opportunités (PNJ » HDV, HDV » PNJ, HDV » HDV)",
    "/sgl marches — scans des HDV du serveur et personnages",
    "/sgl listes — listes d'achats",
    "/sgl options — paramètres",
    "/sgl arb — panneau de l'hôtel des ventes",
    "/sgl stop — arrêter toute analyse en arrière-plan",
    "/sgl hdv — diagnostic de l'API de l'hôtel des ventes (à lancer devant l'HDV)",
    "/sgl debug [on|off] — messages de diagnostic dans le chat",
    "/sgl diag — rapport de diagnostic copiable",
    "/sgl stats — état de la base",
    "/sgl info <ID> — calcul détaillé dans le chat",
    "/sgl minimap — afficher/masquer l'icône",
    "/sgl resetui — réinitialiser positions et icône",
}

local function itemInfoToChat(id)
    local v = ns.Catalog.GetView(id)
    U.Print("objet " .. id .. " · " .. ns.Catalog.StatusText(v.status) .. " · " .. #v.offers .. " vendeur(s)")
    local price, age, state = ns.Prices.Best(id)
    U.Print("HDV : " .. (price and (U.Money(price) .. (age and (" · " .. age .. " j") or "")) or ("aucun prix (" .. state .. ")")))
    for i = 1, math.min(5, #v.offers) do
        local o = v.offers[i]
        U.Print(string.format("%d. %s · %s · %s · %s · %s", i, o.name, U.SideText(o.side), ns.Catalog.LocationText(o),
            ns.Catalog.PriceText(o), ns.Catalog.SourceText(o)))
    end
    local r, reason = ns.Economy.Evaluate(id, v.best, price, age)
    if r then
        U.Print(string.format("Bénéfice %s · rentabilité %s · seuil %s · %s", U.Money(r.profit, false, true),
            U.Percent(r.roi, true), U.Money(r.breakEven), ns.Economy.VerdictText(r)))
    else
        U.Print(ns.L.CALC_IMPOSSIBLE .. " : " .. tostring(reason))
    end
end

SLASH_SHADSUNGOLDLENS1 = "/sgl"
SLASH_SHADSUNGOLDLENS2 = "/shadsun"
SlashCmdList.SHADSUNGOLDLENS = function(msg)
    local ok, err = pcall(function()
        msg = U.Trim(msg)
        local cmd, rest = msg:match("^(%S*)%s*(.-)$")
        cmd = (cmd or ""):lower()
        if cmd == "" then
            ns.UI.Toggle()
        elseif cmd == "objet" or cmd == "item" then
            local id = U.ItemID(rest)
            if id then ns.UI.ShowItem(id)
            else
                local found = ns.Catalog.SearchByName(rest, 1)
                if found[1] then ns.UI.ShowItem(found[1].id) else U.Print("objet introuvable : " .. rest) end
            end
        elseif cmd == "opp" or cmd == "opportunites" or cmd == "opportunités" then
            ns.UI.Show("opp")
        elseif cmd == "listes" or cmd == "liste" or cmd == "lists" then
            ns.UI.Show("lists")
        elseif cmd == "marches" or cmd == "marchés" or cmd == "marche" or cmd == "markets" then
            ns.UI.Show("markets")
        elseif cmd == "options" or cmd == "config" or cmd == "parametres" or cmd == "paramètres" then
            ns.UI.Show("options")
        elseif cmd == "arb" or cmd == "arbitrage" then
            ns.AuctionPanel.Show()
        elseif cmd == "stop" then
            local stopped = ns.Arbitrage.StopAll()
            U.Print(#stopped > 0 and ("arrêté : " .. table.concat(stopped, ", ") .. ".") or "aucune activité en cours.")
        elseif cmd == "hdv" or cmd == "ah" then
            local report = ns.Arbitrage.Report()
            for line in report:gmatch("[^\n]+") do print(line) end
            ns.UI.ShowCopy("Diagnostic HDV — Shadsun Gold Lens", report)
        elseif cmd == "debug" then
            local v = rest:lower()
            if v == "on" then ns.settings.debug = true elseif v == "off" then ns.settings.debug = false
            else ns.settings.debug = not ns.settings.debug end
            U.Print("diagnostic dans le chat : " .. (ns.settings.debug and "activé" or "désactivé"))
        elseif cmd == "diag" or cmd == "diagnostic" then
            local report = ns.Diag.Report()
            for line in report:gmatch("[^\n]+") do print(line) end
            ns.UI.ShowCopy("Diagnostic — Shadsun Gold Lens", report)
        elseif cmd == "stats" then
            local s = ns.LiveStats()
            U.Print(string.format("%d objets vendus · %d PNJ · %d associations · %d PNJ localisés · %d incomplets · base %s",
                s.itemsWithNpc, s.npcs, s.pairs, s.npcsWithCoords, s.incomplete, tostring(ns.Data.meta.version)))
        elseif cmd == "info" then
            local id = U.ItemID(rest) or ns.lastItem
            if id then itemInfoToChat(id) else U.Print("usage : /sgl info <ID>") end
        elseif cmd == "minimap" then
            ns.settings.minimap.hide = not ns.settings.minimap.hide
            ns.Minimap.Apply()
        elseif cmd == "resetui" then
            ns.DB.ResetUI()
            ns.Minimap.Apply()
            U.Print("positions réinitialisées.")
        else
            for _, l in ipairs(HELP) do print(l) end
        end
    end)
    if not ok then ns.Diag.Error("slash", err) end
end

ns.OnLogin(function()
    local state = ns.Prices.State()
    local extra = (state == "OK") and "" or " · Auctionator absent : prix HDV indisponibles"
    print("|c" .. U.colors.title .. ns.title .. " v" .. ns.version .. "|r · " .. ns.signature .. " · /sgl" .. extra)
    if (ns.DB.migratedRows or 0) > 0 then
        U.Print(ns.DB.migratedRows .. " relevés marchands de la v0.3.0 ont été migrés.")
    end
end)
