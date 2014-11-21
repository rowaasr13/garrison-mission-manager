local dump = DevTools_Dump
local tinsert = table.insert
local wipe = wipe
local pairs = pairs

local buttons = {}

-- function dumpl(pattern, ...)
-- 	local names = { strsplit(",", pattern) }
-- 	for idx = 1, select('#', ...) do
-- 		local name = names[idx]
-- 		if name then name = name:gsub("^%s+", ""):gsub("%s+$", "") end
-- 		print(GREEN_FONT_COLOR_CODE, idx, name, FONT_COLOR_CODE_CLOSE)
-- 		dump(select(idx, ...))
-- 	end
-- end

local min, max = {}, {}
local top = {{}, {}, {}, {}}
local function FindBestFollowersForMission(mission, followers)
	local followers_count = #followers

	for idx = 1, 3 do
		wipe(top[idx])
	end

	local slots = mission.numFollowers
	if slots > followers_count then return end

	local mission_id = mission.missionID
	if C_Garrison.GetNumFollowersOnMission(mission_id) > 0 then
		for idx = 1, #followers do
			C_Garrison.RemoveFollowerFromMission(mission_id, followers[idx].followerID)
		end
	end

	for idx = 1, slots do
	    max[idx] = followers_count - slots + idx
	    min[idx] = nil
	end
	for idx = slots+1, 3 do
	    max[idx] = followers_count + 1
	    min[idx] = followers_count + 1
	end

	local currency_rewards
	for _, reward in pairs(mission.rewards) do
		if reward.currencyID then currency_rewards = true break end
	end

	for i1 = 1, max[1] do
	    for i2 = min[2] or (i1 + 1), max[2] do
	        for i3 = min[3] or (i2 + 1), max[3] do
	        	-- Assign followers to mission
	        	local follower1 = followers[i1]
	            if not C_Garrison.AddFollowerToMission(mission_id, follower1.followerID) then --[[ error handling! ]] end
	            local follower2 = followers[i2]
	            if follower2 and not C_Garrison.AddFollowerToMission(mission_id, follower2.followerID) then --[[ error handling! ]] end
	            local follower3 = followers[i3]
	            if follower3 and not C_Garrison.AddFollowerToMission(mission_id, follower3.followerID) then --[[ error handling! ]] end

	            -- Calculate result
	            local totalTimeString, totalTimeSeconds, isMissionTimeImproved, successChance, partyBuffs, isEnvMechanicCountered, xpBonus, materialMultiplier = C_Garrison.GetPartyMissionInfo(mission_id)
	            for idx = 1, 3 do
	            	local current = top[idx]
	            	local found
	            	repeat -- Checking if new candidate for top is better than any top 3 already sored
	            		-- TODO: risk lower chance mission if material multiplier gives better average result
	            		if not current[1] then found = true break end

	            		if current.successChance < successChance then found = true break end
	            		if current.successChance > successChance then break end

	            		if currency_rewards then
	            			if current.materialMultiplier < materialMultiplier then found = true break end
	            			if current.materialMultiplier > materialMultiplier then break end
	            		end

	            		if current.xpBonus < xpBonus then found = true break end
	            		if current.xpBonus > xpBonus then break end

	            		if current.totalTimeSeconds > totalTimeSeconds then found = true break end
	            		if current.totalTimeSeconds < totalTimeSeconds then break end
	            	until true
	            	if found then
	            		local new = top[4]
	            		new[1] = follower1
	            		new[2] = follower2
	            		new[3] = follower3
	            		new.successChance = successChance
	            		new.materialMultiplier = materialMultiplier
	            		new.xpBonus = xpBonus
	            		new.totalTimeSeconds = totalTimeSeconds
	            		tinsert(top, idx, new)
	            		top[5] = nil
	            		break
	            	end
	            end

	            -- Unasssign
	            C_Garrison.RemoveFollowerFromMission(mission_id, follower1.followerID)
	            if follower2 then C_Garrison.RemoveFollowerFromMission(mission_id, follower2.followerID) end
	            if follower3 then C_Garrison.RemoveFollowerFromMission(mission_id, follower3.followerID) end
	        end
	    end
	end

	-- dump(top)
	-- local location, xp, environment, environmentDesc, environmentTexture, locPrefix, isExhausting, enemies = C_Garrison.GetMissionInfo(missionID);
	-- /run dumpl("location, xp, environment, environmentDesc, environmentTexture, locPrefix, isExhausting, enemies", C_Garrison.GetMissionInfo(GarrisonMissionFrame.MissionTab.MissionPage.missionInfo.missionID))
	-- /run dumpl("totalTimeString, totalTimeSeconds, isMissionTimeImproved, successChance, partyBuffs, isEnvMechanicCountered, xpBonus, materialMultiplier", C_Garrison.GetPartyMissionInfo(GarrisonMissionFrame.MissionTab.MissionPage.missionInfo.missionID))
	-- /run GMM_BestForCurrentSelectedMission()
end

local filtered_followers = {}
local filtered_followers_count
local available_missions = {}
function GMM_BestForCurrentSelectedMission()
	local GarrisonMissionFrame = GarrisonMissionFrame
	if not GarrisonMissionFrame then return end
	local MissionPage = GarrisonMissionFrame.MissionTab.MissionPage
	if not MissionPage then return end
	local missionInfo = MissionPage.missionInfo
	if not missionInfo then return end
	local mission_id = missionInfo.missionID

	-- print("Mission ID:", mission_id)

	local followers = C_Garrison.GetFollowers()
	wipe(filtered_followers)
	filtered_followers_count = 0
	for idx = 1, #followers do
		local follower = followers[idx]
		repeat
			if not follower.isCollected then break end
			local status = follower.status
			if status then break end

			filtered_followers_count = filtered_followers_count + 1
			filtered_followers[filtered_followers_count] = follower
		until true
	end
	-- dump(filtered_followers)

	C_Garrison.GetAvailableMissions(available_missions)
	local mission
	for idx = 1, #available_missions do
		if available_missions[idx].missionID == mission_id then
			mission = available_missions[idx]
			break
		end
	end

	-- dump(mission)

	FindBestFollowersForMission(mission, filtered_followers)

	if not buttons['MissionPage1'] then GMM_ButtonsInit() end
	for idx = 1, 3 do
		local button = buttons['MissionPage' .. idx]
		local top_entry = top[idx]
		button[1] = top_entry[1] and top_entry[1].followerID or nil
		button[2] = top_entry[2] and top_entry[2].followerID or nil
		button[3] = top_entry[3] and top_entry[3].followerID or nil
		if top_entry.successChance then button:SetFormattedText("%d%%", top_entry.successChance) else button:SetText("") end
	end

end

local function PartyButtonOnClick(self)
	if self[1] then
		local MissionPageFollowers = GarrisonMissionFrame.MissionTab.MissionPage.Followers
		for idx = 1, #MissionPageFollowers do
			local followerFrame = MissionPageFollowers[idx]
			local follower = self[idx]
			if follower then
				local followerInfo = C_Garrison.GetFollowerInfo(follower)
				GarrisonMissionPage_SetFollower(followerFrame, followerInfo)
			end
		end
	end

	GarrisonMissionPage_UpdateMissionForParty()
end

function GMM_ButtonsInit()
	local prev
	for idx = 1, 3 do
		if not buttons['MissionPage' .. idx] then
			local set_followers_button = CreateFrame("Button", nil,  GarrisonMissionFrame.MissionTab.MissionPage, "UIPanelButtonTemplate")
			set_followers_button:SetText(idx)
			set_followers_button:SetWidth(100)
			set_followers_button:SetHeight(50)
			if not prev then
				set_followers_button:SetPoint("TOPLEFT", GarrisonMissionFrame.MissionTab.MissionPage, "TOPRIGHT", 0, 0)
			else
				set_followers_button:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 0)
			end
			set_followers_button:SetScript("OnClick", PartyButtonOnClick)
			set_followers_button:Show()
			prev = set_followers_button
			buttons['MissionPage' .. idx] = set_followers_button
		end
	end
end
if GarrisonMissionFrame and GarrisonMissionFrame.MissionTab.MissionPage then
	GMM_ButtonsInit()
	hooksecurefunc("GarrisonMissionPage_ShowMission", GMM_BestForCurrentSelectedMission)
end

-- TODO: init in ADDON_LOADED instead