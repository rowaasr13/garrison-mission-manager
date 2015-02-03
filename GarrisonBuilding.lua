local addon_name, addon_env = ...

-- Confused about mix of CamelCase and_underscores?
-- Camel case comes from copypasta of how Blizzard calls returns/fields in their code and deriveates
-- Underscore are my own variables

-- [AUTOLOCAL START] Automatic local aliases for Blizzard's globals
local After = C_Timer.After
local AssignFollowerToBuilding = C_Garrison.AssignFollowerToBuilding
local FONT_COLOR_CODE_CLOSE = FONT_COLOR_CODE_CLOSE
local GARRISON_FOLLOWER_WORKING = GARRISON_FOLLOWER_WORKING
local GetFollowerInfoForBuilding = C_Garrison.GetFollowerInfoForBuilding
local GetFollowerStatus = C_Garrison.GetFollowerStatus
local RED_FONT_COLOR_CODE = RED_FONT_COLOR_CODE
local RemoveFollowerFromBuilding = C_Garrison.RemoveFollowerFromBuilding
local pairs = pairs
local tconcat = table.concat
local wipe = wipe
-- [AUTOLOCAL END]

local c_garrison_cache = addon_env.c_garrison_cache
local gmm_buttons = addon_env.gmm_buttons
local events_for_buildings = addon_env.events_for_buildings

local event_frame = addon_env.event_frame
local RegisterEvent = event_frame.RegisterEvent
local UnregisterEvent = event_frame.UnregisterEvent

local GarrisonBuilding_UpdateCurrentFollowers
local GarrisonBuilding_UpdateButtons

local assign_remove_buildings_list = {}
local assign_remove_building_names = {}
local assign_remove_building_icons = {}
local assign_remove_current_followers = {}
local assign_followers_best = {}
local assign_followers_status = {}
local assign_remove_buildings_count
local can_remove
local can_assign
local can_assign_busy

local function GarrisonBuilding_UpdateAssignBestFollowers()
   if assign_remove_buildings_count == 0 then return end
   wipe(assign_followers_best)
   for plotID, possible_followers in pairs(assign_remove_buildings_list) do
      local best_follower
      for follower_idx = 1, #possible_followers do
         local other_follower = possible_followers[follower_idx]
         if not best_follower then
            best_follower = other_follower
         elseif other_follower.level > best_follower.level then
            best_follower = other_follower
         -- I assume follower can't have traits for 2 different buildings and will not work in another building.
         elseif (best_follower.status and best_follower.status ~= GARRISON_FOLLOWER_WORKING) and not (other_follower.status and other_follower.status ~= GARRISON_FOLLOWER_WORKING) then
            best_follower = other_follower
         elseif not (best_follower.status and best_follower.status ~= GARRISON_FOLLOWER_WORKING) and (other_follower.status and other_follower.status ~= GARRISON_FOLLOWER_WORKING) then
            -- skip
         elseif other_follower.level == best_follower.level and other_follower.iLevel < best_follower.iLevel then
            best_follower = other_follower
         end
      end
      if best_follower then
         assign_followers_best[plotID] = best_follower
      end
   end
end

local last_broker_text
local concat_list = {}
GarrisonBuilding_UpdateCurrentFollowers = function()
   if assign_remove_buildings_count == 0 then return end
   wipe(assign_remove_current_followers)
   local broker = addon_env.broker
   local idx = 0
   if broker then
      wipe(concat_list)
      idx = 0
   end
   can_remove = nil
   can_assign = nil
   can_assign_busy = nil
   for plotID in pairs(assign_remove_buildings_list) do
      local followerName, level, quality, displayID, followerID, garrFollowerID, status, portraitIconID = GetFollowerInfoForBuilding(plotID)
      if followerName then
         assign_remove_current_followers[plotID] = followerName
         can_remove = true
         if broker then
            idx = idx + 1
            concat_list[idx] = assign_remove_building_icons[plotID]
         end
      else
         local status = GetFollowerStatus(assign_followers_best[plotID].followerID)
         assign_followers_status[plotID] = status
         can_assign_busy = true
         if not status then
            can_assign = true
         end
      end
   end
   if broker then
      local new_broker_text = tconcat(concat_list, '')
      if last_broker_text ~= new_broker_text then
         last_broker_text = new_broker_text
         broker.text = new_broker_text
      end
   end
end

local function GarrisonBuilding_UpdateAssignRemoveBuildings()
   wipe(assign_remove_buildings_list)
   local assign_remove_buildings_count = 0
   local buildings = c_garrison_cache.GetBuildings
   for idx = 1, #buildings do
      local building = buildings[idx]
      local buildingID = building.buildingID
      if buildingID then
         local plotID = building.plotID
         local possible_followers = C_Garrison.GetPossibleFollowersForBuilding(plotID)
         if possible_followers and #possible_followers > 0 then
            assign_remove_buildings_list[plotID] = possible_followers
            local id, name, texPrefix, icon, description, rank, currencyID, currencyQty, goldQty, buildTime, needsPlan, isPrebuilt, possSpecs, upgrades, canUpgrade, isMaxLevel, hasFollowerSlot, knownSpecs, currSpec, specCooldown, isBuilding, startTime, buildDuration, timeLeftStr, canActivate = C_Garrison.GetOwnedBuildingInfo(plotID)
            assign_remove_building_icons[plotID] = "|T" .. icon .. ":0|t"
            assign_remove_building_names[plotID] = name
            assign_remove_buildings_count = assign_remove_buildings_count + 1
         end
      end
   end
   GarrisonBuilding_UpdateAssignBestFollowers()
   GarrisonBuilding_UpdateCurrentFollowers()
end
addon_env.GarrisonBuilding_UpdateAssignRemoveBuildings = GarrisonBuilding_UpdateAssignRemoveBuildings

GarrisonBuilding_UpdateButtons = function ()
   if assign_remove_in_progress or assign_remove_buildings_count == 0 then
      gmm_buttons.remove_all_workers:Disable()
      gmm_buttons.assign_all_workers:Hide()
      gmm_buttons.assign_all_workers_disabled:Show()
   else
      if can_assign then
         gmm_buttons.assign_all_workers:Show()
         gmm_buttons.assign_all_workers:Enable()
         gmm_buttons.assign_all_workers_disabled:Hide()
      else
         if can_assign_busy then
            gmm_buttons.assign_all_workers:Hide()
            gmm_buttons.assign_all_workers_disabled:Show()
         else
            gmm_buttons.assign_all_workers:Show()
            gmm_buttons.assign_all_workers:Disable()
            gmm_buttons.assign_all_workers_disabled:Hide()
         end
      end

      if can_remove then
         gmm_buttons.remove_all_workers:Enable()
      else
         gmm_buttons.remove_all_workers:Disable()
      end
   end
end

local function GarrisonBuilding_HideTooltip()
   return GameTooltip:Hide()
end
addon_env.HideTooltip = GarrisonBuilding_HideTooltip

local function RemoveAllWorkers_TooltipSetText()
   wipe(concat_list)
   local idx = 0
   for plotID, followerName in pairs(assign_remove_current_followers) do
      if idx ~= 0 then 
         idx = idx + 1
         concat_list[idx] = "\n"
      end
      idx = idx + 1
      concat_list[idx] = assign_remove_building_icons[plotID]
      idx = idx + 1
      concat_list[idx] = followerName
      idx = idx + 1
      concat_list[idx] = " ("
      idx = idx + 1
      concat_list[idx] = assign_remove_building_names[plotID]
      idx = idx + 1
      concat_list[idx] = ")"
   end
   GameTooltip:SetText(tconcat(concat_list, ''))
end
addon_env.RemoveAllWorkers_TooltipSetText = RemoveAllWorkers_TooltipSetText

local function AssignAllWorkers_TooltipSetText()
   wipe(concat_list)
   local idx = 0
   for plotID, followerName in pairs(assign_remove_buildings_list) do
      if not assign_remove_current_followers[plotID] then
         local best_follower = assign_followers_best[plotID]
         if idx ~= 0 then 
            idx = idx + 1
            concat_list[idx] = "\n"
         end
         idx = idx + 1
         concat_list[idx] = assign_remove_building_icons[plotID]
         local status = assign_followers_status[plotID]
         if status then
            idx = idx + 1
            concat_list[idx] = RED_FONT_COLOR_CODE
         end
         idx = idx + 1
         concat_list[idx] = best_follower.name
         if status then
            idx = idx + 1
            concat_list[idx] = " - "
            idx = idx + 1
            concat_list[idx] = status
         end
         idx = idx + 1
         concat_list[idx] = " ("
         idx = idx + 1
         concat_list[idx] = assign_remove_building_names[plotID]
         idx = idx + 1
         concat_list[idx] = ")"
         if status then
            idx = idx + 1
            concat_list[idx] = FONT_COLOR_CODE_CLOSE
         end
      end
   end
   GameTooltip:SetText(tconcat(concat_list, ''))
end

local function AssignAllWorkers_TooltipShow(self)
   GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
   AssignAllWorkers_TooltipSetText()
   GameTooltip:Show()
end

local function RemoveAllWorkers_TooltipShow(self)
   GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
   RemoveAllWorkers_TooltipSetText()
   GameTooltip:Show()
end
addon_env.RemoveAllWorkers_TooltipShow = RemoveAllWorkers_TooltipShow

local function AssignRemove_PerformInit()
   PlaySound("gsTitleOptionOK")
   for event in pairs(events_for_buildings) do UnregisterEvent(event_frame, event) end
   assign_remove_in_progress = true
   GarrisonBuilding_UpdateButtons()
end

local function AssignRemove_PerformFinalize(sound)
   assign_remove_in_progress = nil
   GarrisonBuilding_UpdateCurrentFollowers()
   GarrisonBuilding_UpdateButtons()
   PlaySound(sound)
   GarrisonBuildingFrame_OnShow(GarrisonBuildingFrame)
   for event in pairs(events_for_buildings) do RegisterEvent(event_frame, event) end
end

local function AssignAllWorkers_Perform()
   assign_remove_in_progress = true
   if not can_assign then return end
   if not GarrisonBuildingFrame:IsVisible() then return end
   GarrisonBuilding_UpdateCurrentFollowers()
   local empty
   for plotID in pairs(assign_remove_buildings_list) do
      if not assign_remove_current_followers[plotID] then
         local best_follower = assign_followers_best[plotID]
         if not assign_followers_status[plotID] then
            empty = true
            AssignFollowerToBuilding(plotID, best_follower.followerID)
         end
      end
   end
   if not empty then
      AssignRemove_PerformFinalize("UI_Garrison_CommandTable_AssignFollower")
   else
      After(0.001, AssignAllWorkers_Perform)
   end
end

local function AssignAllWorkers()
   if not GarrisonBuildingFrame:IsVisible() then return end

   GarrisonBuilding_UpdateCurrentFollowers()
   if can_assign then
      AssignRemove_PerformInit()
      AssignAllWorkers_Perform()
   end
end

local function RemoveAllWorkers_Perform()
   if not can_remove then return end
   if not GarrisonBuildingFrame:IsVisible() then return end
   local empty = true
   GarrisonBuilding_UpdateCurrentFollowers()
   for plotID, followerName in pairs(assign_remove_current_followers) do
      if GetFollowerInfoForBuilding(plotID) then
         empty = false
         RemoveFollowerFromBuilding(plotID)
      end
   end
   if empty then
      AssignRemove_PerformFinalize("UI_Garrison_CommandTable_UnassignFollower")
   else
      After(0.001, RemoveAllWorkers_Perform)
   end
end

local function RemoveAllWorkers()
   if not GarrisonBuildingFrame:IsVisible() then return end

   GarrisonBuilding_UpdateCurrentFollowers()
   if can_remove then
      AssignRemove_PerformInit()
      RemoveAllWorkers_Perform()
   end
end

GarrisonBuildingFrame:HookScript("OnShow", function()
   assign_remove_in_progress = nil
   GarrisonBuilding_UpdateAssignRemoveBuildings()
   GarrisonBuilding_UpdateButtons()
   for event in pairs(events_for_buildings) do RegisterEvent(event_frame, event) end
end)

GarrisonBuildingFrame:HookScript("OnHide", function()
   for event in pairs(events_for_buildings) do UnregisterEvent(event_frame, event) end
end)

local function GarrisonBuilding_ButtonsInit()
   local anchor = GarrisonBuildingFrame

   -- "Disabled" pseudo-button that still shows tooltip
   local button = CreateFrame("Button", nil, anchor, "UIPanelButtonTemplate")
   button:SetText(GARRISON_FOLLOWERS)
   button:SetWidth(100)
   button:SetHeight(50)
   button:SetPoint("LEFT", anchor, "RIGHT", 0, 0)
   button:SetPoint("TOP", anchor.InfoBox, "TOP", 0, 0)
   button:SetScript('OnEnter', AssignAllWorkers_TooltipShow) 
   button:SetScript('OnLeave', GarrisonBuilding_HideTooltip)
   button:SetScript("OnMouseDown", nil)
   button:SetScript("OnMouseUp", nil)
   button:HookScript("OnShow", function(self) self:GetScript("OnDisable")(self) end)
   gmm_buttons['assign_all_workers_disabled'] = button

   local button = CreateFrame("Button", nil, anchor, "UIPanelButtonTemplate")
   button:SetText(GARRISON_FOLLOWERS)
   button:SetWidth(100)
   button:SetHeight(50)
   button:SetPoint("LEFT", anchor, "RIGHT", 0, 0)
   button:SetPoint("TOP", anchor.InfoBox, "TOP", 0, 0)
   button:SetScript('OnClick', AssignAllWorkers)
   button:SetScript('OnEnter', AssignAllWorkers_TooltipShow)
   button:SetScript('OnLeave', GarrisonBuilding_HideTooltip)
   gmm_buttons['assign_all_workers'] = button
   local prev = button

   local button = CreateFrame("Button", nil, anchor, "UIPanelButtonTemplate")
   button:SetText(REMOVE)
   button:SetWidth(100)
   button:SetHeight(50)
   button:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 0)
   button:SetScript('OnClick', RemoveAllWorkers)
   button:SetScript('OnEnter', RemoveAllWorkers_TooltipShow)
   button:SetScript('OnLeave', GarrisonBuilding_HideTooltip)
   gmm_buttons['remove_all_workers'] = button
end

GarrisonBuilding_ButtonsInit()
addon_env.GarrisonBuilding_UpdateCurrentFollowers = GarrisonBuilding_UpdateCurrentFollowers
addon_env.GarrisonBuilding_UpdateButtons = GarrisonBuilding_UpdateButtons
