-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this file,
-- You can obtain one at http://mozilla.org/MPL/2.0/.

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

local VERSION = "10.0.16"
local NAME = "FloFlyout"
local SPELLFLYOUT_DEFAULT_SPACING = 4
local SPELLFLYOUT_INITIAL_SPACING = 7
local SPELLFLYOUT_FINAL_SPACING = 4
local STRIPE_COLOR = {r=0.9, g=0.9, b=1}

-------------------------------------------------------------------------------
-- Variables
-------------------------------------------------------------------------------
local _
local _classicUI

FLOFLYOUT_CONFIG = {
	flyouts = {
		--[[ Sample config : each flyout can have a list of actions and an icon
		[1] = {
			actionTypes = {
				[1] = "spell",
				[2] = "item",
				[3] = "macro",
				[4] = "pet"
			},
			spells,
				[1] = 8024, -- Flametongue
				[2] = 8033, -- Frostbite
				[3] = 8232, -- Windfury
				[4] = 8017, -- RockBite
				[5] = 51730, -- earthliving
			},
			icon = ""
		},
		]]
	},
	actions = {
		[1] = {
			--[[ Sample config : for each talent group there is a list of actions bound to flyouts
			[13] = 1,
			[49] = 1,
			[25] = 1,
			]]
		},
		[2] = {
		},
		[3] = {
		},
		[4] = {
		},
		[5] = {
		},
	}
}

local FloFlyout = {
	openers = {},
	config = FLOFLYOUT_CONFIG
}

local L = FLOFLYOUT_L10N_STRINGS

-------------------------------------------------------------------------------
-- Functions
-------------------------------------------------------------------------------

function FloFlyout.ReadCmd(line)
	local cmd, arg1, arg2 = strsplit(' ', line or "", 3);

	if cmd == "addflyout" then
		DEFAULT_CHAT_FRAME:AddMessage("New flyout : "..FloFlyout:AddFlyout())
	elseif cmd == "removeflyout" and FloFlyout:IsValidFlyoutId(arg1) then
		FloFlyout:RemoveFlyout(arg1)
		FloFlyout:ApplyConfig()
	elseif cmd == "addspell" and FloFlyout:IsValidFlyoutId(arg1) then
		DEFAULT_CHAT_FRAME:AddMessage("New spell : "..FloFlyout:AddSpell(arg1, arg2))
		FloFlyout:ApplyConfig()
	elseif cmd == "removespell" and FloFlyout:IsValidFlyoutId(arg1) and FloFlyout:IsValidSpellPos(arg1, arg2) then
		FloFlyout:RemoveSpell(arg1, arg2)
		FloFlyout:ApplyConfig()
	elseif cmd == "bind" and tonumber(arg1) and FloFlyout:IsValidFlyoutId(arg2) then
		FloFlyout:AddAction(arg1, arg2)
		FloFlyout:ApplyConfig()
	elseif cmd == "unbind" and tonumber(arg1) then
		FloFlyout:RemoveAction(arg1)
		FloFlyout:ApplyConfig()
	elseif cmd == "apply" then
		FloFlyout:ApplyConfig()
	else
		DEFAULT_CHAT_FRAME:AddMessage(L["USAGE"]);
		return;
	end
end

-- Executed on load, calls general set-up functions
function FloFlyout_OnLoad(self)

	DEFAULT_CHAT_FRAME:AddMessage( "|cffd78900"..NAME.." v"..VERSION.."|r loaded." )

	SLASH_FLOFLYOUT1 = "/floflyout"
	SLASH_FLOFLYOUT2 = "/ffo"
	SlashCmdList["FLOFLYOUT"] = FloFlyout.ReadCmd

	StaticPopupDialogs["CONFIRM_DELETE_FLO_FLYOUT"] = {
		text = L["CONFIRM_DELETE"],
		button1 = YES,
		button2 = NO,
		OnAccept = function (self) FloFlyout:RemoveFlyout(self.data); FloFlyout.ConfigPane_Update(); FloFlyout:ApplyConfig(); end,
		OnCancel = function (self) end,
		hideOnEscape = 1,
		timeout = 0,
		exclusive = 1,
		whileDead = 1,
	}

	self:RegisterEvent("ADDON_LOADED")
	self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	--self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")

	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("PLAYER_ALIVE")
	self:RegisterEvent("UPDATE_BINDINGS")
	self:RegisterEvent("ACTIONBAR_SLOT_CHANGED")

	_classicUI = _G["ClassicUI"]
	if _classicUI then
		DEFAULT_CHAT_FRAME:AddMessage( NAME.." : |cffd78900ClassicUI v".._classicUI.VERSION.."|r detected." )
		local cuipew = _classicUI.MF_PLAYER_ENTERING_WORLD
		_classicUI.MF_PLAYER_ENTERING_WORLD = function (cui)
			cuipew(cui)
			FloFlyout:ApplyConfig()
		end
	end

end

function FloFlyout_OnEvent(self, event, arg1, ...)

	if event == "PLAYER_ENTERING_WORLD" --[[or event == "PLAYER_ALIVE"]] then

		if not _classicUI or not _classicUI:IsEnabled() then
			FloFlyout:ApplyConfig()
		end

	--elseif event == "SPELL_UPDATE_COOLDOWN" or event == "ACTIONBAR_UPDATE_USABLE" then

	elseif event == "ADDON_LOADED" and arg1 == NAME then

		self:UnregisterEvent("ADDON_LOADED")
		-- Ici, nous avons rechargé notre configuration
		FloFlyout.config = FLOFLYOUT_CONFIG

		for i, button in ipairs({FloFlyoutFrame:GetChildren()}) do
			if button:GetObjectType() == "CheckButton" then
				SecureHandlerWrapScript(button, "OnClick", button, "self:GetParent():Hide()")
			end
		end

		FloFlyoutConfigFlyoutFrame.IsConfig = true
		
		for _, flyout in ipairs(FloFlyout.config.flyouts) do
			if flyout.actionTypes == nil then
				flyout.actionTypes = {}
				for i, _ in ipairs(flyout.spells) do
					flyout.actionTypes[i] = "spell"
				end
			end
			if flyout.mountIndex == nil then
				flyout.mountIndex = {}
			end
			if flyout.spellNames == nil then
					flyout.spellNames = {}
			end
		end

		for i=3,5 do
			if FloFlyout.config.actions[i] == nil then
				FloFlyout.config.actions[i] = {}
			end
		end

	elseif event == "ACTIONBAR_SLOT_CHANGED" then
		local idAction = arg1
		-- Dans tous les cas, si nous avions un flyout sur cette action, il faut l'enlever de l'action et le mettre dans le curseur
		local configChanged
		local oldFlyoutId = FloFlyout.config.actions[GetSpecialization()][idAction]

		local actionType, id, subType = GetActionInfo(idAction)
		-- Si actionType vide, c'est sans doute que l'on vient de détruire la macro bidon
		if not actionType then
			return
		elseif actionType == "macro" then
			local name, texture, body = GetMacroInfo(id)
			if name == "__ffodnd" then
				FloFlyout:AddAction(idAction, body)
				-- La pseudo macro a fait son travail
				DeleteMacro("__ffodnd")
				configChanged = true
			end
		end
		if oldFlyoutId then
			FloFlyout:PickupFlyout(oldFlyoutId)
			if not configChanged then
				FloFlyout:RemoveAction(idAction)
				configChanged = true
			end
		end
		if configChanged then
			FloFlyout:ApplyConfig()
		end

	elseif event == "UPDATE_BINDINGS" then

	elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
		FloFlyout:ApplyConfig()
	else

	end
end

function FloFlyoutFrame_OnEvent(self, event, ...)
	if event == "SPELL_UPDATE_COOLDOWN" then
		local i = 1
		local button = _G[self:GetName().."Button"..i]
		while (button and button:IsShown() and button.spellID) do
			SpellFlyoutButton_UpdateCooldown(button)
			i = i+1
			button = _G[self:GetName().."Button"..i]
		end
	elseif event == "CURRENT_SPELL_CAST_CHANGED" then
		local i = 1
		local button = _G[self:GetName().."Button"..i]
		while (button and button:IsShown() and button.spellID) do
			SpellFlyoutButton_UpdateState(button)
			i = i+1
			button = _G[self:GetName().."Button"..i]
		end
	elseif event == "SPELL_UPDATE_USABLE" then
		local i = 1
		local button = _G[self:GetName().."Button"..i]
		while (button and button:IsShown() and button.spellID) do
			SpellFlyoutButton_UpdateUsable(button)
			i = i+1
			button = _G[self:GetName().."Button"..i]
		end
	elseif event == "BAG_UPDATE" then
		local i = 1
		local button = _G[self:GetName().."Button"..i]
		while (button and button:IsShown() and button.spellID) do
			SpellFlyoutButton_UpdateCount(button)
			SpellFlyoutButton_UpdateUsable(button)
			i = i+1
			button = _G[self:GetName().."Button"..i]
		end
	elseif event == "SPELL_FLYOUT_UPDATE" then
		local i = 1
		local button = _G[self:GetName().."Button"..i]
		while (button and button:IsShown() and button.spellID) do
			SpellFlyoutButton_UpdateCooldown(button)
			SpellFlyoutButton_UpdateState(button)
			SpellFlyoutButton_UpdateUsable(button)
			SpellFlyoutButton_UpdateCount(button)
			i = i+1
			button = _G[self:GetName().."Button"..i]
		end
	end
end

function FloFlyout:GetTexture(actionType, data)
	if actionType == "spell" then
		return GetSpellTexture(data)
	elseif actionType == "item" then
		return GetItemIcon(data)
	end
end

function FloFlyout:GetName(actionType, data)
	if actionType == "spell" then
		return GetSpellInfo(data)
	elseif actionType == "item" then
		return GetItemInfo(data)
	elseif actionType == "macro" then
	end
end

function FloFlyout:BindFlyoutToAction(idFlyout, idAction)

	local direction, actionButton, actionBarPage, bonusBar, typeActionButton
	typeActionButton = 0
	direction = "UP"

	if idAction <= 12 then
		bonusBar = 0
		actionBarPage = 1
		actionButton = _G["ActionButton"..idAction]
	elseif idAction <= 24 then
		actionBarPage = 2
		actionButton = _G["ActionButton"..(idAction - 12)]
	elseif idAction <= 36 then
		if MultiBar3_IsVisible() then
			actionButton = _G["MultiBarRightButton"..(idAction - 24)]
			direction = "LEFT"
			typeActionButton = 2
		else
			actionBarPage = 3
			actionButton = _G["ActionButton"..(idAction - 24)]
		end
	elseif idAction <= 48 then
		if MultiBar4_IsVisible() then
			actionButton = _G["MultiBarLeftButton"..(idAction - 36)]
			direction = "LEFT"
			typeActionButton = 2
		else
			actionBarPage = 4
			actionButton = _G["ActionButton"..(idAction - 36)]
		end
	elseif idAction <= 60 then
		if MultiBar2_IsVisible() then
			actionButton = _G["MultiBarBottomRightButton"..(idAction - 48)]
			typeActionButton = 1
		else
			actionBarPage = 5
			actionButton = _G["ActionButton"..(idAction - 48)]
		end
	elseif idAction <= 72 then
		if MultiBar1_IsVisible() then
			actionButton = _G["MultiBarBottomLeftButton"..(idAction - 60)]
			typeActionButton = 1
		else
			actionBarPage = 6
			actionButton = _G["ActionButton"..(idAction - 60)]
		end
	elseif idAction <= 84 then
		bonusBar = 1
		actionBarPage = 1
		actionButton = _G["ActionButton"..(idAction - 72)]
	elseif idAction <= 96 then
		bonusBar = 2
		actionBarPage = 1
		actionButton = _G["ActionButton"..(idAction - 84)]
	elseif idAction <= 108 then
		bonusBar = 3
		actionBarPage = 1
		actionButton = _G["ActionButton"..(idAction - 96)]
	elseif idAction <= 120 then
		bonusBar = 4
		actionBarPage = 1
		actionButton = _G["ActionButton"..(idAction - 108)]
	elseif idAction <= 132 then
		bonusBar = 5
		actionBarPage = 1
		actionButton = _G["ActionButton"..(idAction - 120)]
	elseif idAction <= 154 then
		bonusBar = 6
		actionBarPage = 1
		actionButton = _G["ActionButton"..(idAction - 132)]
	elseif idAction <= 166 then
		bonusBar = 7
		actionBarPage = 1
		actionButton = _G["ActionButton"..(idAction - 154)]
	elseif idAction <= 178 then
		bonusBar = 8
		actionBarPage = 1
		actionButton = _G["ActionButton"..(idAction - 166)]
	end

	FloFlyout:CreateOpener("FloFlyoutOpener"..idAction, idFlyout, idAction, direction, actionButton, actionBarPage, bonusBar, typeActionButton)
end

local function Opener_OnReceiveDrag(self)
	if InCombatLockdown() then
		return
	end

	local cursor = GetCursorInfo()
	if cursor then
		PlaceAction(self.actionId)
	end
end

local function Opener_OnDragStart(self)
	if not InCombatLockdown() and (LOCK_ACTIONBAR ~= "1" or IsShiftKeyDown()) then
		FloFlyout:PickupFlyout(self.flyoutId)
		FloFlyout:RemoveAction(self.actionId)
		FloFlyout:ApplyConfig()
	end
end

local function Opener_UpdateFlyout(self)
	-- Update border and determine arrow position
	local arrowDistance;
	-- Update border
	local isMouseOverButton =  GetMouseFocus() == self;
	local isFlyoutShown = FloFlyoutFrame and FloFlyoutFrame:IsShown() and FloFlyoutFrame:GetParent() == self;
	if isFlyoutShown or isMouseOverButton then
		self.FlyoutBorderShadow:Show();
		arrowDistance = 5;
	else
		self.FlyoutBorderShadow:Hide();
		arrowDistance = 2;
	end

	-- Update arrow
	local isButtonDown = self:GetButtonState() == "PUSHED"
	local flyoutArrowTexture = self.FlyoutArrowContainer.FlyoutArrowNormal

	if isButtonDown then
		flyoutArrowTexture = self.FlyoutArrowContainer.FlyoutArrowPushed;

		self.FlyoutArrowContainer.FlyoutArrowNormal:Hide();
		self.FlyoutArrowContainer.FlyoutArrowHighlight:Hide();
	elseif isMouseOverButton then
		flyoutArrowTexture = self.FlyoutArrowContainer.FlyoutArrowHighlight;

		self.FlyoutArrowContainer.FlyoutArrowNormal:Hide();
		self.FlyoutArrowContainer.FlyoutArrowPushed:Hide();
	else
		self.FlyoutArrowContainer.FlyoutArrowHighlight:Hide();
		self.FlyoutArrowContainer.FlyoutArrowPushed:Hide();
	end

	self.FlyoutArrowContainer:Show();
	flyoutArrowTexture:Show();
	flyoutArrowTexture:ClearAllPoints();

	local direction = self:GetAttribute("flyoutDirection");
	if (direction == "LEFT") then
		flyoutArrowTexture:SetPoint("LEFT", self, "LEFT", -arrowDistance, 0);
		SetClampedTextureRotation(flyoutArrowTexture, 270);
	elseif (direction == "RIGHT") then
		flyoutArrowTexture:SetPoint("RIGHT", self, "RIGHT", arrowDistance, 0);
		SetClampedTextureRotation(flyoutArrowTexture, 90);
	elseif (direction == "DOWN") then
		flyoutArrowTexture:SetPoint("BOTTOM", self, "BOTTOM", 0, -arrowDistance);
		SetClampedTextureRotation(flyoutArrowTexture, 180);
	else
		flyoutArrowTexture:SetPoint("TOP", self, "TOP", 0, arrowDistance);
		SetClampedTextureRotation(flyoutArrowTexture, 0);
	end
	self.SlotArt:Hide()
	self.NormalTexture:Hide()
end

local function Opener_PreClick(self, button, down)
	self:SetChecked(not self:GetChecked())
	local direction = self:GetAttribute("flyoutDirection");
	local spellList = { strsplit(",", self:GetAttribute("spelllist")) }
	local typeList = { strsplit(",", self:GetAttribute("typelist")) }
	local buttonList = { FloFlyoutFrame:GetChildren() }
	table.remove(buttonList, 1)
	for i, buttonRef in ipairs(buttonList) do
		if spellList[i] then
			buttonRef.spellID = spellList[i]
			buttonRef.actionType = typeList[i]
			local icon = FloFlyout:GetTexture(typeList[i], spellList[i])
			_G[buttonRef:GetName().."Icon"]:SetTexture(icon)
			SpellFlyoutButton_UpdateCooldown(buttonRef)
			SpellFlyoutButton_UpdateState(buttonRef)
			SpellFlyoutButton_UpdateUsable(buttonRef)
			SpellFlyoutButton_UpdateCount(buttonRef)
		end
	end
	FloFlyoutFrame.Background.End:ClearAllPoints()
	FloFlyoutFrame.Background.Start:ClearAllPoints()
	local distance = 3
	if (direction == "UP") then
		FloFlyoutFrame.Background.End:SetPoint("TOP", 0, SPELLFLYOUT_INITIAL_SPACING);
		SetClampedTextureRotation(FloFlyoutFrame.Background.End, 0);
		SetClampedTextureRotation(FloFlyoutFrame.Background.VerticalMiddle, 0);
		FloFlyoutFrame.Background.Start:SetPoint("TOP", FloFlyoutFrame.Background.VerticalMiddle, "BOTTOM");
		SetClampedTextureRotation(FloFlyoutFrame.Background.Start, 0);
		FloFlyoutFrame.Background.HorizontalMiddle:Hide();
		FloFlyoutFrame.Background.VerticalMiddle:Show();
		FloFlyoutFrame.Background.VerticalMiddle:ClearAllPoints();
		FloFlyoutFrame.Background.VerticalMiddle:SetPoint("TOP", FloFlyoutFrame.Background.End, "BOTTOM");
		FloFlyoutFrame.Background.VerticalMiddle:SetPoint("BOTTOM", 0, distance);
	elseif (direction == "DOWN") then
		FloFlyoutFrame.Background.End:SetPoint("BOTTOM", 0, -SPELLFLYOUT_INITIAL_SPACING);
		SetClampedTextureRotation(FloFlyoutFrame.Background.End, 180);
		SetClampedTextureRotation(FloFlyoutFrame.Background.VerticalMiddle, 180);
		FloFlyoutFrame.Background.Start:SetPoint("BOTTOM", FloFlyoutFrame.Background.VerticalMiddle, "TOP");
		SetClampedTextureRotation(FloFlyoutFrame.Background.Start, 180);
		FloFlyoutFrame.Background.HorizontalMiddle:Hide();
		FloFlyoutFrame.Background.VerticalMiddle:Show();
		FloFlyoutFrame.Background.VerticalMiddle:ClearAllPoints();
		FloFlyoutFrame.Background.VerticalMiddle:SetPoint("BOTTOM", FloFlyoutFrame.Background.End, "TOP");
		FloFlyoutFrame.Background.VerticalMiddle:SetPoint("TOP", 0, -distance);
	elseif (direction == "LEFT") then
		FloFlyoutFrame.Background.End:SetPoint("LEFT", -SPELLFLYOUT_INITIAL_SPACING, 0);
		SetClampedTextureRotation(FloFlyoutFrame.Background.End, 270);
		SetClampedTextureRotation(FloFlyoutFrame.Background.HorizontalMiddle, 180);
		FloFlyoutFrame.Background.Start:SetPoint("LEFT", FloFlyoutFrame.Background.HorizontalMiddle, "RIGHT");
		SetClampedTextureRotation(FloFlyoutFrame.Background.Start, 270);
		FloFlyoutFrame.Background.VerticalMiddle:Hide();
		FloFlyoutFrame.Background.HorizontalMiddle:Show();
		FloFlyoutFrame.Background.HorizontalMiddle:ClearAllPoints();
		FloFlyoutFrame.Background.HorizontalMiddle:SetPoint("LEFT", FloFlyoutFrame.Background.End, "RIGHT");
		FloFlyoutFrame.Background.HorizontalMiddle:SetPoint("RIGHT", -distance, 0);
	elseif (direction == "RIGHT") then
		FloFlyoutFrame.Background.End:SetPoint("RIGHT", SPELLFLYOUT_INITIAL_SPACING, 0);
		SetClampedTextureRotation(FloFlyoutFrame.Background.End, 90);
		SetClampedTextureRotation(FloFlyoutFrame.Background.HorizontalMiddle, 0);
		FloFlyoutFrame.Background.Start:SetPoint("RIGHT", FloFlyoutFrame.Background.HorizontalMiddle, "LEFT");
		SetClampedTextureRotation(FloFlyoutFrame.Background.Start, 90);
		FloFlyoutFrame.Background.VerticalMiddle:Hide();
		FloFlyoutFrame.Background.HorizontalMiddle:Show();
		FloFlyoutFrame.Background.HorizontalMiddle:ClearAllPoints();
		FloFlyoutFrame.Background.HorizontalMiddle:SetPoint("RIGHT", FloFlyoutFrame.Background.End, "LEFT");
		FloFlyoutFrame.Background.HorizontalMiddle:SetPoint("LEFT", distance, 0);
	end
	FloFlyoutFrame:SetBorderColor(0.7, 0.7, 0.7)
	FloFlyoutFrame:SetBorderSize(47);
end

local snippet_Opener_Click = [=[
	local ref = self:GetFrameRef("FloFlyoutFrame")
	local direction = self:GetAttribute("flyoutDirection")
	local prevButton = nil;

	if ref:IsShown() and ref:GetParent() == self then
		ref:Hide()
	else
		ref:SetParent(self)
		ref:ClearAllPoints()
		if direction == "UP" then
			ref:SetPoint("BOTTOM", self, "TOP", 0, 0)
		elseif direction == "DOWN" then
			ref:SetPoint("TOP", self, "BOTTOM", 0, 0)
		elseif direction == "LEFT" then
			ref:SetPoint("RIGHT", self, "LEFT", 0, 0)
		elseif direction == "RIGHT" then
			ref:SetPoint("LEFT", self, "RIGHT", 0, 0)
		end

		local spellList = table.new(strsplit(",", self:GetAttribute("spellnamelist")))
		local typeList = table.new(strsplit(",", self:GetAttribute("typelist")))
		local buttonList = table.new(ref:GetChildren())
		table.remove(buttonList, 1)
		for i, buttonRef in ipairs(buttonList) do
			if spellList[i] then
				buttonRef:ClearAllPoints()
				if direction == "UP" then
					if prevButton then
						buttonRef:SetPoint("BOTTOM", prevButton, "TOP", 0, ]=]..SPELLFLYOUT_DEFAULT_SPACING..[=[)
					else
						buttonRef:SetPoint("BOTTOM", "$parent", 0, ]=]..SPELLFLYOUT_INITIAL_SPACING..[=[)
					end
				elseif direction == "DOWN" then
					if prevButton then
						buttonRef:SetPoint("TOP", prevButton, "BOTTOM", 0, -]=]..SPELLFLYOUT_DEFAULT_SPACING..[=[)
					else
						buttonRef:SetPoint("TOP", "$parent", 0, -]=]..SPELLFLYOUT_INITIAL_SPACING..[=[)
					end
				elseif direction == "LEFT" then
					if prevButton then
						buttonRef:SetPoint("RIGHT", prevButton, "LEFT", -]=]..SPELLFLYOUT_DEFAULT_SPACING..[=[, 0)
					else
						buttonRef:SetPoint("RIGHT", "$parent", -]=]..SPELLFLYOUT_INITIAL_SPACING..[=[, 0)
					end
				elseif direction == "RIGHT" then
					if prevButton then
						buttonRef:SetPoint("LEFT", prevButton, "RIGHT", ]=]..SPELLFLYOUT_DEFAULT_SPACING..[=[, 0)
					else
						buttonRef:SetPoint("LEFT", "$parent", ]=]..SPELLFLYOUT_INITIAL_SPACING..[=[, 0)
					end
				end

				buttonRef:SetAttribute("type", typeList[i])
				buttonRef:SetAttribute(typeList[i], spellList[i])
				buttonRef:Show()

				prevButton = buttonRef
			else
				buttonRef:Hide()
			end
		end
		local numButtons = table.maxn(spellList)
		if direction == "UP" or direction == "DOWN" then
			ref:SetWidth(prevButton:GetWidth())
			ref:SetHeight((prevButton:GetHeight()+]=]..SPELLFLYOUT_DEFAULT_SPACING..[=[) * numButtons - ]=]..SPELLFLYOUT_DEFAULT_SPACING..[=[ + ]=]..SPELLFLYOUT_INITIAL_SPACING..[=[ + ]=]..SPELLFLYOUT_FINAL_SPACING..[=[)
		else
			ref:SetHeight(prevButton:GetHeight())
			ref:SetWidth((prevButton:GetWidth()+]=]..SPELLFLYOUT_DEFAULT_SPACING..[=[) * numButtons - ]=]..SPELLFLYOUT_DEFAULT_SPACING..[=[ + ]=]..SPELLFLYOUT_INITIAL_SPACING..[=[ + ]=]..SPELLFLYOUT_FINAL_SPACING..[=[)
		end
		ref:Show()
		--ref:RegisterAutoHide(1)
		--ref:AddToAutoHide(self)
	end
]=]

function FloFlyout:CreateOpener(name, idFlyout, actionId, direction, actionButton, actionBarPage, bonusBar, typeActionButton)

	local flyoutConf = self.config.flyouts[idFlyout]
	local opener = self.openers[name] or CreateFrame("CheckButton", name, UIParent, "ActionButtonTemplate, SecureHandlerClickTemplate")
	self.openers[name] = opener
	opener.flyoutId = idFlyout
	opener.actionId = actionId

	if _classicUI then
		_classicUI.LayoutActionButton(opener, typeActionButton)
		opener:SetScale(actionButton:GetScale())
	end
	if actionButton:GetSize() and actionButton:IsRectValid() then
		opener:SetAllPoints(actionButton)
	else
		local spacerName = "ActionBarButtonSpacer"..tostring(actionButton.index)
		local children = {actionButton:GetParent():GetChildren()}
		for _, child in ipairs(children) do
			if child:GetName() == spacerName then
				opener:SetAllPoints(child)
				break;
			end
		end
	end
	opener:SetFrameStrata("MEDIUM")
	opener:SetFrameLevel(100)
	opener:SetToplevel(true)

	opener:SetAttribute("flyoutDirection", direction)
	opener:SetFrameRef("FloFlyoutFrame", FloFlyoutFrame)
	opener:SetAttribute("spelllist", strjoin(",", unpack(flyoutConf.spells)))
	local spellnameList = flyoutConf.spellNames
	for i, spellID in ipairs(flyoutConf.spells) do
		if spellnameList[i] == nil then
			spellnameList[i] = self:GetName(flyoutConf.actionTypes[i], spellID)
		end
	end
	opener:SetAttribute("spellnamelist", strjoin(",", unpack(flyoutConf.spellNames)))
	opener:SetAttribute("typelist", strjoin(",", unpack(flyoutConf.actionTypes)))

	opener:SetScript("OnUpdate", Opener_UpdateFlyout)
	opener:SetScript("OnEnter", Opener_UpdateFlyout)
	opener:SetScript("OnLeave", Opener_UpdateFlyout)

	opener:SetScript("OnReceiveDrag", Opener_OnReceiveDrag)
	opener:SetScript("OnMouseUp", Opener_OnReceiveDrag)
	opener:SetScript("OnDragStart", Opener_OnDragStart)

	opener:SetScript("PreClick", Opener_PreClick)
	opener:SetAttribute("_onclick", snippet_Opener_Click)
	opener:RegisterForClicks("AnyUp")
	opener:RegisterForDrag("LeftButton")

	opener.SlotArt:Hide()
	opener.NormalTexture:Hide()
	

	local icon = _G[opener:GetName().."Icon"]
	if flyoutConf.icon then
		if type(flyoutConf.icon) == "number" then
			icon:SetTexture(flyoutConf.icon)
		else
			icon:SetTexture("INTERFACE\\ICONS\\"..flyoutConf.icon)
		end
	elseif flyoutConf.spells[1] then
		local texture = FloFlyout:GetTexture(flyoutConf.actionTypes[1], flyoutConf.spells[1])
		icon:SetTexture(texture)
	end

	local stateCondition = "nopetbattle,nooverridebar,novehicleui,nopossessbar"
	if actionBarPage then
		stateCondition = ",bar:"..actionBarPage
	end
	if bonusBar then
		if bonusBar == 0 then
			stateCondition = stateCondition..",nobonusbar:1,nobonusbar:2,nobonusbar:3,nobonusbar:4"
		else
			stateCondition = stateCondition..",bonusbar:"..bonusBar
		end
	end
	if stateCondition ~= "" then
		RegisterStateDriver(opener, "visibility", "["..stateCondition.."] show; hide")
	else
		opener:Show()
	end
end

function FloFlyout:ClearOpeners()
	for name, opener in pairs(self.openers) do
		opener:Hide()
		UnregisterStateDriver(opener, "visibility")
	end
end

function FloFlyout:ApplyConfig()
	if InCombatLockdown() then
		return
	end
	self:ClearOpeners()
	for a,f in pairs(self.config.actions[GetSpecialization()]) do
		self:BindFlyoutToAction(f, a)
	end
end

function FloFlyout:IsValidFlyoutId(arg1)
	local id = tonumber(arg1)
	return id and self.config.flyouts[id]
end

function FloFlyout:IsValidSpellPos(flyoutId, arg2)
	if type(flyoutId) == "string" then flyoutId = tonumber(flyoutId) end
	local pos = tonumber(arg2)
	return pos and self.config.flyouts[flyoutId].spells[pos]
end

function FloFlyout:AddFlyout()
	table.insert(self.config.flyouts, { spells = {}, actionTypes = {}, mountIndex = {}, spellNames = {} })
	return #self.config.flyouts
end

function FloFlyout:RemoveFlyout(flyoutId)
	if type(flyoutId) == "string" then flyoutId = tonumber(flyoutId) end
	table.remove(self.config.flyouts, flyoutId)
	-- shift references
	for i = 1, 3 do
		for a,f in pairs(self.config.actions[i]) do
			if f == flyoutId then
				self.config.actions[i][a] = nil
			elseif f > flyoutId then
				self.config.actions[i][a] = f - 1
			end
		end
	end
end

function FloFlyout:AddSpell(flyoutId, actionType, spellId)
	if type(flyoutId) == "string" then flyoutId = tonumber(flyoutId) end
	if type(spellId) == "string" then spellId = tonumber(spellId) end
	local flyoutConf = self.config.flyouts[flyoutId]
	table.insert(flyoutConf.spells, spellId)
	local newPos = #flyoutConf.spells
	flyoutConf.actionTypes[newPos] = actionType
	return newPos
end

function FloFlyout:RemoveSpell(flyoutId, spellPos)
	if type(flyoutId) == "string" then flyoutId = tonumber(flyoutId) end
	if type(spellPos) == "string" then spellPos = tonumber(spellPos) end
	local flyoutConf = self.config.flyouts[flyoutId]
	table.remove(flyoutConf.spells, spellPos)
	table.remove(flyoutConf.actionTypes, spellPos)
	table.remove(flyoutConf.mountIndex, spellPos)
	table.remove(flyoutConf.spellNames, spellPos)
end

function FloFlyout:AddAction(actionId, flyoutId)
	if type(actionId) == "string" then actionId = tonumber(actionId) end
	if type(flyoutId) == "string" then flyoutId = tonumber(flyoutId) end
	self.config.actions[GetSpecialization()][actionId] = flyoutId
end

function FloFlyout:RemoveAction(actionId)
	if type(actionId) == "string" then actionId = tonumber(actionId) end
	self.config.actions[GetSpecialization()][actionId] = nil
end

function FloFlyout:PickupFlyout(flyoutId)
	-- No drag 'n drop in combat, I use protected API
	if InCombatLockdown() then
		return;
	end

	local flyoutConf = self.config.flyouts[flyoutId]
	local texture = flyoutConf.icon

	if not texture and flyoutConf.spells[1] then
		texture = FloFlyout:GetTexture(flyoutConf.actionTypes[1], flyoutConf.spells[1])
	end
	if not texture then
		texture = "INV_Misc_QuestionMark"
	end
	-- Recreate dummy macro
	DeleteMacro("__ffodnd")
	local macroId = CreateMacro("__ffodnd", texture, flyoutId, nil, nil)
	PickupMacro(macroId)
end

function FloFlyoutButton_SetTooltip(self)
	if GetCVar("UberTooltips") == "1" then
		GameTooltip_SetDefaultAnchor(GameTooltip, self)

		local setTooltip
		if self.actionType == "spell" then
			setTooltip = GameTooltip.SetSpellByID
		elseif self.actionType == "item" then
			setTooltip = GameTooltip.SetItemByID
		end
		if setTooltip and setTooltip(GameTooltip, self.spellID) then
			self.UpdateTooltip = FloFlyoutButton_SetTooltip
		else
			self.UpdateTooltip = nil
		end
	else
		local parent = self:GetParent():GetParent():GetParent():GetParent()
		if parent == MultiBarBottomRight or parent == MultiBarRight or parent == MultiBarLeft then
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		else
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		end
		local spellName = FloFlyout:GetName(self.actionType, self.spellID)
		GameTooltip:SetText(spellName, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
		self.UpdateTooltip = nil
	end
end

function FloFlyoutButton_OnDragStart(self)
	if InCombatLockdown() then return end

	local actionType = self.actionType
	local spell = self.spellID
	local mountIndex = self.mountIndex
	if actionType == "spell" then
		if mountIndex == nil then
			PickupSpell(spell)
		else
			C_MountJournal.Pickup(mountIndex)
		end
		FloFlyout.mountIndex = mountIndex
	elseif actionType == "item" then
		PickupItem(spell)
	end

	local parent = self:GetParent()
	if parent.IsConfig then
		FloFlyout:RemoveSpell(parent.idFlyout, self:GetID())
		FloFlyout:ApplyConfig()
		FloFlyoutConfigFlyoutFrame_Update(parent, parent.idFlyout)
	end
end

FloFlyout.mountIndex = nil;
function FloFlyout.MountJournal_PickupHook(index)
	FloFlyout.mountIndex = index;
end
hooksecurefunc(C_MountJournal, "Pickup", FloFlyout.MountJournal_PickupHook);

function FloFlyoutButton_OnReceiveDrag(self)
	local parent = self:GetParent()
	if not parent.IsConfig then return end

	local kind, info1, info2, info3 = GetCursorInfo()
	local actionType, actionData, mountIndex
	if kind == "spell" then
		actionType = "spell"
		actionData = info3
	elseif kind == "mount" then
		actionType = "spell"
		_, actionData, _, _, _, _, _, _, _, _, _ = C_MountJournal.GetDisplayedMountInfo(FloFlyout.mountIndex);
		mountIndex = FloFlyout.mountIndex
	elseif kind == "item" then
		actionType = "item"
		actionData = info1
	end
	if actionType then
		local flyoutConf = FloFlyout.config.flyouts[parent.idFlyout]
		local oldActionData = flyoutConf.spells[self:GetID()]
		local oldActionType = flyoutConf.actionTypes[self:GetID()]
		local oldMountIndex = flyoutConf.mountIndex[self:GetID()]
		local oldSpellName = flyoutConf.spellNames[self:GetID()]
		flyoutConf.spells[self:GetID()] = actionData
		flyoutConf.actionTypes[self:GetID()] = actionType
		flyoutConf.mountIndex[self:GetID()] = mountIndex
		flyoutConf.spellNames[self:GetID()] = FloFlyout:GetName(flyoutConf.actionTypes[i], actionData)
		ClearCursor()
		FloFlyout:ApplyConfig()
		FloFlyoutConfigFlyoutFrame_Update(parent, parent.idFlyout)
		if oldActionType == "spell" then
			if oldMountIndex == nil then
				PickupSpell(oldActionData)
			else
					C_MountJournal.Pickup(oldMountIndex)
			end
		elseif oldActionType == "item" then
			PickupItem(oldActionData)
		end
	end
end

function FloFlyoutConfigFlyoutFrame_Update(self, idFlyout)
	local direction = "RIGHT"
	local parent = self.parent

	self.idFlyout = idFlyout

	-- Update all spell buttons for this flyout
	local prevButton = nil;
	local numButtons = 0;
	local spells = FloFlyout.config.flyouts[idFlyout].spells
	local actionTypes = FloFlyout.config.flyouts[idFlyout].actionTypes
	local mountIndexes = FloFlyout.config.flyouts[idFlyout].mountIndex

	for i=1, math.min(#spells+1, 10) do
		local spellID = spells[i]
		local actionType = actionTypes[i]
		local mountIndex = mountIndexes[i]
		local button = _G["FloFlyoutConfigFlyoutFrameButton"..numButtons+1]

		button:ClearAllPoints()
		if direction == "UP" then
			if prevButton then
				button:SetPoint("BOTTOM", prevButton, "TOP", 0, SPELLFLYOUT_DEFAULT_SPACING)
			else
				button:SetPoint("BOTTOM", 0, SPELLFLYOUT_INITIAL_SPACING)
			end
		elseif direction == "DOWN" then
			if prevButton then
				button:SetPoint("TOP", prevButton, "BOTTOM", 0, -SPELLFLYOUT_DEFAULT_SPACING)
			else
				button:SetPoint("TOP", 0, -SPELLFLYOUT_INITIAL_SPACING)
			end
		elseif direction == "LEFT" then
			if prevButton then
				button:SetPoint("RIGHT", prevButton, "LEFT", -SPELLFLYOUT_DEFAULT_SPACING, 0)
			else
				button:SetPoint("RIGHT", -SPELLFLYOUT_INITIAL_SPACING, 0)
			end
		elseif direction == "RIGHT" then
			if prevButton then
				button:SetPoint("LEFT", prevButton, "RIGHT", SPELLFLYOUT_DEFAULT_SPACING, 0)
			else
				button:SetPoint("LEFT", SPELLFLYOUT_INITIAL_SPACING, 0)
			end
		end

		button:Show()

		if spellID then
			button.spellID = spellID
			button.actionType = actionType
			button.mountIndex = mountIndex
			local texture = FloFlyout:GetTexture(actionType, spellID)
			_G[button:GetName().."Icon"]:SetTexture(texture)
			SpellFlyoutButton_UpdateCooldown(button)
			SpellFlyoutButton_UpdateState(button)
			SpellFlyoutButton_UpdateUsable(button)
			SpellFlyoutButton_UpdateCount(button)
		else
			_G[button:GetName().."Icon"]:SetTexture(nil)
			button.spellID = nil
			button.actionType = nil
			button.mountIndex = nil
		end

		prevButton = button
		numButtons = numButtons+1
	end

	-- Hide unused buttons
	local unusedButtonIndex = numButtons+1
	while _G["FloFlyoutConfigFlyoutFrameButton"..unusedButtonIndex] do
		_G["FloFlyoutConfigFlyoutFrameButton"..unusedButtonIndex]:Hide()
		unusedButtonIndex = unusedButtonIndex+1
	end

	if numButtons == 0 then
		self:Hide()
		return
	end

	-- Show the flyout
	self:SetFrameStrata("DIALOG")
	self:ClearAllPoints()

	local distance = 3

	self.Background.End:ClearAllPoints()
	self.Background.Start:ClearAllPoints()
	if (direction == "UP") then
		self:SetPoint("BOTTOM", parent, "TOP");
		self.Background.End:SetPoint("TOP", 0, SPELLFLYOUT_INITIAL_SPACING);
		SetClampedTextureRotation(self.Background.End, 0);
		SetClampedTextureRotation(self.Background.VerticalMiddle, 0);
		self.Background.Start:SetPoint("TOP", self.Background.VerticalMiddle, "BOTTOM");
		SetClampedTextureRotation(self.Background.Start, 0);
		self.Background.HorizontalMiddle:Hide();
		self.Background.VerticalMiddle:Show();
		self.Background.VerticalMiddle:ClearAllPoints();
		self.Background.VerticalMiddle:SetPoint("TOP", self.Background.End, "BOTTOM");
		self.Background.VerticalMiddle:SetPoint("BOTTOM", 0, distance);
	elseif (direction == "DOWN") then
		self:SetPoint("TOP", parent, "BOTTOM");
		self.Background.End:SetPoint("BOTTOM", 0, -SPELLFLYOUT_INITIAL_SPACING);
		SetClampedTextureRotation(self.Background.End, 180);
		SetClampedTextureRotation(self.Background.VerticalMiddle, 180);
		self.Background.Start:SetPoint("BOTTOM", self.Background.VerticalMiddle, "TOP");
		SetClampedTextureRotation(self.Background.Start, 180);
		self.Background.HorizontalMiddle:Hide();
		self.Background.VerticalMiddle:Show();
		self.Background.VerticalMiddle:ClearAllPoints();
		self.Background.VerticalMiddle:SetPoint("BOTTOM", self.Background.End, "TOP");
		self.Background.VerticalMiddle:SetPoint("TOP", 0, -distance);
	elseif (direction == "LEFT") then
		self:SetPoint("RIGHT", parent, "LEFT");
		self.Background.End:SetPoint("LEFT", -SPELLFLYOUT_INITIAL_SPACING, 0);
		SetClampedTextureRotation(self.Background.End, 270);
		SetClampedTextureRotation(self.Background.HorizontalMiddle, 180);
		self.Background.Start:SetPoint("LEFT", self.Background.HorizontalMiddle, "RIGHT");
		SetClampedTextureRotation(self.Background.Start, 270);
		self.Background.VerticalMiddle:Hide();
		self.Background.HorizontalMiddle:Show();
		self.Background.HorizontalMiddle:ClearAllPoints();
		self.Background.HorizontalMiddle:SetPoint("LEFT", self.Background.End, "RIGHT");
		self.Background.HorizontalMiddle:SetPoint("RIGHT", -distance, 0);
	elseif (direction == "RIGHT") then
		self:SetPoint("LEFT", parent, "RIGHT");
		self.Background.End:SetPoint("RIGHT", SPELLFLYOUT_INITIAL_SPACING, 0);
		SetClampedTextureRotation(self.Background.End, 90);
		SetClampedTextureRotation(self.Background.HorizontalMiddle, 0);
		self.Background.Start:SetPoint("RIGHT", self.Background.HorizontalMiddle, "LEFT");
		SetClampedTextureRotation(self.Background.Start, 90);
		self.Background.VerticalMiddle:Hide();
		self.Background.HorizontalMiddle:Show();
		self.Background.HorizontalMiddle:ClearAllPoints();
		self.Background.HorizontalMiddle:SetPoint("RIGHT", self.Background.End, "LEFT");
		self.Background.HorizontalMiddle:SetPoint("LEFT", distance, 0);
	end

	if direction == "UP" or direction == "DOWN" then
		self:SetWidth(prevButton:GetWidth())
		self:SetHeight((prevButton:GetHeight()+SPELLFLYOUT_DEFAULT_SPACING) * numButtons - SPELLFLYOUT_DEFAULT_SPACING + SPELLFLYOUT_INITIAL_SPACING + SPELLFLYOUT_FINAL_SPACING)
	else
		self:SetHeight(prevButton:GetHeight())
		self:SetWidth((prevButton:GetWidth()+SPELLFLYOUT_DEFAULT_SPACING) * numButtons - SPELLFLYOUT_DEFAULT_SPACING + SPELLFLYOUT_INITIAL_SPACING + SPELLFLYOUT_FINAL_SPACING)
	end

	self.direction = direction;
	self:SetBorderColor(0.7, 0.7, 0.7);
	self:SetBorderSize(47);
end

function FloFlyoutConfigPane_OnLoad(self)
	HybridScrollFrame_OnLoad(self)
	self.update = FloFlyout.ConfigPane_Update
	HybridScrollFrame_CreateButtons(self, "FloFlyoutConfigButtonTemplate")
end

function FloFlyoutConfigPane_OnShow(self)
	HybridScrollFrame_CreateButtons(self, "FloFlyoutConfigButtonTemplate")
	FloFlyout.ConfigPane_Update()
end

function FloFlyoutConfigPane_OnHide(self)
	FloFlyoutConfigDialogPopup:Hide()
	FloFlyoutConfigFlyoutFrame:Hide()
end

function FloFlyoutConfigPane_OnUpdate(self)
	for i = 1, #self.buttons do
		local button = self.buttons[i]
		if button:IsMouseOver() then
			if button.name then
				button.DeleteButton:Show()
				button.EditButton:Show()
			else
				button.DeleteButton:Hide()
				button.EditButton:Hide()
			end
			button.HighlightBar:Show()
		else
			button.DeleteButton:Hide()
			button.EditButton:Hide()
			button.HighlightBar:Hide()
		end
	end
end

function FloFlyout.ConfigPane_Update()
	local numRows = #FloFlyout.config.flyouts + 1
	HybridScrollFrame_Update(FloFlyoutConfigPane, numRows * EQUIPMENTSET_BUTTON_HEIGHT + 20, FloFlyoutConfigPane:GetHeight())

	local scrollOffset = HybridScrollFrame_GetOffset(FloFlyoutConfigPane)
	local buttons = FloFlyoutConfigPane.buttons
	local selectedIdx = FloFlyoutConfigPane.selectedIdx
	FloFlyoutConfigFlyoutFrame:Hide()
	local texture, button, flyout
	for i = 1, #buttons do
		if i+scrollOffset <= numRows then
			button = buttons[i]
			buttons[i]:Show()
			button:Enable()

			if i+scrollOffset < numRows then
				-- Normal flyout button
				button.name = i+scrollOffset
				button.text:SetText(button.name);
				button.text:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b);
				flyout = FloFlyout.config.flyouts[i+scrollOffset]
				texture = flyout.icon

				if not texture and flyout.spells[1] then
					texture = FloFlyout:GetTexture(flyout.actionTypes[1], flyout.spells[1])
				end
				if texture then
                                        if(type(texture) == "number") then
                                                button.icon:SetTexture(texture);
                                        else
                                                button.icon:SetTexture("INTERFACE\\ICONS\\"..texture);
                                        end
				else
					button.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
				end

				if selectedIdx and (i+scrollOffset) == selectedIdx then
					button.SelectedBar:Show()
					button.Arrow:Show()
					FloFlyoutConfigFlyoutFrame.parent = button
					FloFlyoutConfigFlyoutFrame_Update(FloFlyoutConfigFlyoutFrame, i+scrollOffset)
					FloFlyoutConfigFlyoutFrame:Show()
				else
					button.SelectedBar:Hide()
					button.Arrow:Hide()
				end

				button.icon:SetSize(36, 36)
				button.icon:SetPoint("LEFT", 4, 0)
			else
				-- This is the Add New button
				button.name = nil
				button.text:SetText(L["NEW_FLYOUT"])
				button.text:SetTextColor(GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
				button.icon:SetTexture("Interface\\PaperDollInfoFrame\\Character-Plus")
				button.icon:SetSize(30, 30)
				button.icon:SetPoint("LEFT", 7, 0)
				button.SelectedBar:Hide()
				button.Arrow:Hide()
			end

			if (i+scrollOffset) == 1 then
				buttons[i].BgTop:Show()
				buttons[i].BgMiddle:SetPoint("TOP", buttons[i].BgTop, "BOTTOM")
			else
				buttons[i].BgTop:Hide()
				buttons[i].BgMiddle:SetPoint("TOP")
			end

			if (i+scrollOffset) == numRows then
				buttons[i].BgBottom:Show()
				buttons[i].BgMiddle:SetPoint("BOTTOM", buttons[i].BgBottom, "TOP")
			else
				buttons[i].BgBottom:Hide()
				buttons[i].BgMiddle:SetPoint("BOTTOM")
			end
			
			if (i+scrollOffset)%2 == 0 then
				buttons[i].Stripe:SetTexture(STRIPE_COLOR.r, STRIPE_COLOR.g, STRIPE_COLOR.b)
				buttons[i].Stripe:SetAlpha(0.1)
				buttons[i].Stripe:Show()
			else
				buttons[i].Stripe:Hide()
			end
		else
			buttons[i]:Hide()
		end
	end

end

function FloFlyoutConfigButton_OnClick(self, button, down)
	if self.name and self.name ~= "" then
		if FloFlyoutConfigPane.selectedIdx == self.name then
			FloFlyoutConfigPane.selectedIdx = nil
		else
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)		-- inappropriately named, but a good sound.
			FloFlyoutConfigPane.selectedIdx = self.name
		end
		FloFlyout.ConfigPane_Update()
		FloFlyoutConfigDialogPopup:Hide()
	else
		-- This is the "New" button
		FloFlyoutConfigDialogPopup:Show()
		FloFlyoutConfigPane.selectedIdx = nil
		FloFlyout.ConfigPane_Update()
	end
end

function FloFlyoutConfigButton_OnDragStart(self)
	if self.name and self.name ~= "" then
		FloFlyout:PickupFlyout(self.name)
	end
end

local NUM_FLYOUT_ICONS_SHOWN = 100--15
local NUM_FLYOUT_ICONS_PER_ROW = 10 --5
local NUM_FLYOUT_ICON_ROWS = 10 --3
local FLYOUT_ICON_ROW_HEIGHT = 36
local FC_ICON_FILENAMES = {}

function FloFlyoutConfigDialogPopup_OnLoad (self)
	self.buttons = {}

	local button = CreateFrame("CheckButton", "FloFlyoutConfigDialogPopupButton1", FloFlyoutConfigDialogPopup, "FloFlyoutConfigPopupButtonTemplate")
	button:SetPoint("TOPLEFT", 24, -37)
	button:SetID(1)
	tinsert(self.buttons, button)

	local lastPos
	for i = 2, NUM_FLYOUT_ICONS_SHOWN do
		button = CreateFrame("CheckButton", "FloFlyoutConfigDialogPopupButton" .. i, FloFlyoutConfigDialogPopup, "FloFlyoutConfigPopupButtonTemplate")
		button:SetID(i)

		lastPos = (i - 1) / NUM_FLYOUT_ICONS_PER_ROW
		if lastPos == math.floor(lastPos) then
			button:SetPoint("TOPLEFT", self.buttons[i-NUM_FLYOUT_ICONS_PER_ROW], "BOTTOMLEFT", 0, -8)
		else
			button:SetPoint("TOPLEFT", self.buttons[i-1], "TOPRIGHT", 10, 0)
		end
		tinsert(self.buttons, button)
	end

	self.SetSelection = function(self, fTexture, Value)
		if fTexture then
			self.selectedTexture = Value
			self.selectedIcon = nil
		else
			self.selectedTexture = nil
			self.selectedIcon = Value
		end
	end
end

function FloFlyoutConfigDialogPopup_OnShow(self)
	PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
	self.name = nil
	self.isEdit = false
	RecalculateFloFlyoutConfigDialogPopup()
end

function FloFlyoutConfigDialogPopup_OnHide(self)
	FloFlyoutConfigDialogPopup.name = nil
	FloFlyoutConfigDialogPopup:SetSelection(true, nil)
	--FloFlyoutConfigDialogPopupEditBox:SetText("")
	FC_ICON_FILENAMES = nil
	collectgarbage()
end

function RecalculateFloFlyoutConfigDialogPopup(iconTexture)
	local popup = FloFlyoutConfigDialogPopup;

	if iconTexture then
		popup:SetSelection(true, iconTexture)
	else
		popup:SetSelection(false, 1)
	end

	--[[ 
	Scroll and ensure that any selected equipment shows up in the list.
	When we first press "save", we want to make sure any selected equipment set shows up in the list, so that
	the user can just make his changes and press Okay to overwrite.
	To do this, we need to find the current set (by icon) and move the offset of the FloFlyoutConfigDialogPopup
	to display it. Issue ID: 171220
	]]
	FloFlyout.RefreshFlyoutIconInfo()
	local totalItems = #FC_ICON_FILENAMES
	local texture, _
	if popup.selectedTexture then
		local foundIndex = nil
		for index=1, totalItems do
			texture = FloFlyout.GetFlyoutIconInfo(index)
			if texture == popup.selectedTexture then
				foundIndex = index
				break
			end
		end
		if foundIndex == nil then
			foundIndex = 1
		end
		-- now make it so we always display at least NUM_FLYOUT_ICON_ROWS of data
		local offsetnumIcons = floor((totalItems-1)/NUM_FLYOUT_ICONS_PER_ROW)
		local offset = floor((foundIndex-1) / NUM_FLYOUT_ICONS_PER_ROW)
		offset = offset + min((NUM_FLYOUT_ICON_ROWS-1), offsetnumIcons-offset) - (NUM_FLYOUT_ICON_ROWS-1)
		if foundIndex<=NUM_FLYOUT_ICONS_SHOWN then
			offset = 0			--Equipment all shows at the same place.
		end
		FauxScrollFrame_OnVerticalScroll(FloFlyoutConfigDialogPopupScrollFrame, offset*FLYOUT_ICON_ROW_HEIGHT, FLYOUT_ICON_ROW_HEIGHT, nil);
	else
		FauxScrollFrame_OnVerticalScroll(FloFlyoutConfigDialogPopupScrollFrame, 0, FLYOUT_ICON_ROW_HEIGHT, nil);
	end
	FloFlyoutConfigDialogPopup_Update()
end

--[[
RefreshFlyoutIconInfo() counts how many uniquely textured spells the player has in the current flyout. 
]]
function FloFlyout.RefreshFlyoutIconInfo()
	FC_ICON_FILENAMES = {}
	FC_ICON_FILENAMES[1] = "INV_MISC_QUESTIONMARK"
	local index = 2

	local popup = FloFlyoutConfigDialogPopup
	if popup.name then
		local spells = FloFlyout.config.flyouts[popup.name].spells
		local actionTypes = FloFlyout.config.flyouts[popup.name].actionTypes
		for i = 1, #spells do
			local itemTexture = FloFlyout:GetTexture(actionTypes[i], spells[i])
			if itemTexture then
				FC_ICON_FILENAMES[index] = gsub( strupper(itemTexture), "INTERFACE\\ICONS\\", "" )
				if FC_ICON_FILENAMES[index] then
					index = index + 1
					for j=1, (index-1) do
						if FC_ICON_FILENAMES[index] == FC_ICON_FILENAMES[j] then
							FC_ICON_FILENAMES[index] = nil
							index = index - 1
							break
						end
					end
				end
			end
		end
	end
	GetLooseMacroIcons(FC_ICON_FILENAMES)
	GetMacroIcons(FC_ICON_FILENAMES)
end

function FloFlyout.GetFlyoutIconInfo(index)
	return FC_ICON_FILENAMES[index]
end

function FloFlyoutConfigDialogPopup_Update()
	FloFlyout.RefreshFlyoutIconInfo()

	local popup = FloFlyoutConfigDialogPopup
	local buttons = popup.buttons
	local offset = FauxScrollFrame_GetOffset(FloFlyoutConfigDialogPopupScrollFrame) or 0
	-- Icon list
	local texture, index, _
	for i=1, NUM_FLYOUT_ICONS_SHOWN do
		local button = buttons[i]
		index = (offset * NUM_FLYOUT_ICONS_PER_ROW) + i
		if index <= #FC_ICON_FILENAMES then
			texture = FloFlyout.GetFlyoutIconInfo(index)

			if(type(texture) == "number") then
				button.icon:SetTexture(texture);
			else
				button.icon:SetTexture("INTERFACE\\ICONS\\"..texture);
			end
			button:Show()
			if index == popup.selectedIcon then
				button:SetChecked(1)
			elseif string.upper(texture) == popup.selectedTexture then
				button:SetChecked(1)
				popup:SetSelection(false, index)
			else
				button:SetChecked(nil)
			end
		else
			button.icon:SetTexture("")
			button:Hide()
		end

	end

	-- Scrollbar stuff
	FauxScrollFrame_Update(FloFlyoutConfigDialogPopupScrollFrame, ceil(#FC_ICON_FILENAMES / NUM_FLYOUT_ICONS_PER_ROW), NUM_FLYOUT_ICON_ROWS, FLYOUT_ICON_ROW_HEIGHT)
end

function FloFlyout.ConfigDialogPopupOkay_Update()
	local popup = FloFlyoutConfigDialogPopup
	local button = FloFlyoutConfigDialogPopupOkay

	if popup.selectedIcon --[[and popup.name]] then
		button:Enable()
	else
		button:Disable()
	end
end

function FloFlyoutConfigDialogPopupOkay_OnClick(self, button, pushed)
	local popup = FloFlyoutConfigDialogPopup
	local iconTexture
	if popup.selectedIcon ~= 1 then
		iconTexture = FloFlyout.GetFlyoutIconInfo(popup.selectedIcon)
	end

	if popup.isEdit then
		-- Modifying a flyout
		FloFlyout.config.flyouts[popup.name].icon = iconTexture
	else
		-- Saving a new flyout
		FloFlyout.config.flyouts[FloFlyout:AddFlyout()].icon = iconTexture
	end
	popup:Hide()
	FloFlyout.ConfigPane_Update()
	FloFlyout:ApplyConfig()
end

function FloFlyoutConfigDialogPopupCancel_OnClick ()
	FloFlyoutConfigDialogPopup:Hide()
end

function FloFlyoutConfigPopupButton_OnClick(self, button, down)
	local popup = FloFlyoutConfigDialogPopup
	local offset = FauxScrollFrame_GetOffset(FloFlyoutConfigDialogPopupScrollFrame) or 0
	popup.selectedIcon = (offset * NUM_FLYOUT_ICONS_PER_ROW) + self:GetID()
 	popup.selectedTexture = nil
	FloFlyoutConfigDialogPopup_Update()
	FloFlyout.ConfigDialogPopupOkay_Update()
end


