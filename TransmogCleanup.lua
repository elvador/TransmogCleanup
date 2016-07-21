
local folder, ns = ...
TransmogCleanup = CreateFrame("Frame")
local addon = TransmogCleanup

--------------------------------------------------------------------------------
-- Upvalues
--

local orgPrint = print
local cimi = CanIMogIt
local ItemUpgradeInfo = LibStub("LibItemUpgradeInfo-1.0")
local YES, NO, OKAY, CANCEL = YES, NO, OKAY, CANCEL

--------------------------------------------------------------------------------
-- Variables
--

local enabled = true -- changed via checkForDependencies
local maxItemlevelToSell = 0

--------------------------------------------------------------------------------
-- Debug Functions
--

local function print(...)
	orgPrint("|cffec7600TransmogCleanup|r:", ...)
end

--------------------------------------------------------------------------------
-- Functions
--

local function checkForDependencies()
	if not CanIMogIt then
		print("Dependency missing! Download |cff93c763Can I Mog It?|r from Curse here: |cff72aacahttp://mods.curse.com/addons/wow/can-i-mog-it|r")
    enabled = false
	end
end

local function iterateBagItems(sellThem, maxIlvl)
	local itemList = ""
  local itemsSold = 0
  local itemsSoldValue = 0

	for bag = 0,4 do
		for slot = 1,GetContainerNumSlots(bag) do
			local link = GetContainerItemLink(bag, slot)
			if link then
				local ilvl = ItemUpgradeInfo:GetUpgradedItemLevel(link)
        local vendorPrice = select(11, GetItemInfo(link))
				if ilvl <= maxIlvl and vendorPrice > 0 then -- pricecheck: can item be sold
					local mogStatus = cimi:GetTooltipText(link)
					if mogStatus == cimi.KNOWN or
						 mogStatus == cimi.KNOWN_FROM_ANOTHER_ITEM or
						 mogStatus == cimi.KNOWN_BY_ANOTHER_CHARACTER or
						 mogStatus == cimi.KNOWN_BUT_TOO_LOW_LEVEL then
						if sellThem then
							UseContainerItem(bag, slot)
              itemsSold = itemsSold + 1
              itemsSoldValue = itemsSoldValue + vendorPrice
						end

						itemList = itemList .. link .. "(".. ilvl ..")" .. "\n"
					end
				end
			end
		end
	end

  if sellThem then
    return itemsSold, itemsSoldValue
  else
    return itemList
  end
end

local function confirmSellingItems()
  StaticPopupDialogs["SellKnownMogItemsConfirm"] = {
    text = "You will sell these Items:\n"..iterateBagItems(false, maxItemlevelToSell),
    button1 = OKAY,
    button2 = CANCEL,
    OnAccept = function(self)
      local itemsSold, itemsSoldValue = iterateBagItems(true, maxItemlevelToSell)
      print(("You earned %s by selling %d items."):format(GetCoinTextureString(itemsSoldValue), itemsSold))
    end,
  }

  StaticPopup_Show("SellKnownMogItemsConfirm","Sell Transmog Items?")
end

local function wantToSellItems()
  StaticPopupDialogs["SellKnownMogItems"] = {
    text = "Do you want to sell the Items which appearance you have learned?\nInput the maximum Item level you want to sell here:",
    button1 = YES,
    button2 = NO,
    hasEditBox = 1,
    OnAccept = function(self)
      maxItemlevelToSell = tonumber(self.editBox:GetText())
      C_Timer.After(0, function() -- hack to avoid 2 static popups
        confirmSellingItems()
      end)
    end,
    }

    StaticPopup_Show("SellKnownMogItems","Sell Transmog Items?")
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

function events:MERCHANT_SHOW(...)
  if enabled then
    wantToSellItems()
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
	print("Go to a merchant!")
end

SlashCmdList['TRANSMOGCLEANUP_SLASHCMD'] = slashCmdHandler
SLASH_TRANSMOGCLEANUP_SLASHCMD1 = '/transmogcleanup'
