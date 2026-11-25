-- Shadsun Gold Lens — script d'audit de la base v0.3.0 / v0.3.0 data audit
-- Auteur : Tarak Ben Abda – novembre 2026
-- Usage : lua5.1 audit.lua  (Reference.lua et Vendors.lua v0.3.0 dans le dossier courant)
print("Shadsun Gold Lens — audit v0.3.0 · Auteur : Tarak Ben Abda")
local addon = {}
local function load(f) local chunk = assert(loadfile(f)); chunk("ShadsunGoldLens", addon) end
load("Reference.lua"); load("Vendors.lua")
local function cnt(t) local n=0 for _ in pairs(t) do n=n+1 end return n end
print("referenceVendors", cnt(addon.referenceVendors))
print("referenceOffers items", cnt(addon.referenceOffers))
print("referenceNames", cnt(addon.referenceNames))
print("knownItems", cnt(addon.knownItems))
print("EG vendors", cnt(addon.vendors))
print("EG offers items", cnt(addon.offers))
-- union
local items, npcs, pairsN = {}, {}, 0
local priced, extra, zero, missingVendor = 0,0,0,0
local sides = {}
local noCoord=0
for _,src in ipairs({{addon.referenceOffers, addon.referenceVendors,"ref"},{addon.offers, addon.vendors,"eg"}}) do
  local o, v, tag = src[1], src[2], src[3]
  for id, rows in pairs(o) do
    items[id] = items[id] or {}
    for _,r in ipairs(rows) do
      pairsN = pairsN + 1
      local vend = v[r[1]]
      if not vend then missingVendor = missingVendor + 1 else
        npcs[r[1]] = true
        sides[tostring(vend[2])] = (sides[tostring(vend[2])] or 0) + 0
      end
      if r[5] then extra = extra + 1 elseif r[2] and r[2] > 0 then priced = priced + 1 else zero = zero + 1 end
      items[id][tag] = true
    end
  end
end
print("union items", cnt(items), "npcs used", cnt(npcs), "pairs", pairsN, "missingVendor", missingVendor, "priced", priced, "extracost", extra, "zero", zero)
local onlyRef, onlyEg, both = 0,0,0
for id,t in pairs(items) do if t.ref and t.eg then both=both+1 elseif t.ref then onlyRef=onlyRef+1 else onlyEg=onlyEg+1 end end
print("onlyRef", onlyRef, "onlyEg", onlyEg, "both", both)
-- faction tally
local fs = {}
for id,v in pairs(addon.referenceVendors) do fs["ref:"..tostring(v[2])] = (fs["ref:"..tostring(v[2])] or 0)+1 if not (v[3] and v[4]) then noCoord=noCoord+1 end end
for id,v in pairs(addon.vendors) do fs["eg:"..tostring(v[2])] = (fs["eg:"..tostring(v[2])] or 0)+1 if not (v[3] and v[4]) then noCoord=noCoord+1 end end
for k,n in pairs(fs) do print(k,n) end
print("vendors without coords", noCoord)
-- names missing for items
local noname=0 for id in pairs(items) do if not addon.referenceNames[id] then noname=noname+1 end end
print("items with no reference name", noname)
-- price disagreements ref vs EG
local diff, same, cmp = 0,0,0
for id, rows in pairs(addon.offers) do
  local ref = addon.referenceOffers[id]
  if ref then
    local refp = {}
    for _,r in ipairs(ref) do refp[r[1]] = r[2] end
    for _,r in ipairs(rows) do if refp[r[1]] then cmp=cmp+1 if refp[r[1]]==r[2] then same=same+1 else diff=diff+1 end end end
  end
end
print("ref vs EG same npc price: compared", cmp, "same", same, "diff", diff)
-- map ids used
local maps = {}
for _,v in pairs(addon.referenceVendors) do maps[v[3] or "nil"]=true end
for _,v in pairs(addon.vendors) do maps[v[3] or "nil"]=true end
local ml={} for m in pairs(maps) do ml[#ml+1]=tostring(m) end table.sort(ml) print("maps", #ml, table.concat(ml," "))
-- condition column
local conds={} for id,rows in pairs(addon.referenceOffers) do for _,r in ipairs(rows) do conds[tostring(r[7])]=(conds[tostring(r[7])] or 0)+1 end end
for k,n in pairs(conds) do print("cond",k,n) end
-- vendor coord mismatch between ref and eg same npc
local mism=0 local sideMism=0
for npc,v in pairs(addon.vendors) do local r=addon.referenceVendors[npc] if r then if r[3]~=v[3] or math.abs((r[4] or 0)-(v[4] or 0))>3 or math.abs((r[5] or 0)-(v[5] or 0))>3 then mism=mism+1 end if r[2]~=v[2] then sideMism=sideMism+1 end end end
print("vendor coord/map mismatch ref vs eg", mism, "side mismatch", sideMism)
