local addon_name, addon_env = ...

-- Confused about mix of CamelCase and_underscores?
-- Camel case comes from copypasta of how Blizzard calls returns/fields in their code and deriveates
-- Underscore are my own variables

-- [AUTOLOCAL START]
-- [AUTOLOCAL END]

addon_env.MissionPage_ButtonsInit("ShipyardMissionPage", GarrisonShipyardFrame.MissionTab.MissionPage)

local BestForCurrentSelectedMission = addon_env.BestForCurrentSelectedMission
hooksecurefunc(GarrisonShipyardFrame, "ShowMission", function()
   BestForCurrentSelectedMission(LE_FOLLOWER_TYPE_SHIPYARD_6_2, GarrisonShipyardFrame.MissionTab.MissionPage, "ShipyardMissionPage")
end)