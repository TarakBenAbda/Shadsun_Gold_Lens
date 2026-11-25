-- Shadsun Gold Lens — script d'audit de la base v0.3.0 / v0.3.0 data audit
-- Auteur : Tarak Ben Abda – novembre 2026
-- Usage : lua5.1 audit3.lua  (Reference.lua et Vendors.lua v0.3.0 dans le dossier courant)
print("Shadsun Gold Lens — audit v0.3.0 · Auteur : Tarak Ben Abda")
local addon = {}
for _,f in ipairs{"Reference.lua","Vendors.lua"} do assert(loadfile(f))("x", addon) end
local c=0
for id, rows in pairs(addon.offers) do local ref=addon.referenceOffers[id] if ref then local rp={} for _,r in ipairs(ref) do rp[r[1]..":"..r[3]]=r[2] end
 for _,r in ipairs(rows) do local p=rp[r[1]..":"..r[3]] if p and p>0 and r[2]/p < 0.5 then c=c+1 if c<15 then print(id, addon.referenceNames[id], "npc", r[1], addon.vendors[r[1]][1], "ref", p, "eg", r[2], "qty", r[3], r[6]) end end end end end
-- qty mismatches: same npc different qty
local q=0
for id, rows in pairs(addon.offers) do local ref=addon.referenceOffers[id] if ref then local rq={} for _,r in ipairs(ref) do rq[r[1]]=r[3] end for _,r in ipairs(rows) do if rq[r[1]] and rq[r[1]]~=r[3] then q=q+1 if q<6 then print("qtymis",id,addon.referenceNames[id],r[1],"ref",rq[r[1]],"eg",r[3]) end end end end end
print("qty mismatches", q)
-- dup rows within same source
local d=0 for id,rows in pairs(addon.referenceOffers) do local s={} for _,r in ipairs(rows) do local k=r[1]..":"..r[3]..":"..tostring(r[5]) if s[k] then d=d+1 end s[k]=true end end print("dup ref rows",d)
d=0 for id,rows in pairs(addon.offers) do local s={} for _,r in ipairs(rows) do local k=r[1]..":"..r[3]..":"..tostring(r[5]) if s[k] then d=d+1 end s[k]=true end end print("dup eg rows",d)
-- ref vendors with no map
local nm=0 for id,v in pairs(addon.referenceVendors) do if not v[3] then nm=nm+1 if nm<5 then print("nomap",id,v[1],v[2]) end end end print("ref vendors no map",nm)
-- distinct builds
local b={} for id,rows in pairs(addon.offers) do for _,r in ipairs(rows) do b[r[6]]=(b[r[6]] or 0)+1 end end for k,v in pairs(b) do print("build",k,v) end
