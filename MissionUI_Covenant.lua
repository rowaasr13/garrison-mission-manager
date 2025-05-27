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
   ratio_current_health:SetWidth(50)
   ratio_current_health:SetHeight(0)
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

   if alliesWinTurn < enemiesWinTurn then
      -- allies winning faster -> success rate is better than 50/50
      if is_devel then print("ally win confidence:", enemiesWinTurn / alliesWinTurn) end
      ratio_current_health:SetFormattedText("W %0.2f", enemiesWinTurn / alliesWinTurn)
   else
      -- enemies winning faster
      if is_devel then print("enemy confidence (we lose):",  alliesWinTurn / enemiesWinTurn) end
      ratio_current_health:SetFormattedText("L %0.2f", alliesWinTurn / enemiesWinTurn)
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

local expiration_text_args = { if_more_than_day_show_only_days = true }
local function CovenantCallingQuestMixin_GMMHook_Update(self)
   local expiration_text_widget = addon_env.child_frame_cache.CallingExpirationText[self]
   local questID = self.calling.questID

   if not questID then return expiration_text_widget:SetText(nil) end

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

