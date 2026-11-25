-- =============================================================================
-- Shadsun Gold Lens — Core/Navigation.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Points de navigation. Priorité à l'API publique de TomTom
--      TomTom:AddWaypoint(uiMapID, x01, y01, opts) ; sinon repère natif du jeu
--      (C_Map.SetUserWaypoint). Commande « /tway #uiMapID x y nom » proposée
--      uniquement si l'identifiant de carte existe sur ce client et que les
--      coordonnées sont valides — aucune commande approximative.
-- EN : Waypoints via TomTom API, native user waypoint fallback, safe command.
-- =============================================================================
local _, ns = ...
local U, L = ns.U, ns.L
local N = {}
ns.Navigation = N

function N.HasTomTom()
    return type(TomTom) == "table" and type(TomTom.AddWaypoint) == "function"
end

-- Validation d'une position / position validation
function N.Validate(offer)
    if not offer or offer.nopos or not offer.map or not offer.x or not offer.y then
        return false, L.NAV_NO_COORDS
    end
    if offer.x <= 0 or offer.x >= 100 or offer.y <= 0 or offer.y >= 100 then
        return false, L.NAV_NO_COORDS
    end
    if not U.MapName(offer.map) then return false, L.NAV_BAD_MAP end
    return true
end

local function title(offer, itemName)
    local t = offer.name or "?"
    if itemName then t = t .. " — " .. itemName end
    return t
end

function N.Command(offer)
    local ok = N.Validate(offer)
    if not ok then return nil end
    local name = (offer.name or ""):gsub("[\r\n]", " ")
    return string.format("/tway #%d %.1f %.1f %s", offer.map, offer.x, offer.y, name)
end

-- Ajoute le point (TomTom ou natif). Retourne succès, message.
function N.AddWaypoint(offer, itemName)
    local ok, err = N.Validate(offer)
    if not ok then return false, err end
    local label = title(offer, itemName)
    if N.HasTomTom() then
        local done, uid = pcall(TomTom.AddWaypoint, TomTom, offer.map, offer.x / 100, offer.y / 100, {
            title = label, from = ns.title, persistent = false, minimap = true, world = true, crazy = true,
        })
        if done and uid then
            local msg = string.format(L.NAV_ADDED, label)
            if offer.moves then msg = msg .. " — " .. L.NAV_MOVES_WARN end
            return true, msg
        end
        if ns.Diag then ns.Diag.Log("TomTom.AddWaypoint a échoué : " .. tostring(uid)) end
    end
    return N.SetNative(offer, label)
end

-- Repère natif du client (sans TomTom) / native user waypoint
function N.SetNative(offer, label)
    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
        return false, L.NAV_CMD_NONE
    end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(offer.map) then
        return false, L.NAV_BAD_MAP
    end
    local ok = pcall(function()
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(offer.map, offer.x / 100, offer.y / 100))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
    end)
    if ok then return true, string.format(L.NAV_NATIVE, label or offer.name or "?") end
    return false, L.NAV_BAD_MAP
end

-- Ouvre la carte du monde sur la zone du marchand et place le repère natif.
function N.ShowOnMap(offer)
    local ok, err = N.Validate(offer)
    if not ok then return false, err end
    if InCombatLockdown() then return false, L.NAV_COMBAT end
    N.SetNative(offer, offer.name)
    if OpenWorldMap then
        pcall(OpenWorldMap, offer.map)
    elseif WorldMapFrame and WorldMapFrame.SetMapID then
        if not WorldMapFrame:IsShown() and ToggleWorldMap then ToggleWorldMap() end
        pcall(WorldMapFrame.SetMapID, WorldMapFrame, offer.map)
    end
    return true
end
