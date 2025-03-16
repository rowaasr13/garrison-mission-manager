local addon_name, addon_env = ...
local a_name, a_env = ...
if not addon_env.load_this then return end

local menu_data = {
   { type = "garrison", id = Enum.GarrisonType.Type_6_0_Garrison, menu_button_text = _G.EXPANSION_NAME5 },
   { type = "garrison", id = Enum.GarrisonType.Type_7_0_Garrison, menu_button_text = _G.EXPANSION_NAME6 },
   { type = "garrison", id = Enum.GarrisonType.Type_8_0_Garrison, menu_button_text = _G.EXPANSION_NAME7 },
   { type = "garrison", id = Enum.GarrisonType.Type_9_0_Garrison, menu_button_text = _G.EXPANSION_NAME8, has_sections = true },
}

function GMMExpansionLandingPagesMenu(owner, rootDescription)
   rootDescription:CreateTitle(GARRISON_MISSIONS)

   for idx = 1, #menu_data do repeat
      local button_data = menu_data[idx]
      local garrison_id = button_data.id
      local click_handler = button_data.click_handler
      if not click_handler then
         local has_sections = button_data.has_sections
         click_handler = function(data)
            if (GarrisonLandingPage and GarrisonLandingPage:IsShown() and GarrisonLandingPage.garrTypeID == garrison_id) then return end
            HideUIPanel(GarrisonLandingPage)
            local sections = GarrisonLandingPage.Report.Sections
            if has_sections then sections:Show() else sections:Hide() end
            ShowGarrisonLandingPage(garrison_id)

            GarrisonLandingPageTab3:SetScript("OnEnter", nil) -- Blizz bug
            GarrisonLandingPageTab3:SetScript("OnLeave", nil) -- Blizz bug
         end
         button_data.click_handler = click_handler
      end

      local menu_button = rootDescription:CreateButton(button_data.menu_button_text, click_handler)
      menu_button:SetEnabled(C_Garrison.IsLandingPageMinimapButtonVisible(garrison_id))
   until true end
end

local original_onclick = ExpansionLandingPageMinimapButton:GetScript("OnClick")
local function ExpansionLandingPageMinimapButton_GMMOnClickPreHook(self, button, down)
   if button == "RightButton" then
      MenuUtil.CreateContextMenu(self, GMMExpansionLandingPagesMenu)
      return
   end

   return original_onclick(self, button, down)
end
ExpansionLandingPageMinimapButton:SetScript("OnClick", ExpansionLandingPageMinimapButton_GMMOnClickPreHook)
ExpansionLandingPageMinimapButton:RegisterForClicks("AnyUp")
