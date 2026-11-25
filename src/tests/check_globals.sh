#!/bin/sh
# =============================================================================
# Shadsun Gold Lens — tests/check_globals.sh
# Auteur : Tarak Ben Abda – novembre 2026
# FR : Liste les variables globales lues et écrites par le code de l'add-on
#      (hors bibliothèques) et signale toute globale hors liste blanche.
# EN : Lists globals read/written by addon code; flags unknown ones.
# =============================================================================
echo "======================================================================"
echo " Shadsun Gold Lens — vérification des globales / globals check"
echo " Auteur : Tarak Ben Abda"
echo "======================================================================"
ADDON="${1:-../../ShadsunGoldLens}"
ALLOW="next ERR_AUCTION_SOLD_S ERR_AUCTION_EXPIRED_S ReloadUI HandleModifiedItemClick ChatEdit_InsertLink IsAltKeyDown IsShiftKeyDown IsControlKeyDown rawget GetCurrentRegionName GetNormalizedRealmName GetRealmName GetMoney ITEM_QUALITY_COLORS GetItemCount MERCHANT_ITEMS_PER_PAGE MerchantFrame GetAddOnMemoryUsage UpdateAddOnMemoryUsage Auctionator AuctionHouseFrame C_AuctionHouse C_AddOns C_Container C_Item C_Map C_MerchantFrame C_SuperTrack C_Timer ChatEdit_InsertLink ChatFrameUtil CreateFrame Enum GameTooltip GetBuildInfo GetItemClassInfo GetItemInfo GetItemInfoInstant GetItemSpell GetItemSubClassInfo GetLocale GetMerchantItemInfo GetMerchantItemLink GetMerchantNumItems GetTime HideUIPanel InCombatLockdown IsShiftKeyDown ItemRefTooltip LibStub OpenWorldMap SLASH_SHADSUNGOLDLENS1 SLASH_SHADSUNGOLDLENS2 Settings SettingsPanel ShadsunGoldLensDB ShadsunGoldLensGlobal ShadsunGoldLens_OnAddonCompartmentClick ShadsunGoldLens_OnAddonCompartmentEnter ShadsunGoldLens_OnAddonCompartmentLeave SlashCmdList ToggleWorldMap TomTom TooltipDataProcessor UIParent UISpecialFrames UiMapPoint UnitFactionGroup UnitGUID UnitName UnitReaction WOW_PROJECT_ID WorldMapFrame _G date debugprofilestop debugstack hooksecurefunc ipairs issecretvalue math pairs pcall print select setmetatable string strsplit table time tinsert tonumber tostring type wipe xpcall"
STATUS=0
for f in "$ADDON"/Core/*.lua "$ADDON"/UI/*.lua "$ADDON"/Locale/*.lua "$ADDON"/Data/*.lua; do
  for g in $(luac5.1 -l -p "$f" | grep -E "[GS]ETGLOBAL" | sed -E 's/.*; (.*)$/\1/' | sort -u); do
    case " $ALLOW " in *" $g "*) ;; *) echo "GLOBALE INCONNUE : $g dans $f"; STATUS=1 ;; esac
  done
done
echo "Globales écrites :"
for f in "$ADDON"/Core/*.lua "$ADDON"/UI/*.lua; do
  luac5.1 -l -p "$f" | grep -E "SETGLOBAL" | sed -E 's/.*; (.*)$/  \1/' | sed "s|\$| ($(basename "$f"))|"
done
[ $STATUS -eq 0 ] && echo "Résultat : aucune globale inconnue." || echo "Résultat : globales à vérifier."
exit $STATUS
