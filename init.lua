local OP = rawget(_G, "prisontest")
if type(OP) ~= "table" then
    return
end

if type(OP.enable_feature) == "function" then
    OP.enable_feature("enchant_jackhammer")
end

local MODPATH = minetest.get_modpath(minetest.get_current_modname())
OP.jackhammer_mod = {
    modpath = MODPATH,
}

dofile(MODPATH .. "/lib/config.lua")
dofile(MODPATH .. "/lib/core.lua")
