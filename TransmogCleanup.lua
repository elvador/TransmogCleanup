
--------------------------------------------------------------------------------
-- TransmogCleanup by Elvador
--
-- GLOBALS: TransmogCleanup, SLASH_TRANSMOGCLEANUP_SLASHCMD1, CanIMogIt, SellJunk
-- GLOBALS: MerchantFrame, MerchantFramePortrait, StaticPopup_Show, StaticPopupDialogs
-- GLOBALS: TransmogCleanupDB, UIParent, ITEM_SOULBOUND, ITEM_BNETACCOUNTBOUND, ITEM_BIND_ON_EQUIP
--

local folder, ns = ...

TransmogCleanup = CreateFrame("Frame")
local addon = TransmogCleanup

TransmogCleanupDB = {}
addon.db = TransmogCleanupDB

local version = "@project-version@"
local debug = false
--@debug@
version = "(git)"
debug = true
--@end-debug@

--------------------------------------------------------------------------------
-- Upvalues
--

local _G = _G
local orgPrint = print
local cimi = CanIMogIt
local ItemUpgradeInfo = LibStub("LibItemUpgradeInfo-1.0")
local YES, NO, OKAY, CANCEL = YES, NO, OKAY, CANCEL
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local GetAverageItemLevel = GetAverageItemLevel
local GetCoinTextureString = GetCoinTextureString
local GetContainerItemLink = GetContainerItemLink
local GetContainerNumSlots = GetContainerNumSlots
local GetContainerItemPurchaseInfo = GetContainerItemPurchaseInfo
local GetItemInfo = GetItemInfo
local GetItemSpell = GetItemSpell
local SecondsToTime = SecondsToTime
local select = select
local tonumber = tonumber
local UseContainerItem = UseContainerItem
local unpack = unpack
local GameFontHighlightSmall = GameFontHighlightSmall
local floor = math.floor
local max = math.max
local sort = table.sort
local pairs = pairs
local GameTooltip = GameTooltip
local SetUpSideDressUpFrame = SetUpSideDressUpFrame
local IsControlKeyDown = IsControlKeyDown
local DressUpItemLink = DressUpItemLink
local SideDressUpFrame = SideDressUpFrame

--------------------------------------------------------------------------------
-- Variables
--

local enabled = true -- changed via checkForDependencies
local maxItemlevelToSell = 0
local merchantButton = nil
local sellWindow = nil
local scanningTooltip = nil
local updateItemListThrottle = nil
local itemQualities = {
	{   1,    1,    1}, -- common
	{0.12,    1,    0}, -- uncommon
	{   0, 0.44, 0.87}, -- rare
	{0.64, 0.21, 0.93}, -- epic
	{   1, 0.50,    0}, -- legendary
}
local bindOn = {
	{"BoE", "Bind on Equip"},
	{"BoP", "Bind on Pickup"},
	{"BoA", "Bind to Account"},
}
local learnedTypes = {
	{"Learned", "Sell items learned by any char"},
	{"Can't be learned", "Sell items which are non transmoggable (like trinkets and rings)"},
	{"Can be learned by another char", "Sell items which can be learned by another character"},
}

--------------------------------------------------------------------------------
-- Debug Functions
--

local function print(...)
	orgPrint("|cffec7600TransmogCleanup|r:", ...)
end

local function dbg(...)
	if debug then
		print(...)
	end
end

--------------------------------------------------------------------------------
-- Functions
--

local function checkForDependencies()
	if not CanIMogIt then
		print("Dependency missing! Download |cff93c763Can I Mog It?|r from Curse: |cff72aacahttp://mods.curse.com/addons/wow/can-i-mog-it|r")
		enabled = false
	end
end

local function getTransmogStatus(link)
	local mogStatus = cimi:GetTooltipText(link)
	if mogStatus == cimi.KNOWN or
		 mogStatus == cimi.KNOWN_FROM_ANOTHER_ITEM or
		 mogStatus == cimi.KNOWN_BY_ANOTHER_CHARACTER or
		 mogStatus == cimi.KNOWN_BUT_TOO_LOW_LEVEL then
		return 1
	elseif mogStatus == cimi.NOT_TRANSMOGABLE then
		return 2
	elseif mogStatus == cimi.UNKNOWABLE_BY_CHARACTER then
		return 3
	end
	return nil
end

local function getItemIdByLink(itemLink)
	return tonumber(select(3, itemLink:find("item:(%d+)")))
end

local function isItemIgnored(itemLink)
	local id = getItemIdByLink(itemLink)

	return addon.db.ignoredItems[id]
end

local function getItemBind(bag, slot)
	local name = "TransmogCleanupTT"
	scanningTooltip = scanningTooltip or CreateFrame("GameTooltip", name, nil, "GameTooltipTemplate") -- TODO
	local r = nil
	scanningTooltip:SetOwner(UIParent, "ANCHOR_NONE")
	scanningTooltip:SetBagItem(bag, slot)
	scanningTooltip:Show()
	for i = 1,scanningTooltip:NumLines() do
		if(_G[name.."TextLeft"..i]:GetText() == ITEM_BIND_ON_EQUIP) then
			r = 1
		elseif(_G[name.."TextLeft"..i]:GetText() == ITEM_SOULBOUND) then
			r = 2
		elseif(_G[name.."TextLeft"..i]:GetText() == ITEM_BNETACCOUNTBOUND) then
			r = 3
		end
	end
	scanningTooltip:Hide()
	return r
end

local function iterateBagItems()
	local itemList = {}

	for bag = 0,4 do
		for slot = 1,GetContainerNumSlots(bag) do
			local link = GetContainerItemLink(bag, slot)
			if link then
				local ilvl = ItemUpgradeInfo:GetUpgradedItemLevel(link)
				local status = getTransmogStatus(link)
				local bind = getItemBind(bag, slot)
				local _, _, quality = GetItemInfo(link)
				local vendorPrice = select(11, GetItemInfo(link))
				local hasOnUseEffect = GetItemSpell(link)

				if status and status > 0 then -- check if Can I Mog It checks the itemList
					if not (addon.db.filters.onuse and hasOnUseEffect) then
						if ilvl <= addon.db.filters.ilvl then
							if addon.db.filters.quality[quality] then
								if addon.db.filters.bind[bind] then
									if addon.db.filters.learned[status] then
										itemList[#itemList+1] = {link = link, ilvl = ilvl, bag = bag, slot = slot, status = status, price = vendorPrice}
									else
										--dbg(link, "learned", status)
									end
								else
									--dbg(link, "bind", bind)
								end
							else
								--dbg(link, "quality", quality)
							end
						else
							--dbg(link, "ilvl", ilvl, addon.db.filters.ilvl, ilvl < addon.db.filters.ilvl)
						end
					else
						--dbg(link, "hasOnUseEffect", hasOnUseEffect)
					end
				end
			end
		end
	end

	return itemList
end

local function sortItemList(itemList)
	sort(itemList, function(a,b)
		return a.ilvl == b.ilvl and a.link < b.link or a.ilvl < b.ilvl -- sort by ilvl, then by itemlink (should be item id)
	end)
	return itemList
end

local function isSafeModeEnabled()
	return addon.db.sellMode.safe
end

local function isVerboseModeEnabled()
	return addon.db.sellMode.verbose
end

local function sellItems()
	local itemList = sellWindow.scrollframe.content.itemList
	local itemsSold = 0
	local itemsSoldValue = 0

	for i = 1, #itemList do
		local item = itemList[i]
		if not isItemIgnored(item.link) and item.price > 0 then

			local _, _, refundSec = GetContainerItemPurchaseInfo(item.bag, item.slot)
			if refundSec then
				print(("Not selling %s because it is still refundable. Please wait %s before selling it."):format(item.link, SecondsToTime(refundSec, true, true)))
			else
				if isVerboseModeEnabled() then
					print(("Selling item %s for %s."):format(item.link, GetCoinTextureString(item.price)))
				end

				UseContainerItem(item.bag, item.slot)
				itemsSold = itemsSold + 1
				itemsSoldValue = itemsSoldValue + item.price

				if isSafeModeEnabled() and i > 11 then
					print(("Stopped selling items after %d items due to safe mode. Press the sell button again to continue selling %d items."):format(i, #itemList - i))
					break
				end
			end
		end
	end

	if itemsSold > 0 then
		print(("You earned %s by selling %d items."):format(GetCoinTextureString(itemsSoldValue), itemsSold))
	end
end

local function onIgnoredCheckedChange(self, ...)
	if IsControlKeyDown() then
		DressUpItemLink(self.item.link)
		self:SetChecked(not self:GetChecked()) -- hack it to the limit!
		if GameTooltip:GetOwner() == sellWindow then
			GameTooltip:SetPoint("TOPLEFT", SideDressUpFrame, "TOPRIGHT")
		end
	else
		addon.db.ignoredItems[self.itemId] = self:GetChecked()
	end
end

local function updateItemList(frame)
	local content = frame.scrollframe.content

	content.lines =	content.lines or {}

	local itemList = iterateBagItems()

	itemList = sortItemList(itemList)

	for i = #content.lines+1, #itemList do
		local cb = CreateFrame("CheckButton", "parentCB"..i, content, "InterfaceOptionsCheckButtonTemplate")
		cb:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -1 - 16 * (i-1))
		cb:SetHitRectInsets(0, -300, 0, 0)
		cb:SetHeight(20)
		cb:SetWidth(20)
		cb:SetScript("OnClick", onIgnoredCheckedChange)
		cb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(frame, "ANCHOR_NONE")
			if SideDressUpFrame:IsShown() then
				GameTooltip:SetPoint("TOPLEFT", SideDressUpFrame, "TOPRIGHT")
			else
				GameTooltip:SetPoint("TOPLEFT", frame, "TOPRIGHT")
			end
			GameTooltip:SetBagItem(self.item.bag, self.item.slot)
		end)
		cb:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)

		local itemString = content:CreateFontString("$parentItem"..i, nil, "GameFontNormal")
		itemString:SetPoint("TOPLEFT", content, "TOPLEFT", 35, -5 - 16 * (i-1))
		itemString:SetFont("Fonts\\ARIALN.TTF", 12)
		itemString:SetWidth(125)
		itemString:SetWordWrap(false)
		itemString:SetJustifyH("LEFT")

		local ilvlString = content:CreateFontString("$parentIlvl"..i, nil, "GameFontNormal")
		ilvlString:SetPoint("TOPLEFT", content, "TOPLEFT", 160, -5 - 16 * (i-1))
		ilvlString:SetFont("Fonts\\ARIALN.TTF", 12)
		ilvlString:SetTextColor(1, 1, 1)
		ilvlString:SetJustifyH("CENTER")
		ilvlString:SetWidth(35)

		local statusString = content:CreateFontString("$parentStatus"..i, nil, "GameFontNormal")
		statusString:SetPoint("TOPLEFT", content, "TOPLEFT", 195, -5 - 16 * (i-1))
		statusString:SetFont("Fonts\\ARIALN.TTF", 12)
		statusString:SetTextColor(1, 1, 1)
		statusString:SetJustifyH("LEFT")

		content.lines[#content.lines + 1] = {cb = cb, item = itemString, ilvl = ilvlString, status = statusString}
	end

	for i = 1, #itemList do
		local line = content.lines[i]
		line.cb:Show()
		line.item:Show()
		line.ilvl:Show()
		line.status:Show()
	end

	for i = #itemList+1, #content.lines do
		local line = content.lines[i]
		line.cb:Hide()
		line.cb.itemId = nil
		line.cb.item = nil
		line.item:Hide()
		line.ilvl:Hide()
		line.status:Hide()
	end

	for i = 1, #itemList do
		local line = content.lines[i]
		local item = itemList[i]

		line.cb:SetChecked(isItemIgnored(item.link))
		line.cb.itemId = getItemIdByLink(item.link)
		line.cb.item = item
		line.item:SetText(item.link)
		line.ilvl:SetText(item.ilvl)
		line.status:SetText(learnedTypes[item.status][1])
	end

	content.itemList = itemList

	content:SetWidth(300)
	content:SetHeight(#itemList * 16 + 5)

	frame.scrollbar:SetMinMaxValues(1, max(1, content:GetHeight() - (frame:GetHeight() - (180+35)))) -- scrollframe points
end

local function onFilterCheckedChange(self, ...)
	if self.type=="onuse" then
		addon.db.filters[self.type] = self:GetChecked()
	else
		addon.db.filters[self.type][self.id] = self:GetChecked()
	end
	updateItemList(sellWindow)
end

local function onSellModeCheckedChange(self, ...)
	addon.db.sellMode[self.type] = self:GetChecked()
end

local function ilvlSliderValueChanged(self, value)
	local newValue = floor(value + 0.5)
	self:SetValue(newValue)
	self.editbox:SetText(newValue)
	addon.db.filters.ilvl = newValue

	if updateItemListThrottle then
		updateItemListThrottle:Cancel()
	end

	updateItemListThrottle = C_Timer.NewTimer(0.2, function()
		updateItemList(sellWindow)
	end)
end

local function createSellWindow()
	-- Main Window
	local frame = CreateFrame("Frame", "TCSellWindow", MerchantFrame)
	frame:SetWidth(MerchantFrame:GetWidth())
	frame:SetHeight(MerchantFrame:GetHeight())
	frame:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 5, 0)

	local tex = frame:CreateTexture("$parentBg","BACKGROUND")
	tex:SetColorTexture(0, 0, 0, 0.4)
	tex:SetAllPoints(frame)

	-- Header Text
	local header = frame:CreateFontString("$parentHeaderText", nil, "GameFontNormal")
	header:SetPoint("TOP", frame, "TOP", 0, -5)
	header:SetFont("Fonts\\ARIALN.TTF", 14, "OUTLINE")
	header:SetTextColor(1, 1, 1)
	header:SetText("TransmogCleanup " .. version)

	local filterText = frame:CreateFontString("$parentDescText", nil, "GameFontNormal")
	filterText:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -10 - header:GetStringHeight())
	filterText:SetFont("Fonts\\ARIALN.TTF", 12, "OUTLINE")
	filterText:SetTextColor(1, 1, 1)
	filterText:SetJustifyH("left")
	filterText:SetText("Sell filters")

	local qualityCBs = {}
	for i = 1, #itemQualities do
		local cb = CreateFrame("CheckButton", "TCSellWindowQualityCB"..i, frame, "InterfaceOptionsCheckButtonTemplate")
		cb:SetPoint("LEFT", frame, "TOPLEFT", 5, -34 - 17 * i)
		_G["TCSellWindowQualityCB"..i.."Text"]:SetText(_G["ITEM_QUALITY"..i.."_DESC"])
		_G["TCSellWindowQualityCB"..i.."Text"]:SetTextColor(unpack(itemQualities[i]))
		cb:SetHitRectInsets(0, -80, 0, 0)
		cb.type = "quality"
		cb.id = i
		cb:SetScript("OnClick", onFilterCheckedChange)
		qualityCBs[#qualityCBs + 1] = cb
	end
	frame.qualityCBs = qualityCBs

	local bindCBs = {}
	for i = 1, #bindOn do
		local cb = CreateFrame("CheckButton", "TCSellWindowBindCB"..i, frame, "InterfaceOptionsCheckButtonTemplate")
		cb:SetPoint("LEFT", frame, "TOPLEFT", 120, -34 - 17 * i)
		_G["TCSellWindowBindCB"..i.."Text"]:SetText(bindOn[i][1])
		cb:SetHitRectInsets(0, -35, 0, 0)
		cb.type = "bind"
		cb.id = i
		cb:SetScript("OnClick", onFilterCheckedChange)
		bindCBs[#bindCBs + 1] = cb
	end
	frame.bindCBs = bindCBs

	local learnedCBs = {}
	for i = 1, #learnedTypes do
		local cb = CreateFrame("CheckButton", "TCSellWindowLearnedCB"..i, frame, "InterfaceOptionsCheckButtonTemplate")
		cb:SetPoint("LEFT", frame, "TOPLEFT", 180, -34 - 17 * i)
		_G["TCSellWindowLearnedCB"..i.."Text"]:SetText(learnedTypes[i][1])
		_G["TCSellWindowLearnedCB"..i.."Text"]:SetWidth(120)
		cb.type = "learned"
		cb.id = i
		cb:SetScript("OnClick", onFilterCheckedChange)
		learnedCBs[#learnedCBs + 1] = cb
	end
	frame.learnedCBs = learnedCBs

	-- some shenanigans for the long text CheckButton
	-- this will break with localization
	_G["TCSellWindowLearnedCB3Text"]:SetPoint("TOPLEFT", "TCSellWindowLearnedCB3", "TOPRIGHT", 2, 1)
	_G["TCSellWindowLearnedCB3Text"]:SetHeight(37)
	_G["TCSellWindowLearnedCB3Text"]:SetWordWrap(true)
	_G["TCSellWindowLearnedCB3Text"]:SetJustifyV("MIDDLE")

	-- On Use Filter
	local cb = CreateFrame("CheckButton", "TCSellWindowOnUseCB", frame, "InterfaceOptionsCheckButtonTemplate")
	cb:SetPoint("LEFT", frame, "TOPLEFT", 120, -102)
	_G["TCSellWindowOnUseCBText"]:SetText("On Use")
	cb:SetHitRectInsets(0, -35, 0, 0)
	cb.type = "onuse"
	cb:SetScript("OnClick", onFilterCheckedChange)
	frame.onUseCB = cb

	-- Safe mode selling
	local safeModeCB = CreateFrame("CheckButton", "TCSellWindowSafeModeCB", frame, "InterfaceOptionsCheckButtonTemplate")
	safeModeCB:SetPoint("LEFT", frame, "BOTTOMLEFT", 120, 24)
	safeModeCB:SetHeight(20)
	safeModeCB:SetWidth(20)
	_G["TCSellWindowSafeModeCBText"]:SetText("Safe Mode")
	_G["TCSellWindowSafeModeCBText"]:SetFont("Fonts\\ARIALN.TTF", 12)
	safeModeCB:SetHitRectInsets(0, -50, 0, 0)
	safeModeCB.type = "safe"
	safeModeCB:SetScript("OnClick", onSellModeCheckedChange)
	frame.safeModeCB = safeModeCB

	-- Verbose selling
	local verboseModeCB = CreateFrame("CheckButton", "TCSellWindowVerboseModeCB", frame, "InterfaceOptionsCheckButtonTemplate")
	verboseModeCB:SetPoint("TOPLEFT", safeModeCB, "BOTTOMLEFT", 0, 7)
	verboseModeCB:SetHeight(20)
	verboseModeCB:SetWidth(20)
	_G["TCSellWindowVerboseModeCBText"]:SetText("Verbose Mode")
	_G["TCSellWindowVerboseModeCBText"]:SetFont("Fonts\\ARIALN.TTF", 12)
	verboseModeCB:SetHitRectInsets(0, -50, 0, 0)
	verboseModeCB.type = "verbose"
	verboseModeCB:SetScript("OnClick", onSellModeCheckedChange)
	frame.verboseModeCB = verboseModeCB

	-- Item level slider
	local ilvlSlider = CreateFrame("Slider", "TCSellWindowIlvlSlider", frame, "OptionsSliderTemplate")
	ilvlSlider:SetPoint("TOPLEFT", frame, "TOPLEFT", 125, -120)
	ilvlSlider:SetWidth(190)
	_G["TCSellWindowIlvlSliderText"]:SetText("Max Item level")
	_G["TCSellWindowIlvlSliderLow"]:SetText("1")
	_G["TCSellWindowIlvlSliderHigh"]:SetText("750")
	ilvlSlider:SetMinMaxValues(1, 750)
 	ilvlSlider:SetValue(720)
	ilvlSlider:SetValueStep(1)
	ilvlSlider:SetHitRectInsets(0, 0, 0, 0) -- default from OptionsSliderTemplate: 0,0,-10,-10

	local editbox = CreateFrame("EditBox", nil, frame)
	editbox:SetAutoFocus(false)
	editbox:SetFontObject(GameFontHighlightSmall)
	editbox:SetPoint("TOP", ilvlSlider, "BOTTOM")
	editbox:SetHeight(14)
	editbox:SetWidth(70)
	editbox:SetJustifyH("CENTER")
	editbox:EnableMouse(true)
	editbox:SetBackdrop({
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
		tile = true, edgeSize = 1, tileSize = 5,
	})
	editbox:SetBackdropColor(0, 0, 0, 0.5)
	editbox:SetBackdropBorderColor(0.3, 0.3, 0.30, 0.80)
	editbox:SetText(ilvlSlider:GetValue())

	editbox.slider = ilvlSlider
	ilvlSlider.editbox = editbox
	frame.ilvlSlider = ilvlSlider

	ilvlSlider:SetScript("OnValueChanged", ilvlSliderValueChanged)

	editbox:SetScript("OnEnterPressed", function(self)
		self.slider:SetValue(tonumber(self:GetText()))
	end)

	editbox:SetScript("OnEscapePressed", function(self)
		self:SetText(self.slider:GetValue())
	end)

	local ignoredHeaderText = frame:CreateFontString("$parentIgnoredHeaderText", nil, "GameFontNormal")
	ignoredHeaderText:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -165)
	ignoredHeaderText:SetFont("Fonts\\ARIALN.TTF", 12, "OUTLINE")
	ignoredHeaderText:SetTextColor(1, 1, 1)
	ignoredHeaderText:SetText("Ignored")

	local itemHeaderText = frame:CreateFontString("$parentItemHeaderText", nil, "GameFontNormal")
	itemHeaderText:SetPoint("TOPLEFT", frame, "TOPLEFT", 95, -165)
	itemHeaderText:SetFont("Fonts\\ARIALN.TTF", 12, "OUTLINE")
	itemHeaderText:SetTextColor(1, 1, 1)
	itemHeaderText:SetText("Item")

	local ilvlHeaderText = frame:CreateFontString("$parentIlvlHeaderText", nil, "GameFontNormal")
	ilvlHeaderText:SetPoint("TOPLEFT", frame, "TOPLEFT", 176, -165)
	ilvlHeaderText:SetFont("Fonts\\ARIALN.TTF", 12, "OUTLINE")
	ilvlHeaderText:SetTextColor(1, 1, 1)
	ilvlHeaderText:SetText("ilvl")

	local statusHeaderText = frame:CreateFontString("$parentStatusHeaderText", nil, "GameFontNormal")
	statusHeaderText:SetPoint("TOPLEFT", frame, "TOPLEFT", 235, -165)
	statusHeaderText:SetFont("Fonts\\ARIALN.TTF", 12, "OUTLINE")
	statusHeaderText:SetTextColor(1, 1, 1)
	statusHeaderText:SetText("Status")

	--scrollframe
	local scrollframe = CreateFrame("ScrollFrame", nil, frame)
	scrollframe:SetPoint("TOPLEFT", 5, -180)
	scrollframe:SetPoint("BOTTOMRIGHT", -26, 35)
	scrollframe:SetScript("OnMouseWheel", function(self, value)
		local scrollbar = self:GetParent().scrollbar
		local scrollStep = scrollbar.scrollStep or scrollbar:GetHeight() / 2
		if ( value > 0 ) then
			scrollbar:SetValue(scrollbar:GetValue() - scrollStep)
		else
			scrollbar:SetValue(scrollbar:GetValue() + scrollStep)
		end
	end)
	local texture = scrollframe:CreateTexture()
	texture:SetAllPoints()
	texture:SetColorTexture(0, 0, 0, 0.4)
	frame.scrollframe = scrollframe

	--scrollbar
	local scrollbar = CreateFrame("Slider", nil, scrollframe, "UIPanelScrollBarTemplate")
	scrollbar:SetPoint("TOPLEFT", scrollframe, "TOPRIGHT", 2, -16)
	scrollbar:SetPoint("BOTTOMLEFT", scrollframe, "BOTTOMRIGHT", 2, 16)
	scrollbar:SetMinMaxValues(1, 200)
	scrollbar:SetValueStep(1)
	scrollbar:SetValue(0)
	scrollbar:SetWidth(16)
	scrollbar:SetScript("OnValueChanged", function (self, value)
		self:GetParent():SetVerticalScroll(value)
	end)
	local scrollbg = scrollbar:CreateTexture(nil, "BACKGROUND")
	scrollbg:SetAllPoints(scrollbar)
	scrollbg:SetColorTexture(0, 0, 0, 0.4)
	frame.scrollbar = scrollbar

	--content frame
	local content = CreateFrame("Frame", nil, scrollframe)

	scrollbar.scrollStep = 16

	scrollframe.content = content

	scrollframe:SetScrollChild(content)

	local sellButton = CreateFrame("Button", "TCSellWindowSellButton", frame, "UIPanelButtonTemplate")
	sellButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)
	sellButton:SetWidth(105)
	sellButton:SetHeight(26)
	sellButton:SetText("Sell the items!")
	sellButton:SetScript("OnClick", function(self) sellItems() end)

	local hideButton = CreateFrame("Button", "TCSellWindowSellButton", frame, "UIPanelButtonTemplate")
	hideButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 5, 5)
	hideButton:SetWidth(105)
	hideButton:SetHeight(26)
	hideButton:SetText("Hide")
	hideButton:SetScript("OnClick", function(self) self:GetParent():Hide() end)

	frame:Hide()

	sellWindow = frame
end

local function updateSellSettings(sellWindow)
	for i =1,#sellWindow.qualityCBs do
		sellWindow.qualityCBs[i]:SetChecked(addon.db.filters.quality[i])
	end

	for i =1,#sellWindow.bindCBs do
		sellWindow.bindCBs[i]:SetChecked(addon.db.filters.bind[i])
	end

	for i =1,#sellWindow.learnedCBs do
		sellWindow.learnedCBs[i]:SetChecked(addon.db.filters.learned[i])
	end

	sellWindow.onUseCB:SetChecked(addon.db.filters.onuse)

	sellWindow.ilvlSlider:SetValue(addon.db.filters.ilvl)

	sellWindow.safeModeCB:SetChecked(addon.db.sellMode.safe)

	sellWindow.verboseModeCB:SetChecked(addon.db.sellMode.verbose)
end

local function displaySellWindow()
	if not sellWindow then createSellWindow() end

	updateSellSettings(sellWindow)

	updateItemList(sellWindow)

	SetUpSideDressUpFrame(sellWindow, 400, 600, "TOPLEFT", "TOPRIGHT", -5, 0)

	sellWindow:Show()
end

local function createMerchantButton()
	if not merchantButton then
		merchantButton = CreateFrame("Button", "TCMerchantButton", MerchantFrame, "UIPanelButtonTemplate")
		merchantButton:SetWidth(110)
		if SellJunk then -- dirty hack to avoid overlapping buttons
			merchantButton:SetPoint("BOTTOMLEFT", MerchantFramePortrait, "BOTTOMRIGHT", 5, -12)
			merchantButton:SetHeight(16)
		else
			merchantButton:SetPoint("BOTTOMLEFT", MerchantFramePortrait, "BOTTOMRIGHT", 2, -2)
			merchantButton:SetHeight(26)
		end
		merchantButton:SetText("Sell Transmog")
		merchantButton:SetScript("OnClick", function(self) displaySellWindow() end)
	end
end


--------------------------------------------------------------------------------
-- Event Handler
--

local events = {}

function events:PLAYER_ENTERING_WORLD(...)
	C_Timer.After(10, function()
		checkForDependencies()
	end)
end

function events:ADDON_LOADED(...)
	if select(1, ...) == "TransmogCleanup" then
		addon:UnregisterEvent("ADDON_LOADED")
		addon.db = TransmogCleanupDB
		local db = addon.db

		if not db.filters then
			db.filters = {
				["quality"] = {
					[1] = true,
					[2] = true,
					[3] = true,
					[4] = true,
				},
				["bind"] = {
					[1] = true,
					[2] = true,
					[3] = true,
				},
				["learned"] = {
					[1] = true,
					[2] = true,
				},
				["ilvl"] = 700,
			}
		end
		if not db.filters.onuse and db.filters.onuse ~= false then
			db.filters.onuse = true
		end

		if not db.ignoredItems then
			db.ignoredItems = {}
		end

		for k,v in pairs(addon:getDefaultIgnoredItems()) do
			if not db.ignoredItems[k] and db.ignoredItems[k] ~= false then
				db.ignoredItems[k] = v
			end
		end

		if not db.sellMode then
			db.sellMode = {
				["safe"] = true,
				["verbose"] = false,
			}
		end
	end
end

function events:MERCHANT_SHOW(...)
	if enabled then
		createMerchantButton()
	end
end

function events:BAG_UPDATE(...)
	if sellWindow and sellWindow:IsShown() then
		if updateItemListThrottle then
			updateItemListThrottle:Cancel()
		end

		updateItemListThrottle = C_Timer.NewTimer(0.2, function()
			updateItemList(sellWindow)
		end)
	end
end

addon:SetScript("OnEvent", function(self, event, ...)
	events[event](self, ...)
end)

for k,_ in pairs(events) do
	addon:RegisterEvent(k)
end

--------------------------------------------------------------------------------
-- Slash Command Handler
--
local function slashCmdHandler(msg)
	print("Go to a merchant and click Sell Transmog!")
end

SlashCmdList['TRANSMOGCLEANUP_SLASHCMD'] = slashCmdHandler
SLASH_TRANSMOGCLEANUP_SLASHCMD1 = '/transmogcleanup'
