-- =============================================================================
-- Shadsun Gold Lens — tests/wowmock.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Simulation STRICTE d'un sous-ensemble du client WoW moderne pour les
--      tests hors jeu (Lua 5.1). Toute méthode de widget absente de la liste
--      blanche (API réelle) lève une erreur, afin de détecter les appels à des
--      fonctions inexistantes. Ce n'est PAS le jeu : les résultats ne
--      remplacent pas les tests en jeu.
-- EN : Strict mock of a subset of the modern WoW client for offline tests.
-- =============================================================================
local M = {}
M.printed = {}
M.timers = {}
M.time = 1000
M.shift = false
M.combat = false
M.locale = "frFR"

local function addAll(t, list) for _, k in ipairs(list) do t[k] = true end return t end

local REGION = addAll({}, { "Show", "Hide", "IsShown", "IsVisible", "SetShown", "SetSize", "SetWidth", "SetHeight",
    "GetWidth", "GetHeight", "GetRight", "GetTop", "GetLeft", "GetBottom", "SetPoint", "ClearAllPoints", "SetAllPoints", "GetPoint", "GetCenter", "SetParent",
    "GetParent", "GetName", "SetAlpha", "GetAlpha", "IsObjectType", "GetObjectType", "GetEffectiveScale", "SetScale" })
local FRAME = addAll(addAll({}, (function() local l = {} for k in pairs(REGION) do l[#l + 1] = k end return l end)()),
    { "SetScript", "GetScript", "HookScript", "HasScript", "RegisterEvent", "UnregisterEvent", "UnregisterAllEvents",
        "SetFrameStrata", "GetFrameStrata", "SetFrameLevel", "GetFrameLevel", "SetToplevel", "SetClampedToScreen",
        "SetMovable", "EnableMouse", "EnableMouseWheel", "RegisterForDrag", "StartMoving", "StopMovingOrSizing",
        "CreateFontString", "CreateTexture", "CreateAnimationGroup", "SetFixedFrameStrata", "SetFixedFrameLevel",
        "IsForbidden", "SetID", "GetID", "Raise", "Lower", "IsMouseOver", "SetHitRectInsets", "SetClampRectInsets" })
local BACKDROP = addAll({}, { "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor" })
local BUTTON = addAll({}, { "SetText", "GetText", "SetEnabled", "Enable", "Disable", "IsEnabled", "RegisterForClicks",
    "LockHighlight", "UnlockHighlight", "SetNormalTexture", "SetHighlightTexture", "SetPushedTexture", "GetFontString",
    "Click", "SetNormalFontObject", "SetFontString" })
local CHECK = addAll({}, { "SetChecked", "GetChecked" })
local EDIT = addAll({}, { "SetText", "GetText", "SetAutoFocus", "SetMaxLetters", "SetFocus", "ClearFocus", "HasFocus",
    "HighlightText", "SetCursorPosition", "SetMultiLine", "SetFontObject", "SetNumeric", "Insert", "SetTextInsets", "SetJustifyH" })
local SLIDER = addAll({}, { "SetOrientation", "SetMinMaxValues", "GetMinMaxValues", "SetValue", "GetValue",
    "SetValueStep", "SetObeyStepOnDrag", "SetThumbTexture", "GetThumbTexture" })
local SCROLL = addAll({}, { "SetScrollChild", "GetVerticalScroll", "SetVerticalScroll", "GetVerticalScrollRange", "UpdateScrollChildRect" })
local FONTSTRING = addAll({}, { "SetText", "GetText", "SetJustifyH", "SetJustifyV", "SetWordWrap", "SetSpacing",
    "SetTextColor", "SetFontObject", "GetStringWidth", "SetDrawLayer" })
local TEXTURE = addAll({}, { "SetTexture", "SetColorTexture", "SetTexCoord", "SetVertexColor", "GetVertexColor", "SetBlendMode", "SetDrawLayer", "SetRotation" })
local TOOLTIP = addAll({}, { "SetOwner", "AddLine", "AddDoubleLine", "ClearLines", "SetText", "NumLines", "SetItemByID",
    "SetHyperlink", "GetItem", "IsOwned", "GetPrimaryTooltipData", "GetPrimaryTooltipInfo", "RefreshData", "SetMinimumWidth" })

local eventFrames = {}
M.allFrames = {}

local Widget = {}
Widget.__index = function(self, key)
    local v = rawget(Widget, key)
    if v then
        local allowed = self.__allowed
        if not allowed[key] and key:sub(1, 2) ~= "__" then
            error("mock: method " .. key .. " not available on " .. self.__type .. (self.__templates ~= "" and (" (" .. self.__templates .. ")") or ""), 2)
        end
        return v
    end
    return nil
end
Widget.__newindex = rawset

local function newWidget(kind, allowed, name, parent, templates)
    local w = setmetatable({ __type = kind, __allowed = allowed, __name = name, __parent = parent,
        __shown = true, __scripts = {}, __hooks = {}, __templates = templates or "", __w = 0, __h = 0, __level = 1 }, Widget)
    M.allFrames[#M.allFrames + 1] = w
    return w
end

-- Région / region
function Widget:Show() local was = self.__shown; self.__shown = true; if not was then self:__fire("OnShow") end end
function Widget:Hide() local was = self.__shown; self.__shown = false; if was then self:__fire("OnHide") end end
function Widget:IsShown() return self.__shown end
function Widget:IsVisible()
    local p = self
    while p do if not p.__shown then return false end p = p.__parent end
    return true
end
function Widget:SetShown(v) if v then self:Show() else self:Hide() end end
function Widget:SetSize(w, h) self.__w, self.__h = w, h end
function Widget:SetWidth(w) self.__w = w end
function Widget:SetHeight(h) self.__h = h end
function Widget:GetWidth() return self.__w end
function Widget:GetHeight() return self.__h end
function Widget:SetPoint(...) self.__point = { ... } end
function Widget:ClearAllPoints() self.__point = nil end
function Widget:SetAllPoints() end
function Widget:GetPoint() local p = self.__point or { "CENTER" } return p[1], nil, p[3] or p[1], 10, 20 end
function Widget:GetCenter() return 500, 400 end
function Widget:GetRight() return self.__right end
function Widget:GetTop() return self.__top end
function Widget:GetLeft() return self.__left end
function Widget:GetBottom() return self.__bottom end
function Widget:SetParent(p) self.__parent = p end
function Widget:GetParent() return self.__parent end
function Widget:GetName() return self.__name end
function Widget:SetAlpha(a) self.__alpha = a end
function Widget:GetAlpha() return self.__alpha or 1 end
function Widget:IsObjectType(t) return t == self.__type end
function Widget:GetObjectType() return self.__type end
function Widget:GetEffectiveScale() return 1 end
function Widget:SetScale(s) self.__scale = s end
-- Frame
function Widget:__fire(script, ...)
    local s = self.__scripts[script]
    if s then s(self, ...) end
    for _, h in ipairs(self.__hooks[script] or {}) do h(self, ...) end
end
function Widget:SetScript(n, f) self.__scripts[n] = f end
function Widget:GetScript(n) return self.__scripts[n] end
function Widget:HookScript(n, f) self.__hooks[n] = self.__hooks[n] or {}; table.insert(self.__hooks[n], f) end
function Widget:HasScript() return true end
function Widget:RegisterEvent(e) eventFrames[e] = eventFrames[e] or {}; eventFrames[e][self] = true end
function Widget:UnregisterEvent(e) if eventFrames[e] then eventFrames[e][self] = nil end end
function Widget:UnregisterAllEvents() for _, t in pairs(eventFrames) do t[self] = nil end end
function Widget:SetFrameStrata() end
function Widget:GetFrameStrata() return "MEDIUM" end
function Widget:SetFrameLevel(l) self.__level = l end
function Widget:GetFrameLevel() return self.__level end
function Widget:SetToplevel() end
function Widget:SetClampedToScreen() end
function Widget:SetClampRectInsets(l, r, t, b) self.__clampInsets = { l, r, t, b } end
function Widget:SetMovable() end
function Widget:EnableMouse() end
function Widget:EnableMouseWheel() end
function Widget:RegisterForDrag() end
function Widget:StartMoving() end
function Widget:StopMovingOrSizing() end
function Widget:CreateFontString(name) return newWidget("FontString", addAll(addAll({}, (function() local l = {} for k in pairs(REGION) do l[#l + 1] = k end return l end)()), (function() local l = {} for k in pairs(FONTSTRING) do l[#l + 1] = k end return l end)()), name, self) end
function Widget:CreateTexture(name) return newWidget("Texture", addAll(addAll({}, (function() local l = {} for k in pairs(REGION) do l[#l + 1] = k end return l end)()), (function() local l = {} for k in pairs(TEXTURE) do l[#l + 1] = k end return l end)()), name, self) end
function Widget:CreateAnimationGroup()
    local g = setmetatable({}, { __index = {
        CreateAnimation = function() return setmetatable({}, { __index = { SetOrder = function() end, SetDuration = function() end,
            SetFromAlpha = function() end, SetToAlpha = function() end, SetStartDelay = function() end } }) end,
        Play = function() end, Stop = function() end, SetToFinalAlpha = function() end, IsPlaying = function() return false end } })
    return g
end
function Widget:SetFixedFrameStrata() end
function Widget:SetFixedFrameLevel() end
function Widget:IsForbidden() return false end
function Widget:SetID(i) self.__id = i end
function Widget:GetID() return self.__id end
function Widget:Raise() end
function Widget:Lower() end
function Widget:IsMouseOver() return false end
function Widget:SetHitRectInsets() end
-- Backdrop
function Widget:SetBackdrop(b) self.__backdrop = b end
function Widget:SetBackdropColor() end
function Widget:SetBackdropBorderColor(r, g, b) self.__border = { r, g, b } end
-- Texte / text (Button, EditBox, FontString, Tooltip)
function Widget:SetText(t)
    if self.__type == "GameTooltip" then self:ClearLines(); self:AddLine(t) return end
    self.__text = t
    local fs = rawget(self, "__fontstring")
    if fs then fs.__text = t end
end
function Widget:GetText() return self.__text end
function Widget:SetJustifyH() end
function Widget:SetJustifyV() end
function Widget:SetWordWrap() end
function Widget:SetSpacing() end
function Widget:SetTextColor() end
function Widget:SetFontObject() end
function Widget:GetStringWidth() return 50 end
function Widget:SetDrawLayer() end
-- Bouton / button
function Widget:SetEnabled(v) self.__enabled = v and true or false end
function Widget:Enable() self.__enabled = true end
function Widget:Disable() self.__enabled = false end
function Widget:IsEnabled() return self.__enabled ~= false end
function Widget:RegisterForClicks() end
function Widget:LockHighlight() self.__locked = true end
function Widget:UnlockHighlight() self.__locked = false end
function Widget:SetNormalTexture() end
function Widget:SetHighlightTexture() end
function Widget:SetPushedTexture() end
function Widget:GetFontString() return rawget(self, "__fontstring") or self end
function Widget:SetFontString(fs) self.__fontstring = fs end
function Widget:Click(button) self:__fire("OnClick", button or "LeftButton") end
function Widget:SetNormalFontObject() end
function Widget:SetChecked(v) self.__checked = v and true or false end
function Widget:GetChecked() return self.__checked end
-- EditBox
function Widget:SetAutoFocus() end
function Widget:SetMaxLetters() end
function Widget:SetFocus() self.__focus = true; self:__fire("OnEditFocusGained") end
function Widget:ClearFocus() if self.__focus then self.__focus = false; self:__fire("OnEditFocusLost") end end
function Widget:HasFocus() return self.__focus or false end
function Widget:HighlightText() end
function Widget:SetCursorPosition() end
function Widget:SetMultiLine() end
function Widget:SetNumeric() end
function Widget:Insert() end
function Widget:SetTextInsets() end
-- Slider
function Widget:SetOrientation() end
function Widget:SetMinMaxValues(a, b) self.__min, self.__max = a, b end
function Widget:GetMinMaxValues() return self.__min or 0, self.__max or 0 end
function Widget:SetValue(v) local old = self.__value; self.__value = v; if old ~= v then self:__fire("OnValueChanged", v) end end
function Widget:GetValue() return self.__value or 0 end
function Widget:SetValueStep() end
function Widget:SetObeyStepOnDrag() end
function Widget:SetThumbTexture() self.__thumb = self:CreateTexture() end
function Widget:GetThumbTexture() return self.__thumb end
-- ScrollFrame
function Widget:SetScrollChild(c) self.__child = c end
function Widget:GetVerticalScroll() return self.__vs or 0 end
function Widget:SetVerticalScroll(v) self.__vs = v end
function Widget:GetVerticalScrollRange() return 100 end
function Widget:UpdateScrollChildRect() end
-- Texture
function Widget:SetTexture(t) self.__tex = t end
function Widget:SetColorTexture() end
function Widget:SetTexCoord() end
function Widget:SetVertexColor() end
function Widget:GetVertexColor() return 1, 1, 1 end
function Widget:SetBlendMode() end
function Widget:SetRotation(r) self.__rotation = r end

-- -----------------------------------------------------------------------------
-- GameTooltip simulée / simulated tooltip
-- -----------------------------------------------------------------------------
function Widget:SetOwner(owner) self.__owner = owner; self:ClearLines() end
function Widget:ClearLines()
    self.lines = {}
    self:__fire("OnTooltipCleared")
end
-- Expose les lignes comme le client : _G[nom.."TextLeft"..i]:GetText()
local function exposeLine(tt, i)
    local name = rawget(tt, "__name")
    if name then
        _G[name .. "TextLeft" .. i] = { GetText = function() local l = tt.lines[i]; return l and l.left end }
    end
end
function Widget:AddLine(t, r, g, b, wrap) self.lines[#self.lines + 1] = { left = tostring(t) }; exposeLine(self, #self.lines) end
function Widget:AddDoubleLine(l, r) self.lines[#self.lines + 1] = { left = tostring(l), right = tostring(r) }; exposeLine(self, #self.lines) end
function Widget:NumLines() return #self.lines end
function Widget:Show()
    local was = self.__shown
    self.__shown = true
    self.showCalls = (self.showCalls or 0) + 1
    self.height = #(self.lines or {}) -- la hauteur suit le nombre de lignes au moment de Show()
    if not was then self:__fire("OnShow") end
end
function Widget:IsOwned(o) return self.__owner == o end
function Widget:GetPrimaryTooltipData() return self.__primary end
function Widget:GetPrimaryTooltipInfo() return self.__primaryInfo end
function Widget:SetMinimumWidth() end
function Widget:GetItem()
    local d = self.__primary
    if d and d.id then return "item", "|Hitem:" .. d.id .. "|h[x]|h" end
    return nil
end
function Widget:SetItemByID(id) M.ProcessItem(self, id) end
function Widget:SetHyperlink(link) local id = tonumber(link:match("item:(%d+)")); if id then M.ProcessItem(self, id) end end
function Widget:RefreshData() if self.__lastProcess then M.ProcessItem(self, unpack(self.__lastProcess)) end end

-- Traitement d'une infobulle d'objet à la manière du client moderne :
-- ClearLines → lignes Blizzard → (infobulle imbriquée) → post-calls → Show
M.postCalls = {}
function M.ProcessItem(tt, id, opts)
    opts = opts or {}
    tt.__lastProcess = { id, opts }
    tt:ClearLines()
    local data = { type = 0, id = id, hyperlink = "item:" .. id }
    tt.__primary = data
    tt.__primaryInfo = opts.info
    local item = M.items[id]
    tt:AddLine(item and item.name or ("Item " .. id))
    tt:AddLine("Ligne Blizzard 2")
    if opts.nested then
        -- Objet fabriqué affiché dans la recette : post-call avec ses propres données.
        local nestedData = { type = 0, id = opts.nested, hyperlink = "item:" .. opts.nested }
        tt:AddLine("  Objet créé")
        for _, cb in ipairs(M.postCalls) do cb(tt, nestedData) end
    end
    for _, cb in ipairs(M.postCalls) do cb(tt, data) end
    if opts.double then for _, cb in ipairs(M.postCalls) do cb(tt, data) end end
    tt:Show()
end

-- -----------------------------------------------------------------------------
-- CreateFrame
-- -----------------------------------------------------------------------------
local function merge(...)
    local out = {}
    for _, t in ipairs({ ... }) do for k in pairs(t) do out[k] = true end end
    return out
end

function M.CreateFrame(kind, name, parent, template)
    template = template or ""
    local allowed
    if kind == "Frame" then allowed = merge(FRAME)
    elseif kind == "Button" then allowed = merge(FRAME, BUTTON)
    elseif kind == "CheckButton" then allowed = merge(FRAME, BUTTON, CHECK)
    elseif kind == "EditBox" then allowed = merge(FRAME, EDIT)
    elseif kind == "Slider" then allowed = merge(FRAME, SLIDER)
    elseif kind == "ScrollFrame" then allowed = merge(FRAME, SCROLL)
    elseif kind == "GameTooltip" then allowed = merge(FRAME, TOOLTIP)
    else error("mock: unsupported frame type " .. kind) end
    if template:find("BackdropTemplate") then allowed = merge(allowed, BACKDROP) end
    local known = { [""] = 1, BackdropTemplate = 1, UIPanelButtonTemplate = 1, UICheckButtonTemplate = 1,
        InputBoxTemplate = 1, UIPanelCloseButton = 1, GameTooltipTemplate = 1 }
    for t in template:gmatch("[^,%s]+") do
        if not known[t] then error("mock: unknown template " .. t) end
    end
    local w = newWidget(kind, allowed, name, parent, template)
    if kind == "GameTooltip" then w.lines = {}; w.__shown = false end
    if template:find("UIPanelButtonTemplate") or template:find("UIPanelCloseButton") then
        -- texte du bouton
    end
    if name then _G[name] = w end
    return w
end

function M.ResetEvents()
    for k in pairs(eventFrames) do eventFrames[k] = nil end
end

function M.FireEvent(event, ...)
    for f in pairs(eventFrames[event] or {}) do
        local s = f.__scripts.OnEvent
        if s then s(f, event, ...) end
    end
end

function M.RunOneTimer()
    local t = table.remove(M.timers, 1)
    if t then t() return true end
    return false
end

function M.RunTimers()
    local guard = 0
    while #M.timers > 0 and guard < 1000 do
        guard = guard + 1
        local t = table.remove(M.timers, 1)
        t()
    end
end

-- -----------------------------------------------------------------------------
-- Données d'objets simulées / simulated item cache
-- name, quality, stack, icon, sell, class, subclass, bind
-- -----------------------------------------------------------------------------
M.items = {
    [6325] = { name = "Recette : Goujon brillant", sell = 10, class = 9, sub = 5, bind = 0 },
    [6290] = { name = "Goujon brillant", sell = 1, class = 0, sub = 5, bind = 0 },
    [159] = { name = "Eau de source rafraîchissante", sell = 1, class = 0, sub = 5, bind = 0 },
    [7005] = { name = "Couteau à dépecer", sell = 16, class = 7, sub = 0, bind = 0 },
    [25] = { name = "Épée courte usée", sell = 7, class = 2, sub = 7, bind = 0 },
    [99999] = { name = "Objet hors base", sell = 0, class = 15, sub = 0, bind = 0 },
    [5441] = { name = "Petite giberne", sell = 25, class = 11, sub = 3, bind = 0 },
    [2589] = { name = "Étoffe de lin", sell = 13, class = 7, sub = 5, bind = 0 },
    [2449] = { name = "Terrestrine", sell = 20, class = 7, sub = 9, bind = 0 },
    [4306] = { name = "Composant générique", sell = 5, class = 7, sub = 0, bind = 0 },
    [18170] = { name = "Mantelet de givre de l'Aube", sell = 0, class = 4, sub = 0, bind = 1 },
}
M.uncached = {}

return M
