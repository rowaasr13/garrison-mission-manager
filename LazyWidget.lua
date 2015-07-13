local addon_name, addon_env = ...

-- [AUTOLOCAL START]
local CreateFrame = CreateFrame
local GetItemInfo = GetItemInfo
local tinsert = table.insert
local tremove = table.remove
-- [AUTOLOCAL END]

local event_frame = CreateFrame("Frame")
local event_handlers = {}
event_frame:SetScript("OnEvent", function(self, event, ...)
   local handler = event_handlers[event]
   if handler then return handler(self, event, ...) end
end)

local pending_item_textures = {}
local function ApplyPendingItemTextures(self)
   for idx = #pending_item_textures, 1, -1 do
      local entry = pending_item_textures[idx]
      local item_id = entry[3]
      local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, itemSellPrice = GetItemInfo(item_id)
      if itemTexture then
         local widget = entry[1]
         widget[entry[2]](widget, itemTexture)
         tremove(pending_item_textures, idx)
      end
   end
   if #pending_item_textures == 0 then self:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
end
event_handlers.GET_ITEM_INFO_RECEIVED = ApplyPendingItemTextures

local function SetTextureOrItem(widget, method, texture, item_id)
   if texture then
      widget[method](widget, texture)
      return
   end
   if item_id then
      local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, itemSellPrice = GetItemInfo(item_id)
      if itemTexture then
         widget[method](widget, itemTexture)
      else
         widget[method](widget, 0, 0, 0, 0)
         tinsert(pending_item_textures, { widget, method, item_id })
         event_frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
      end
      return
   end
end

local points = { "BOTTOMRIGHT", "BOTTOMLEFT", "TOPLEFT" }

local function Widget(a)
   local type = a.type or a[1]
   local parent = a.parent or a[2]
   local template = a.template or a[3]

   local widget
   if type == "Texture" then
      widget = parent:CreateTexture(nil, a.Layer, template, a.SubLayer)
   elseif type == "FontString" then
      widget = parent:CreateFontString(nil, a.Layer, template)
   else
      widget = CreateFrame(type, nil, parent, template)
   end
   if a.Hide then widget:Hide() end
   local prop = a.Atlas if prop then widget:SetAtlas(prop, a.AtlasSize) end
   local prop = a.Width if prop then widget:SetWidth(prop) end
   local prop = a.Height if prop then widget:SetHeight(prop) end

   for idx = 1, #points do
      local point_name = points[idx]
      local prop = a[point_name] if prop then
         if prop == true then widget:SetPoint(point_name, parent, point_name, 0, 0)
         elseif #prop == 2 then widget:SetPoint(point_name, parent, point_name, prop[1], prop[2]) end
      end
   end

   local texture, item_id
   local prop = a.TextureToItem if prop then
      item_id = prop
   end
   if type == "Button" then
      local prop = a.NormalTexture if prop then texture = prop end
      SetTextureOrItem(widget, 'SetNormalTexture', texture, item_id)
      local prop = a.HighlightTexture if prop then
         -- if type(prop)
      end
   else
      SetTextureOrItem(widget, 'SetTexture', texture, item_id)
   end

   local prop = a.Color if prop then widget:SetTexture(prop[1], prop[2], prop[3], prop[4]) end

   local prop = a.Text if prop then widget:SetText(prop) end

   local prop = a.FrameLevelOffset if prop then widget:SetFrameLevel(widget:GetFrameLevel() + prop) end

   local prop = a.OnClick if prop then widget:SetScript("OnClick", prop) end
   local prop = a.OnEnter if prop then widget:SetScript("OnEnter", prop) end
   local prop = a.OnLeave if prop then widget:SetScript("OnLeave", prop) end

   return widget
end
addon_env.Widget = Widget