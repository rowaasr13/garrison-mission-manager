local addon_name, addon_env = ...

local function Widget(a)
   local type = a.type or a[1]
   local parent = a.parent or a[2]
   local template = a.template or a[3]

   local widget
   if type == "Texture" then
      widget = parent:CreateTexture(nil, a.Layer, template, a.SubLayer)
   else
      widget = CreateFrame(type, nil, parent, template)
   end
   if a.Hide then widget:Hide() end   
   local prop = a.Width if prop then widget:SetWidth(prop) end
   local prop = a.Height if prop then widget:SetHeight(prop) end
   local prop = a.BOTTOMLEFT if prop then
      if #prop == 2 then widget:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", prop[1], prop[2]) end
   end
   local prop = a.Color if prop then widget:SetTexture(prop[1], prop[2], prop[3], prop[4]) end
   local prop = a.FrameLevelOffset if prop then widget:SetFrameLevel(widget:GetFrameLevel() + prop) end
   local prop = a.OnClick if prop then widget:SetScript("OnClick", prop) end
      
   return widget
end
addon_env.Widget = Widget