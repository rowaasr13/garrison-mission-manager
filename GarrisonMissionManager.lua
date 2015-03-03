local addon_name, addon_env = ...

-- Confused about mix of CamelCase and_underscores?
-- Camel case comes from copypasta of how Blizzard calls returns/fields in their code and deriveates
-- Underscore are my own variables

local c_garrison_cache = addon_env.c_garrison_cache

-- [AUTOLOCAL START] Automatic local aliases for Blizzard's globals
local AddFollowerToMission = C_Garrison.AddFollowerToMission
local After = C_Timer.After
local CANCEL = CANCEL
local C_Garrison = C_Garrison
local FONT_COLOR_CODE_CLOSE = FONT_COLOR_CODE_CLOSE
local GARRISON_CURRENCY = GARRISON_CURRENCY
local GARRISON_FOLLOWER_IN_PARTY = GARRISON_FOLLOWER_IN_PARTY
local GARRISON_FOLLOWER_MAX_LEVEL = GARRISON_FOLLOWER_MAX_LEVEL
local GARRISON_FOLLOWER_ON_MISSION = GARRISON_FOLLOWER_ON_MISSION
local GARRISON_FOLLOWER_ON_MISSION_WITH_DURATION = GARRISON_FOLLOWER_ON_MISSION_WITH_DURATION
local GREEN_FONT_COLOR_CODE = GREEN_FONT_COLOR_CODE
local GarrisonMissionFrame = GarrisonMissionFrame
local GetCurrencyInfo = GetCurrencyInfo
local GetFollowerInfoForBuilding = C_Garrison.GetFollowerInfoForBuilding
local GetFollowerMissionTimeLeft = C_Garrison.GetFollowerMissionTimeLeft
local GetFollowerStatus = C_Garrison.GetFollowerStatus
local GetFramesRegisteredForEvent = GetFramesRegisteredForEvent
local GetItemInfo = GetItemInfo
local GetLandingPageShipmentInfo = C_Garrison.GetLandingPageShipmentInfo
local GetPartyMissionInfo = C_Garrison.GetPartyMissionInfo
local HybridScrollFrame_GetOffset = HybridScrollFrame_GetOffset
local RED_FONT_COLOR_CODE = RED_FONT_COLOR_CODE
local RemoveFollowerFromMission = C_Garrison.RemoveFollowerFromMission
local dump = DevTools_Dump
local format = string.format
local pairs = pairs
local tconcat = table.concat
local tinsert = table.insert
local tsort = table.sort
local wipe = wipe
-- [AUTOLOCAL END]

local MissionPage = GarrisonMissionFrame.MissionTab.MissionPage
local MissionPageFollowers = GarrisonMissionFrame.MissionTab.MissionPage.Followers

-- Config
local ingored_followers = {}
SVPC_GarrisonMissionManager = {}
SVPC_GarrisonMissionManager.ingored_followers = ingored_followers


local _, _, garrison_currency_texture = GetCurrencyInfo(GARRISON_CURRENCY)
garrison_currency_texture = "|T" .. garrison_currency_texture .. ":0|t"
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
local top_for_mission_dirty = true

local filtered_followers = {}
local filtered_followers_count
local filtered_free_followers_count
local filtered_followers_dirty = true

addon_env.event_frame = addon_env.event_frame or CreateFrame("Frame")
local event_frame = addon_env.event_frame
local RegisterEvent = event_frame.RegisterEvent
local UnregisterEvent = event_frame.UnregisterEvent

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
event_frame:SetScript("OnEvent", function(self, event, arg1)
   -- if events_top_for_mission_dirty[event] then top_for_mission_dirty = true end
   -- if events_for_followers[event] then filtered_followers_dirty = true end
   -- Let's clear both for now, or else we often miss one follower state update when we start mission

   local event_for_followers = events_for_followers[event]
   if event_for_followers or events_top_for_mission_dirty[event] then
      top_for_mission_dirty = true
      filtered_followers_dirty = true
   end

   if event == "GARRISON_LANDINGPAGE_SHIPMENTS" then
      event_frame:UnregisterEvent("GARRISON_LANDINGPAGE_SHIPMENTS")
      CheckPartyForProfessionFollowers()
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

   if event == "ADDON_LOADED" and arg1 == addon_name then
      if SVPC_GarrisonMissionManager then
         ingored_followers = SVPC_GarrisonMissionManager.ingored_followers
      end
      event_frame:UnregisterEvent("ADDON_LOADED")
   end
end)
for event in pairs(events_top_for_mission_dirty) do event_frame:RegisterEvent(event) end
for event in pairs(events_for_followers) do event_frame:RegisterEvent(event) end
for event in pairs(events_for_buildings) do RegisterEvent(event_frame, event) end
event_frame:RegisterEvent("ADDON_LOADED")

local gmm_buttons = {}
addon_env.gmm_buttons = gmm_buttons
local gmm_frames = {}
local mission_page_pending_click

function GMM_dumpl(pattern, ...)
   local names = { strsplit(",", pattern) }
   for idx = 1, select('#', ...) do
      local name = names[idx]
      if name then name = name:gsub("^%s+", ""):gsub("%s+$", "") end
      print(GREEN_FONT_COLOR_CODE, idx, name, FONT_COLOR_CODE_CLOSE)
      dump((select(idx, ...)))
   end
end

-- local prof = time_record.new():ldb_register('GMM - FindBestFollowersForMission')
-- local timer = prof.timer

local min, max = {}, {}
local top = {{}, {}, {}, {}}
local top_yield = {{}, {}, {}, {}}
local top_unavailable = {{}, {}, {}, {}}
local best_modes = { "success" }
local best_mode_unavailable = {}
local preserve_mission_page_followers = {}
local function FindBestFollowersForMission(mission, followers, mode)
   local followers_count = #followers

   local top_entries = mode == "mission_list" and 1 or 3

   for idx = 1, top_entries do
      wipe(top[idx])
      wipe(top_yield[idx])
      wipe(top_unavailable[idx])
   end

   local slots = mission.numFollowers
   if slots > followers_count then return end

   local event_handlers = { GetFramesRegisteredForEvent("GARRISON_FOLLOWER_LIST_UPDATE") }
   for idx = 1, #event_handlers do UnregisterEvent(event_handlers[idx], "GARRISON_FOLLOWER_LIST_UPDATE") end

   local mission_id = mission.missionID
   local party_followers_count = #MissionPageFollowers
   if party_followers_count > 0 then
      for party_idx = 1, party_followers_count do
         preserve_mission_page_followers[party_idx] = MissionPageFollowers[party_idx].info
      end
   end

   if C_Garrison.GetNumFollowersOnMission(mission_id) > 0 then
      for idx = 1, followers_count do
         RemoveFollowerFromMission(mission_id, followers[idx].followerID)
      end
   end

   for idx = 1, slots do
      max[idx] = followers_count - slots + idx
      min[idx] = nil
   end
   for idx = slots + 1, 3 do
      max[idx] = followers_count + 1
      min[idx] = followers_count + 1
   end

   local best_modes_count = 1

   local gr_rewards
   local xp_only_rewards
   for _, reward in pairs(mission.rewards) do
      if reward.currencyID == GARRISON_CURRENCY then gr_rewards = true end
      if reward.followerXP and xp_only_rewards == nil then xp_only_rewards = true end
      if not reward.followerXP then xp_only_rewards = false end
   end

   if gr_rewards and mode ~= "mission_list" then
      best_modes_count = best_modes_count + 1
      best_modes[best_modes_count] = "gr_yield"
   end

   local salvage_yard_level = c_garrison_cache.salvage_yard_level
   local all_followers_maxed = followers.all_followers_maxed

   local follower1_added, follower2_added, follower3_added

   -- for prof_runs = 1, mode ~= "mission_list" and 100 or 1 do local prof_start = timer()

   for i1 = 1, max[1] do
      local follower1 = followers[i1]
      local follower1_id = follower1.followerID
      local follower1_maxed = follower1.levelXP == 0 and 1 or 0
      local follower1_level = follower1.level if follower1_level == GARRISON_FOLLOWER_MAX_LEVEL then follower1_level = follower1.iLevel end
      local follower1_busy = follower1.is_busy_for_mission and 1 or 0 -- at least one follower in party is busy (i.e. staus non-empty/non-party) for mission
      for i2 = min[2] or (i1 + 1), max[2] do
         local follower2_maxed = 0
         local follower2 = followers[i2]
         local follower2_id
         local follower2_level = 0
         local follower2_busy = 0
         if follower2 then
            follower2_id = follower2.followerID
            if follower2.levelXP == 0 then follower2_maxed = 1 end
            follower2_level = follower2.level if follower2_level == GARRISON_FOLLOWER_MAX_LEVEL then follower2_level = follower2.iLevel end
            if follower2.is_busy_for_mission then follower2_busy = 1 end
         end
         for i3 = min[3] or (i2 + 1), max[3] do
            local follower3_maxed = 0
            local follower3 = followers[i3]
            local follower3_id
            local follower3_level = 0
            local follower3_busy = 0
            if follower3 then
               follower3_id = follower3.followerID
               if follower3.levelXP == 0 then follower3_maxed = 1 end
               follower3_level = follower3.level if follower3_level == GARRISON_FOLLOWER_MAX_LEVEL then follower3_level = follower3.iLevel end
               if follower3.is_busy_for_mission then follower3_busy = 1 end
            end

            local followers_maxed = follower1_maxed + follower2_maxed + follower3_maxed
            local follower_is_busy_for_mission = (follower1_busy + follower2_busy + follower3_busy) > 0

            if
               -- On follower XP-only missions throw away any team that is completely filled with maxed out followers
               (xp_only_rewards and slots == followers_maxed and not (salvage_yard_level and all_followers_maxed))
               -- On mission list screen don't bother calculating unavailable followers for now
               or (mode == "mission_list" and follower_is_busy_for_mission)
            then
               -- skip
            else
               local follower_level_total = follower1_level + follower2_level + follower3_level

               if follower3 then
                  if follower3_added and follower3_added ~= follower3_id then
                     RemoveFollowerFromMission(mission_id, follower3_added)
                     follower3_added = nil
                  end
               end

               if follower2 then
                  if follower2_added and follower2_added ~= follower2_id then
                     RemoveFollowerFromMission(mission_id, follower2_added)
                     follower2_added = nil
                  end
               end

               if follower1_added and follower1_added ~= follower1_id then
                  RemoveFollowerFromMission(mission_id, follower1_added)
                  follower1_added = nil
               end

               if not follower1_added then
                  if AddFollowerToMission(mission_id, follower1_id) then
                     follower1_added = follower1_id
                  else
                     --[[ error handling! ]]
                  end
               end

               if follower2 and not follower2_added then
                  if AddFollowerToMission(mission_id, follower2_id) then
                     follower2_added = follower2_id
                  else
                     --[[ error handling! ]]
                  end
               end

               if follower3 and not follower3_added then
                  if AddFollowerToMission(mission_id, follower3_id) then
                     follower3_added = follower3_id
                  else
                     --[[ error handling! ]]
                  end
               end

               -- Calculate result
               local totalTimeString, totalTimeSeconds, isMissionTimeImproved, successChance, partyBuffs, isEnvMechanicCountered, xpBonus, materialMultiplier, goldMultiplier = GetPartyMissionInfo(mission_id)
               isEnvMechanicCountered = isEnvMechanicCountered and 1 or 0
               local buffCount = #partyBuffs

               local saved_best_modes
               local saved_best_modes_count
               if follower_is_busy_for_mission then
                  saved_best_modes = best_modes
                  saved_best_modes_count = best_modes_count
                  best_modes = best_mode_unavailable
                  best_mode_unavailable[1] = gr_rewards and "gr_yield" or "success"
                  best_modes_count = 1
               end

               for best_modes_idx = 1, best_modes_count do
                  local mode = best_modes[best_modes_idx]
                  local gr_yield
                  if gr_rewards then
                     gr_yield = materialMultiplier * successChance
                  end

                  local top_list
                  if follower_is_busy_for_mission then
                     top_list = top_unavailable
                  elseif mode == 'gr_yield' then
                     top_list = top_yield
                  else
                     top_list = top
                  end

                  for idx = 1, top_entries do
                     local current = top_list[idx]

                     local found
                     repeat -- Checking if new candidate for top is better than any top 3 already sored

                        if mode == "gr_yield" and not follower_is_busy_for_mission and materialMultiplier == 1 then
                           -- No reason to place non-GR boosted team in special sorting list,
                           -- success chance top will be better or same anyway, unless it is "unavailable" list.
                           break
                        end

                        if not current[1] then found = true break end

                        local c_gr_yield = current.gr_yield
                        if mode == 'gr_yield' then
                           if c_gr_yield < gr_yield then found = true break end
                           if c_gr_yield > gr_yield then break end
                        end

                        local cSuccessChance = current.successChance
                        if cSuccessChance < successChance then found = true break end
                        if cSuccessChance > successChance then break end

                        if gr_rewards then
                           local cMaterialMultiplier = current.materialMultiplier
                           if cMaterialMultiplier < materialMultiplier then found = true break end
                           if cMaterialMultiplier > materialMultiplier then break end
                        end

                        local c_followers_maxed = current.followers_maxed
                        if c_followers_maxed > followers_maxed then found = true break end
                        if c_followers_maxed < followers_maxed then break end

                        local cXpBonus = current.xpBonus
                        -- Maximize XP bonus only if party have unmaxed followers
                        if slots ~= followers_maxed then
                           if cXpBonus < xpBonus then found = true break end
                           if cXpBonus > xpBonus then break end
                        end

                        local cTotalTimeSeconds = current.totalTimeSeconds
                        if cTotalTimeSeconds > totalTimeSeconds then found = true break end
                        if cTotalTimeSeconds < totalTimeSeconds then break end

                        local c_follower_level_total = current.follower_level_total
                        if c_follower_level_total > follower_level_total then found = true break end
                        if c_follower_level_total < follower_level_total then break end

                        -- Maximize GR yield in general mode when possible too
                        if gr_rewards then
                           if c_gr_yield < gr_yield then found = true break end
                           if c_gr_yield > gr_yield then break end
                        end

                        -- Minimize XP bonus if all followers are maxed, because it indicates either overkill or XP-bonus traits better used elsewhere
                        if slots == followers_maxed then
                           if cXpBonus > xpBonus then found = true break end
                           if cXpBonus < xpBonus then break end
                        end

                        local cBuffCount = current.buffCount
                        if cBuffCount > buffCount then found = true break end
                        if cBuffCount < buffCount then break end

                        local cIsEnvMechanicCountered = current.isEnvMechanicCountered
                        if cIsEnvMechanicCountered > isEnvMechanicCountered then found = true break end
                        if cIsEnvMechanicCountered < isEnvMechanicCountered then break end
                     until true

                     if found then
                        local all_followers_maxed_on_mission = slots == followers_maxed
                        local new = top_list[4]
                        new[1] = follower1
                        new[2] = follower2
                        new[3] = follower3
                        new.successChance = successChance
                        new.materialMultiplier = materialMultiplier
                        new.gr_rewards = gr_rewards
                        new.xpBonus = xpBonus
                        new.totalTimeSeconds = totalTimeSeconds
                        new.isMissionTimeImproved = isMissionTimeImproved
                        new.followers_maxed = followers_maxed
                        new.buffCount = buffCount
                        new.isEnvMechanicCountered = isEnvMechanicCountered
                        new.gr_yield = gr_yield
                        new.xp_reward_wasted = xp_only_rewards and all_followers_maxed_on_mission
                        new.all_followers_maxed = all_followers_maxed_on_mission
                        new.follower_level_total = follower_level_total
                        new.mission_level = mission.level
                        tinsert(top_list, idx, new)
                        top_list[5] = nil
                        break
                     end
                  end
               end

               if follower_is_busy_for_mission then
                  best_modes = saved_best_modes
                  best_modes_count = saved_best_modes_count
               end
            end
         end
      end
   end

   if follower1_added then RemoveFollowerFromMission(mission_id, follower1_added) end
   if follower2_added then RemoveFollowerFromMission(mission_id, follower2_added) end
   if follower3_added then RemoveFollowerFromMission(mission_id, follower3_added) end

   -- local prof_end = timer() if mode ~= "mission_list" then prof:record("permutation loop - mission page", prof_end - prof_start) end end

   top.gr_rewards = gr_rewards
   -- TODO:
   -- If we have GR yield list, check it and remove all entries where gr_yield is worse than #1 from regular top list.
   -- dump(top[1])

   if party_followers_count > 0 then
      for party_idx = 1, party_followers_count do
         if preserve_mission_page_followers[party_idx] then
            GarrisonMissionPage_SetFollower(MissionPageFollowers[party_idx], preserve_mission_page_followers[party_idx])
         end
      end
   end

   for idx = 1, #event_handlers do RegisterEvent(event_handlers[idx], "GARRISON_FOLLOWER_LIST_UPDATE") end

   -- dump(top)
   -- local location, xp, environment, environmentDesc, environmentTexture, locPrefix, isExhausting, enemies = C_Garrison.GetMissionInfo(missionID);
   -- /run GMM_dumpl("location, xp, environment, environmentDesc, environmentTexture, locPrefix, isExhausting, enemies", C_Garrison.GetMissionInfo(GarrisonMissionFrame.MissionTab.MissionPage.missionInfo.missionID))
   -- /run GMM_dumpl("totalTimeString, totalTimeSeconds, isMissionTimeImproved, successChance, partyBuffs, isEnvMechanicCountered, xpBonus, materialMultiplier", C_Garrison.GetPartyMissionInfo(GarrisonMissionFrame.MissionTab.MissionPage.missionInfo.missionID))
end

local function SortFollowersByLevel(a, b)
   local a_level = a.level
   local b_level = b.level
   if a_level ~= b_level then return a_level > b_level end
   return a.iLevel > b.iLevel
end

local function GetFilteredFollowers()
   if filtered_followers_dirty then
      local followers = C_Garrison.GetFollowers()
      wipe(filtered_followers)
      filtered_followers_count = 0
      filtered_free_followers_count = 0
      local all_followers_maxed = true
      for idx = 1, #followers do
         local follower = followers[idx]
         repeat
            if not follower.isCollected then break end

            if ingored_followers[follower.followerID] then break end

            filtered_followers_count = filtered_followers_count + 1
            filtered_followers[filtered_followers_count] = follower

            local status = follower.status
            if status and status ~= GARRISON_FOLLOWER_IN_PARTY then
               follower.is_busy_for_mission = true
            else
               if follower.levelXP ~= 0 then all_followers_maxed = nil end
               filtered_free_followers_count = filtered_free_followers_count + 1
            end
         until true
      end
      filtered_followers.all_followers_maxed = all_followers_maxed

      tsort(filtered_followers, SortFollowersByLevel)

      -- dump(filtered_followers)

      filtered_followers_dirty = false
      top_for_mission_dirty = true
   end

   return filtered_followers, filtered_free_followers_count
end

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
      local material_multiplier = top_entry.gr_rewards and top_entry.materialMultiplier > 1 and top_entry.materialMultiplier or ''
      local material_multiplier_icon = material_multiplier ~= '' and garrison_currency_texture or ''

      button:SetFormattedText(
         "%d%%\n%s%s%s%s%s",
         top_entry.successChance,
         xp_bonus, xp_bonus_icon,
         material_multiplier, material_multiplier_icon,
         top_entry.isMissionTimeImproved and time_texture or ""
      )
   else
      button:SetText("")
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
local function BestForCurrentSelectedMission()
   if addon_env.RegisterManualInterraction then addon_env.RegisterManualInterraction() end
   local missionInfo = MissionPage.missionInfo
   local mission_id = missionInfo.missionID

   -- print("Mission ID:", mission_id)

   local filtered_followers, filtered_free_followers_count = GetFilteredFollowers()

   local mission = missionInfo

   -- dump(mission)

   FindBestFollowersForMission(mission, filtered_followers)

   for suffix_idx = 1, #button_suffixes do
      local suffix = button_suffixes[suffix_idx]
      for idx = 1, 3 do
         local button = gmm_buttons['MissionPage' .. suffix .. idx]
         local top_entry
         if suffix == 'Yield' then
            if top.gr_rewards then
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

   if mission_page_pending_click then
      gmm_buttons['MissionPage' .. mission_page_pending_click]:Click()
      mission_page_pending_click = nil
   end
end

local last_shipment_request = 0
local shipment_followers = {}
CheckPartyForProfessionFollowers = function()
   local party_followers_count = #MissionPageFollowers
   local present
   for idx = 1, party_followers_count do
      if MissionPageFollowers[idx].info then present = true end
      gmm_frames["MissionPageFollowerWarning" .. idx]:Hide()
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
         if timeleftString then
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
                              shipment_followers[party_idx .. 'r'] = shipmentsTotal - shipmentsReady
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
         warning:SetFormattedText("%s%s %s (%d)", RED_FONT_COLOR_CODE, time_left, building_name, incomplete_shipments)
         warning:Show()
      end
   end
end
hooksecurefunc("GarrisonMissionPage_UpdateMissionForParty", CheckPartyForProfessionFollowers)

local function MissionPage_PartyButtonOnClick(self)
   if self[1] then
      event_frame:UnregisterEvent("GARRISON_FOLLOWER_LIST_UPDATE")
      for idx = 1, #MissionPageFollowers do
         GarrisonMissionPage_ClearFollower(MissionPageFollowers[idx])
      end

      for idx = 1, #MissionPageFollowers do
         local followerFrame = MissionPageFollowers[idx]
         local follower = self[idx]
         if follower then
            local followerInfo = C_Garrison.GetFollowerInfo(follower)
            GarrisonMissionPage_SetFollower(followerFrame, followerInfo)
         end
      end
      event_frame:RegisterEvent("GARRISON_FOLLOWER_LIST_UPDATE")
   end

   GarrisonMissionPage_UpdateMissionForParty()
end

local function MissionList_PartyButtonOnClick(self)
   if addon_env.RegisterManualInterraction then addon_env.RegisterManualInterraction() end
   -- mission_page_pending_click = 1
   return self:GetParent():Click()
end

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
         buttons[i]:SetAlpha(1)
      end
      return
   end

   local missions = self.availableMissions
   local numMissions = #missions
   if numMissions == 0 then return end

   if top_for_mission_dirty then
      wipe(top_for_mission)
      top_for_mission_dirty = false
   end

   local missions = self.availableMissions
   local offset = HybridScrollFrame_GetOffset(scrollFrame)

   local filtered_followers, filtered_free_followers_count = GetFilteredFollowers()
   local more_missions_to_cache
   local _, garrison_resources = GetCurrencyInfo(GARRISON_CURRENCY)

   for i = 1, numButtons do
      local button = buttons[i]
      local alpha = 1
      local index = offset + i
      if index <= numMissions then
         local mission = missions[index]
         local gmm_button = gmm_buttons['MissionList' .. i]

         if (mission.numFollowers > filtered_free_followers_count) or (mission.cost > garrison_resources) then
            button:SetAlpha(0.3)
            gmm_button:SetText("")
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
                     top_for_this_mission.gr_rewards = top1.gr_rewards
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
            button:SetAlpha(1)
         end
         gmm_button:Show()
      end
   end

   if more_missions_to_cache and more_missions_to_cache > 0 then
      -- print(more_missions_to_cache, GetTime())
      After(0.001, GarrisonMissionList_Update_More)
   end
end
hooksecurefunc("GarrisonMissionList_Update", GarrisonMissionList_Update_More)
hooksecurefunc(GarrisonMissionFrame.MissionTab.MissionList.listScroll, "update", GarrisonMissionList_Update_More)

addon_env.HideGameTooltip = function() return GameTooltip:Hide() end
addon_env.OnShowEmulateDisabled = function(self) self:GetScript("OnDisable")(self) end

local function MissionPage_ButtonsInit()
   local prev
   for suffix_idx = 1, #button_suffixes do
      local suffix = button_suffixes[suffix_idx]
      for idx = 1, 3 do
         local name = 'MissionPage' .. suffix .. idx
         if not gmm_buttons[name] then
            local set_followers_button = CreateFrame("Button", nil, GarrisonMissionFrame.MissionTab.MissionPage, "UIPanelButtonTemplate")
            set_followers_button:SetText(idx)
            set_followers_button:SetWidth(100)
            set_followers_button:SetHeight(50)
            if not prev then
               set_followers_button:SetPoint("TOPLEFT", GarrisonMissionFrame.MissionTab.MissionPage, "TOPRIGHT", 0, 0)
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
   gmm_buttons['MissionPageYield1']:SetPoint("TOPLEFT", gmm_buttons['MissionPage3'], "BOTTOMLEFT", 0, -50)
   gmm_buttons['MissionPageUnavailable1']:SetPoint("TOPLEFT", gmm_buttons['MissionPageYield3'], "BOTTOMLEFT", 0, -50)
end

local function MissionList_ButtonsInit()
   local level_anchor = GarrisonMissionFrame.MissionTab.MissionList.listScroll
   local blizzard_buttons = GarrisonMissionFrame.MissionTab.MissionList.listScroll.buttons
   for idx = 1, #blizzard_buttons do
      if not gmm_buttons['MissionList' .. idx] then
         local blizzard_button = blizzard_buttons[idx]

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
   end
end

MissionPage_ButtonsInit()
MissionList_ButtonsInit()
MissionPage_WarningInit()
hooksecurefunc("GarrisonMissionPage_ShowMission", BestForCurrentSelectedMission)
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
      top_for_mission_dirty = true
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

local function GarrisonFollowerList_Update_More(self)
   -- Somehow Blizzard UI insists on updating hidden frames AND explicitly updates them OnShow.
   --  Following suit is just a waste of CPU, so we'll update only when frame is actually visible.
   if not self:IsVisible() then return end

   local followerFrame = self
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
               local level = portrait_frame.Level
               level:SetFormattedText("%s %d", ITEM_LEVEL_ABBR, follower.iLevel)
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
hooksecurefunc("GarrisonFollowerList_Update", GarrisonFollowerList_Update_More)

gmm_buttons.StartMission = MissionPage.StartMissionButton

-- Globals deliberately exposed for people outside
function GMM_Click(button_name)
   local button = gmm_buttons[button_name]
   if button and button:IsVisible() then button:Click() end
end

-- /dump GarrisonMissionFrame.MissionTab.MissionList.listScroll.buttons
-- /dump GarrisonMissionFrame.MissionTab.MissionList.listScroll.scrollBar