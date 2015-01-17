local addon_name, addon_env = ...

local getters = {}
local cache = setmetatable({}, { __index = function(t, key)
   local result = getters[key]()
   t[key] = result
   return result
end})
addon_env.c_garrison_cache = cache

getters.GetBuildings = C_Garrison.GetBuildings

local salvage_yard_level_building_id = { [52]  = 1, [140] = 2, [141] = 3 }
getters.salvage_yard_level = function()
   local buildings = cache.GetBuildings
   for idx = 1, #buildings do
      local buildingID = buildings[idx].buildingID
      local possible_salvage_yard_level = salvage_yard_level_building_id[buildingID]
      if possible_salvage_yard_level then return possible_salvage_yard_level end
   end
   return false
end
