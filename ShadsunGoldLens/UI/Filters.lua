-- =============================================================================
-- Shadsun Gold Lens — UI/Filters.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Barre de filtres commune à toutes les listes d'opportunités :
--       - Catégorie : arbre de l'hôtel des ventes (catégorie » sous-catégorie
--         » emplacement), noms issus du jeu ;
--       - Qualité minimale (couleurs du jeu) ;
--       - Recherche par nom, sans tenir compte des majuscules ni des accents.
-- EN : Shared filter bar: AH-like category tree, minimum quality, name search.
-- =============================================================================
local _, ns = ...
local U, W = ns.U, ns.W
local F = {}
ns.Filters = F

F.QUALITIES = {
    { 0, "Médiocre" }, { 1, "Classique" }, { 2, "Inhabituelle" }, { 3, "Rare" }, { 4, "Épique" }, { 5, "Légendaire" },
}

function F.New() return { cat = nil, quality = nil, text = "" } end

local function qualityName(q)
    local v = _G["ITEM_QUALITY" .. q .. "_DESC"]
    if type(v) == "string" and v ~= "" then return v end
    for _, o in ipairs(F.QUALITIES) do if o[1] == q then return o[2] end end
    return tostring(q)
end
F.QualityName = qualityName

-- Filtre actif ? / any filter set?
function F.Active(st)
    return st.cat ~= nil or st.quality ~= nil or (st.text or "") ~= ""
end

-- L'objet passe-t-il les filtres ? Objet non chargé : exclu si un filtre de
-- qualité est actif (chargement demandé), le nom vient alors de la base.
function F.Match(st, id, name)
    if st.cat and not ns.Categories.Match(st.cat, id) then return false end
    local info
    if st.quality then
        info = U.ItemInfo(id)
        if not info then U.RequestItem(id); return false end
        if (info.quality or 0) < st.quality then return false end
    end
    if st.text and st.text ~= "" then
        if not st.folded or st.foldedFrom ~= st.text then st.folded, st.foldedFrom = U.Fold(st.text), st.text end
        info = info or U.ItemInfo(id)
        local n = (info and info.name) or name or (ns.Data.names and ns.Data.names[id])
        if not n or not U.Fold(n):find(st.folded, 1, true) then return false end
    end
    return true
end

local function sameCat(a, b)
    if a == nil or b == nil then return a == b end
    return a.class == b.class and a.sub == b.sub and a.slot == b.slot
end

-- Menu de catégories / category menu items
function F.CategoryItems(st)
    local items = { { text = "Toutes les catégories", value = "ALL", checked = st.cat == nil } }
    for _, c in ipairs(ns.Categories.Tree()) do
        local cv = { class = c.class }
        local node = { text = c.name, value = cv, checked = sameCat(st.cat, cv) }
        if #c.subs > 0 then
            node.children = { { text = "Tout : " .. c.name, value = cv, checked = sameCat(st.cat, cv) } }
            for _, s in ipairs(c.subs) do
                local sv = { class = c.class, sub = s.sub }
                local sn = { text = s.name, value = sv, checked = sameCat(st.cat, sv) }
                if #s.slots > 0 then
                    sn.children = { { text = "Tout : " .. s.name, value = sv, checked = sameCat(st.cat, sv) } }
                    for _, sl in ipairs(s.slots) do
                        local lv = { class = c.class, sub = s.sub, slot = sl.slot }
                        sn.children[#sn.children + 1] = { text = sl.name, value = lv, checked = sameCat(st.cat, lv) }
                    end
                end
                node.children[#node.children + 1] = sn
            end
        end
        items[#items + 1] = node
    end
    return items
end

-- Barre de filtres / filter bar. widths = { catégorie, qualité, recherche }
function F.Bar(parent, st, onChange, widths)
    widths = widths or { 230, 160, 160 }
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(widths[1] + widths[2] + widths[3] + 12, 22)
    local cat = W.Dropdown(holder, widths[1], "Catégorie : ", function() return ns.Categories.Label(st.cat) end,
        function() return F.CategoryItems(st) end,
        function(v)
            st.cat = (v ~= "ALL") and v or nil
            onChange()
        end, "Catégories de l'hôtel des ventes. Survolez une catégorie pour choisir une sous-catégorie.")
    cat:SetPoint("TOPLEFT", 0, 0)
    local qOpts = { { "ALL", "Toutes" } }
    for _, o in ipairs(F.QUALITIES) do qOpts[#qOpts + 1] = { o[1], qualityName(o[1]), U.QualityHex(o[1]) } end
    local quality = W.Cycle(holder, widths[2], "Qualité min. : ", qOpts,
        function() return st.quality == nil and "ALL" or st.quality end,
        function(v) st.quality = (v ~= "ALL") and v or nil; onChange() end,
        "Affiche les objets de cette qualité ou supérieure.")
    quality:SetPoint("LEFT", cat, "RIGHT", 6, 0)
    local search = W.SearchBox(holder, widths[3], "Nom de l'objet…", function(t)
        st.text = U.Trim(t)
        onChange()
    end)
    search:SetPoint("LEFT", quality, "RIGHT", 10, 0)
    holder.cat, holder.quality, holder.search = cat, quality, search
    function holder:Refresh() cat:Refresh(); quality:Refresh() end
    function holder:Reset()
        st.cat, st.quality, st.text = nil, nil, ""
        search:SetText("")
        search.Changed(true)
        self:Refresh()
    end
    return holder
end
