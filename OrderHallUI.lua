local addon_name, addon_env = ...

-- Confused about mix of CamelCase and_underscores?
-- Camel case comes from copypasta of how Blizzard calls returns/fields in their code and deriveates
-- Underscore are my own variables

-- [AUTOLOCAL START]
local CreateFrame = CreateFrame
local LE_FOLLOWER_TYPE_GARRISON_7_0 = LE_FOLLOWER_TYPE_GARRISON_7_0
-- [AUTOLOCAL END]

addon_env.event_frame = addon_env.event_frame or CreateFrame("Frame")
local event_frame = addon_env.event_frame
local RegisterEvent = event_frame.RegisterEvent
local UnregisterEvent = event_frame.UnregisterEvent

local BestForCurrentSelectedMission = addon_env.BestForCurrentSelectedMission

function addon_env.OrderHallInitUI()
   if not OrderHallMissionFrame then return end

   local base_frame = OrderHallMissionFrame
   local prefix = "OrderHall"
   local currency = C_Garrison.GetCurrencyTypes(LE_GARRISON_TYPE_7_0)
   local follower_type = LE_FOLLOWER_TYPE_GARRISON_7_0

   local MissionTab = OrderHallMissionFrame.MissionTab
   local MissionPage = MissionTab.MissionPage
   local MissionList = MissionTab.MissionList
   local mission_page_prefix = prefix .. "MissionPage"
   local mission_list_prefix = prefix .. "MissionList"
   
   addon_env.MissionPage_ButtonsInit(mission_page_prefix, MissionPage)
   addon_env.mission_page_button_prefix_for_type_id[follower_type] = mission_page_prefix
   hooksecurefunc(base_frame, "ShowMission", addon_env.ShowMission_More)

   addon_env.MissionList_ButtonsInit(MissionList, mission_list_prefix)
   local MissionList_Update_More = addon_env.MissionList_Update_More

   local function MissionList_Update_More_Settings()
      MissionList_Update_More(MissionList, MissionList_Update_More_Settings, mission_list_prefix, follower_type, currency)
   end

   hooksecurefunc(MissionList,            "Update", MissionList_Update_More_Settings)
   hooksecurefunc(MissionList.listScroll, "update", MissionList_Update_More_Settings)
   MissionList_Update_More_Settings()

   addon_env.OrderHallInitUI = nil
end

if OrderHallMissionFrame and addon_env.OrderHallInitUI then
   addon_env.OrderHallInitUI()
end
-- Set an additional timer to catch load if we STILL manage to miss it?