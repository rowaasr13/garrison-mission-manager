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
local After = C_Timer.After
local CANCEL = CANCEL
local C_Garrison = C_Garrison
local ChatEdit_ActivateChat = ChatEdit_ActivateChat
local FONT_COLOR_CODE_CLOSE = FONT_COLOR_CODE_CLOSE
local GARRISON_CURRENCY = GARRISON_CURRENCY
local GARRISON_FOLLOWER_IN_PARTY = GARRISON_FOLLOWER_IN_PARTY
local GARRISON_FOLLOWER_MAX_LEVEL = GARRISON_FOLLOWER_MAX_LEVEL
local GARRISON_FOLLOWER_ON_MISSION = GARRISON_FOLLOWER_ON_MISSION
local GARRISON_FOLLOWER_ON_MISSION_WITH_DURATION = GARRISON_FOLLOWER_ON_MISSION_WITH_DURATION
local GREEN_FONT_COLOR_CODE = GREEN_FONT_COLOR_CODE
local LE_FOLLOWER_TYPE_GARRISON_6_0 = LE_FOLLOWER_TYPE_GARRISON_6_0
local LE_FOLLOWER_TYPE_SHIPYARD_6_2 = LE_FOLLOWER_TYPE_SHIPYARD_6_2
local GarrisonMissionFrame = GarrisonMissionFrame
local GetCurrencyInfo = GetCurrencyInfo
local GetFollowerInfoForBuilding = C_Garrison.GetFollowerInfoForBuilding
local GetFollowerMissionTimeLeft = C_Garrison.GetFollowerMissionTimeLeft
local GetFollowerStatus = C_Garrison.GetFollowerStatus
local GetItemInfo = GetItemInfo
local GetLandingPageShipmentInfo = C_Garrison.GetLandingPageShipmentInfo
local HybridScrollFrame_GetOffset = HybridScrollFrame_GetOffset
local RED_FONT_COLOR_CODE = RED_FONT_COLOR_CODE
local dump = DevTools_Dump
local format = string.format
local pairs = pairs
local tconcat = table.concat
local tsort = table.sort
local wipe = wipe
-- [AUTOLOCAL END]

local MissionPage = GarrisonMissionFrame.MissionTab.MissionPage
local MissionPageFollowers = MissionPage.Followers

local maxed_follower_color_code = "|cff22aa22"

-- Config
local ingored_followers = {}
SVPC_GarrisonMissionManager = {}
SVPC_GarrisonMissionManager.ingored_followers = ingored_followers

local currency_texture = {}
for _, currency in pairs({ GARRISON_CURRENCY, GARRISON_SHIP_OIL_CURRENCY, 823 --[[Apexis]] }) do
   local _, _, texture = GetCurrencyInfo(currency)
   currency_texture[currency] = "|T" .. texture .. ":0|t"
end

local time_texture = "|TInterface\\Icons\\spell_holy_borrowedtime:0|t"

local hardcoded_salvage_textures = {
   [114116] = "Interface\\ICONS\\INV_Misc_Bag_12.blp",
   [114119] = "Interface\\ICONS\\INV_Crate_01.blp",
   [114120] = "Interface\\ICONS\\INV_Eng_Crate2.blp",
}
local salvage_textures = setmetatable({}, { __index = function(t, key)
   local item_id
   if key == "bag" then
      item_id = 114116
   elseif key == "crate" then
      item_id = 114119
   elseif key == "big_crate" then
      item_id = 114120
   end

   if item_id then
      local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, itemSellPrice = GetItemInfo(item_id)
      if not itemTexture then
         return "|T" .. hardcoded_salvage_textures[item_id] .. ":0|t"
      end
      itemTexture = "|T" .. itemTexture .. ":0|t"
      t[key] = itemTexture
      return itemTexture
   end
   return --[[ some default texture ]]
end})

local button_suffixes = { '', 'Yield', 'Unavailable' }

local top_for_mission = {}
addon_env.top_for_mission = top_for_mission
addon_env.top_for_mission_dirty = true

local filtered_followers = {
   [LE_FOLLOWER_TYPE_GARRISON_6_0] = {},
   [LE_FOLLOWER_TYPE_SHIPYARD_6_2] = {},
}
local filtered_followers_dirty = true
local follower_xp_cap = {}

addon_env.event_frame = addon_env.event_frame or CreateFrame("Frame")
addon_env.event_handlers = addon_env.event_handlers or {}
local event_frame = addon_env.event_frame
local event_handlers = addon_env.event_handlers

-- Pre-declared functions defined below
local CheckPartyForProfessionFollowers
local MissionPage_PartyButtonOnClick

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
         ingored_followers = SVPC_GarrisonMissionManager.ingored_followers
      end
      event_frame:UnregisterEvent("ADDON_LOADED")
   end
end
local loaded, finished = IsAddOnLoaded(addon_name)
if finished then
   event_handlers:ADDON_LOADED("ADDON_LOADED", addon_name)
else
   event_frame:RegisterEvent("ADDON_LOADED")
end

local gmm_buttons = {}
addon_env.gmm_buttons = gmm_buttons
local gmm_frames = {}

function GMM_dumpl(pattern, ...)
   local names = { strsplit(",", pattern) }
   for idx = 1, select('#', ...) do
      local name = names[idx]
      if name then name = name:gsub("^%s+", ""):gsub("%s+$", "") end
      print(GREEN_FONT_COLOR_CODE, idx, name, FONT_COLOR_CODE_CLOSE)
      dump((select(idx, ...)))
   end
end

-- easy hooking for similar old style (functional) and new style (class-like) functions
-- returns true on hooking class
local function PostHookFunctionOrClass(old_function, new_class, new_method, post_hook)
   if new_class then
      local new_class_table = type(new_class) == "string" and _G[new_class] or new_class
      if new_class_table and new_class_table[new_method] then
         -- print("GMM: hooking", new_class, new_method)
         hooksecurefunc(new_class_table, new_method, post_hook)
         return true
      end
   end

   -- print("GMM: hooking", old_function)
   hooksecurefunc(old_function, post_hook)
end

local function SortFollowersByLevel(a, b)
   local a_level = a.level
   local b_level = b.level
   if a_level ~= b_level then return a_level > b_level end
   return a.iLevel > b.iLevel
end

local function GetFilteredFollowers(type_id)
   if filtered_followers_dirty then
      local followers = C_Garrison.GetFollowers()

      local container = filtered_followers[LE_FOLLOWER_TYPE_GARRISON_6_0]
      wipe(container)
      container.count = 0
      container.free = 0
      container.all_maxed = true

      local container = filtered_followers[LE_FOLLOWER_TYPE_SHIPYARD_6_2]
      wipe(container)
      container.count = 0
      container.free = 0
      container.all_maxed = true

      for idx = 1, #followers do
         local follower = followers[idx]
         repeat
            if not follower.isCollected then break end

            if ingored_followers[follower.followerID] then break end

            local type_id = follower.followerTypeID
            local container = filtered_followers[type_id]

            local count = container.count count = count + 1 container.count = count
            container[count] = follower

            local xp_to_level = follower.levelXP

            local status = follower.status
            if status and status ~= GARRISON_FOLLOWER_IN_PARTY then
               follower.is_busy_for_mission = true
            else
               if xp_to_level ~= 0 then container.all_maxed = nil end
               container.free = container.free + 1
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
      tsort(filtered_followers[LE_FOLLOWER_TYPE_GARRISON_6_0], SortFollowersByLevel)
      tsort(filtered_followers[LE_FOLLOWER_TYPE_SHIPYARD_6_2], SortFollowersByLevel)

      -- dump(filtered_followers)

      filtered_followers_dirty = false
      addon_env.top_for_mission_dirty = true
   end

   return filtered_followers[type_id]
end
addon_env.GetFilteredFollowers = GetFilteredFollowers

local function SetTeamButtonText(button, top_entry)
   if top_entry.successChance then
      local xp_bonus, xp_bonus_icon
      if top_entry.xp_reward_wasted then
         local salvage_yard_level = c_garrison_cache.salvage_yard_level
         xp_bonus = ''
         if salvage_yard_level == 1 or top_entry.mission_level <= 94 then
            xp_bonus_icon = salvage_textures.bag
         elseif salvage_yard_level == 2 then
            xp_bonus_icon =  salvage_textures.crate
         elseif salvage_yard_level == 3 then
            xp_bonus_icon = salvage_textures.big_crate
         end
      else
         xp_bonus = top_entry.xpBonus
         if xp_bonus == 0 or top_entry.all_followers_maxed then
            xp_bonus = ''
            xp_bonus_icon = ''
         else
            xp_bonus_icon = " |TInterface\\Icons\\XPBonus_Icon:0|t"
         end
      end

      local multiplier, multiplier_icon = "", ""
      if top_entry.gold_rewards and top_entry.goldMultiplier > 1 then
         multiplier = top_entry.goldMultiplier
         multiplier_icon = "|TInterface\\MoneyFrame\\UI-GoldIcon:0|t"
      elseif top_entry.material_rewards and top_entry.materialMultiplier > 1 then
         multiplier = top_entry.materialMultiplier
         multiplier_icon = currency_texture[top_entry.material_rewards]
      end

      button:SetFormattedText(
         "%d%%\n%s%s%s%s%s",
         top_entry.successChance,
         xp_bonus, xp_bonus_icon,
         multiplier, multiplier_icon,
         top_entry.isMissionTimeImproved and time_texture or ""
      )
   else
      button:SetText()
   end
end

addon_env.concat_list = addon_env.concat_list or {}
local concat_list = addon_env.concat_list
local function SetTeamButtonTooltip(button)
   local followers = #button

   if followers > 0 then
      wipe(concat_list)
      local idx = 0

      for follower_idx = 1, #button do
         local follower = button[follower_idx]
         local name = button["name" .. follower_idx]
         local status = GetFollowerStatus(follower)
         if status == GARRISON_FOLLOWER_ON_MISSION then
            status = format(GARRISON_FOLLOWER_ON_MISSION_WITH_DURATION, GetFollowerMissionTimeLeft(follower))
         elseif status == GARRISON_FOLLOWER_IN_PARTY then
            status = nil
         end

         if idx ~= 0 then
            idx = idx + 1
            concat_list[idx] = "\n"
         end

         if status then
            idx = idx + 1
            concat_list[idx] = RED_FONT_COLOR_CODE
         end

         idx = idx + 1
         concat_list[idx] = name

         if status and status ~= GARRISON_FOLLOWER_IN_PARTY then
            idx = idx + 1
            concat_list[idx] = " ("
            idx = idx + 1
            concat_list[idx] = status
            idx = idx + 1
            concat_list[idx] = ")"
            idx = idx + 1
            concat_list[idx] = FONT_COLOR_CODE_CLOSE
         end
      end

      GameTooltip:SetOwner(button, "ANCHOR_CURSOR_RIGHT")
      GameTooltip:SetText(tconcat(concat_list, ''))
      GameTooltip:Show()
   end
end

local available_missions = {}
local function BestForCurrentSelectedMission(type_id, mission_page, button_prefix)
   if addon_env.RegisterManualInterraction then addon_env.RegisterManualInterraction() end

   local missionInfo = mission_page.missionInfo
   local mission_id = missionInfo.missionID

   -- print("Mission ID:", mission_id)

   local filtered_followers = GetFilteredFollowers(type_id)

   local mission = missionInfo

   -- dump(mission)

   FindBestFollowersForMission(mission, filtered_followers)

   for suffix_idx = 1, #button_suffixes do
      local suffix = button_suffixes[suffix_idx]
      for idx = 1, 3 do
         local button = gmm_buttons[button_prefix .. suffix .. idx]
         local top_entry
         if suffix == 'Yield' then
            if top.material_rewards or top.gold_rewards then
               top_entry = top_yield[idx]
            else
               top_entry = false
            end
         elseif suffix == 'Unavailable' then
            top_entry = top_unavailable[idx]
         else
            top_entry = top[idx]
         end

         if top_entry ~= false then
            local follower = top_entry[1] if follower then button[1] = follower.followerID button.name1 = follower.name else button[1] = nil end
            local follower = top_entry[2] if follower then button[2] = follower.followerID button.name2 = follower.name else button[2] = nil end
            local follower = top_entry[3] if follower then button[3] = follower.followerID button.name3 = follower.name else button[3] = nil end
            SetTeamButtonText(button, top_entry)
            button:Show()
         else
            button:Hide()
         end
      end
   end

   if addon_env.mission_page_pending_click then
      MissionPage_PartyButtonOnClick(gmm_buttons[addon_env.mission_page_pending_click])
      addon_env.mission_page_pending_click = nil
   end
end
addon_env.BestForCurrentSelectedMission = BestForCurrentSelectedMission

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

local GarrisonFollowerMission_class_UpdateMissionParty = PostHookFunctionOrClass("GarrisonMissionPage_UpdateMissionForParty", "GarrisonMissionFrame", "UpdateMissionParty", CheckPartyForProfessionFollowers)

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

   if level == GARRISON_FOLLOWER_MAX_LEVEL then
      local level_border = portraitFrame.LevelBorder
      level_border:SetAtlas("GarrMission_PortraitRing_iLvlBorder")
      level_border:SetWidth(70)
      portraitFrame.Level:SetFormattedText("%s%s %d", (i_level == 675 and not boosted) and maxed_follower_color_code or "", ITEM_LEVEL_ABBR, i_level)
   end
end
hooksecurefunc("GarrisonMissionFrame_SetFollowerPortrait", GarrisonMissionFrame_SetFollowerPortrait_More)

local function GarrisonMissionPage_ShowMission_More(self, missionInfo)
   local mission_page
   if self.ShowMission then
      mission_page = self.MissionTab.MissionPage
   else
      missionInfo = self
      mission_page = MissionPage
   end

   if missionInfo.iLevel > 0 then
      mission_page.showItemLevel = false
      local stage = mission_page.Stage
      stage.Level:SetPoint("CENTER", stage.Header, "TOPLEFT", 30, -36)
      stage.ItemLevel:Hide()
      stage.Level:SetText(missionInfo.iLevel)
      mission_page.ItemLevelHitboxFrame:Show()
   else
      mission_page.ItemLevelHitboxFrame:Hide()
   end

   BestForCurrentSelectedMission(LE_FOLLOWER_TYPE_GARRISON_6_0, MissionPage, "MissionPage")
end

local class_based_SetClearFollower = GarrisonMissionFrame and GarrisonMissionFrame.AssignFollowerToMission and GarrisonMissionFrame.RemoveFollowerFromMission and true
--[[ localized above ]] MissionPage_PartyButtonOnClick = function(self)
   local method_base = self.method_base
   local follower_frames = self.follower_frames

   if self[1] then
      event_frame:UnregisterEvent("GARRISON_FOLLOWER_LIST_UPDATE")
      for idx = 1, #follower_frames do
         if class_based_SetClearFollower then method_base:RemoveFollowerFromMission(follower_frames[idx]) else GarrisonMissionPage_ClearFollower(follower_frames[idx]) end
      end

      for idx = 1, #follower_frames do
         local followerFrame = follower_frames[idx]
         local follower = self[idx]
         if follower then
            local followerInfo = C_Garrison.GetFollowerInfo(follower)
            if class_based_SetClearFollower then method_base:AssignFollowerToMission(followerFrame, followerInfo) else GarrisonMissionPage_SetFollower(followerFrame, followerInfo) end
         end
      end
      event_frame:RegisterEvent("GARRISON_FOLLOWER_LIST_UPDATE")
   end

   if GarrisonFollowerMission_class_UpdateMissionParty then
      method_base:UpdateMissionParty(follower_frames)
   else
      GarrisonMissionPage_UpdateMissionForParty()
   end
end

local function MissionList_PartyButtonOnClick(self)
   if addon_env.RegisterManualInterraction then addon_env.RegisterManualInterraction() end
   addon_env.mission_page_pending_click = "MissionPage1"
   return self:GetParent():Click()
end

local function UpdateMissionListButton(mission, filtered_followers, blizzard_button, gmm_button, more_missions_to_cache, resources, inactive_alpha)
   if (mission.numFollowers > filtered_followers.free) or (mission.cost > resources) then
      blizzard_button:SetAlpha(inactive_alpha or 0.3)
      gmm_button:SetText()
   else
      local top_for_this_mission = top_for_mission[mission.missionID]
      if not top_for_this_mission then
         if more_missions_to_cache then
            more_missions_to_cache = more_missions_to_cache + 1
         else
            more_missions_to_cache = 0
            FindBestFollowersForMission(mission, filtered_followers, "mission_list")
            local top1 = top[1]
            top_for_this_mission = {}
            top_for_this_mission.successChance = top1.successChance
            if top_for_this_mission.successChance then
               top_for_this_mission.materialMultiplier = top1.materialMultiplier
               top_for_this_mission.material_rewards = top1.material_rewards
               top_for_this_mission.goldMultiplier = top1.goldMultiplier
               top_for_this_mission.gold_rewards = top1.gold_rewards
               top_for_this_mission.xpBonus = top1.xpBonus
               top_for_this_mission.isMissionTimeImproved = top1.isMissionTimeImproved
               top_for_this_mission.xp_reward_wasted = top1.xp_reward_wasted
               top_for_this_mission.all_followers_maxed = top1.all_followers_maxed
               top_for_this_mission.mission_level = top1.mission_level
            end
            top_for_mission[mission.missionID] = top_for_this_mission
         end
      end

      if top_for_this_mission then
         SetTeamButtonText(gmm_button, top_for_this_mission)
      else
         gmm_button:SetText("...")
      end
      blizzard_button:SetAlpha(1)
   end
   gmm_button:Show()

   return more_missions_to_cache
end
addon_env.UpdateMissionListButton = UpdateMissionListButton

local mission_expiration_format_days  = "%s" .. DAY_ONELETTER_ABBR:gsub(" ", "") .. " %02d:%02d"
local mission_expiration_format_hours = "%s" ..                                        "%d:%02d"
-- Add more data to mission list over Blizzard's own
-- GarrisonMissionList_Update
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
hooksecurefunc("GarrisonMissionList_Update", GarrisonMissionList_Update_More)
hooksecurefunc(GarrisonMissionFrame.MissionTab.MissionList.listScroll, "update", GarrisonMissionList_Update_More)

addon_env.HideGameTooltip = GameTooltip_Hide or function() return GameTooltip:Hide() end
addon_env.OnShowEmulateDisabled = function(self) self:GetScript("OnDisable")(self) end
addon_env.OnEnterShowGameTooltip = function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT") GameTooltip:SetText(self.tooltip, nil, nil, nil, nil, true) end

addon_env.MissionPage_ButtonsInit = function(button_prefix, parent_frame)
   local prev
   for suffix_idx = 1, #button_suffixes do
      local suffix = button_suffixes[suffix_idx]
      for idx = 1, 3 do
         local name = button_prefix .. suffix .. idx
         if not gmm_buttons[name] then
            local set_followers_button = CreateFrame("Button", nil, parent_frame, "UIPanelButtonTemplate")
            -- Ugly, but I can't just parent to BorderFrame - buttons would be visible even on map screen
            if button_prefix == "ShipyardMissionPage" then
               set_followers_button:SetFrameLevel(set_followers_button:GetFrameLevel() + 4)
               set_followers_button.method_base = GarrisonShipyardFrame
               set_followers_button.follower_frames = GarrisonShipyardFrame.MissionTab.MissionPage.Followers
            else
               set_followers_button.method_base = GarrisonMissionFrame
               set_followers_button.follower_frames = MissionPage.Followers
            end
            set_followers_button:SetText(idx)
            set_followers_button:SetWidth(100)
            set_followers_button:SetHeight(50)
            if not prev then
               set_followers_button:SetPoint("TOPLEFT", parent_frame, "TOPRIGHT", 0, 0)
            else
               set_followers_button:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 0)
            end

            if suffix ~= "Unavailable" then
               set_followers_button:SetScript("OnClick", MissionPage_PartyButtonOnClick)
            else
               set_followers_button:SetScript("OnMouseDown", nil)
               set_followers_button:SetScript("OnMouseUp", nil)
               set_followers_button:HookScript("OnShow", addon_env.OnShowEmulateDisabled)
            end

            set_followers_button:SetScript('OnEnter', SetTeamButtonTooltip)
            set_followers_button:SetScript('OnLeave', addon_env.HideGameTooltip)

            prev = set_followers_button
            gmm_buttons[name] = set_followers_button
         end
      end
   end
   gmm_buttons[button_prefix .. 'Yield1']:SetPoint("TOPLEFT", gmm_buttons[button_prefix .. '3'], "BOTTOMLEFT", 0, -50)
   gmm_buttons[button_prefix .. 'Unavailable1']:SetPoint("TOPLEFT", gmm_buttons[button_prefix .. 'Yield3'], "BOTTOMLEFT", 0, -50)

   local button = CreateFrame("Button", nil, parent_frame)
   button:SetNormalTexture("Interface\\Buttons\\UI-LinkProfession-Up")
   button:SetPushedTexture("Interface\\Buttons\\UI-LinkProfession-Down")
   button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
   button:SetHeight(30)
   button:SetWidth(30)
   button.tooltip = BROWSER_COPY_LINK .. " (Wowhead)"
   button:SetPoint("RIGHT", parent_frame.Stage.Title, "LEFT", 0, 0)
   button:SetScript("OnEnter", addon_env.OnEnterShowGameTooltip)
   button:SetScript("OnLeave", addon_env.HideGameTooltip)
   button:SetScript("OnClick", function()
      local chat_box = ACTIVE_CHAT_EDIT_BOX or LAST_ACTIVE_CHAT_EDIT_BOX
      if chat_box then
         local missionInfo = parent_frame.missionInfo
         local mission_id = missionInfo.missionID
         if mission_id then
            local existing_text = chat_box:GetText()
            local inserted_text = ("http://www.wowhead.com/mission=%s"):format(mission_id)
            if existing_text:find(inserted_text, 1, true) then return end
            -- TODO: what really should be cheked is that there's no space before cursor
            if existing_text ~= "" and not existing_text:find(" $") then inserted_text = " " .. inserted_text end
            ChatEdit_ActivateChat(chat_box)
            chat_box:Insert(inserted_text)
         end
      end
   end)
end

local function MissionList_ButtonsInit()
   local level_anchor = GarrisonMissionFrame.MissionTab.MissionList.listScroll
   local blizzard_buttons = GarrisonMissionFrame.MissionTab.MissionList.listScroll.buttons
   for idx = 1, #blizzard_buttons do
      local blizzard_button = blizzard_buttons[idx]
      if not gmm_buttons['MissionList' .. idx] then
         -- move first reward to left a little, rest are anchored to first
         local reward = blizzard_button.Rewards[1]
         for point_idx = 1, reward:GetNumPoints() do
            local point, relative_to, relative_point, x, y = reward:GetPoint(point_idx)
            if point == "RIGHT" then
               x = x - 60
               reward:SetPoint(point, relative_to, relative_point, x, y)
               break
            end
         end

         local set_followers_button = CreateFrame("Button", nil, blizzard_button, "UIPanelButtonTemplate")
         set_followers_button:SetText(idx)
         set_followers_button:SetWidth(80)
         set_followers_button:SetHeight(40)
         set_followers_button:SetPoint("LEFT", blizzard_button, "RIGHT", -65, 0)
         set_followers_button:SetScript("OnClick", MissionList_PartyButtonOnClick)
         gmm_buttons['MissionList' .. idx] = set_followers_button
      end

      if not gmm_frames['MissioListExpirationText' .. idx] then
         local expiration = blizzard_button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
         expiration:SetWidth(500)
         expiration:SetHeight(1)
         expiration:SetPoint("BOTTOMRIGHT", blizzard_button, "BOTTOMRIGHT", -10, 8)
         expiration:SetJustifyH("RIGHT")
         gmm_frames['MissioListExpirationText' .. idx] = expiration
      end
   end
   -- GarrisonMissionFrame.MissionTab.MissionList.listScroll.scrollBar:SetFrameLevel(gmm_buttons['MissionList1']:GetFrameLevel() - 3)
end

local function MissionPage_WarningInit()
   for idx = 1, #MissionPageFollowers do
      local follower_frame = MissionPageFollowers[idx]
      -- TODO: inherit from name?
      local warning = follower_frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      warning:SetWidth(185)
      warning:SetHeight(1)
      warning:SetPoint("BOTTOM", follower_frame, "TOP", 0, -68)
      gmm_frames["MissionPageFollowerWarning" .. idx] = warning

      gmm_frames["MissionPageFollowerXP" .. idx]          = Widget{type = "Texture", parent = follower_frame, SubLayer = 3, Width = 104, Height = 4, BOTTOMLEFT = {55, 2}, Color = { 0.212, 0, 0.337 }, Hide = true }
      gmm_frames["MissionPageFollowerXPGainBase" .. idx]  = Widget{type = "Texture", parent = follower_frame, SubLayer = 2, Width = 104, Height = 4, BOTTOMLEFT = {55, 2}, Color = { 0.6, 1, 0 }, Hide = true }
      gmm_frames["MissionPageFollowerXPGainBonus" .. idx] = Widget{type = "Texture", parent = follower_frame, SubLayer = 1, Width = 104, Height = 4, BOTTOMLEFT = {55, 2}, Color = { 0, 0.75, 1 }, Hide = true }
   end
end

addon_env.MissionPage_ButtonsInit("MissionPage", MissionPage)
MissionList_ButtonsInit()
MissionPage_WarningInit()
PostHookFunctionOrClass("GarrisonMissionPage_ShowMission", "GarrisonMissionFrame", "ShowMission", GarrisonMissionPage_ShowMission_More)
-- local count = 0
-- hooksecurefunc("GarrisonFollowerList_UpdateFollowers", function(self) count = count + 1 print("GarrisonFollowerList_UpdateFollowers", count, self:GetName(), self:GetParent():GetName()) end)

local info_ignore_toggle = {
   notCheckable = true,
   func = function(self, followerID)
      if ingored_followers[followerID] then
         ingored_followers[followerID] = nil
      else
         ingored_followers[followerID] = true
      end
      addon_env.top_for_mission_dirty = true
      filtered_followers_dirty = true
      if GarrisonMissionFrame:IsShown() then
         GarrisonFollowerList_UpdateFollowers(GarrisonMissionFrame.FollowerList)
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
      info_ignore_toggle.text = ingored_followers[followerID] and "GMM: Unignore" or "GMM: Ignore"
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

local GarrisonFollowerList_Update_More_need_parent
local function GarrisonFollowerList_Update_More(self)
   -- Somehow Blizzard UI insists on updating hidden frames AND explicitly updates them OnShow.
   --  Following suit is just a waste of CPU, so we'll update only when frame is actually visible.
   if not self:IsVisible() then return end

   local followerFrame = GarrisonFollowerList_Update_More_need_parent and self:GetParent() or self
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
      local portrait_frame = button.PortraitFrame
      local level_border = portrait_frame.LevelBorder

      if ( index <= numFollowers ) then
         local follower = followers[followersList[index]]
         if ( follower.isCollected ) then
            if ingored_followers[follower.followerID] then
               button.BusyFrame:Show()
               button.BusyFrame.Texture:SetTexture(0.5, 0, 0, 0.3)
            end

            if follower.level == GARRISON_FOLLOWER_MAX_LEVEL then
               level_border:SetAtlas("GarrMission_PortraitRing_iLvlBorder")
               level_border:SetWidth(70)
               local i_level = follower.iLevel
               portrait_frame.Level:SetFormattedText("%s%s %d", i_level == 675 and maxed_follower_color_code or "", ITEM_LEVEL_ABBR, i_level)
               button.ILevel:SetText(nil)
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
GarrisonFollowerList_Update_More_need_parent = PostHookFunctionOrClass("GarrisonFollowerList_Update", GarrisonMissionFrame.FollowerList, "UpdateData", GarrisonFollowerList_Update_More)

gmm_buttons.StartMission = MissionPage.StartMissionButton

-- Globals deliberately exposed for people outside
function GMM_Click(button_name)
   local button = gmm_buttons[button_name]
   if button and button:IsVisible() then button:Click() end
end

-- /dump GarrisonMissionFrame.MissionTab.MissionList.listScroll.buttons
-- /dump GarrisonMissionFrame.MissionTab.MissionList.listScroll.scrollBar