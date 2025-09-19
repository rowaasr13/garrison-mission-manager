local addon_name, addon_env = ...
local a_name, a_env = ...
if not addon_env.load_this then return end
local is_devel = addon_env.is_devel

-- [AUTOLOCAL START]
-- [AUTOLOCAL END]

local ratio_current_health

local function MissionPage_RatioInit(gmm_options)
   local Board = gmm_options.MissionPage.Board
   ratio_current_health = Board:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
   ratio_current_health:SetWidth(0)
   ratio_current_health:SetHeight(1)
   ratio_current_health:SetJustifyH("LEFT")
   ratio_current_health:SetPoint("BOTTOMLEFT", Board.AllyHealthValue, "TOPLEFT", 0, 15)
end

local function UpdateEnemyToAllyPowerRatio(self, missionPage)
   -- TODO: find all info yourself, don't rely on reading it from UI
   local missionInfo = missionPage.missionInfo
   local missionID = missionInfo.missionID
   local missionDeploymentInfo = C_Garrison.GetMissionDeploymentInfo(missionInfo.missionID)

   local enemies = missionDeploymentInfo.enemies
   local enemiesAttack = 0
   local enemiesMaxHealth = 0
   for idx = 1, #enemies do
      local enemy = enemies[idx]
      enemiesAttack    = enemiesAttack    + enemy.attack
      enemiesMaxHealth = enemiesMaxHealth + enemy.maxHealth
   end

   local alliesAttack = 0
   local alliesCurrentHealth = 0
   for followerFrame in missionPage.Board:EnumerateFollowers() do
      local info = followerFrame.info
      if info then
         alliesAttack        = alliesAttack        + info.autoCombatantStats.attack
         alliesCurrentHealth = alliesCurrentHealth + info.autoCombatantStats.currentHealth
      end
   end

   local enemiesWinTurn = alliesCurrentHealth / enemiesAttack
   local alliesWinTurn = enemiesMaxHealth / alliesAttack

   if is_devel then
      print("---")
      print("eatt", enemiesAttack, "ehel", enemiesMaxHealth)
      print("aatt", alliesAttack, "ahel", alliesCurrentHealth)
      print("enemies win:", enemiesWinTurn)
      print("allies win:",  alliesWinTurn)
   end

   if (alliesAttack == 0 or alliesCurrentHealth == 0) then
      ratio_current_health:SetText("------")
   elseif alliesWinTurn < enemiesWinTurn then
      -- allies winning faster -> success rate is better than 50/50
      if is_devel then print("ally win confidence:", enemiesWinTurn / alliesWinTurn) end
      ratio_current_health:SetFormattedText("%sW %0.2f", GREEN_FONT_COLOR_CODE, enemiesWinTurn / alliesWinTurn)
   else
      -- enemies winning faster
      if is_devel then print("enemy confidence (we lose):",  alliesWinTurn / enemiesWinTurn) end
      ratio_current_health:SetFormattedText("%sL %0.2f", RED_FONT_COLOR_CODE, alliesWinTurn / enemiesWinTurn)
   end
end

-- Each of 3 quest displays in landing page's "callings" section
addon_env.child_frame_cache.CallingExpirationText = addon_env.BuildChildFrameCache(function(blizzard_covenant_calling_quest)
   local expiration = blizzard_covenant_calling_quest:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
   expiration:SetPoint("BOTTOM", blizzard_covenant_calling_quest, "BOTTOM", 0, 0)
   expiration:SetJustifyH("CENTER")
   local fontFile, height, flags = expiration:GetFont()
   expiration:SetFont(fontFile, height, (flags or "") .. ',OUTLINE')

   return expiration
end)

addon_env.child_frame_cache.CallingObjectiveText = addon_env.BuildChildFrameCache(function(blizzard_covenant_calling_quest)
   local objective = blizzard_covenant_calling_quest:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
   local attach = addon_env.child_frame_cache.CallingExpirationText[blizzard_covenant_calling_quest]
   objective:SetPoint("BOTTOM", attach, "TOP", 0, 0)
   objective:SetJustifyH("CENTER")
   local fontFile, height, flags = objective:GetFont()
   objective:SetFont(fontFile, height, (flags or "") .. ',OUTLINE')

   return objective
end)

local qel_success = {}
local function RetryQuestTimeLeft(questID, callback)
   -- QuestEventListener alone is not enough, so combine it with .After
   local last_success = qel_success[questID]
   if last_success and ((GetTime() - last_success) > 60) then
      last_success = nil
      qel_success[questID] = last_success
   end

   if not last_success then
      return QuestEventListener:AddCallback(questID, function()
         qel_success[questID] = GetTime()
         return callback()
      end)
   end

   return C_Timer.After(0.5, callback)
end

local quest_locations = {
   (C_Map.GetAreaInfo(10534)), -- "Bastion"
   (C_Map.GetAreaInfo(10413)), -- "Revendreth"
   (C_Map.GetAreaInfo(11510)), -- "Ardenweald"
   (C_Map.GetAreaInfo(11462)), -- "Maldraxxus"
   (C_Map.GetAreaInfo(11400)), -- "The Maw"
   (GetDifficultyInfo(167)),   -- "Torghast", also GroupFinderCategory:113
}

local coin_of_brokerage = Item:CreateFromItemID(179327)
local coin_of_brokerage_name = ""
local rare_resources_quest_name = ""
local shortests_coin_of_brokerage_location
coin_of_brokerage:ContinueOnItemLoad(function()
     coin_of_brokerage_name = coin_of_brokerage:GetItemName()
end)

local cache_quest_id_to_location = {
}

local function GetRareResourcesShortestWidthString(questID)
   if rare_resources_quest_name == nil or rare_resources_quest_name == "" then rare_resources_quest_name = QuestUtils_GetQuestName(questID) end
   if rare_resources_quest_name == nil or rare_resources_quest_name == "" then return end
   if coin_of_brokerage_name == nil or coin_of_brokerage_name == "" then return end

   local _, tmp_widget = next(addon_env.child_frame_cache.CallingObjectiveText)
   local old_text = tmp_widget:GetText()

   tmp_widget:SetText(coin_of_brokerage_name)
   local width1 = tmp_widget:GetWidth()
   tmp_widget:SetText(rare_resources_quest_name)
   local width2 = tmp_widget:GetWidth()
   tmp_widget:SetText(old_text)

   shortests_coin_of_brokerage_location = (width1 < width2) and coin_of_brokerage_name or rare_resources_quest_name
   return shortests_coin_of_brokerage_location
end

local function GetCallingLocation(questID, text, objectiveType, required)
   -- rare resources
   if objectiveType == "item" and required == 3 then
      local location = shortests_coin_of_brokerage_location or GetRareResourcesShortestWidthString(questID) or QuestUtils_GetQuestName(questID) or ""
      if shortests_coin_of_brokerage_location then cache_quest_id_to_location[questID] = shortests_coin_of_brokerage_location end
      return location
   end

   if not text then text = QuestUtils_GetQuestName(questID) end
   for idx = 1, #quest_locations do
      local location = quest_locations[idx]
      if string.match(text, location) then
         location = quest_locations[idx]
         cache_quest_id_to_location[questID] = location
         return location
      end
   end

   -- return "The Maw" for "kill 3" quests and cache them
   if objectiveType == "monster" and required == 3 then
      location = quest_locations[5]
      cache_quest_id_to_location[questID] = location
      return location
   end

   -- if nothing matched, assume it's home location for "complete 3 quests at home" and don't cache it
   local covenant_id = C_Covenants.GetActiveCovenantID()
   if     covenant_id == Enum.CovenantType.Kyrian    then return quest_locations[1]
   elseif covenant_id == Enum.CovenantType.Venthyr   then return quest_locations[2]
   elseif covenant_id == Enum.CovenantType.NightFae  then return quest_locations[3]
   elseif covenant_id == Enum.CovenantType.Necrolord then return quest_locations[4]
   end
end

local function GetCallingObjectiveByQuestID(questID)
   local text, objectiveType, finished, fulfilled, required = GetQuestObjectiveInfo(questID, 1, false)
   local location = cache_quest_id_to_location[questID]
   if not location then
      location = GetCallingLocation(questID, text, objectiveType, required)
   else
   end

   if fulfilled == nil then
      return location
   elseif objectiveType == "progressbar" then
      return GetQuestProgressBarPercent(questID) .. '% ' .. location
   else
      return fulfilled .. '/' .. required .. ' ' .. location
   end
end

local expiration_text_args = { if_more_than_day_show_only_days = true }
local function CovenantCallingQuestMixin_GMMHook_Update(self)
   local expiration_text_widget = addon_env.child_frame_cache.CallingExpirationText[self]
   local objective_text_widget = addon_env.child_frame_cache.CallingObjectiveText[self]

   local questID = self.calling.questID

   if not questID then
      objective_text_widget:SetText(nil)
      return expiration_text_widget:SetText(nil)
   end

   if C_QuestLog.ReadyForTurnIn(questID) then
      objective_text_widget:SetText(nil)
   else
      objective_text_widget:SetText(GetCallingObjectiveByQuestID(questID))
   end

   local secondsRemaining = C_TaskQuest.GetQuestTimeLeftSeconds(questID)

   if not secondsRemaining then
      -- data is not loaded yet, print ticker and retry,
      expiration_text_widget:SetText(string.rep('.', GetTime() % 3 + 1))
      return RetryQuestTimeLeft(questID, function() return CovenantCallingQuestMixin_GMMHook_Update(self) end)
   end

   return a_env.SetFormattedExpirationText(expiration_text_widget, secondsRemaining, expiration_text_args)
end

local function Blizzard_CovenantCallings_GMMHook_Init()
   hooksecurefunc(CovenantCallingQuestMixin, "Update", CovenantCallingQuestMixin_GMMHook_Update)
end

local function InitUI(gmm_options)
   MissionPage_RatioInit(gmm_options)
   hooksecurefunc(CovenantMissionFrame, "UpdateAllyPower", UpdateEnemyToAllyPowerRatio)

   EventUtil.ContinueOnAddOnLoaded("Blizzard_CovenantCallings", Blizzard_CovenantCallings_GMMHook_Init)
end

addon_env.AddInitUI({
   follower_type = Enum.GarrisonFollowerType.FollowerType_9_0_GarrisonFollower,
   gmm_prefix    = 'Covenant',
   init          = InitUI,
})

