-- =============================================================================
-- Shadsun Gold Lens — UI/Minimap.lua
-- Auteur : Tarak Ben Abda – novembre 2026
-- FR : Icône de minicarte standard (LibDataBroker + LibDBIcon, comme Questie)
--      et entrée du compartiment d'add-ons du client moderne.
--      Clic gauche : fenêtre principale · Clic droit : paramètres.
-- EN : Standard LDB/LibDBIcon minimap button + addon compartment.
-- =============================================================================
local _, ns = ...
local U = ns.U
local MM = {}
ns.Minimap = MM

MM.ICON = "Interface\\AddOns\\ShadsunGoldLens\\Media\\icon"

local function onClick(button)
    if button == "RightButton" then ns.UI.Toggle("options") else ns.UI.Toggle() end
end

local function tooltip(tt)
    tt:AddLine(U.Color(U.colors.title, ns.title) .. " " .. U.Color(U.colors.dim, ns.version))
    tt:AddLine("Clic gauche : fenêtre principale", 1, 1, 1)
    tt:AddLine("Clic droit : paramètres", 1, 1, 1)
    tt:AddLine("Glisser : déplacer autour de la minicarte", 0.7, 0.7, 0.7)
    local state = ns.Prices.State()
    tt:AddLine(state == "OK" and "Auctionator : détecté" or "Auctionator : indisponible", 0.7, 0.7, 0.7)
    if ns.Market and ns.DB.G then
        for _, key in ipairs({ ns.Market.PlayerKey(), "N" }) do
            local s = ns.Market.Snap(key)
            tt:AddLine(ns.Market.Label(key) .. " : " .. (s and ns.Market.SourceText(s) or "aucun prix"), 0.7, 0.7, 0.7)
        end
    end
    tt:AddLine(ns.signature, 0.55, 0.55, 0.55)
end

function MM.Apply()
    local icon = LibStub and LibStub("LibDBIcon-1.0", true)
    if not icon or not icon:IsRegistered("ShadsunGoldLens") then return end
    icon:Refresh("ShadsunGoldLens", ns.settings.minimap)
    if ns.settings.minimap.hide then icon:Hide("ShadsunGoldLens") else icon:Show("ShadsunGoldLens") end
end

ns.OnLogin(function()
    local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
    local icon = LibStub and LibStub("LibDBIcon-1.0", true)
    if not (ldb and icon) then
        ns.Diag.Log("LibDataBroker/LibDBIcon indisponibles : pas d'icône de minicarte.")
        return
    end
    local obj = ldb:NewDataObject("ShadsunGoldLens", {
        type = "launcher", text = ns.title, icon = MM.ICON,
        OnClick = function(_, button)
            local ok, err = pcall(onClick, button)
            if not ok then ns.Diag.Error("minimap", err) end
        end,
        OnTooltipShow = function(tt) pcall(tooltip, tt) end,
    })
    if obj and not icon:IsRegistered("ShadsunGoldLens") then
        icon:Register("ShadsunGoldLens", obj, ns.settings.minimap)
    end
    MM.Apply()
end)

ns.On("UI_RESET", function() MM.Apply() end)

-- Compartiment d'add-ons (déclaré dans le .toc) / addon compartment (.toc)
function ShadsunGoldLens_OnAddonCompartmentClick(_, buttonName)
    local button = type(buttonName) == "table" and buttonName.buttonName or buttonName
    onClick(button)
end
function ShadsunGoldLens_OnAddonCompartmentEnter(_, frame)
    GameTooltip:SetOwner(frame or UIParent, "ANCHOR_LEFT")
    tooltip(GameTooltip)
    GameTooltip:Show()
end
function ShadsunGoldLens_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
