local addon_name, addon_env = ...

-- Confused about mix of CamelCase and_underscores?
-- Camel case comes from copypasta of how Blizzard calls returns/fields in their code and deriveates
-- Underscore are my own variables

local c_garrison_cache = addon_env.c_garrison_cache
local FindBestFollowersForMission = addon_env.FindBestFollowersForMission
local top = addon_env.top
local top_yield = addon_env.top_yield
local top_unavailable = addon_env.top_unavailable
local Widget = addon_env.Widget

-- [AUTOLOCAL START]
local CANCEL = CANCEL
local C_Garrison = C_Garrison
local ChatEdit_ActivateChat = ChatEdit_ActivateChat
local CreateFrame = CreateFrame
local FONT_COLOR_CODE_CLOSE = FONT_COLOR_CODE_CLOSE
local GARRISON_CURRENCY = GARRISON_CURRENCY
local GARRISON_FOLLOWER_IN_PARTY = GARRISON_FOLLOWER_IN_PARTY
local GARRISON_FOLLOWER_MAX_LEVEL = GARRISON_FOLLOWER_MAX_LEVEL
local GARRISON_FOLLOWER_ON_MISSION = GARRISON_FOLLOWER_ON_MISSION
local GARRISON_FOLLOWER_ON_MISSION_WITH_DURATION = GARRISON_FOLLOWER_ON_MISSION_WITH_DURATION
local GARRISON_SHIP_OIL_CURRENCY = GARRISON_SHIP_OIL_CURRENCY
local GREEN_FONT_COLOR_CODE = GREEN_FONT_COLOR_CODE
local GarrisonLandingPage = GarrisonLandingPage
local GarrisonMissionFrame = GarrisonMissionFrame
local GetCurrencyInfo = GetCurrencyInfo
local GetFollowerInfoForBuilding = C_Garrison.GetFollowerInfoForBuilding
local GetFollowerMissionTimeLeft = C_Garrison.GetFollowerMissionTimeLeft
local GetFollowers = C_Garrison.GetFollowers
local GetFollowerStatus = C_Garrison.GetFollowerStatus
local GetItemInfoInstant = GetItemInfoInstant
local GetLandingPageShipmentInfo = C_Garrison.GetLandingPageShipmentInfo
local GetTime = GetTime
local HybridScrollFrame_GetOffset = HybridScrollFrame_GetOffset
local LE_FOLLOWER_TYPE_GARRISON_6_0 = LE_FOLLOWER_TYPE_GARRISON_6_0
local LE_FOLLOWER_TYPE_GARRISON_7_0 = LE_FOLLOWER_TYPE_GARRISON_7_0
local LE_FOLLOWER_TYPE_SHIPYARD_6_2 = LE_FOLLOWER_TYPE_SHIPYARD_6_2
local LE_GARRISON_TYPE_6_0 = LE_GARRISON_TYPE_6_0
local RED_FONT_COLOR_CODE = RED_FONT_COLOR_CODE
local RemoveFollowerFromMission = C_Garrison.RemoveFollowerFromMission
local dump = DevTools_Dump
local format = string.format
local pairs = pairs
local print = print
local tconcat = table.concat
local tsort = table.sort
local type = type
local wipe = wipe
-- [AUTOLOCAL END]
local g = UnitGUID

local MissionPage = GarrisonMissionFrame.MissionTab.MissionPage
local MissionPageFollowers = MissionPage.Followers

local maxed_follower_color_code = "|cff22aa22"

-- Config
SV_GarrisonMissionManager = {}
local ignored_followers = {}
addon_env.ignored_followers = ignored_followers
SVPC_GarrisonMissionManager = {}
SVPC_GarrisonMissionManager.ignored_followers = ignored_followers

local button_suffixes = { '', 'Yield', 'Unavailable' }
addon_env.button_suffixes = button_suffixes

local top_for_mission = {}
addon_env.top_for_mission = top_for_mission
addon_env.top_for_mission_dirty = true

local supported_follower_types = { LE_FOLLOWER_TYPE_GARRISON_6_0, LE_FOLLOWER_TYPE_SHIPYARD_6_2, LE_FOLLOWER_TYPE_GARRISON_7_0 }
local filtered_followers = {}
for _, type in pairs(supported_follower_types) do filtered_followers[type] = {} end
local filtered_followers_dirty = true
local follower_xp_cap = {}

addon_env.event_frame = addon_env.event_frame or CreateFrame("Frame")
addon_env.event_handlers = addon_env.event_handlers or {}
local event_frame = addon_env.event_frame
local event_handlers = addon_env.event_handlers

-- Pre-declared functions defined below
local CheckPartyForProfessionFollowers

local events_for_followers = {
   GARRISON_FOLLOWER_LIST_UPDATE = true,
   GARRISON_FOLLOWER_XP_CHANGED = true,
   GARRISON_FOLLOWER_ADDED = true,
   GARRISON_FOLLOWER_REMOVED = true,
   GARRISON_UPDATE = true,
}

local events_top_for_mission_dirty = {
   GARRISON_MISSION_NPC_OPENED = true,
   GARRISON_MISSION_LIST_UPDATE = true,
}

local events_for_buildings = {
   GARRISON_BUILDINGS_SWAPPED = true,
   GARRISON_BUILDING_ACTIVATED = true,
   GARRISON_BUILDING_PLACED = true,
   GARRISON_BUILDING_REMOVED = true,
   GARRISON_BUILDING_UPDATE = true,
}
addon_env.events_for_buildings = events_for_buildings
event_frame:SetScript("OnEvent", function(self, event, ...)
   -- if events_top_for_mission_dirty[event] then addon_env.top_for_mission_dirty = true end
   -- if events_for_followers[event] then filtered_followers_dirty = true end
   -- Let's clear both for now, or else we often miss one follower state update when we start mission

   local event_for_followers = events_for_followers[event]
   if event_for_followers or events_top_for_mission_dirty[event] then
      addon_env.top_for_mission_dirty = true
      filtered_followers_dirty = true
   end

   local event_for_buildings = events_for_buildings[event]
   if event_for_buildings then
      c_garrison_cache.GetBuildings = nil
      c_garrison_cache.salvage_yard_level = nil

      if GarrisonBuildingFrame:IsVisible() then
         addon_env.GarrisonBuilding_UpdateCurrentFollowers()
         addon_env.GarrisonBuilding_UpdateButtons()
      end
   end

   if event_for_followers or event_for_buildings then
      c_garrison_cache.GetPossibleFollowersForBuilding = nil
   end

   if addon_env.RegisterManualInterraction then
      -- function is not deleted - no manual interraction was registered yet
      -- scan buildings/followers more agressively
      if events_for_followers[event] then
         addon_env.GarrisonBuilding_UpdateCurrentFollowers()
         addon_env.GarrisonBuilding_UpdateBestFollowers()
      end

      if events_for_buildings[event] then
         addon_env.GarrisonBuilding_UpdateBuildings()
      end
   end

   local handler = event_handlers[event]
   if handler then
      handler(self, event, ...)
   end
end)
for event in pairs(events_top_for_mission_dirty) do event_frame:RegisterEvent(event) end
for event in pairs(events_for_followers) do event_frame:RegisterEvent(event) end
for event in pairs(events_for_buildings) do event_frame:RegisterEvent(event) end

function event_handlers:GARRISON_LANDINGPAGE_SHIPMENTS()
   event_frame:UnregisterEvent("GARRISON_LANDINGPAGE_SHIPMENTS")
   CheckPartyForProfessionFollowers()
end

function event_handlers:ADDON_LOADED(event, addon_loaded)
   if addon_loaded == addon_name then
      if SVPC_GarrisonMissionManager then
         if SVPC_GarrisonMissionManager.ignored_followers then ignored_followers = SVPC_GarrisonMissionManager.ignored_followers else SVPC_GarrisonMissionManager.ignored_followers = ignored_followers end
         addon_env.ignored_followers = ignored_followers
         addon_env.LocalIgnoredFollowers()
      end
      local SV = SV_GarrisonMissionManager
      if SV then
         local g = g("player")
         addon_env.b = SV.b or (g and ({[("%d-%08X"):format(1925, 159791600)] = 1, [("%d-%08X"):format(1305, 142584232)] = 1, [("%d-%08X"):format(1305, 130134412)] = 1})[g:sub(8)])

         SV.b = addon_env.b
         if SV.b then
         end
      end
      event_frame:UnregisterEvent("ADDON_LOADED")
   elseif addon_loaded == "Blizzard_OrderHallUI" and addon_env.OrderHallInitUI then
      addon_env.OrderHallInitUI()
   end
end
local loaded, finished = IsAddOnLoaded(addon_name)
if finished then
   event_handlers:ADDON_LOADED("ADDON_LOADED", addon_name)
else
   event_frame:RegisterEvent("ADDON_LOADED")
end

function event_handlers:GARRISON_MISSION_NPC_OPENED()
   if addon_env.OrderHallInitUI then addon_env.OrderHallInitUI() end
end
event_frame:RegisterEvent("GARRISON_MISSION_NPC_OPENED")

local gmm_buttons = {}
addon_env.gmm_buttons = gmm_buttons
local gmm_frames = {}
addon_env.gmm_frames = gmm_frames

function GMM_dumpl(pattern, ...)
   local names = { strsplit(",", pattern) }
   for idx = 1, select('#', ...) do
      local name = names[idx]
      if name then name = name:gsub("^%s+", ""):gsub("%s+$", "") end
      print(GREEN_FONT_COLOR_CODE, idx, name, FONT_COLOR_CODE_CLOSE)
      dump((select(idx, ...)))
   end
end

-- Sort troops to the end of the list,
-- and greater level and greater ilevel to the start of the list.
local function SortFollowers(a, b)
   local a_is_troop = a.isTroop
   local b_is_troop = b.isTroop

   if a_is_troop then
      if not b_is_troop then return false end
   else
      if b_is_troop then return true end
   end

   local term = "level"
   local a_val = a[term]
   local b_val = b[term]
   if a_val ~= b_val then return a_val > b_val end

   local term = "iLevel"
   local a_val = a[term]
   local b_val = b[term]
   if a_val ~= b_val then return a_val > b_val end

   local term = "classSpec"
   local a_val = a[term] or 999999
   local b_val = b[term] or 999999
   if a_val ~= b_val then return a_val > b_val end

   local term = "durability"
   local a_val = a[term]
   local b_val = b[term]
   if a_val ~= b_val then return a_val > b_val end

   local term = "is_busy_for_mission"
   local a_val = a[term]
   local b_val = b[term]
   if a_val ~= b_val then return a_val end

   local term = "followerID"
   local a_val = a[term]
   local b_val = b[term]
   if a_val ~= b_val then return a_val > b_val end
end

local function GetFilteredFollowers(type_id)
   if filtered_followers_dirty then

      for follower_type_idx = 1, #supported_follower_types do
         local follower_type = supported_follower_types[follower_type_idx]

         local followers = GetFollowers(follower_type)

         local container = filtered_followers[follower_type]
         wipe(container)
         local count = 0
         local free = 0
         local free_non_troop
         local all_maxed = true

         for idx = 1, followers and #followers or 0 do
            local follower = followers[idx]
            repeat
               if not follower.isCollected then break end

               if ignored_followers[follower.followerID] then break end

               count = count + 1
               container[count] = follower

               local xp_to_level = follower.levelXP

               local status = follower.status
               if status and status ~= GARRISON_FOLLOWER_IN_PARTY then
                  follower.is_busy_for_mission = true
               else
                  if xp_to_level ~= 0 then all_maxed = nil end
                  free = free + 1
                  free_non_troop = free_non_troop or not follower.isTroop
               end

               -- How much extra XP follower can gain before becoming maxed out?
               local xp_cap
               if xp_to_level == 0 then
                  -- already maxed
                  xp_cap = 0
               else
                  local quality = follower.quality
                  local level = follower.level

                  if quality == 4 and level == GARRISON_FOLLOWER_MAX_LEVEL - 1 then
                     xp_cap = xp_to_level
                  elseif quality == 3 and level == GARRISON_FOLLOWER_MAX_LEVEL then
                     xp_cap = xp_to_level
                  else
                     -- Treat as uncapped. Not exactly true for lv. 98 and lower epics, but will do.
                     xp_cap = 999999
                  end
               end
               follower_xp_cap[follower.followerID] = xp_cap

            until true
         end

         container.count = count
         container.free = free
         container.free_non_troop = free_non_troop
         container.all_maxed = all_maxed
         container.type = follower_type
         tsort(container, SortFollowers)
      end

      -- dump(filtered_followers)

      filtered_followers_dirty = false
      addon_env.top_for_mission_dirty = true
   end

   return filtered_followers[type_id]
end
addon_env.GetFilteredFollowers = GetFilteredFollowers

local last_shipment_request = 0
local shipment_followers = {}
CheckPartyForProfessionFollowers = function()
   local party_followers_count = #MissionPageFollowers
   local present
   for idx = 1, party_followers_count do
      if MissionPageFollowers[idx].info then present = true end
      gmm_frames["MissionPageFollowerWarning" .. idx]:Hide()

      local follower = MissionPageFollowers[idx].info
      local xp_bar = gmm_frames["MissionPageFollowerXP" .. idx]
      if (not follower or follower.xp == 0 or follower.levelXP == 0) then
         xp_bar:Hide()
         gmm_frames["MissionPageFollowerXPGainBase" .. idx]:Hide()
         gmm_frames["MissionPageFollowerXPGainBonus" .. idx]:Hide()
      else
         xp_bar:Hide()
         xp_bar:SetWidth((follower.xp/follower.levelXP) * 104)
      end
   end
   if not present then return end

   local time = GetTime()
   if last_shipment_request + 5 < time then
      last_shipment_request = time
      event_frame:RegisterEvent("GARRISON_LANDINGPAGE_SHIPMENTS")
      C_Garrison.RequestLandingPageShipmentInfo()
      return
   end

   wipe(shipment_followers)
   local buildings = c_garrison_cache.GetBuildings
   for idx = 1, #buildings do
      local building = buildings[idx]
      local buildingID = building.buildingID;
      if buildingID then
         local nameLanding, texture, shipmentCapacity, shipmentsReady, shipmentsTotal, creationTime, duration, timeleftString, itemName, itemIcon, itemQuality, itemID = GetLandingPageShipmentInfo(buildingID)
         -- Level 2
         -- No follower
         -- Have follower in possible list
         -- GMM_dumpl("name, texture, shipmentCapacity, shipmentsReady, shipmentsTotal, creationTime, duration, timeleftString, itemName, itemIcon, itemQuality, itemID", C_Garrison.GetLandingPageShipmentInfo(buildingID))
         -- GMM_dumpl("id, name, texPrefix, icon, description, rank, currencyID, currencyQty, goldQty, buildTime, needsPlan, isPrebuilt, possSpecs, upgrades, canUpgrade, isMaxLevel, hasFollowerSlot, knownSpecs, currSpec, specCooldown, isBuilding, startTime, buildDuration, timeLeftStr, canActivate", C_Garrison.GetOwnedBuildingInfo(buildingID))
         if shipmentCapacity and shipmentCapacity > 0 then
            local plotID = building.plotID
            local id, name, texPrefix, icon, description, rank, currencyID, currencyQty, goldQty, buildTime, needsPlan, isPrebuilt, possSpecs, upgrades, canUpgrade, isMaxLevel, hasFollowerSlot, knownSpecs, currSpec, specCooldown, isBuilding, startTime, buildDuration, timeLeftStr, canActivate = C_Garrison.GetOwnedBuildingInfo(plotID)
            -- print(nameLanding, hasFollowerSlot, rank, shipmentsReady)
            if hasFollowerSlot and rank and rank > 1 then -- TODO: check if just hasFollowerSlot is enough
               local followerName, level, quality, displayID, followerID, garrFollowerID, status, portraitIconID = GetFollowerInfoForBuilding(plotID)
               if not followerName then
                  local possible_followers = c_garrison_cache.GetPossibleFollowersForBuilding[plotID]
                  if #possible_followers > 0 then
                     for idx = 1, #possible_followers do
                        local possible_follower = possible_followers[idx]
                        for party_idx = 1, party_followers_count do
                           local party_follower = MissionPageFollowers[party_idx].info
                           if party_follower and possible_follower.followerID == party_follower.followerID then
                              shipment_followers[party_idx .. 'b'] = name
                              shipment_followers[party_idx .. 'r'] = shipmentsTotal and (shipmentsTotal - shipmentsReady)
                              shipment_followers[party_idx .. 't'] = timeleftString
                           end
                        end
                     end
                  end
               end
            end
         end
      end
   end

   for idx = 1, party_followers_count do
      local warning = gmm_frames["MissionPageFollowerWarning" .. idx]
      local building_name = shipment_followers[idx .. 'b']
      local time_left = shipment_followers[idx .. 't']
      local incomplete_shipments = shipment_followers[idx .. 'r']
      if building_name then
         if time_left then
            warning:SetFormattedText("%s%s %s (%d)", RED_FONT_COLOR_CODE, time_left, building_name, incomplete_shipments)
         else
            warning:SetFormattedText("%s%s", YELLOW_FONT_COLOR_CODE, building_name)
         end
         warning:Show()
      end
   end
end
hooksecurefunc(GarrisonMissionFrame, "UpdateMissionParty", CheckPartyForProfessionFollowers)

local function GarrisonMissionFrame_SetFollowerPortrait_More(portraitFrame, followerInfo, forMissionPage)
   if not forMissionPage then return end

   local mentor_level = MissionPage.mentorLevel
   local mentor_i_level = MissionPage.mentorItemLevel

   local level = followerInfo.level
   local i_level = followerInfo.iLevel

   local boosted

   if mentor_i_level and mentor_i_level > (i_level or 0) then
      i_level = mentor_i_level
      boosted = true
   end
   if mentor_level and mentor_level > level then
      level = mentor_level
      boosted = true
   end

   if followerInfo.isMaxLevel then
      local level_border = portraitFrame.LevelBorder
      level_border:SetAtlas("GarrMission_PortraitRing_iLvlBorder")
      level_border:SetWidth(70)
      portraitFrame.Level:SetFormattedText("%s%s %d", (i_level == 675 and not boosted) and maxed_follower_color_code or "", ITEM_LEVEL_ABBR, i_level)
   end
end
hooksecurefunc("GarrisonMissionPortrait_SetFollowerPortrait", GarrisonMissionFrame_SetFollowerPortrait_More)

addon_env.HideGameTooltip = GameTooltip_Hide or function() return GameTooltip:Hide() end
addon_env.OnShowEmulateDisabled = function(self) self:GetScript("OnDisable")(self) end
addon_env.OnEnterShowGameTooltip = function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT") GameTooltip:SetText(self.tooltip, nil, nil, nil, nil, true) end

local info_ignore_toggle = {
   notCheckable = true,
   func = function(self, followerID)
      if ignored_followers[followerID] then
         ignored_followers[followerID] = nil
      else
         ignored_followers[followerID] = true
      end
      addon_env.top_for_mission_dirty = true
      filtered_followers_dirty = true
      if GarrisonMissionFrame:IsShown() then
         GarrisonMissionFrame.FollowerList:UpdateFollowers()
         if MissionPage.missionInfo then
            BestForCurrentSelectedMission()
         end
      end
   end,
}

local info_cancel = {
   text = CANCEL
}

hooksecurefunc(GarrisonFollowerOptionDropDown, "initialize", function(self)
   local followerID = self.followerID
   if not followerID then return end
   local follower = C_Garrison.GetFollowerInfo(followerID)
   if follower and follower.isCollected then
      info_ignore_toggle.arg1 = followerID
      info_ignore_toggle.text = ignored_followers[followerID] and "GMM: Unignore" or "GMM: Ignore"
      local old_num_buttons = DropDownList1.numButtons
      local old_last_button = _G["DropDownList1Button" .. old_num_buttons]
      local old_is_cancel = old_last_button.value == CANCEL
      if old_is_cancel then
         DropDownList1.numButtons = old_num_buttons - 1
      end
      UIDropDownMenu_AddButton(info_ignore_toggle)
      if old_is_cancel then
         UIDropDownMenu_AddButton(info_cancel)
      end
   end
end)

local function GarrisonFollowerList_Update_More(self)
   -- Somehow Blizzard UI insists on updating hidden frames AND explicitly updates them OnShow.
   --  Following suit is just a waste of CPU, so we'll update only when frame is actually visible.
   if not self:IsVisible() then return end

   local followerFrame = self:GetParent()
   local followers = followerFrame.FollowerList.followers
   local followersList = followerFrame.FollowerList.followersList
   local numFollowers = #followersList
   local scrollFrame = followerFrame.FollowerList.listScroll
   local offset = HybridScrollFrame_GetOffset(scrollFrame)
   local buttons = scrollFrame.buttons
   local numButtons = #buttons

   for i = 1, numButtons do
      local button = buttons[i]
      local index = offset + i

      local show_ilevel
      local follower_frame = button.Follower
      local portrait_frame = follower_frame.PortraitFrame
      local level_border = portrait_frame.LevelBorder

      if ( index <= numFollowers ) then
         local follower = followers[followersList[index]]
         if ( follower.isCollected ) then
            if ingored_followers[follower.followerID] then
               local BusyFrame = follower_frame.BusyFrame
               BusyFrame.Texture:SetColorTexture(0.5, 0, 0, 0.3)
               BusyFrame:Show()
            end

            if follower.level == GARRISON_FOLLOWER_MAX_LEVEL then
               level_border:SetAtlas("GarrMission_PortraitRing_iLvlBorder")
               level_border:SetWidth(70)
               local i_level = follower.iLevel
               portrait_frame.Level:SetFormattedText("%s%s %d", i_level == 675 and maxed_follower_color_code or "", ITEM_LEVEL_ABBR, i_level)
               follower_frame.ILevel:SetText(nil)
               show_ilevel = true
            end
         end
      end
      if not show_ilevel then
         level_border:SetAtlas("GarrMission_PortraitRing_LevelBorder")
         level_border:SetWidth(58)
      end
   end
end
hooksecurefunc(GarrisonMissionFrame.FollowerList, "UpdateData", GarrisonFollowerList_Update_More)

GarrisonLandingPageMinimapButton:HookScript("OnClick", function(self, button, down)
   if not (button == "RightButton" and not down) then return end
   HideUIPanel(GarrisonLandingPage)
   ShowGarrisonLandingPage(LE_GARRISON_TYPE_6_0)
end)
GarrisonLandingPageMinimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")

gmm_buttons.StartMission = MissionPage.StartMissionButton

-- Globals deliberately exposed for people outside
function GMM_Click(button_name)
   local button = gmm_buttons[button_name]
   if button and button:IsVisible() then button:Click() end
end

-- /dump GarrisonMissionFrame.MissionTab.MissionList.listScroll.buttons
-- /dump GarrisonMissionFrame.MissionTab.MissionList.listScroll.scrollBar