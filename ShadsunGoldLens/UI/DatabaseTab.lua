-- =============================================================================
-- Shadsun Gold Lens — UI/DatabaseTab.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : État de la base (statistiques recalculées sur les tables réellement
--      chargées, pas sur des chiffres annoncés), sources, observations,
--      diagnostic copiable.
-- EN : Database status computed from loaded tables, sources, diagnostics.
-- =============================================================================
local _, ns = ...
local U, W = ns.U, ns.W

-- Statistiques recalculées en jeu / live statistics
function ns.LiveStats()
    local D = ns.Data
    local s = { items = 0, pairs = 0, itemsWithNpc = 0, npcs = 0, npcsWithCoords = 0, incomplete = 0, known = 0 }
    local used = {}
    for _, flat in pairs(D.items) do
        s.items = s.items + 1
        local any = false
        for i = 1, #flat, 6 do
            s.pairs = s.pairs + 1
            local n = D.npcs[flat[i]]
            if n then
                any = true
                used[flat[i]] = true
                if not n[4] or n[3] == "?" or ((flat[i + 1] or 0) <= 0 and flat[i + 3] % 16 < 8) then
                    s.incomplete = s.incomplete + 1
                end
            else
                s.incomplete = s.incomplete + 1
            end
        end
        if any then s.itemsWithNpc = s.itemsWithNpc + 1 end
    end
    for id in pairs(used) do
        s.npcs = s.npcs + 1
        if D.npcs[id][4] then s.npcsWithCoords = s.npcsWithCoords + 1 end
    end
    local r = D.knownRanges
    for i = 2, #r, 2 do s.known = s.known + r[i] end
    return s
end

ns.UI.RegisterTab("db", "Base & diagnostic", function(page)
    local text = W.Text(page, "GameFontHighlightSmall", "", "LEFT", 400)
    text:SetPoint("TOPLEFT", 4, -4)
    text:SetSpacing(3)
    local src = W.Text(page, "GameFontHighlightSmall", "", "LEFT", 390)
    src:SetPoint("TOPLEFT", 420, -4)
    src:SetSpacing(3)

    local box = W.CopyBox(page, 812, 200)
    box:SetPoint("BOTTOMLEFT", 0, 30)
    local diagBtn = W.Button(page, "Actualiser le diagnostic", 190, 22, function() box:SetText(ns.Diag.Report()) end)
    diagBtn:SetPoint("BOTTOMLEFT", 0, 2)
    local copyBtn = W.Button(page, "Ouvrir pour copier", 160, 22, function() ns.UI.ShowCopy("Diagnostic — Shadsun Gold Lens", ns.Diag.Report()) end)
    copyBtn:SetPoint("LEFT", diagBtn, "RIGHT", 6, 0)
    local armed = false
    local purge
    purge = W.Button(page, "Effacer mes observations", 190, 22, function()
        if not armed then
            armed = true
            purge:SetText("Confirmer l'effacement ?")
            C_Timer.After(3, function() armed = false; purge:SetText("Effacer mes observations") end)
            return
        end
        armed = false
        purge:SetText("Effacer mes observations")
        ns.DB.PurgeObservations()
        page.OnActivate()
    end)
    purge:SetPoint("BOTTOMRIGHT", 0, 2)

    page.OnActivate = function()
        local m, live = ns.Data.meta, ns.LiveStats()
        local oi, orows, onpc = ns.DB.CountObservations()
        local lines = {
            U.Color(U.colors.title, "Base intégrée (calculée sur les fichiers chargés)"),
            "Objets vendus par au moins un PNJ : " .. live.itemsWithNpc .. " / " .. live.items,
            "PNJ marchands distincts : " .. live.npcs,
            "Associations objet-vendeur : " .. live.pairs,
            "PNJ avec coordonnées : " .. live.npcsWithCoords,
            "Enregistrements incomplets : " .. live.incomplete,
            "Objets connus (avec ou sans vendeur) : " .. live.known,
            "Date de construction : " .. tostring(m.version),
            "",
            U.Color(U.colors.title, "Qualité (rapport de construction)"),
            "Confirmés sur Forever : " .. (m.items_confirmed_forever or 0) .. " · référence Classic seule : " .. (m.items_reference_only or 0),
            "Alliance seule : " .. (m.items_alliance_only or 0) .. " · Horde seule : " .. (m.items_horde_only or 0)
                .. " · deux factions : " .. (m.items_both_factions or 0) .. " · incertaine : " .. (m.items_faction_uncertain or 0),
            "Coordonnées observées sur Forever : " .. (m.items_with_reliable_coords or 0) .. " objets",
            "Prix Forever différent de Classic : " .. (m.items_price_forever_changed or 0) .. " objets",
            "",
            U.Color(U.colors.title, "Vos observations en jeu"),
            oi .. " objets · " .. orows .. " relevés · " .. onpc .. " PNJ · migrés depuis v0.3.0 : " .. (ns.DB.migratedRows or 0),
        }
        text:SetText(table.concat(lines, "\n"))
        src:SetText(table.concat({
            U.Color(U.colors.title, "Sources et licences"),
            "QuestieDB Forever — vendeurs, positions (GPLv3)",
            "CMaNGOS Classic DB — tarifs de référence (GPLv3)",
            "Efficient Games / EG Link — observations Forever " .. tostring(m.observedBuilds) .. " (CC BY 4.0)",
            "pfQuest — noms français des PNJ (MIT)",
            "Vos relevés marchands — prioritaires sur tout le reste",
            "",
            U.Color(U.colors.title, "Statuts"),
            U.Color(U.colors.good, "Confirmé") .. " : vu sur Forever (EG Link ou vous)",
            U.Color(U.colors.warn, "À vérifier") .. " : référence Classic non confirmée",
            "Aucun vendeur confirmé : connu des bases, aucun vendeur listé",
            "Information non disponible : objet absent des bases",
            "",
            "Mise à jour : voir LISEZ-MOI.md (outil tools/sgl_build_db.py).",
        }, "\n"))
        box:SetText(ns.Diag.Report())
    end
end)
