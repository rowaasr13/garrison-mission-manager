local addon_name, addon_env = ...

local c_garrison_cache = addon_env.c_garrison_cache

-- [AUTOLOCAL START]
local AddFollowerToMission = C_Garrison.AddFollowerToMission
local C_Garrison = C_Garrison
local CreateFrame = CreateFrame
local GARRISON_CURRENCY = GARRISON_CURRENCY
local GARRISON_FOLLOWER_MAX_LEVEL = GARRISON_FOLLOWER_MAX_LEVEL
local GARRISON_SHIP_OIL_CURRENCY = GARRISON_SHIP_OIL_CURRENCY
local GarrisonMissionFrame = GarrisonMissionFrame
local GetFramesRegisteredForEvent = GetFramesRegisteredForEvent
local GetPartyMissionInfo = C_Garrison.GetPartyMissionInfo
local RemoveFollowerFromMission = C_Garrison.RemoveFollowerFromMission
local dump = DevTools_Dump
local pairs = pairs
local sfind = string.find
local tinsert = table.insert
local wipe = wipe
-- [AUTOLOCAL END]

local MissionPage = GarrisonMissionFrame.MissionTab.MissionPage
local MissionPageFollowers = MissionPage.Followers

addon_env.event_frame = addon_env.event_frame or CreateFrame("Frame")
local event_frame = addon_env.event_frame
local RegisterEvent = event_frame.RegisterEvent
local UnregisterEvent = event_frame.UnregisterEvent

-- local prof = time_record.new():ldb_register('GMM - FindBestFollowersForMission')
-- local timer = prof.timer

-- will be "table" in 6.2, number before it
local currencyMultipliers_type
local class_based_SetClearFollower = GarrisonMissionFrame and GarrisonMissionFrame.AssignFollowerToMission and GarrisonMissionFrame.RemoveFollowerFromMission and true

local top = {{}, {}, {}, {}}
local top_yield = {{}, {}, {}, {}}
local top_unavailable = {{}, {}, {}, {}}

local min, max = {}, {}
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
   -- TODO: this can break everything else if player initiates combat and gets "too slow" before handlers are returned
   -- TODO: restoration of events and previous followers should be put in separate function and called through .After
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

   local material_rewards
   local xp_only_rewards
   local gold_rewards
   for _, reward in pairs(mission.rewards) do
      local currencyID = reward.currencyID
      if currencyID == 823 --[[Apexis]] then material_rewards = currencyID end
      if currencyID == GARRISON_SHIP_OIL_CURRENCY and (not material_rewards or material_rewards == GARRISON_CURRENCY) then material_rewards = currencyID end
      if currencyID == GARRISON_CURRENCY and not material_rewards then material_rewards = currencyID end
      if currencyID == 0 then gold_rewards = true end
      if reward.followerXP and xp_only_rewards == nil then xp_only_rewards = true end
      if not reward.followerXP then xp_only_rewards = false end
   end

   local mission_type = mission.type
   if mission_type == "Ship-Legendary" or sfind(mission_type, "Ship-Siege", 1, true) == 1 then
      xp_only_rewards = false
   end

   if mode ~= "mission_list" then
      if gold_rewards then
         best_modes_count = best_modes_count + 1
         best_modes[best_modes_count] = "gold_yield"
      elseif material_rewards then
         best_modes_count = best_modes_count + 1
         best_modes[best_modes_count] = "material_yield"
      end
   end

   local salvage_yard_level = followers.type == LE_FOLLOWER_TYPE_GARRISON_6_0 and c_garrison_cache.salvage_yard_level
   local all_followers_maxed = followers.all_maxed

   local follower1_added, follower2_added, follower3_added

   -- for prof_runs = 1, mode ~= "mission_list" and 100 or 1 do local prof_start = timer()

   for i1 = 1, max[1] do
      local follower1 = followers[i1]
      local follower1_id = follower1.followerID
      local follower1_maxed = follower1.levelXP == 0 and 1 or 0
      local follower1_level = follower1.isMaxLevel and follower1.iLevel or follower1.level
      local follower1_busy = follower1.is_busy_for_mission and 1 or 0
      for i2 = min[2] or (i1 + 1), max[2] do
         local follower2_maxed = 0
         local follower2 = followers[i2]
         local follower2_id
         local follower2_level = 0
         local follower2_busy = 0
         if follower2 then
            follower2_id = follower2.followerID
            if follower2.levelXP == 0 then follower2_maxed = 1 end
            follower2_level = follower2.isMaxLevel and follower2.iLevel or follower2.level
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
               follower3_level = follower3.isMaxLevel and follower3.iLevel or follower3.level
               if follower3.is_busy_for_mission then follower3_busy = 1 end
            end

            local followers_maxed = follower1_maxed + follower2_maxed + follower3_maxed
            -- at least one follower in party is busy (i.e. staus non-empty/non-party) for mission
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
               -- Uh, thanks 6.2, for lots of new calls and tables going directly to garbage right in the middle of most computational heavy loop.
               -- At least I can eliminate "type" after first check.
               if not currencyMultipliers_type and materialMultiplier then
                  local detected_type = type(materialMultiplier)
                  if detected_type == "table" or detected_type == "number" then currencyMultipliers_type = detected_type end
               end
               if currencyMultipliers_type == "table" then materialMultiplier = materialMultiplier[material_rewards] or 1 end
               isEnvMechanicCountered = isEnvMechanicCountered and 1 or 0
               local buffCount = #partyBuffs

               local saved_best_modes
               local saved_best_modes_count
               if follower_is_busy_for_mission then
                  saved_best_modes = best_modes
                  saved_best_modes_count = best_modes_count
                  best_modes = best_mode_unavailable
                  best_mode_unavailable[1] = material_rewards and "material_yield" or (gold_rewards and "gold_yield" or "success")
                  best_modes_count = 1
               end

               for best_modes_idx = 1, best_modes_count do
                  local mode = best_modes[best_modes_idx]
                  local material_yield
                  if material_rewards then
                     material_yield = materialMultiplier * successChance
                  end

                  local gold_yield
                  if gold_rewards then
                     gold_yield = goldMultiplier * successChance
                  end

                  local top_list
                  if follower_is_busy_for_mission then
                     top_list = top_unavailable
                  elseif mode == 'material_yield' or mode == 'gold_yield' then
                     top_list = top_yield
                  else
                     top_list = top
                  end

                  for idx = 1, top_entries do
                     local current = top_list[idx]

                     local found
                     repeat -- Checking if new candidate for top is better than any top 3 already sored

                        if not follower_is_busy_for_mission and (
                           (mode == "material_yield" and materialMultiplier == 1) or
                           (mode == "gold_yield" and goldMultiplier == 1)
                        ) then
                           -- No reason to place non-boosted team in special sorting list,
                           -- success chance top will be better or same anyway, unless it is "unavailable" list.
                           break
                        end

                        if not current[1] then found = true break end

                        local c_material_yield = current.material_yield
                        if mode == 'material_yield' then
                           if c_material_yield < material_yield then found = true break end
                           if c_material_yield > material_yield then break end
                        end

                        local c_gold_yield = current.gold_yield
                        if mode == 'gold_yield' then
                           if c_gold_yield < gold_yield then found = true break end
                           if c_gold_yield > gold_yield then break end
                        end

                        local cSuccessChance = current.successChance
                        if cSuccessChance < successChance then found = true break end
                        if cSuccessChance > successChance then break end

                        if material_rewards then
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

                        -- Maximize material/gold yield in general mode when possible too
                        if material_rewards then
                           if c_material_yield < material_yield then found = true break end
                           if c_material_yield > material_yield then break end
                        end

                        if gold_rewards then
                           if c_gold_yield < gold_yield then found = true break end
                           if c_gold_yield > gold_yield then break end
                        end

                        -- Minimize XP bonus if all followers are maxed, because it indicates either overkill or XP-bonus traits better used elsewhere
                        -- but only if there are unmaxed followers. Otherwise minimize it after other optimizations.
                        if not all_followers_maxed then
                           if slots == followers_maxed then
                              if cXpBonus > xpBonus then found = true break end
                              if cXpBonus < xpBonus then break end
                           end
                        end

                        -- Minimize material/gold multiplier if possible if no corresponding reward is available.
                        if not material_rewards then
                           local c_material_multiplier = current.materialMultiplier
                           if c_material_multiplier > materialMultiplier then found = true break end
                           if c_material_multiplier < materialMultiplier then break end
                        end

                        if not gold_rewards then
                           local c_gold_multiplier = current.goldMultiplier
                           if c_gold_multiplier > goldMultiplier then found = true break end
                           if c_gold_multiplier < goldMultiplier then break end
                        end

                        local cBuffCount = current.buffCount
                        if cBuffCount > buffCount then found = true break end
                        if cBuffCount < buffCount then break end

                        if all_followers_maxed then
                           if slots == followers_maxed then
                              if cXpBonus > xpBonus then found = true break end
                              if cXpBonus < xpBonus then break end
                           end
                        end

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
                        new.goldMultiplier = goldMultiplier
                        new.material_rewards = material_rewards
                        new.gold_rewards = gold_rewards
                        new.xpBonus = xpBonus
                        new.totalTimeSeconds = totalTimeSeconds
                        new.isMissionTimeImproved = isMissionTimeImproved
                        new.followers_maxed = followers_maxed
                        new.buffCount = buffCount
                        new.isEnvMechanicCountered = isEnvMechanicCountered
                        new.material_yield = material_yield
                        new.gold_yield = gold_yield
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

   top.material_rewards = material_rewards
   top.gold_rewards = gold_rewards
   -- TODO:
   -- If we have material/gold yield list, check it and remove all entries where material_yield is worse than #1 from regular top list.
   -- dump(top[1])

   if party_followers_count > 0 then
      for party_idx = 1, party_followers_count do
         if preserve_mission_page_followers[party_idx] then
            if class_based_SetClearFollower then GarrisonMissionFrame:AssignFollowerToMission(MissionPageFollowers[party_idx], preserve_mission_page_followers[party_idx]) else GarrisonMissionPage_SetFollower(MissionPageFollowers[party_idx], preserve_mission_page_followers[party_idx]) end
         end
      end
   end

   for idx = 1, #event_handlers do RegisterEvent(event_handlers[idx], "GARRISON_FOLLOWER_LIST_UPDATE") end

   -- dump(top)
   -- local location, xp, environment, environmentDesc, environmentTexture, locPrefix, isExhausting, enemies = C_Garrison.GetMissionInfo(missionID);
   -- /run GMM_dumpl("location, xp, environment, environmentDesc, environmentTexture, locPrefix, isExhausting, enemies", C_Garrison.GetMissionInfo(GarrisonMissionFrame.MissionTab.MissionPage.missionInfo.missionID))
   -- /run GMM_dumpl("totalTimeString, totalTimeSeconds, isMissionTimeImproved, successChance, partyBuffs, isEnvMechanicCountered, xpBonus, materialMultiplier", C_Garrison.GetPartyMissionInfo(GarrisonMissionFrame.MissionTab.MissionPage.missionInfo.missionID))
end
addon_env.FindBestFollowersForMission = FindBestFollowersForMission
addon_env.top = top
addon_env.top_yield = top_yield
addon_env.top_unavailable = top_unavailable