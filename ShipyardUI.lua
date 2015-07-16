local addon_name, addon_env = ...

-- Confused about mix of CamelCase and_underscores?
-- Camel case comes from copypasta of how Blizzard calls returns/fields in their code and deriveates
-- Underscore are my own variables

-- [AUTOLOCAL START]
local After = C_Timer.After
local GetCurrencyInfo = GetCurrencyInfo
local wipe = wipe
-- [AUTOLOCAL END]

local Widget = addon_env.Widget
local gmm_buttons = addon_env.gmm_buttons
local top_for_mission = addon_env.top_for_mission
local GetFilteredFollowers = addon_env.GetFilteredFollowers
local UpdateMissionListButton = addon_env.UpdateMissionListButton

local MissionPage = GarrisonShipyardFrame.MissionTab.MissionPage

local function ShipyardMissionList_PartyButtonOnClick(self)
   if addon_env.RegisterManualInterraction then addon_env.RegisterManualInterraction() end
   addon_env.mission_page_pending_click = "ShipyardMissionPage1"
   return self:GetParent():Click()
end

local shipyard_mission_list_gmm_button_template = { "Button", nil, "UIPanelButtonTemplate", Width = 80, Height = 40, OnClick = ShipyardMissionList_PartyButtonOnClick, FrameLevelOffset = 3 }
local function GarrisonShipyardMap_UpdateMissions_More()
   -- Blizzard updates those when not visible too, but there's no reason to copy them.
   local self = GarrisonShipyardFrame.MissionTab.MissionList
   if not self:IsVisible() then return end   

   local missions = self.missions
   local mission_frames = self.missionFrames

   if addon_env.top_for_mission_dirty then
      wipe(top_for_mission)
      addon_env.top_for_mission_dirty = false
   end

   local filtered_followers = GetFilteredFollowers(LE_FOLLOWER_TYPE_SHIPYARD_6_2)
   local more_missions_to_cache
   local _, oil = GetCurrencyInfo(GARRISON_SHIP_OIL_CURRENCY)

   for i = 1, #missions do
      local mission = missions[i]
         
      -- Cache mission frames
      local frame = mission_frames[i]
      if frame then
         if (mission.offeredGarrMissionTextureID ~= 0 and not mission.inProgress and not mission.canStart) then
            frame:Hide()
         else
            local gmm_button = gmm_buttons['ShipyardMissionList' .. i]
            if not gmm_button then
               shipyard_mission_list_gmm_button_template.parent = frame
               gmm_button = Widget(shipyard_mission_list_gmm_button_template)
               gmm_button:SetText(i)
               gmm_button:SetPoint("TOP", frame, "BOTTOM", 0, 10)
               gmm_button:SetScale(0.60)
               gmm_buttons['ShipyardMissionList' .. i] = gmm_button
            end
            
            if (mission.inProgress) then
               gmm_button:Hide()
            else
               gmm_button:Show()
               more_missions_to_cache = UpdateMissionListButton(mission, filtered_followers, frame, gmm_button, more_missions_to_cache, oil, 0.5)               
            end
         end
      end
   end

   if more_missions_to_cache and more_missions_to_cache > 0 then
      After(0.001, GarrisonShipyardMap_UpdateMissions_More)
   end
end
hooksecurefunc("GarrisonShipyardMap_UpdateMissions", GarrisonShipyardMap_UpdateMissions_More)

addon_env.MissionPage_ButtonsInit("ShipyardMissionPage", MissionPage)

local BestForCurrentSelectedMission = addon_env.BestForCurrentSelectedMission
hooksecurefunc(GarrisonShipyardFrame, "ShowMission", function()
   BestForCurrentSelectedMission(LE_FOLLOWER_TYPE_SHIPYARD_6_2, MissionPage, "ShipyardMissionPage")
end)

gmm_buttons.StartShipyardMission = MissionPage.StartMissionButton