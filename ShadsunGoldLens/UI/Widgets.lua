-- =============================================================================
-- Shadsun Gold Lens — UI/Widgets.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Composants d'interface réutilisables, construits uniquement avec des
--      gabarits présents dans le client moderne (BackdropTemplate,
--      UIPanelButtonTemplate, UICheckButtonTemplate, InputBoxTemplate,
--      UIPanelCloseButton). Les listes recyclent un nombre fixe de lignes :
--      aucune création infinie de cadres ou de textures.
-- EN : Reusable widgets; fixed row pools (no unbounded frame creation).
-- =============================================================================
local _, ns = ...
local U = ns.U
local W = {}
ns.W = W

W.BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
W.PANEL_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
}

function W.Text(parent, template, text, justify, width)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    fs:SetJustifyH(justify or "LEFT")
    if width then fs:SetWidth(width) end
    if text then fs:SetText(text) end
    return fs
end

function W.Panel(parent, w, h)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if w and h then f:SetSize(w, h) end
    f:SetBackdrop(W.PANEL_BACKDROP)
    f:SetBackdropColor(0.04, 0.05, 0.07, 0.85)
    f:SetBackdropBorderColor(0.30, 0.26, 0.18, 0.9)
    return f
end

function W.Button(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 100, h or 22)
    b:SetText(text)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

function W.Check(parent, label, get, set, tooltip)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    local fs = W.Text(parent, "GameFontHighlight", label)
    fs:SetPoint("LEFT", c, "RIGHT", 2, 1)
    c.label = fs
    c:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        ns.Fire("SETTINGS_CHANGED")
    end)
    if tooltip then
        c:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 0.82, 0)
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    function c:Refresh() self:SetChecked(get() and true or false) end
    c:Refresh()
    return c
end

function W.Edit(parent, w, onCommit)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(w or 120, 20)
    e:SetAutoFocus(false)
    e:SetMaxLetters(200)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if onCommit then
        e:SetScript("OnEnterPressed", function(self) onCommit(self); self:ClearFocus() end)
        e:SetScript("OnEditFocusLost", function(self) onCommit(self) end)
    else
        e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    end
    return e
end

-- Champ numérique lié à un paramètre (saisie « 5,5 » acceptée)
function W.NumberSetting(parent, label, section, key, minV, maxV, width)
    local fs = W.Text(parent, "GameFontHighlight", label)
    local e = W.Edit(parent, width or 60, function(self)
        local v = U.ParseNumber(self:GetText())
        if v then
            v = math.min(math.max(v, minV), maxV)
            ns.settings[section][key] = v
            ns.Fire("SETTINGS_CHANGED")
        end
        self:SetText((tostring(ns.settings[section][key]):gsub("%.", ",")))
    end)
    e:SetPoint("LEFT", fs, "RIGHT", 10, 0)
    function e:Refresh() self:SetText((tostring(ns.settings[section][key]):gsub("%.", ","))) end
    e:Refresh()
    return fs, e
end

-- -----------------------------------------------------------------------------
-- Couleurs de l'interface / UI palette
-- -----------------------------------------------------------------------------
W.GOLD = { 0.90, 0.75, 0.40 }
W.BORDER = { 0.30, 0.26, 0.18 }
W.FIELD_BG = { 0.02, 0.025, 0.035, 0.92 }

local function tip(owner, title, text, anchor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_TOP")
    GameTooltip:SetText(title, 1, 0.82, 0)
    if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
    GameTooltip:Show()
end
W.ShowTip = tip

-- Flèche : texture de sous-menu du jeu (pointe à droite), pivotée au besoin.
-- Arrow from the game's submenu texture (points right), rotated as needed.
W.ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow"
local ROT = { right = 0, up = math.pi / 2, left = math.pi, down = -math.pi / 2 }
function W.SetArrow(tex, dir)
    tex:SetTexture(W.ARROW)
    if tex.SetRotation then tex:SetRotation(ROT[dir] or 0) end
end

-- Bouton plat à fond sombre (champ, onglet, segment) / flat dark button
local function flatButton(parent, w, h, font)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, h)
    b:SetBackdrop(W.PANEL_BACKDROP)
    b:SetBackdropColor(W.FIELD_BG[1], W.FIELD_BG[2], W.FIELD_BG[3], W.FIELD_BG[4])
    b:SetBackdropBorderColor(W.BORDER[1], W.BORDER[2], W.BORDER[3], 1)
    local fs = b:CreateFontString(nil, "ARTWORK", font or "GameFontNormalSmall")
    fs:SetPoint("LEFT", 8, 0)
    fs:SetPoint("RIGHT", -8, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    b:SetFontString(fs)
    b.label = fs
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.10)
    return b
end
W.FlatButton = flatButton

-- -----------------------------------------------------------------------------
-- Bouton icône avec infobulle / icon button with tooltip
-- crop = true pour les icônes d'objets (bord retiré).
-- -----------------------------------------------------------------------------
function W.IconButton(parent, texture, title, text, onClick, size, crop)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(size or 18, size or 18)
    b:SetBackdrop(W.PANEL_BACKDROP)
    b:SetBackdropColor(0, 0, 0, 0.55)
    b:SetBackdropBorderColor(W.BORDER[1], W.BORDER[2], W.BORDER[3], 1)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetPoint("TOPLEFT", 1, -1)
    t:SetPoint("BOTTOMRIGHT", -1, 1)
    t:SetTexture(texture)
    if crop ~= false then t:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    b.icon = t
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(W.GOLD[1], W.GOLD[2], W.GOLD[3], 1)
        W.RowHover(self, true)
        tip(self, title, text)
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(W.BORDER[1], W.BORDER[2], W.BORDER[3], 1)
        W.RowHover(self, false)
        GameTooltip:Hide()
    end)
    function b:SetUsable(v)
        self:SetEnabled(v and true or false)
        self:SetAlpha(v and 1 or 0.3)
    end
    return b
end

-- Logo et icône de l'add-on (Media) / add-on logo and icon
W.LOGO = "Interface\\AddOns\\ShadsunGoldLens\\Media\\logo"
W.ICON = "Interface\\AddOns\\ShadsunGoldLens\\Media\\icon"
-- Grand médaillon (logo préparé pour 76 px, ombre portée) / large header medallion
W.MEDALLION = "Interface\\AddOns\\ShadsunGoldLens\\Media\\medaillon"
W.MEDALLION_SIZE, W.MEDALLION_X, W.MEDALLION_Y = 76, -22, 34

-- Survol d'un bouton dans une ligne de tableau : la ligne reste en surbrillance.
-- Hovering a button inside a table row keeps the row highlighted.
function W.RowHover(btn, on)
    local row = btn and btn:GetParent()
    if row and row.isListRow then
        if on then row:LockHighlight() else row:UnlockHighlight() end
    end
end

-- Icônes communes / shared icons
W.ICON_SEARCH = "Interface\\Common\\UI-Searchbox-Icon"
W.ICON_MAP = "Interface\\Icons\\INV_Misc_Map_01"
W.ICON_COPY = "Interface\\Icons\\INV_Misc_Note_01"
W.ICON_ADD = "Interface\\Buttons\\UI-PlusButton-Up"
W.ICON_REMOVE = "Interface\\Buttons\\UI-StopButton"
W.ICON_RELOAD = "Interface\\Buttons\\UI-RefreshButton"

-- Cellules « Sacs » et « Vente » / stock cells
W.TIP_BAGS = "Dans les sacs de ce personnage. Banque et autres personnages : survol de la ligne (infobulle « Possédé »)."
W.TIP_SALE = "Mis en vente à l'HDV, pas encore vendu (tous vos personnages du serveur). Relevé à chaque visite de l'HDV, corrigé par les messages de vente et d'expiration ; « ~ » = au plus."
function W.BagsText(d)
    local n = d.bags or 0
    return n > 0 and U.Color(U.colors.title, tostring(n)) or U.Color(U.colors.dim, "0")
end
function W.SaleText(d)
    return d.saleText and U.Color(U.colors.title, d.saleText) or U.Color(U.colors.dim, "-")
end

W.ICON_MINUS = "Interface\\Buttons\\UI-MinusButton-Up"
W.STEP_SHIFT = 5   -- Maj+clic : pas de 5 / Shift+click step

-- Boutons « + » et « - » : ajoutent ou retirent un exemplaire de l'objet de
-- la ligne dans la liste d'achats active (Maj+clic : 5). Le « - » se place
-- tout seul à gauche du « + » ; un badge sur le « + » donne la quantité déjà
-- dans la liste. getID(button) retourne l'identifiant de l'objet.
-- Add/remove buttons (the minus button sits left of the plus button).
local stepButtons = {}

local function stepTip(self, plus)
    local id = self.getID(self.main)
    local LS = ns.Lists
    local l = LS and LS.Active()
    local lines = {}
    lines[#lines + 1] = "Liste active : « " .. (l and l.name or "?") .. " » (onglet Listes)."
    if id then
        lines[#lines + 1] = "Dans la liste : " .. LS.ActiveQty(id)
        local have = LS.HaveText(id)
        if have ~= "" then lines[#lines + 1] = "Vous avez : " .. have end
    end
    lines[#lines + 1] = "Maj+clic : " .. (plus and "+" or "-") .. W.STEP_SHIFT .. "." .. (plus and " Alt+clic sur un objet ajoute aussi 1." or " Sous 1, l'objet quitte la liste.")
    tip(self, plus and "Ajouter à la liste d'achats" or "Retirer de la liste d'achats", table.concat(lines, "\n"))
end

local function stepClick(self, sign)
    local id = self.getID(self.main)
    if not id then return end
    local n = (IsShiftKeyDown and IsShiftKeyDown()) and W.STEP_SHIFT or 1
    local _, msg = ns.Lists.Step(id, sign * n)
    U.Print(msg)
    if self:IsMouseOver() then stepTip(self, sign > 0) end
end

function W.AddButton(parent, getID)
    local b = W.IconButton(parent, W.ICON_ADD, "Ajouter à la liste d'achats", nil, function(self) stepClick(self, 1) end, 18, false)
    local m = W.IconButton(parent, W.ICON_MINUS, "Retirer de la liste d'achats", nil, function(self) stepClick(self, -1) end, 18, false)
    m:SetPoint("RIGHT", b, "LEFT", -2, 0)
    b.getID, m.getID, b.main, m.main, b.minus = getID, getID, b, b, m
    for _, btn in ipairs({ b, m }) do
        btn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(W.GOLD[1], W.GOLD[2], W.GOLD[3], 1)
            W.RowHover(self, true)
            stepTip(self, self == b)
        end)
    end
    local badge = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    badge:SetPoint("BOTTOMRIGHT", 1, -1)
    badge:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
    b.badge = badge
    function b:Refresh()
        local id = self:GetParent().data and getID(self)
        local q = (id and ns.Lists) and ns.Lists.ActiveQty(id) or 0
        badge:SetText(q > 0 and (q > 99 and "99+" or tostring(q)) or "")
        m:SetUsable(q > 0)
    end
    b:HookScript("OnShow", function(self) self:Refresh() end)
    stepButtons[#stepButtons + 1] = b
    return b
end

ns.On("LISTS_CHANGED", function()
    for _, b in ipairs(stepButtons) do
        if b:IsVisible() and b:GetParent().data then b:Refresh() end
    end
end)

-- -----------------------------------------------------------------------------
-- Menus déroulants imbriqués / nested popup menus
-- items = { { text, value, checked, children = {…}, disabled, color }, … }
-- Clic sur une ligne avec valeur : sélection. Survol d'une ligne avec
-- sous-menu : ouverture du niveau suivant (3 niveaux au plus).
-- -----------------------------------------------------------------------------
local Menu = { levels = {}, MAX_ROWS = 30, ROW_H = 18 }
W.Menu = Menu

local function menuLevel(n)
    local f = Menu.levels[n]
    if f then return f end
    local name = "ShadsunGoldLensMenu" .. n
    f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetBackdrop(W.BACKDROP)
    f:SetBackdropColor(0.05, 0.06, 0.08, 0.98)
    f:SetBackdropBorderColor(W.GOLD[1], W.GOLD[2], W.GOLD[3], 1)
    f.buttons = {}
    f.level = n
    f:Hide()
    if n == 1 then
        tinsert(UISpecialFrames, name)
        f:SetScript("OnHide", function() for i = 2, #Menu.levels do Menu.levels[i]:Hide() end end)
    end
    Menu.levels[n] = f
    return f
end

local function menuRow(f, i)
    local b = f.buttons[i]
    if b then return b end
    b = CreateFrame("Button", nil, f)
    b:SetHeight(Menu.ROW_H)
    b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * Menu.ROW_H)
    b:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.18)
    b.check = b:CreateTexture(nil, "ARTWORK")
    b.check:SetSize(14, 14)
    b.check:SetPoint("LEFT", 0, 0)
    b.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    b.arrow = b:CreateTexture(nil, "ARTWORK")
    b.arrow:SetSize(12, 12)
    b.arrow:SetPoint("RIGHT", 0, 0)
    W.SetArrow(b.arrow, "right")
    local fs = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", 18, 0)
    fs:SetPoint("RIGHT", -14, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    b:SetFontString(fs)
    b:SetScript("OnEnter", function(self)
        local it = self.item
        if not it then return end
        for k = f.level + 1, #Menu.levels do Menu.levels[k]:Hide() end
        if it.children and #it.children > 0 and f.level < 3 then
            Menu.Open(self, it.children, f.onSelect, f.level + 1)
        end
    end)
    b:SetScript("OnClick", function(self)
        local it = self.item
        if not it or it.disabled then return end
        if it.value == nil and it.children then return end
        local cb = f.onSelect
        Menu.CloseAll()
        if cb then cb(it.value, it) end
    end)
    f.buttons[i] = b
    return b
end

function Menu.Open(anchor, items, onSelect, level)
    level = level or 1
    local f = menuLevel(level)
    f.onSelect, f.anchor = onSelect, anchor
    local n = math.min(#items, Menu.MAX_ROWS)
    local width = 140
    for i = 1, n do
        local it = items[i]
        local b = menuRow(f, i)
        b.item = it
        local txt = it.text or "?"
        if it.color then txt = U.Color(it.color, txt) end
        b:SetText(txt)
        b.check:SetShown(it.checked and true or false)
        b.arrow:SetShown(it.children ~= nil and #it.children > 0 and level < 3)
        b:SetEnabled(not it.disabled)
        b:SetAlpha(it.disabled and 0.45 or 1)
        b:Show()
        local fs = b:GetFontString()
        local fsw = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0
        width = math.max(width, fsw + 46)
    end
    for i = n + 1, #f.buttons do f.buttons[i]:Hide(); f.buttons[i].item = nil end
    f:SetSize(math.min(width, 320), n * Menu.ROW_H + 12)
    f:ClearAllPoints()
    if level == 1 then
        f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    else
        f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 6)
    end
    f:Show()
    return f
end

function Menu.CloseAll()
    for _, f in ipairs(Menu.levels) do f:Hide() end
end

function Menu.IsOpenFor(anchor)
    local f = Menu.levels[1]
    return f and f:IsShown() and f.anchor == anchor
end

-- Ligne du menu ouvert portant ce texte (aide aux tests et au diagnostic).
function Menu.Find(text, level)
    local f = Menu.levels[level or 1]
    if not f or not f:IsShown() then return nil end
    for _, b in ipairs(f.buttons) do
        if b:IsShown() and b.item and b.item.text == text then return b end
    end
    return nil
end

-- Clic en dehors : fermeture / click outside closes the menus
ns.RegisterEvent("GLOBAL_MOUSE_DOWN", function()
    local first = Menu.levels[1]
    if not first or not first:IsShown() then return end
    for _, f in ipairs(Menu.levels) do if f:IsShown() and f:IsMouseOver() then return end end
    if first.anchor and first.anchor.IsMouseOver and first.anchor:IsMouseOver() then return end
    Menu.CloseAll()
end)

-- -----------------------------------------------------------------------------
-- Sélecteur à menu déroulant / dropdown selector
-- getText() : texte de la valeur ; build() : liste des lignes du menu ;
-- onSelect(value, item). Le libellé « Préfixe : valeur » reste lisible.
-- -----------------------------------------------------------------------------
function W.Dropdown(parent, w, prefix, getText, build, onSelect, tipText)
    local b = flatButton(parent, w, 22)
    b.label:SetPoint("RIGHT", -22, 0)
    local arrow = b:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", -6, 0)
    W.SetArrow(arrow, "down")
    arrow:SetVertexColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
    b.arrow = arrow
    b.prefix = prefix
    function b:Refresh()
        self:SetText(prefix .. U.Color("ffffffff", getText() or "?"))
    end
    b:SetScript("OnClick", function(self)
        if Menu.IsOpenFor(self) then Menu.CloseAll(); return end
        Menu.Open(self, build(), function(v, it) onSelect(v, it); self:Refresh() end)
    end)
    b:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(W.GOLD[1], W.GOLD[2], W.GOLD[3], 1)
        if tipText then tip(self, (prefix:gsub("%s*:%s*$", "")), tipText) end
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(W.BORDER[1], W.BORDER[2], W.BORDER[3], 1)
        GameTooltip:Hide()
    end)
    b:SetScript("OnHide", function(self) if Menu.IsOpenFor(self) then Menu.CloseAll() end end)
    b:Refresh()
    return b
end

-- Sélecteur à choix fixes (ancien bouton cyclique, désormais menu déroulant).
-- options = { {value, label}, ... }. Clic : menu ; molette ou clic droit :
-- valeur suivante / précédente. Fixed-choice selector (dropdown menu).
function W.Cycle(parent, w, prefix, options, get, set, tipText)
    local b
    local function labelOf(v)
        for _, o in ipairs(options) do if o[1] == v then return o[2] end end
        return options[1] and options[1][2] or "?"
    end
    local function step(dir)
        local cur, idx = get(), 1
        for i, o in ipairs(options) do if o[1] == cur then idx = i end end
        idx = (idx - 1 + dir) % #options + 1
        set(options[idx][1])
        b:Refresh()
    end
    b = W.Dropdown(parent, w, prefix, function() return labelOf(get()) end, function()
        local items, cur = {}, get()
        for _, o in ipairs(options) do items[#items + 1] = { text = o[2], value = o[1], checked = (o[1] == cur), color = o[3] } end
        return items
    end, function(v) set(v) end, tipText)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local open = b:GetScript("OnClick")
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then Menu.CloseAll(); step(-1) else open(self, button) end
    end)
    b:EnableMouseWheel(true)
    b:SetScript("OnMouseWheel", function(_, delta) Menu.CloseAll(); step(delta > 0 and -1 or 1) end)
    function b:SetOptions(opts) options = opts; self:Refresh() end
    function b:Select(v) set(v); self:Refresh() end
    b:Refresh()
    return b
end

-- -----------------------------------------------------------------------------
-- Commutateur à segments (sens d'arbitrage, sources…) / segmented control
-- options = { {value, label, tip}, ... } ; widths facultatif.
-- -----------------------------------------------------------------------------
function W.Segmented(parent, options, get, set, w, h, font)
    local holder = CreateFrame("Frame", nil, parent)
    h = h or 22
    holder.buttons = {}
    local x = 0
    for i, o in ipairs(options) do
        local bw = (type(w) == "table" and w[i]) or w or 110
        local b = flatButton(holder, bw, h, font or "GameFontNormalSmall")
        b.label:SetJustifyH("CENTER")
        b:SetPoint("TOPLEFT", x, 0)
        x = x + bw - 1
        b:SetText(o[2])
        b.value = o[1]
        b.bar = b:CreateTexture(nil, "OVERLAY")
        b.bar:SetHeight(2)
        b.bar:SetPoint("BOTTOMLEFT", 1, 1)
        b.bar:SetPoint("BOTTOMRIGHT", -1, 1)
        b.bar:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 1)
        b:SetScript("OnClick", function()
            set(o[1])
            holder:Refresh()
        end)
        if o[3] then
            b:SetScript("OnEnter", function(self) tip(self, o[2], o[3]) end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        holder.buttons[i] = b
    end
    holder:SetSize(x + 1, h)
    function holder:Refresh()
        local cur = get()
        for _, b in ipairs(self.buttons) do
            local on = (b.value == cur)
            b.bar:SetShown(on)
            if on then
                b:SetBackdropColor(W.GOLD[1] * 0.28, W.GOLD[2] * 0.28, W.GOLD[3] * 0.28, 0.95)
                b:SetBackdropBorderColor(W.GOLD[1], W.GOLD[2], W.GOLD[3], 1)
                b.label:SetTextColor(1, 1, 1)
                b:LockHighlight()
            else
                b:SetBackdropColor(W.FIELD_BG[1], W.FIELD_BG[2], W.FIELD_BG[3], W.FIELD_BG[4])
                b:SetBackdropBorderColor(W.BORDER[1], W.BORDER[2], W.BORDER[3], 1)
                b.label:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
                b:UnlockHighlight()
            end
        end
    end
    function holder:Find(value)
        for _, b in ipairs(self.buttons) do if b.value == value then return b end end
    end
    holder:Refresh()
    return holder
end

-- -----------------------------------------------------------------------------
-- Champ de recherche avec texte d'aide et bouton d'effacement.
-- onChange(texte) appelé 0,3 s après la dernière frappe.
-- Search box with placeholder, clear button and debounced callback.
-- -----------------------------------------------------------------------------
function W.SearchBox(parent, w, placeholder, onChange)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(w or 150, 20)
    e:SetAutoFocus(false)
    e:SetMaxLetters(60)
    e:SetTextInsets(16, 16, 0, 0)
    local icon = e:CreateTexture(nil, "OVERLAY")
    icon:SetSize(12, 12)
    icon:SetPoint("LEFT", 2, -1)
    icon:SetTexture(W.ICON_SEARCH)
    icon:SetVertexColor(0.7, 0.7, 0.7)
    local hint = e:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 18, 0)
    hint:SetText(placeholder or "Rechercher…")
    e.hint = hint
    local clear = CreateFrame("Button", nil, e)
    clear:SetSize(14, 14)
    clear:SetPoint("RIGHT", -3, 0)
    clear:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    clear:SetHighlightTexture("Interface\\Buttons\\UI-StopButton", "ADD")
    clear:Hide()
    e.clear = clear
    local seq = 0
    local function update(now)
        local t = e:GetText() or ""
        hint:SetShown(t == "" and not e:HasFocus())
        clear:SetShown(t ~= "")
        seq = seq + 1
        local mine = seq
        if now then onChange(t) return end
        C_Timer.After(0.3, function() if mine == seq then onChange(e:GetText() or "") end end)
    end
    e.Changed = update
    e:SetScript("OnTextChanged", function(_, user) if user ~= false then update(false) end end)
    e:SetScript("OnEditFocusGained", function() hint:Hide() end)
    e:SetScript("OnEditFocusLost", function() hint:SetShown((e:GetText() or "") == "") end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus(); update(true) end)
    clear:SetScript("OnClick", function() e:SetText(""); e:ClearFocus(); update(true) end)
    return e
end

-- -----------------------------------------------------------------------------
-- En-têtes de colonnes triables avec flèche / sortable column headers
-- cols = { {key, label, x, w, right, tip}, ... } ; onSort(key)
-- -----------------------------------------------------------------------------
function W.Header(parent, cols, y, width, onSort)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(width, 20)
    bar:SetPoint("TOPLEFT", 0, y)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.08)
    local line = bar:CreateTexture(nil, "BORDER")
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    line:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.45)
    bar.cells = {}
    for _, c in ipairs(cols) do
        local h = CreateFrame("Button", nil, bar)
        h:SetSize(c.w, 20)
        h:SetPoint("LEFT", c.x, 0)
        local fs = W.Text(h, "GameFontNormalSmall", c.label, c.right and "RIGHT" or "LEFT", c.w)
        fs:SetPoint(c.right and "RIGHT" or "LEFT", c.right and -10 or 0, 0)
        if c.right then fs:SetWidth(c.w - 10) end
        h.text = fs
        local arrow = h:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(10, 10)
        arrow:SetVertexColor(1, 0.82, 0)
        if c.right then arrow:SetPoint("RIGHT", 2, 0) else arrow:SetPoint("LEFT", fs, "LEFT", math.min(c.w - 12, (fs:GetStringWidth() or 30) + 2), 0) end
        arrow:Hide()
        h.arrow = arrow
        h.key = c.key
        if c.key and onSort then
            h:SetScript("OnClick", function() onSort(c.key) end)
            h:SetScript("OnEnter", function(self)
                fs:SetTextColor(1, 1, 1)
                tip(self, c.label, (c.tip and (c.tip .. "\n") or "") .. "Cliquez pour trier.")
            end)
            h:SetScript("OnLeave", function() fs:SetTextColor(1, 0.82, 0); GameTooltip:Hide() end)
        end
        bar.cells[#bar.cells + 1] = h
    end
    function bar:Update(sortKey, desc)
        for _, h in ipairs(self.cells) do
            if h.key and h.key == sortKey then
                W.SetArrow(h.arrow, desc and "down" or "up")
                h.arrow:Show()
            else
                h.arrow:Hide()
            end
        end
    end
    return bar
end

-- Titre de section avec filet doré / section title with a gold rule
function W.Section(parent, text, width)
    local fs = W.Text(parent, "GameFontNormal", text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    line:SetWidth(math.max(10, (width or 300) - (fs:GetStringWidth() or 80) - 8))
    line:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.35)
    fs.line = line
    return fs
end

-- Fenêtre principale déplaçable avec mémorisation de position.
function W.Window(globalName, w, h, titleText, posKey)
    local f = CreateFrame("Frame", globalName, UIParent, "BackdropTemplate")
    f:SetSize(w, h)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetBackdrop(W.BACKDROP)
    f:SetBackdropColor(0.06, 0.07, 0.10, 0.97)
    f:SetBackdropBorderColor(0.72, 0.58, 0.32, 1)
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        ns.settings.windows[posKey] = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    function f:RestorePosition()
        self:ClearAllPoints()
        local p = ns.settings.windows[posKey]
        if p and p.point then
            self:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
        else
            self:SetPoint("CENTER")
        end
    end
    f:RestorePosition()
    local title = W.Text(f, "GameFontNormalLarge", titleText)
    title:SetPoint("TOPLEFT", 16, -12)
    f.title = title
    if posKey == "main" then
        -- Fenêtre principale (bouton de la mini-carte) : grand médaillon posé sur
        -- le coin supérieur gauche, qui déborde du cadre vers le haut et la gauche.
        -- La zone de maintien à l'écran inclut le débordement.
        -- Main window: large medallion overlapping the top-left corner.
        local sz, mx, my = W.MEDALLION_SIZE, W.MEDALLION_X, W.MEDALLION_Y
        local logo = f:CreateTexture(nil, "OVERLAY", nil, 7)
        logo:SetSize(sz, sz)
        logo:SetPoint("TOPLEFT", mx, my)
        logo:SetTexture(W.MEDALLION)
        f.logo = logo
        if f.SetClampRectInsets then f:SetClampRectInsets(mx, 0, my, 0) end
        title:SetPoint("TOPLEFT", mx + sz + 8, -12)
    elseif posKey == "ahpanel" then
        -- Panneau de l'HDV (place comptée) : la gemme seule, lisible en petit.
        -- AH panel: gem only, readable at small size.
        local logo = f:CreateTexture(nil, "ARTWORK")
        logo:SetSize(28, 28)
        logo:SetPoint("TOPLEFT", 10, -4)
        logo:SetTexture(W.ICON)
        f.logo = logo
        title:SetPoint("TOPLEFT", 44, -12)
    end
    local rule = f:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 10, -34)
    rule:SetPoint("TOPRIGHT", -10, -34)
    rule:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.30)
    f.rule = rule
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    if globalName then tinsert(UISpecialFrames, globalName) end
    f:Hide()
    return f
end

-- Liste à lignes recyclées / recycled-row list
-- spec = { rows=n, rowHeight=h, create=function(row,i) end, update=function(row,data,index) end }
function W.List(parent, width, spec)
    local list = CreateFrame("Frame", nil, parent)
    list:SetSize(width, spec.rows * spec.rowHeight)
    list.rows, list.data, list.offset = {}, {}, 0
    for i = 1, spec.rows do
        local row = CreateFrame("Button", nil, list)
        row.isListRow = true
        row:SetSize(width - 14, spec.rowHeight)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * spec.rowHeight)
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0.0)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.9, 0.75, 0.4, 0.12)
        row.selected = row:CreateTexture(nil, "BORDER")
        row.selected:SetAllPoints()
        row.selected:SetColorTexture(0.9, 0.75, 0.4, 0.20)
        row.selected:Hide()
        spec.create(row, i)
        list.rows[i] = row
    end
    local slider = CreateFrame("Slider", nil, list, "BackdropTemplate")
    slider:SetOrientation("VERTICAL")
    slider:SetWidth(10)
    slider:SetPoint("TOPRIGHT", 0, 0)
    slider:SetPoint("BOTTOMRIGHT", 0, 0)
    slider:SetBackdrop(W.PANEL_BACKDROP)
    slider:SetBackdropColor(0, 0, 0, 0.4)
    slider:SetBackdropBorderColor(0.3, 0.26, 0.18, 0.8)
    slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = slider:GetThumbTexture()
    thumb:SetVertexColor(0.72, 0.58, 0.32, 0.9)
    thumb:SetSize(10, 24)
    slider:SetMinMaxValues(0, 0)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(0)
    list.slider = slider
    local empty = W.Text(list, "GameFontDisable", spec.empty or "", "CENTER", width - 60)
    empty:SetPoint("TOP", 0, -math.min(60, spec.rows * spec.rowHeight / 3))
    empty:SetSpacing(3)
    list.emptyText = empty
    function list:SetEmptyText(t) empty:SetText(t or "") end

    function list:Refresh()
        local maxOff = math.max(0, #self.data - spec.rows)
        if self.offset > maxOff then self.offset = maxOff end
        slider:SetMinMaxValues(0, maxOff)
        if slider:GetValue() ~= self.offset then slider:SetValue(self.offset) end
        if maxOff == 0 then slider:Hide() else slider:Show() end
        empty:SetShown(#self.data == 0)
        for i, row in ipairs(self.rows) do
            local idx = i + self.offset
            local d = self.data[idx]
            if d then
                row.data, row.index = d, idx
                spec.update(row, d, idx)
                if row.add and row.add.Refresh then row.add:Refresh() end
                row.selected:SetShown(self.selectedIndex == idx)
                row:Show()
            else
                row.data, row.index = nil, nil
                row:Hide()
            end
        end
    end
    -- keep = true : conserve la position de défilement (mise à jour en place)
    function list:SetData(data, keep)
        self.data = data or {}
        if not keep then
            self.offset = 0
            self.selectedIndex = nil
        end
        self:Refresh()
    end
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        if value ~= list.offset then list.offset = value; list:Refresh() end
    end)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
        local maxOff = math.max(0, #self.data - spec.rows)
        local step = IsShiftKeyDown() and spec.rows or 3
        self.offset = math.min(math.max(self.offset - delta * step, 0), maxOff)
        self:Refresh()
    end)
    return list
end

-- Zone de texte multiligne copiable / copyable multi-line text box
function W.CopyBox(parent, w, h)
    local holder = W.Panel(parent, w, h)
    local scroll = CreateFrame("ScrollFrame", nil, holder)
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -6, 6)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetWidth(w - 16)
    edit:SetHeight(h - 12)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(edit)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local cur, maxV = self:GetVerticalScroll(), self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.min(math.max(cur - delta * 40, 0), maxV))
    end)
    holder.edit, holder.scroll = edit, scroll
    function holder:SetText(t)
        edit:SetText(t or "")
        edit:SetCursorPosition(0)
        scroll:SetVerticalScroll(0)
    end
    function holder:SelectAll()
        edit:SetFocus()
        edit:HighlightText()
    end
    return holder
end

-- Ligne de texte à copier (une ligne) / single-line copy field
function W.CopyLine(parent, w)
    local e = W.Edit(parent, w)
    e:SetMaxLetters(400)
    e:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    e:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    return e
end
