local addon_name, addon_env = ...

-- [AUTOLOCAL START]
local After = C_Timer.After
local GARRISON_CURRENCY = GARRISON_CURRENCY
local GarrisonMissionFrame = GarrisonMissionFrame
local GetCurrencyInfo = GetCurrencyInfo
local GetTime = GetTime
local HybridScrollFrame_GetOffset = HybridScrollFrame_GetOffset
local LE_FOLLOWER_TYPE_GARRISON_6_0 = LE_FOLLOWER_TYPE_GARRISON_6_0
local RED_FONT_COLOR_CODE = RED_FONT_COLOR_CODE
local pairs = pairs
local print = print
local wipe = wipe
-- [AUTOLOCAL END]

local gmm_buttons = addon_env.gmm_buttons
local gmm_frames = addon_env.gmm_frames
local top_for_mission = addon_env.top_for_mission
local GetFilteredFollowers = addon_env.GetFilteredFollowers
local UpdateMissionListButton = addon_env.UpdateMissionListButton

-- Add more data to mission list over Blizzard's own
local mission_expiration_format_days  = "%s" .. DAY_ONELETTER_ABBR:gsub(" ", "") .. " %02d:%02d"
local mission_expiration_format_hours = "%s" ..                                        "%d:%02d"
local function GarrisonMissionList_Update_More()
   local self = GarrisonMissionFrame.MissionTab.MissionList
   -- Blizzard updates those when not visible too, but there's no reason to copy them.
   if not self:IsVisible() then return end
   local scrollFrame = self.listScroll
   local buttons = scrollFrame.buttons
   local numButtons = #buttons

   if self.showInProgress then
      for i = 1, numButtons do
         gmm_buttons['MissionList' .. i]:Hide()
         gmm_frames['MissioListExpirationText' .. i]:SetText()
         buttons[i]:SetAlpha(1)
      end
      return
   end

   local missions = self.availableMissions
   local numMissions = #missions
   if numMissions == 0 then return end

   if addon_env.top_for_mission_dirty then
      wipe(top_for_mission)
      addon_env.top_for_mission_dirty = false
   end

   local missions = self.availableMissions
   local offset = HybridScrollFrame_GetOffset(scrollFrame)

   local filtered_followers = GetFilteredFollowers(LE_FOLLOWER_TYPE_GARRISON_6_0)
   local more_missions_to_cache
   local _, garrison_resources = GetCurrencyInfo(GARRISON_CURRENCY)

   local time = GetTime()

   for i = 1, numButtons do
      local button = buttons[i]
      local alpha = 1
      local index = offset + i
      if index <= numMissions then
         local mission = missions[index]
         local gmm_button = gmm_buttons['MissionList' .. i]

         more_missions_to_cache = UpdateMissionListButton(mission, filtered_followers, button, gmm_button, more_missions_to_cache, garrison_resources)

         local is_rare = mission.isRare

         local expiration_text_set
         local offerEndTime = mission.offerEndTime

         -- offerEndTime seems to be present on all missions, though Blizzard UI shows tooltips only on rare
         if offerEndTime then
            local xp_only_rewards
            if not is_rare then
               for _, reward in pairs(mission.rewards) do
                  if reward.followerXP and xp_only_rewards == nil then xp_only_rewards = true end
                  if not reward.followerXP then xp_only_rewards = false break end
               end
            end

            if not xp_only_rewards then
               local remaining = offerEndTime - time -- seconds at this line, but will be reduced to minutes/hours/days below
               local color_code = (remaining < (60 * 60 * 8)) and RED_FONT_COLOR_CODE or ''
               local seconds = remaining % 60
               remaining = (remaining - seconds) / 60
               local minutes = remaining % 60
               remaining = (remaining - minutes) / 60
               local hours = remaining % 24
               local days = (remaining - hours) / 24
               if days > 0 then
                  gmm_frames['MissioListExpirationText' .. i]:SetFormattedText(mission_expiration_format_days, color_code, days, hours, minutes)
               else
                  gmm_frames['MissioListExpirationText' .. i]:SetFormattedText(mission_expiration_format_hours, color_code, hours, minutes)
               end
               expiration_text_set = true
            end
         end

         if not expiration_text_set then
            gmm_frames['MissioListExpirationText' .. i]:SetText()
         end

         -- Just overwrite level with ilevel if it is not 0. There's no use knowing what base level mission have.
         -- Blizzard UI also checks that mission is max "normal" UI, but there's at least one mission mistakenly marked as level 90, despite requiring 675 ilevel.
         if mission.iLevel > 0 then
            button.ItemLevel:Hide()
            -- Restore position that Blizzard's UI changes if mission have both ilevel and rare! text
            if mission.isRare then
               button.Level:SetPoint("CENTER", button, "TOPLEFT", 40, -36)
            end
            button.Level:SetFormattedText("|cffffffd9%d", mission.iLevel)
         end
      end
   end

   if more_missions_to_cache and more_missions_to_cache > 0 then
      -- print(more_missions_to_cache, GetTime())
      After(0.001, GarrisonMissionList_Update_More)
   end
end
addon_env.GarrisonMissionList_Update_More = GarrisonMissionList_Update_More