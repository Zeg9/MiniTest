-- minetest/fire/init.lua

minetest.register_node("fire:basic_flame", {
	description = "Fire",
	drawtype = "plantlike",
	tiles = {{
		name="fire_basic_flame_animated.png",
		animation={type="vertical_frames", aspect_w=16, aspect_h=16, length=1},
	}},
	inventory_image = "fire_basic_flame.png",
	light_source = 14,
	groups = {igniter=2,dig_immediate=3},
	drop = '',
	walkable = false,
	buildable_to = true,
	damage_per_second = 4,
	
	after_place_node = function(pos, placer)
		fire.on_flame_add_at(pos)
	end,
	
	after_dig_node = function(pos, oldnode, oldmetadata, digger)
		fire.on_flame_remove_at(pos)
	end,
})

fire = {}
fire.D = 6
-- key: position hash of low corner of area
-- value: {handle=sound handle, name=sound name}
fire.sounds = {}

function fire.get_area_p0p1(pos)
	local p0 = {
		x=math.floor(pos.x/fire.D)*fire.D,
		y=math.floor(pos.y/fire.D)*fire.D,
		z=math.floor(pos.z/fire.D)*fire.D,
	}
	local p1 = {
		x=p0.x+fire.D-1,
		y=p0.y+fire.D-1,
		z=p0.z+fire.D-1
	}
	return p0, p1
end

function fire.update_sounds_around(pos)
	local p0, p1 = fire.get_area_p0p1(pos)
	local cp = {x=(p0.x+p1.x)/2, y=(p0.y+p1.y)/2, z=(p0.z+p1.z)/2}
	local flames_p = minetest.env:find_nodes_in_area(p0, p1, {"fire:basic_flame"})
	--print("number of flames at "..minetest.pos_to_string(p0).."/"
	--		..minetest.pos_to_string(p1)..": "..#flames_p)
	local should_have_sound = (#flames_p > 0)
	local wanted_sound = nil
	if #flames_p >= 9 then
		wanted_sound = {name="fire_large", gain=1.5}
	elseif #flames_p > 0 then
		wanted_sound = {name="fire_small", gain=1.5}
	end
	local p0_hash = minetest.hash_node_position(p0)
	local sound = fire.sounds[p0_hash]
	if not sound then
		if should_have_sound then
			fire.sounds[p0_hash] = {
				handle = minetest.sound_play(wanted_sound, {pos=cp, loop=true}),
				name = wanted_sound.name,
			}
		end
	else
		if not wanted_sound then
			minetest.sound_stop(sound.handle)
			fire.sounds[p0_hash] = nil
		elseif sound.name ~= wanted_sound.name then
			minetest.sound_stop(sound.handle)
			fire.sounds[p0_hash] = {
				handle = minetest.sound_play(wanted_sound, {pos=cp, loop=true}),
				name = wanted_sound.name,
			}
		end
	end
end

function fire.on_flame_add_at(pos)
	--print("flame added at "..minetest.pos_to_string(pos))
	fire.update_sounds_around(pos)
end

function fire.on_flame_remove_at(pos)
	--print("flame removed at "..minetest.pos_to_string(pos))
	fire.update_sounds_around(pos)
end

function fire.find_pos_for_flame_around(pos)
	return minetest.env:find_node_near(pos, 1, {"air"})
end

function fire.flame_should_extinguish(pos)
	if minetest.setting_getbool("disable_fire") then return true end
	--return minetest.env:find_node_near(pos, 1, {"group:puts_out_fire"})
	local p0 = {x=pos.x-2, y=pos.y, z=pos.z-2}
	local p1 = {x=pos.x+2, y=pos.y, z=pos.z+2}
	local ps = minetest.env:find_nodes_in_area(p0, p1, {"group:puts_out_fire"})
	return (#ps ~= 0)
end

-- Ignite neighboring nodes
minetest.register_abm({
	nodenames = {"group:flammable"},
	neighbors = {"group:igniter"},
	interval = 1,
	chance = 2,
	action = function(p0, node, _, _)
		-- If there is water or stuff like that around flame, don't ignite
		if fire.flame_should_extinguish(p0) then
			return
		end
		local p = fire.find_pos_for_flame_around(p0)
		if p then
			minetest.env:set_node(p, {name="fire:basic_flame"})
			fire.on_flame_add_at(p)
		end
	end,
})

-- Rarely ignite things from far
minetest.register_abm({
	nodenames = {"group:igniter"},
	neighbors = {"air"},
	interval = 2,
	chance = 10,
	action = function(p0, node, _, _)
		local reg = minetest.registered_nodes[node.name]
		if not reg or not reg.groups.igniter or reg.groups.igniter < 2 then
			return
		end
		local d = reg.groups.igniter
		local p = minetest.env:find_node_near(p0, d, {"group:flammable"})
		if p then
			-- If there is water or stuff like that around flame, don't ignite
			if fire.flame_should_extinguish(p) then
				return
			end
			local p2 = fire.find_pos_for_flame_around(p)
			if p2 then
				minetest.env:set_node(p2, {name="fire:basic_flame"})
				fire.on_flame_add_at(p2)
			end
		end
	end,
})

-- Remove flammable nodes and flame
minetest.register_abm({
	nodenames = {"fire:basic_flame"},
	interval = 1,
	chance = 2,
	action = function(p0, node, _, _)
		-- If there is water or stuff like that around flame, remove flame
		if fire.flame_should_extinguish(p0) then
			minetest.env:remove_node(p0)
			fire.on_flame_remove_at(p0)
			return
		end
		-- Make the following things rarer
		if math.random(1,3) == 1 then
			return
		end
		-- If there are no flammable nodes around flame, remove flame
		if not minetest.env:find_node_near(p0, 1, {"group:flammable"}) then
			minetest.env:remove_node(p0)
			fire.on_flame_remove_at(p0)
			return
		end
		if math.random(1,4) == 1 then
			-- remove a flammable node around flame
			local p = minetest.env:find_node_near(p0, 1, {"group:flammable"})
			if p then
				-- If there is water or stuff like that around flame, don't remove
				if fire.flame_should_extinguish(p0) then
					return
				end
				minetest.env:remove_node(p)
				nodeupdate(p)
			end
		else
			-- remove flame
			minetest.env:remove_node(p0)
			fire.on_flame_remove_at(p0)
		end
	end,
})


minetest.register_tool("fire:flint_and_steel", {
	description = "Flint and Steel",
	inventory_image = "fire_flint_and_steel.png",
	on_place = function(stack, placer, pt)
		if not pt.type == "node" then
			return
		end
		local under = minetest.env:get_node(pt.under)
		local above = minetest.env:get_node(pt.above)
		if minetest.registered_nodes[under.name] and minetest.registered_nodes[under.name].on_rightclick then
			stack = minetest.registered_nodes[under.name].on_rightclick(pt.under, under, placer, stack) or stack
			return stack
		end
		if under.name == "default:obsidian" then
			local done = nether.make_portal(pt.under)
			if done and not minetest.setting_getbool("creative_mode") then
				stack:add_wear(65535/(39))
			end
			return stack
		end
		if minetest.registered_nodes[under.name] and minetest.registered_nodes[under.name].buildable_to then
			minetest.env:set_node(pt.under, {name="fire:basic_flame"})
			if not minetest.setting_getbool("creative_mode") then
				stack:add_wear(65535/(39))
			end
			return stack
		end
		if minetest.registered_nodes[above.name] and minetest.registered_nodes[above.name].buildable_to then
			minetest.env:set_node(pt.above, {name="fire:basic_flame"})
			if not minetest.setting_getbool("creative_mode") then
				stack:add_wear(65535/(39))
			end
			return stack
		end
	end,
})

minetest.register_craft({
	type = "shapeless",
	output = "fire:flint_and_steel",
	recipe = {"default:flint", "default:steel_ingot"},
})
