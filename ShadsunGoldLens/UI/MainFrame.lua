-- =============================================================================
-- Shadsun Gold Lens — UI/MainFrame.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Fenêtre principale à onglets (Objet, Opportunités, Marchés,
--      Paramètres, Base & diagnostic). Création paresseuse au premier affichage.
-- EN : Tabbed main window, lazily created on first open.
-- =============================================================================
local _, ns = ...
local U, W = ns.U, ns.W
local UI = { tabs = {}, pages = {}, order = {} }
ns.UI = UI

UI.WIDTH, UI.HEIGHT = 840, 610
UI.MIN_SCALE, UI.MAX_SCALE = 0.7, 1.5

-- Enregistrement des onglets par les autres fichiers UI / tab registration
function UI.RegisterTab(key, label, build)
    UI.order[#UI.order + 1] = { key = key, label = label, build = build }
end

local function create()
    if UI.frame then return UI.frame end
    local f = W.Window("ShadsunGoldLensMainFrame", UI.WIDTH, UI.HEIGHT, ns.title, "main")
    UI.frame = f
    local ver = W.Text(f, "GameFontDisableSmall", "v" .. ns.version)
    ver:SetPoint("LEFT", f.title, "RIGHT", 8, -1)

    -- Taille de la fenêtre : « - » / « + » (pas de 10 %), « 100 % » ; mémorisée.
    -- Window scale buttons, saved per account.
    local function applyScale()
        local s = tonumber(ns.settings.display.mainScale) or 1
        s = math.min(UI.MAX_SCALE, math.max(UI.MIN_SCALE, s))
        ns.settings.display.mainScale = s
        f:SetScale(s)
    end
    UI.ApplyScale = applyScale
    local reset = W.Button(f, "100 %", 52, 20, function() ns.settings.display.mainScale = 1; applyScale() end)
    reset:SetPoint("TOPRIGHT", -36, -10)
    local plus = W.Button(f, "+", 24, 20, function()
        ns.settings.display.mainScale = math.floor(((ns.settings.display.mainScale or 1) + 0.1) * 10 + 0.5) / 10
        applyScale()
    end)
    plus:SetPoint("RIGHT", reset, "LEFT", -4, 0)
    local minus = W.Button(f, "-", 24, 20, function()
        ns.settings.display.mainScale = math.floor(((ns.settings.display.mainScale or 1) - 0.1) * 10 + 0.5) / 10
        applyScale()
    end)
    minus:SetPoint("RIGHT", plus, "LEFT", -4, 0)
    local sizeLbl = W.Text(f, "GameFontDisableSmall", "Taille")
    sizeLbl:SetPoint("RIGHT", minus, "LEFT", -6, 0)
    applyScale()

    local credit = W.Text(f, "GameFontDisableSmall", ns.signature)
    credit:SetPoint("BOTTOMRIGHT", -14, 10)
    local status = W.Text(f, "GameFontDisableSmall", "")
    status:SetPoint("BOTTOMLEFT", 16, 10)
    status:SetWidth(UI.WIDTH - 150)
    status:SetWordWrap(false)
    UI.statusText = status

    -- Onglets plats avec repère doré / flat tabs with a gold marker
    local opts = {}
    for _, t in ipairs(UI.order) do opts[#opts + 1] = { t.key, t.label } end
    local tabW = math.floor((UI.WIDTH - 32) / math.max(#opts, 1)) + 1
    local tabs = W.Segmented(f, opts, function() return UI.current end, function(v) UI.Show(v) end, tabW, 26, "GameFontNormal")
    tabs:SetPoint("TOPLEFT", 16, -40)
    UI.tabBar = tabs
    for _, b in ipairs(tabs.buttons) do UI.tabs[b.value] = b end
    local tabRule = f:CreateTexture(nil, "ARTWORK")
    tabRule:SetHeight(1)
    tabRule:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, 0)
    tabRule:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    tabRule:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.5)
    for _, t in ipairs(UI.order) do
        local page = CreateFrame("Frame", nil, f)
        page:SetPoint("TOPLEFT", 14, -76)
        page:SetPoint("BOTTOMRIGHT", -14, 30)
        page:Hide()
        UI.pages[t.key] = page
        local ok, err = xpcall(function() t.build(page) end, ns.Diag.Handler)
        if not ok then ns.Diag.Error("ui:" .. t.key, err) end
    end
    f:SetScript("OnShow", function() UI.UpdateStatus() end)
    ns.On("UI_RESET", function() ns.settings.display.mainScale = 1; applyScale(); f:RestorePosition() end)
    ns.On("MARKET_CHANGED", function() if f:IsShown() then UI.UpdateStatus() end end)
    ns.On("SETTINGS_CHANGED", function() if f:IsShown() then UI.UpdateStatus() end end)
    return f
end

function UI.UpdateStatus()
    if not UI.statusText then return end
    local state = ns.Prices.State()
    local ah = (state == "OK") and "Auctionator détecté" or "Auctionator indisponible — prix HDV désactivés"
    local tt = ns.Navigation.HasTomTom() and "TomTom détecté" or "TomTom absent (repère natif)"
    local MK = ns.Market
    local key = MK.SellKey()
    local snap = MK.Snap(key)
    local mk = "revente : " .. MK.ColorLabel(key) .. (snap and (" (" .. MK.SourceText(snap) .. ")") or " (aucun prix)")
    UI.statusText:SetText(ah .. " · " .. tt .. " · " .. mk .. " · base " .. tostring(ns.Data.meta.version))
end

function UI.Show(key, arg)
    local f = create()
    key = key or UI.current or "detail"
    UI.current = key
    for k, page in pairs(UI.pages) do page:SetShown(k == key) end
    if UI.tabBar then UI.tabBar:Refresh() end
    f:Show()
    local page = UI.pages[key]
    if page and page.OnActivate then
        local ok, err = xpcall(function() page.OnActivate(page, arg) end, ns.Diag.Handler)
        if not ok then ns.Diag.Error("ui:activate:" .. key, err) end
    end
end

function UI.Toggle(key)
    if UI.frame and UI.frame:IsShown() and (not key or key == UI.current) then
        UI.frame:Hide()
    else
        UI.Show(key)
    end
end

function UI.ShowItem(itemID)
    UI.Show("detail", itemID)
end

-- Petite fenêtre « copier une ligne » (commande /tway) : le texte est déjà
-- sélectionné, il suffit de faire Ctrl+C (les add-ons ne peuvent pas écrire
-- dans le presse-papiers). Single-line copy popup.
function UI.ShowCopyLine(text)
    if not UI.copyLine then
        local f = W.Window("ShadsunGoldLensCopyLine", 460, 92, "Copier — Ctrl+C, puis coller dans le chat", "copyline")
        f:SetFrameStrata("DIALOG")
        local e = W.CopyLine(f, 420)
        e:SetPoint("TOPLEFT", 20, -46)
        e:SetScript("OnEscapePressed", function() f:Hide() end)
        e:SetScript("OnEnterPressed", function() f:Hide() end)
        f.edit = e
        UI.copyLine = f
    end
    local f = UI.copyLine
    f:Show()
    f.edit:SetText(text or "")
    f.edit:SetFocus()
    f.edit:HighlightText()
end

-- Fenêtre de texte copiable (diagnostic) / copy window
function UI.ShowCopy(titleText, text)
    if not UI.copyFrame then
        local f = W.Window("ShadsunGoldLensCopyFrame", 640, 420, titleText, "copy")
        f:SetFrameStrata("DIALOG")
        local box = W.CopyBox(f, 610, 330)
        box:SetPoint("TOPLEFT", 15, -42)
        local hint = W.Text(f, "GameFontDisableSmall", "Ctrl+A puis Ctrl+C pour copier le texte.")
        hint:SetPoint("BOTTOMLEFT", 16, 14)
        local sel = W.Button(f, "Tout sélectionner", 140, 22, function() box:SelectAll() end)
        sel:SetPoint("BOTTOMRIGHT", -14, 10)
        f.box = box
        UI.copyFrame = f
    end
    UI.copyFrame.title:SetText(titleText)
    UI.copyFrame:Show()
    UI.copyFrame.box:SetText(text)
    UI.copyFrame.box:SelectAll()
end
