-- [AUTOLOCAL START]
local ITEM_QUALITY_COLORS = ITEM_QUALITY_COLORS
local GetItemInfo = GetItemInfo
-- [AUTOLOCAL END]

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