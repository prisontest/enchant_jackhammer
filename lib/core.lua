local OP = prisontest
local JM = OP.jackhammer_mod

local active_proc = {}

local function register_message_settings()
    if type(OP.register_message_setting) ~= "function" then
        return
    end
    OP.register_message_setting("jackhammer_proc_messages", "Jackhammer proc")
end
if minetest.register_on_mods_loaded then
    minetest.register_on_mods_loaded(register_message_settings)
else
    register_message_settings()
end

local function jackhammer_cfg()
    return (JM and JM.config and JM.config.gameplay) or {}
end

local function cfg_number(key, fallback)
    local n = tonumber(jackhammer_cfg()[key])
    if not n then
        return fallback
    end
    return n
end

local function jackhammer_proc_chance(level)
    local lvl = math.max(0, math.floor(tonumber(level) or 0))
    if lvl <= 0 then
        return 0
    end
    local base = math.max(0, tonumber(cfg_number("jackhammer_proc_base", 0.0005)) or 0.0005)
    local per_level = math.max(0, tonumber(cfg_number("jackhammer_proc_per_level", 0.00002)) or 0.00002)
    local cap = math.max(0, math.min(1, tonumber(cfg_number("jackhammer_proc_cap", 0.03)) or 0.03))
    return math.max(0, math.min(cap, base + (lvl * per_level)))
end

local function fmt_int(n)
    if type(OP.fmt_int) == "function" then
        return OP.fmt_int(n)
    end
    return tostring(math.floor(tonumber(n) or 0))
end

local function summarize_rewards_text(dug_count, money_gain, token_gain)
    return string.format(
        "Jackhammer cleared layer: %s blocks | +%s money | +%s tokens.",
        fmt_int(dug_count),
        fmt_int(money_gain),
        fmt_int(token_gain)
    )
end

local function play_jackhammer_activate_sound(player)
    if not player or not player:is_player() then
        return
    end
    minetest.sound_play("activate", {
        to_player = player:get_player_name(),
        gain = 0.65,
    }, true)
end

local function clear_layer_fast(mine, y, origin_x, origin_z)
    local minp = {x = mine.mine_min.x, y = y, z = mine.mine_min.z}
    local maxp = {x = mine.mine_max.x, y = y, z = mine.mine_max.z}

    local vm = VoxelManip()
    local emin, emax = vm:read_from_map(minp, maxp)
    local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
    local data = vm:get_data()
    local c_air = minetest.get_content_id("air")

    local counts = {}
    local dug_count = 0
    for z = mine.mine_min.z, mine.mine_max.z do
        for x = mine.mine_min.x, mine.mine_max.x do
            if not (x == origin_x and z == origin_z) then
                local vi = area:index(x, y, z)
                local cid = data[vi]
                local name = minetest.get_name_from_content_id(cid)
                if name and minetest.get_item_group(name, "prisontest_mine") > 0 then
                    counts[name] = (counts[name] or 0) + 1
                    data[vi] = c_air
                    dug_count = dug_count + 1
                end
            end
        end
    end

    if dug_count > 0 then
        vm:set_data(data)
        if type(vm.calc_lighting) == "function" then
            local ok = pcall(function()
                vm:calc_lighting(emin, emax)
            end)
            if not ok then
                pcall(function()
                    vm:calc_lighting()
                end)
            end
        end
        vm:write_to_map()
        if type(vm.update_liquids) == "function" then
            vm:update_liquids()
        end
        if type(minetest.fix_light) == "function" then
            minetest.fix_light(
                {x = minp.x - 1, y = minp.y - 1, z = minp.z - 1},
                {x = maxp.x + 1, y = maxp.y + 1, z = maxp.z + 1}
            )
        end
    end

    return counts, dug_count
end

local function simulate_virtual_rewards(player, stack, counts)
    local reward_ctx = type(OP.get_mining_reward_context) == "function"
        and OP.get_mining_reward_context(player, stack, {source = "jackhammer"})
        or nil
    if type(reward_ctx) ~= "table" then
        return {
            money = 0,
            tokens = 0,
            xp = 0,
            blocks = 0,
            hatchery_level = 0,
        }
    end

    local total_money = 0
    local total_tokens = 0
    local total_xp = 0
    local total_blocks = 0

    for node_name, count in pairs(counts) do
        local block = OP.get_block_by_node(node_name)
        if block then
            for _ = 1, count do
                local reward = OP.roll_mining_block_reward(player, stack, block, reward_ctx, {
                    source = "jackhammer",
                })
                total_money = total_money + reward.money
                total_tokens = total_tokens + reward.tokens
                total_xp = total_xp + reward.xp
            end

            total_blocks = total_blocks + count
        end
    end

    return {
        money = total_money,
        tokens = total_tokens,
        xp = total_xp,
        blocks = total_blocks,
        hatchery_level = reward_ctx.hatchery,
    }
end

function OP.handle_jackhammer_proc(pos, digger, jackhammer_level)
    local lvl = math.max(0, math.floor(tonumber(jackhammer_level) or 0))
    if lvl <= 0 then
        return false
    end
    if not digger or not digger:is_player() then
        return false
    end
    if not pos or type(pos) ~= "table" then
        return false
    end
    if math.random() > jackhammer_proc_chance(lvl) then
        return false
    end

    local pname = digger:get_player_name()
    if active_proc[pname] then
        return false
    end

    local stack = digger:get_wielded_item()
    if not (OP.is_pick and OP.is_pick(stack)) then
        return false
    end

    local mine = nil
    if type(OP.set_mine_bounds_for_player) == "function" then
        mine = OP.set_mine_bounds_for_player(digger)
    end
    if type(mine) ~= "table" or type(mine.mine_min) ~= "table" or type(mine.mine_max) ~= "table" then
        return false
    end

    local y = math.floor(tonumber(pos.y) or 0)
    local mine_y_min = math.floor(tonumber(mine.mine_min.y) or 0) + 1
    local mine_y_max = math.floor(tonumber(mine.mine_max.y) or 0)
    if y < mine_y_min or y > mine_y_max then
        return false
    end

    local origin_x = math.floor(tonumber(pos.x) or 0)
    local origin_z = math.floor(tonumber(pos.z) or 0)

    active_proc[pname] = true
    local ok, err = pcall(function()
        local counts, dug_count = clear_layer_fast(mine, y, origin_x, origin_z)
        if dug_count <= 0 then
            return
        end
        play_jackhammer_activate_sound(digger)

        local rewards = simulate_virtual_rewards(digger, stack, counts)

        if rewards.money > 0 then
            OP.add_money(digger, rewards.money)
        end
        if rewards.tokens > 0 then
            OP.add_tokens(digger, rewards.tokens)
        end
        if type(OP.add_minute_earnings) == "function" then
            OP.add_minute_earnings(digger, rewards.money, rewards.tokens)
        end
        if type(OP.add_token_popup_earnings) == "function" then
            OP.add_token_popup_earnings(digger, rewards.tokens)
        end

        OP.add_blocks_mined(digger, rewards.blocks)
        if type(OP.rewards_trigger_event) == "function" then
            pcall(OP.rewards_trigger_event, digger, "block_mined", {
                count = rewards.blocks,
                blocks_total = OP.get_blocks_mined(digger),
                source = "jackhammer",
            })
        end
        OP.increment_mine_progress(digger, rewards.blocks)

        local milestone_count, milestone_tokens, milestone_money = OP.apply_block_milestone_rewards(digger)
        if milestone_count > 0 then
            local text = string.format(
                "Milestone reward x%d: +%s tokens, +%s money.",
                milestone_count,
                OP.fmt_int(milestone_tokens),
                OP.fmt_int(milestone_money)
            )
            if type(OP.send_message_if_enabled) == "function" then
                OP.send_message_if_enabled(digger, "jackhammer_proc_messages", text, "#ffe36e")
            else
                minetest.chat_send_player(pname, minetest.colorize("#ffe36e", text))
            end
        end

        if type(OP.points_on_blocks_mined) == "function" then
            local points_gain = OP.points_on_blocks_mined(digger, rewards.blocks)
            if points_gain > 0 then
                local text = string.format("You earned %s point%s.", OP.fmt_int(points_gain), points_gain == 1 and "" or "s")
                if type(OP.send_message_if_enabled) == "function" then
                    OP.send_message_if_enabled(digger, "jackhammer_proc_messages", text, "#87d65b")
                else
                    minetest.chat_send_player(pname, minetest.colorize("#87d65b", text))
                end
            end
        end

        if type(OP.pets_on_block_mined) == "function" then
            pcall(OP.pets_on_block_mined, digger, {
                hatchery_level = rewards.hatchery_level,
            })
        end

        if rewards.xp > 0 then
            local wield = digger:get_wielded_item()
            if OP.is_pick and OP.is_pick(wield) then
                local profile_after, levels = OP.add_pick_xp(wield, rewards.xp)
                OP.apply_lore(wield, OP.get_enchants(wield))
                digger:set_wielded_item(wield)
                if levels and levels > 0 then
                    local text = string.format("Pickaxe leveled up to %d!", profile_after.level)
                    if type(OP.send_message_if_enabled) == "function" then
                        OP.send_message_if_enabled(digger, "jackhammer_proc_messages", text, "#55ffff")
                    else
                        minetest.chat_send_player(pname, minetest.colorize("#55ffff", text))
                    end
                end
            end
        end

        local summary = summarize_rewards_text(dug_count, rewards.money, rewards.tokens)
        if type(OP.send_message_if_enabled) == "function" then
            OP.send_message_if_enabled(digger, "jackhammer_proc_messages", summary, "#6ed3ff")
        else
            minetest.chat_send_player(pname, minetest.colorize("#6ed3ff", summary))
        end
    end)

    active_proc[pname] = nil
    if not ok then
        minetest.log("error", "[prisontest_enchant_jackhammer] virtual proc failed for " .. pname .. ": " .. tostring(err))
        return false
    end
    return true
end

minetest.register_on_leaveplayer(function(player)
    if not player or not player:is_player() then
        return
    end
    active_proc[player:get_player_name()] = nil
end)
