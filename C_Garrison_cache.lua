local addon_name, addon_env = ...
if not addon_env.load_this then return end

-- [AUTOLOCAL START]
local C_Garrison = C_Garrison
local Enum_GarrisonFollowerType_FollowerType_6_0_GarrisonFollower = Enum.GarrisonFollowerType.FollowerType_6_0_GarrisonFollower
local Enum_GarrisonType_Type_6_0_Garrison = Enum.GarrisonType.Type_6_0_Garrison
local setmetatable = setmetatable
local wipe = wipe
-- [AUTOLOCAL END]

local getters = {}
local cache = setmetatable({}, { __index = function(t, key)
   local result = getters[key]()
   t[key] = result
   return result
end})
addon_env.c_garrison_cache = cache

local GetBuildings = C_Garrison.GetBuildings
getters.GetBuildings = function()
   return GetBuildings(Enum_GarrisonType_Type_6_0_Garrison)
end

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

local GetPossibleFollowersForBuilding = C_Garrison.GetPossibleFollowersForBuilding
local cache_GetPossibleFollowersForBuilding = setmetatable({}, { __index = function(t, key)
   local result = GetPossibleFollowersForBuilding(Enum_GarrisonFollowerType_FollowerType_6_0_GarrisonFollower, key)
   t[key] = result
   return result
end})

getters.GetPossibleFollowersForBuilding = function()
   wipe(cache_GetPossibleFollowersForBuilding)
   return cache_GetPossibleFollowersForBuilding
end

-- wipe removes all entries, but leaves MT alone, as this test shows
-- WIPE_META_TEST = setmetatable({}, { __index = function(t, key) return "test" end})