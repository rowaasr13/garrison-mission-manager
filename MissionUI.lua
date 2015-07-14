local addon_name, addon_env = ...

-- [AUTOLOCAL START]
local ITEM_QUALITY_COLORS = ITEM_QUALITY_COLORS
local GetItemInfo = GetItemInfo
local CastSpellOnFollower = C_Garrison.CastSpellOnFollower
local FollowerTab = GarrisonMissionFrame.FollowerTab
local GetFollowerInfo = C_Garrison.GetFollowerInfo
local GetFollowerItems = C_Garrison.GetFollowerItems
local GetFollowerAbilities = C_Garrison.GetFollowerAbilities
-- [AUTOLOCAL END]

local Widget = addon_env.Widget
local event_frame = addon_env.event_frame
local event_handlers = addon_env.event_handlers

hooksecurefunc("GarrisonMissionButton_SetRewards", function(self, rewards, numRewards)
   local index = 1
   local Rewards = self.Rewards
   for id, reward in pairs(rewards) do
      local button = Rewards[index]
      local item_id = reward.itemID
      if item_id and reward.quantity == 1 then
         local _, _, itemRarity, itemLevel = GetItemInfo(item_id)
         if itemRarity and itemLevel and itemLevel >= 500 then
            local Quantity = button.Quantity
            Quantity:SetText(ITEM_QUALITY_COLORS[itemRarity].hex .. itemLevel)
            Quantity:Show()
         end
      end
      index = index + 1
   end
end)

local function SetGameTooltipToItem(self)
   GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
   if (self.itemID) then
      GameTooltip:SetItemByID(self.itemID)
      return
   end
end

local upgrade_items = {
   { parent = FollowerTab.ItemWeapon, 114128, 114129, 114131, 114616, 114081, 114622, 120302 },
   { parent = FollowerTab.ItemArmor,  114745, 114808, 114822, 114807, 114806, 114746, 120301 },
}

local uprade_item_strength = {
   [114128] = 3,
   [114129] = 6,
   [114131] = 9,
   [114616] = 615,
   [114081] = 630,
   [114622] = 645,
   [114745] = 3,
   [114808] = 6,
   [114822] = 9,
   [114807] = 615,
   [114806] = 630,
   [114746] = 645,
}

local upgrade_item_buttons = {}
local upgrade_item_normal_textures = {}
local upgrade_item_quantity = {}
local upgrade_buttons_parent = CreateFrame("Frame", nil, FollowerTab.ItemWeapon)
local function UpdateUpgradeItemStates(frame, followerID, followerInfo)
   if not followerID then
      followerID = FollowerTab.followerID
      if not followerID then return end
      if not followerInfo then followerInfo = GetFollowerInfo(followerID) end
   end

   if not followerInfo.isCollected then return end
   if followerInfo.level < GARRISON_FOLLOWER_MAX_LEVEL then return end

   upgrade_buttons_parent:Show()
   local _, ilvl_weapon, _, ilvl_armor = GetFollowerItems(followerID)

   for item_type = 1, #upgrade_items do
      local ilvl_current_type = item_type == 1 and ilvl_weapon or ilvl_armor
      local item_list = upgrade_items[item_type]
      local prev = item_list.parent
      for item_idx = 1, #item_list do
         local item_id = item_list[item_idx]

         local count = GetItemCount(item_id)
         if count > 0 then
            upgrade_item_quantity[item_id]:SetText(count)
            local texture = upgrade_item_normal_textures[item_id]
            texture:SetDesaturated(false)
            texture:SetAlpha(1)

            local strength = uprade_item_strength[item_id]
            if strength then
               local action_button_type = "macro"
               local shift_action_button_type = "macro"
               if ilvl_current_type == 675 or (strength > 600 and ilvl_current_type >= strength) then
                  -- Fadeout and disable button if upgrade is absolutely useless
                  -- i.e. follower has max level or fixed level upgrade is lower than follower current ilevel
                  texture:SetVertexColor(1, 1, 1)
                  texture:SetAlpha(0.3)
                  action_button_type = nil
                  shift_action_button_type = nil
               elseif (strength > 3 and strength < 100 and ilvl_current_type + strength > 677) or (strength > 600 and strength - ilvl_current_type < 7) then
                  -- Dye upgrade yellow and allow only forced use through shift-click if it would be too much waste to use it
                  -- i.e fixed level upgrade providing less than 7 levels or small upgrades providing less than 4 levels.
                  texture:SetVertexColor(1, 1, 0)
                  action_button_type = nil
               else
                  texture:SetVertexColor(1, 1, 1)
               end
               local button = upgrade_item_buttons[item_id]
               button:SetAttribute("type", action_button_type)
               button:SetAttribute("shift-type*", shift_action_button_type)
            end
         else
            upgrade_item_quantity[item_id]:SetText(nil)
            local texture = upgrade_item_normal_textures[item_id]
            texture:SetDesaturated(true)
            texture:SetAlpha(0.3)
            texture:SetVertexColor(1, 1, 1)
         end
      end
   end
end

local mechanic_id = {}
for idx, data in pairs (C_Garrison.GetAllEncounterThreats(LE_FOLLOWER_TYPE_GARRISON_6_0)) do
   tinsert(mechanic_id, data.id)
end

hooksecurefunc(GarrisonMissionFrame.FollowerList, "ShowFollower", function(self)
   local followerID = FollowerTab.followerID
   if not followerID then return end
   local followerInfo = GetFollowerInfo(followerID)

   UpdateUpgradeItemStates(self, followerID, followerInfo)
end)

local function EventToUpdateUpgradeItemStates(self) return UpdateUpgradeItemStates(self) end

event_handlers.BAG_UPDATE_DELAYED = EventToUpdateUpgradeItemStates
event_handlers.PLAYER_REGEN_ENABLED = EventToUpdateUpgradeItemStates
event_handlers.PLAYER_REGEN_DISABLED = function()
   upgrade_buttons_parent:Hide()
end
upgrade_buttons_parent:HookScript("OnShow", function(self)
   EventToUpdateUpgradeItemStates(self)
   event_frame:RegisterEvent("BAG_UPDATE_DELAYED")
   event_frame:RegisterEvent("PLAYER_REGEN_ENABLED")
   event_frame:RegisterEvent("PLAYER_REGEN_DISABLED")
end)
upgrade_buttons_parent:HookScript("OnHide", function()
   event_frame:UnregisterEvent("BAG_UPDATE_DELAYED")
   event_frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
   event_frame:UnregisterEvent("PLAYER_REGEN_DISABLED")
end)

local template_upgrade_button = {
   "Button",
   upgrade_buttons_parent,
   "SecureActionButtonTemplate,SecureHandlerMouseUpDownTemplate",
   Height = 42, Width = 42,
   OnEnter = SetGameTooltipToItem,
   OnLeave = addon_env.HideGameTooltip,
   -- HighlightTexture = Widget{
   --    "Texture",
   --    Texture = "Interface\\BUTTONS\\UI-Common-MouseHilight",
   --    TexCoord = { 0.15, 0.85, 0.15, 0.85 },
   --    BlendMode = "ADD",
   -- },
}
for item_type = 1, #upgrade_items do
   local item_list = upgrade_items[item_type]
   local prev = item_list.parent
   for item_idx = 1, #item_list do
      local item_id = item_list[item_idx]
      template_upgrade_button.TextureToItem = item_id
      local u = Widget(template_upgrade_button)
      u.itemID = item_id
      u:SetPoint("LEFT", prev, "RIGHT", 1, 0)

      local strength = uprade_item_strength[item_id]
      if strength then
         -- Widget{"FontString", u, "NumberFontNormal", TOPLEFT = true, Text = strength > 100 and strength or "+" .. strength}
         local macro_text = "/use item:" .. item_id .."\n/run C_Garrison.CastSpellOnFollower(GarrisonMissionFrame.FollowerTab.followerID)"
         u:SetAttribute("type", "macro")
         u:SetAttribute("macrotext", macro_text)
         u:SetAttribute("shift-type*", "macro")
         u:SetAttribute("shift-macrotext*", macro_text)
      else
         u:SetAttribute("type", "item")
         u:SetAttribute("item", "item:" .. item_id)
      end

      upgrade_item_normal_textures[item_id] = u:GetNormalTexture()
      upgrade_item_quantity[item_id] = Widget{"FontString", u, "NumberFontNormal", BOTTOMRIGHT = true }

      upgrade_item_buttons[item_id] = u
      prev = u
   end
end