local OP = prisontest
local JM = OP.jackhammer_mod
local U = rawget(_G, "prisontest_utils")

local function load_config()
    if not U or type(U.load_json_config) ~= "function" then
        return nil
    end
    return U.load_json_config({
        tag = "prisontest_enchant_jackhammer",
        modpath = JM.modpath,
        relpath = "data/config.json",
        schema = {type = "table"},
    })
end

function JM.apply_config()
    local cfg = load_config()
    if type(cfg) ~= "table" then
        return
    end
    JM.config = cfg

    if type(OP.register_enchant_def) == "function" and type(cfg.enchant) == "table" then
        OP.register_enchant_def("jackhammer", cfg.enchant, {after = tostring(cfg.order_after or "explosive")})
    end
    if type(OP.register_enchant_visibility) == "function" then
        OP.register_enchant_visibility("jackhammer", function()
            return OP.has_feature and OP.has_feature("enchant_jackhammer")
        end)
    end
end

JM.apply_config()
if type(OP.register_config_reload_hook) == "function" then
    OP.register_config_reload_hook(JM.apply_config)
end
