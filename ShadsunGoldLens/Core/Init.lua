-- =============================================================================
-- Shadsun Gold Lens — Core/Init.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Espace de noms, bus d'événements interne, cycle de chargement.
-- EN : Namespace, internal event bus, load lifecycle.
-- =============================================================================
local addonName, ns = ...

ns.name = addonName
ns.title = "Shadsun Gold Lens"
ns.version = "0.16.0"
ns.author = "Tarak Ben Abda"   -- auteur du code (non affiché en jeu)
ns.signature = "Créé par Shadsun" -- signature visible dans l'interface / UI credit
ns.callerID = "ShadsunGoldLens" -- identifiant passé à Auctionator / caller id

-- -----------------------------------------------------------------------------
-- Bus d'événements interne / internal message bus
-- Messages : DATA_CHANGED, PRICES_CHANGED, SETTINGS_CHANGED, ZONE_CHANGED
-- -----------------------------------------------------------------------------
local listeners = {}

function ns.On(message, fn)
    listeners[message] = listeners[message] or {}
    table.insert(listeners[message], fn)
end

function ns.Fire(message, ...)
    local list = listeners[message]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok and ns.Diag then ns.Diag.Error("bus:" .. message, err) end
    end
end

-- -----------------------------------------------------------------------------
-- Événements du jeu / game events (une seule frame / single frame)
-- -----------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}
ns.eventFrame = eventFrame

function ns.RegisterEvent(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        eventFrame:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], event, ...)
        if not ok and ns.Diag then ns.Diag.Error("event:" .. event, err) end
    end
end)

-- Phases de démarrage : modules enregistrés dans l'ordre du .toc.
-- Startup phases: modules registered in .toc order.
ns.initQueue, ns.loginQueue = {}, {}
function ns.OnInit(fn) table.insert(ns.initQueue, fn) end
function ns.OnLogin(fn) table.insert(ns.loginQueue, fn) end

local function runQueue(queue, label)
    for i = 1, #queue do
        local ok, err = pcall(queue[i])
        if not ok then
            if ns.Diag then ns.Diag.Error(label .. "#" .. i, err) else print(addonName .. ": " .. tostring(err)) end
        end
    end
end

ns.RegisterEvent("ADDON_LOADED", function(_, loaded)
    if loaded ~= addonName then return end
    runQueue(ns.initQueue, "init")
    ns.initialized = true
end)

ns.RegisterEvent("PLAYER_LOGIN", function()
    runQueue(ns.loginQueue, "login")
    ns.loggedIn = true
end)
