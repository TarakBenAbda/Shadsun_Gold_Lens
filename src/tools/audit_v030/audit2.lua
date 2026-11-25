-- Shadsun Gold Lens — script d'audit de la base v0.3.0 / v0.3.0 data audit
-- Auteur : Tarak Ben Abda – novembre 2026
-- Usage : lua5.1 audit2.lua  (Reference.lua et Vendors.lua v0.3.0 dans le dossier courant)
print("Shadsun Gold Lens — audit v0.3.0 · Auteur : Tarak Ben Abda")
local addon = {}
for _,f in ipairs{"Reference.lua","Vendors.lua"} do assert(loadfile(f))("x", addon) end
-- nil-side EG vendors
local n=0
for id,v in pairs(addon.vendors) do if v[2]==nil then n=n+1 if n<=12 then print("nilside",id,v[1],v[3],v[4],v[5], addon.referenceVendors[id] and addon.referenceVendors[id][2] or "-") end end end
-- big ids
local big=0 for id,v in pairs(addon.vendors) do if id>100000 then big=big+1 end end print("EG vendor ids >100000:",big)
-- price ratio histogram
local h={}
for id, rows in pairs(addon.offers) do local ref=addon.referenceOffers[id] if ref then local rp={} for _,r in ipairs(ref) do rp[r[1]..":"..r[3]]=r[2] end
 for _,r in ipairs(rows) do local p=rp[r[1]..":"..r[3]] if p and p>0 and r[2]~=p then local ratio=math.floor(r[2]/p*100+0.5) h[ratio]=(h[ratio] or 0)+1 end end end end
local ks={} for k in pairs(h) do ks[#ks+1]=k end table.sort(ks) for _,k in ipairs(ks) do io.write(k,"%:",h[k]," ") end print()
-- conditions examples
local shown={}
for id,rows in pairs(addon.referenceOffers) do for _,r in ipairs(rows) do if r[7]~=0 and not shown[r[7]] then shown[r[7]]=true local v=addon.referenceVendors[r[1]] print("cond",r[7],"item",id,addon.referenceNames[id],"npc",r[1],v and v[1]) end end end
-- extra cost examples
local c=0 for id,rows in pairs(addon.offers) do for _,r in ipairs(rows) do if r[5] then c=c+1 if c<6 then print("extra",id,r[1],addon.vendors[r[1]] and addon.vendors[r[1]][1]) end end end end
-- limited
local lim=0 for id,rows in pairs(addon.referenceOffers) do for _,r in ipairs(rows) do if r[4] then lim=lim+1 end end end print("limited ref rows",lim)
-- side mismatch samples
local m=0 for npc,v in pairs(addon.vendors) do local r=addon.referenceVendors[npc] if r and r[2]~=v[2] then m=m+1 if m<10 then print("sidemis",npc,v[1],"eg",v[2],"ref",r[2]) end end end
-- coord mismatch
for npc,v in pairs(addon.vendors) do local r=addon.referenceVendors[npc] if r and (r[3]~=v[3] or math.abs(r[4]-v[4])>3 or math.abs(r[5]-v[5])>3) then print("coordmis",npc,v[1],v[3],v[4],v[5],"ref",r[3],r[4],r[5]) end end
-- recipe check: Recipe: Gooey Spider cake etc. names starting with Recipe/Pattern/Plans/Schematic/Formula
local rc=0 for id,nm in pairs(addon.referenceNames) do if nm:match("^Recipe") or nm:match("^Pattern") or nm:match("^Plans") or nm:match("^Schematic") or nm:match("^Formula") or nm:match("^Manual") then rc=rc+1 end end print("recipe-like ref items",rc)
print("6325", addon.referenceNames[6325], addon.referenceOffers[6325] and #addon.referenceOffers[6325], addon.offers[6325] and #addon.offers[6325])
