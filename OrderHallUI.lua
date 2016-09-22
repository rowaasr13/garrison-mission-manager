local addon_name, addon_env = ...

-- Confused about mix of CamelCase and_underscores?
-- Camel case comes from copypasta of how Blizzard calls returns/fields in their code and deriveates
-- Underscore are my own variables

-- [AUTOLOCAL START]
local CreateFrame = CreateFrame
local LE_FOLLOWER_TYPE_GARRISON_7_0 = LE_FOLLOWER_TYPE_GARRISON_7_0
-- [AUTOLOCAL END]

local button_prefix = "OrderHallMissionPage"

addon_env.event_frame = addon_env.event_frame or CreateFrame("Frame")
local event_frame = addon_env.event_frame
local RegisterEvent = event_frame.RegisterEvent
local UnregisterEvent = event_frame.UnregisterEvent

local BestForCurrentSelectedMission = addon_env.BestForCurrentSelectedMission

local MissionPage

function addon_env.OrderHallInitUI()
   if not OrderHallMissionFrame then return end
   MissionPage = OrderHallMissionFrame.MissionTab.MissionPage
   addon_env.MissionPage_ButtonsInit(button_prefix, MissionPage)
   addon_env.mission_page_button_prefix_for_type_id[LE_FOLLOWER_TYPE_GARRISON_7_0] = button_prefix
   hooksecurefunc(OrderHallMissionFrame, "ShowMission", addon_env.ShowMission_More)

   addon_env.OrderHallInitUI = nil
end

if OrderHallMissionFrame and addon_env.OrderHallInitUI then
   addon_env.OrderHallInitUI()
end
-- Set an additional timer to catch load if we STILL manage to miss it?