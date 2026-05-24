--[[
    Auctioneer - BigPicture Utility module (Reborn Fix)
    Works on: Bronzebeard / WoW 3.3.5a
]]

if not AucAdvanced then return end

local libName = "BigPicture"
local libType = "Util"

-- Create module safely (older Auctioneer can return nils)
local lib, parent, private = AucAdvanced.NewModule(libType, libName)
if not lib then
    -- Hard fail protection to avoid "table index is nil"
    AucAdvanced.Print("BigPicture failed: Could not create module.")
    return
end

-- Safe locals (older GetModuleLocals does not return full list)
local print,
      decode,
      _, _,          -- placeholders for missing returns in 3.3.5
      replicate,
      empty,
      get,
      set,
      default,
      debugPrint,
      fill =
          AucAdvanced.GetModuleLocals()

-- Fallback in case GetModuleLocals returned nil for some fields
local function NullFunc() end
replicate    = replicate    or NullFunc
empty        = empty        or function() return {} end
get          = get          or function() return nil end
set          = set          or NullFunc
default      = default      or NullFunc
debugPrint   = debugPrint   or NullFunc
fill         = fill         or NullFunc

-- Safe API access
local GetAlgorithms     = AucAdvanced.API.GetAlgorithms
local GetMarketValue    = AucAdvanced.API.GetMarketValue
local GetAlgorithmValue = AucAdvanced.API.GetAlgorithmValue

-- Appraiser may not exist on BB client → protect call
local Appraiser = AucAdvanced.Modules and AucAdvanced.Modules.Util and AucAdvanced.Modules.Util.Appraiser
local GetPrice = Appraiser and Appraiser.GetPrice or function() return nil end

-- Globals for external access
BigPicture       = BigPicture or {}
BigPictureGuild  = BigPictureGuild or {}

local frame
private.CscrollRows = 20
private.GscrollRows = 22
private.items = {}
lib.API = {}
BP_API = lib.API

-- Safe bind type lookup table
local BindTypes = {}

-- Classics exist in all 3.3.5 cores
if ITEM_SOULBOUND          then BindTypes[ITEM_SOULBOUND]          = "Bound" end
if ITEM_BIND_QUEST         then BindTypes[ITEM_BIND_QUEST]         = "Quest" end
if ITEM_CONJURED           then BindTypes[ITEM_CONJURED]           = "Conjured" end

-- These do NOT exist on 3.3.5 normally → safe conditional
if ITEM_BNETACCOUNTBOUND   then BindTypes[ITEM_BNETACCOUNTBOUND]   = "Accountbound" end
if ITEM_ACCOUNTBOUND       then BindTypes[ITEM_ACCOUNTBOUND]       = "Accountbound" end

-- Store it
private.BindTypes = BindTypes


-- ===============================
-- FIXED DEFAULTS + TYPE TABLES
-- ===============================

private.defaults = {
	["util.BigPicture.Activated"]          = true,
	["util.BigPicture.CalcWithBid"]        = 1,
	["util.BigPicture.CalcWithCut"]        = true,
	["util.BigPicture.CalcWithBidBid"]     = false,
	["util.BigPicture.model"]              = "market",
	["util.BigPicture.modelOverride"]      = false,
	["util.BigPicture.CalcRealm"]          = true,
	["util.BigPicture.CalcFaction"]        = true,
	["util.BigPicture.CalcOppositeFaction"]= true,
	["util.BigPicture.ShowGblDetail"]      = false,
	["util.BigPicture.ScanBank"]           = true,
	["util.BigPicture.ScanBags"]           = true,
	["util.BigPicture.CharLists"]          = "Current",
	["util.BigPicture.DeleteCharbutton"]   = false,
	["util.BigPicture.min.quality"]        = 0,
	["util.BigPicture.type.all"]           = true,
	["util.BigPicture.ScanGuild"]          = true,
	["util.BigPicture.PrintMessage"]       = true,
	["util.BigPicture.ScanGuildType"]      = 1,
}

private.typename = {
	"Armor",
	"Consumable",
	"Container",
	"Gem",
	"Key",
	"Miscellaneous",
	"Recipe",
	"Projectile",
	"Quest",
	"Quiver",
	"Trade Goods",
	"Weapon",
	"Glyph",
	"Reagent",
}

private.subtypename = {
	["Weapon"] = {
		"One-Handed Axes","Two-Handed Axes","Bows","Guns",
		"One-Handed Maces","Two-Handed Maces","Polearms",
		"One-Handed Swords","Two-Handed Swords","Staves",
		"Fist Weapons","Miscellaneous","Daggers","Thrown",
		"Crossbows","Wands","Fishing Poles",
	},
	["Armor"] = {
		"Miscellaneous","Cloth","Leather","Mail","Plate",
		"Shields","Sigils",
	},
	["Container"] = {
		"Bag","Herb Bag","Enchanting Bag","Engineering Bag",
		"Gem Bag","Mining Bag","Leatherworking Bag",
		"Inscription Bag","Tackle Box",
	},
	["Consumable"] = {
		"Food & Drink","Potion","Elixir","Flask","Bandage",
		"Item Enhancement","Scroll","Other","Consumable",
	},
	["Glyph"] = {
		"Warrior","Paladin","Hunter","Rogue","Priest","Death Knight",
		"Shaman","Mage","Warlock","Monk","Druid",
	},
	["Trade Goods"] = {
		"Elemental","Cloth","Leather","Metal & Stone","Cooking","Herb","Enchanting",
		"Jewelcrafting","Parts","Devices","Explosives","Materials",
		"Other","Item Enchantment","Trade Goods",
	},
	["Recipe"] = {
		"Book","Leatherworking","Tailoring","Engineering","Blacksmithing",
		"Cooking","Alchemy","First Aid","Enchanting","Fishing",
		"Jewelcrafting","Inscription",
	},
	["Gem"] = {
		"Red","Blue","Yellow","Purple","Green","Orange",
		"Meta","Simple","Prismatic","Cogwheel",
	},
	["Miscellaneous"] = {
		"Junk","Reagent","Companion Pets","Holiday","Other","Mount",
	},
	["Quest"] = { "Quest" },

	-- Battle Pets DO NOT EXIST in 3.3.5 but keeping it won't break anything
	["Battle Pets"] = {
		"Humanoid","Dragonkin","Flying","Undead","Critter",
		"Magic","Elemental","Beast","Aquatic","Mechanical",
	},
}

-- generate default on/off entries for each type/subtype
for _, value in ipairs(private.typename) do
	private.defaults["util.BigPicture.type."..value] = true
end

for ptype, list in pairs(private.subtypename) do
	if type(list) == "table" then
		for _, stype in ipairs(list) do
			private.defaults["util.BigPicture.type."..ptype.."."..stype] = true
		end
	end
end

-- DO NOT SORT defaults (invalid)
-- table.sort(private.defaults)  -- removed!


function private.GetPriceModels(link)
	if not private.scanValueNames then private.scanValueNames = {} end
	for i = 1, #private.scanValueNames do
		private.scanValueNames[i] = nil
	end

	table.insert(private.scanValueNames,{"market", "Market value"})
	local algoList = GetAlgorithms(link)
	for pos, name in ipairs(algoList) do
		if (name ~= lib.libName) then
			table.insert(private.scanValueNames,{name, "Stats: "..name})
		end
	end
	return private.scanValueNames
end

--[[Sidebar Section]]--
function private.slidebar_press(_, button)
	if (button == "LeftButton") then
		private.StandAlone()
	else
	--if we rightclick open the configuration window for the whole addon
		if private.gui and private.gui:IsShown() then
			AucAdvanced.Settings.Hide()
		else
			AucAdvanced.Settings.Show()
			private.gui:ActivateTab(private.guiID)
		end
	end
end
function private.slidebar()
	if LibStub then
		local sideIcon
		sideIcon =  "Interface\\AddOns\\Auc-Util-BigPicture\\Textures\\BigPictureIcon"
		
		local LibDataBroker = LibStub:GetLibrary("LibDataBroker-1.1", true)
		if LibDataBroker then
			private.LDBButton = LibDataBroker:NewDataObject("Auc-Util-BigPicture", {
						type = "launcher",
						icon = sideIcon,
						OnClick = function(self, button) private.slidebar_press(self, button) end,
					})
			
			function private.LDBButton:OnTooltipShow()
				self:AddLine("BigPicture:",  1,1,0.5, 1)
				self:AddLine("Records a snapshot of incomming and outgoing auctions.  It also can track the value of inventory in bags and bank.",  1,1,0.5, 1)
				self:AddLine("|cff1fb3ff".."Left-Click|r to view your Wealth.",  1,1,0.5, 1)
				self:AddLine("|cff1fb3ff".."Right-Click|r to edit the configuration.",  1,1,0.5, 1)
			end

			function private.LDBButton:OnEnter()
				GameTooltip:SetOwner(self, "ANCHOR_NONE")
				GameTooltip:SetPoint("TOPLEFT", self, "BOTTOMLEFT")
				GameTooltip:ClearLines()
				private.LDBButton.OnTooltipShow(GameTooltip)
				GameTooltip:Show()
			end
			
			function private.LDBButton:OnLeave()
				GameTooltip:Hide()
			end
		end
	end
end

function private.wait(seconds)
	local startTime = GetTime()
	local endTime = startTime+seconds
	while (endTime >= GetTime()) do
	end
end

function private.DeleteCharInfo()
	local sourceValue = get("util.BigPicture.CharLists")
	if sourceValue == "Current" then return end
	local realm, faction, name = string.split("-",sourceValue)
	
	private.tempTable = {}

	for key, value in pairs(BigPicture[realm][faction]) do
		if key ~= name then private.tempTable[key] = value end
	end
	BigPicture[realm][faction] = private.tempTable

	for key, value in pairs(private.CharList) do 
		if value == sourceValue then
		  table.remove(private.CharList,key)
		end		
	end
	set("util.BigPicture.CharLists", "Current")
	set("util.BigPicture.DeleteCharbutton", false)
	private.savedVars()
	local gui = private.gui
	gui:Refresh()
end

function private.savedVars()
	local realm = GetRealmName()
	local faction = UnitFactionGroup("player")
	local name = UnitName("player")

	if (BigPicture) then	else BigPicture = { } end
	if (BigPicture[realm]) then	 else BigPicture[realm] = { } end
	if (BigPicture[realm][faction]) then	else BigPicture[realm][faction] = { } end
	if (BigPicture[realm][faction][name]) then	else BigPicture[realm][faction][name] = { } end

	BPChar = BigPicture[realm][faction][name]
	BPChar.realm = realm
	BPChar.faction = faction
	BPChar.name = name
	BPChar.guildname = GetGuildInfo("player") or nil
	BPChar.cutRate = AucAdvanced.cutRate or 0.05
	BPChar.BagsVal = BPChar.BagsVal or 0
	BPChar.BankVal = BPChar.BankVal or 0
	BPChar.BidBidVal = BPChar.BidBidVal or 0
	BPChar.AucBidVal = BPChar.AucBidVal or 0
	BPChar.AucBOVal = BPChar.AucBOVal or 0
	BPChar.BagsScanDate = BPChar.BagsScanDate or nil
	BPChar.BankScanDate = BPChar.BankScanDate or nil
	BPChar.AucScanDate = BPChar.AucScanDate or nil
	BPChar.Money = GetMoney()

	private.CharList = {}
	for realm, factionTable in pairs(BigPicture) do 
		for faction, nameTable in pairs(factionTable) do
			for name, value in pairs(nameTable) do 
				table.insert(private.CharList,(realm.."-"..faction.."-"..name))
			end
		end
	end
	table.sort(private.CharList)
	table.insert(private.CharList,1,"Current")

	if (IsInGuild()) then 
		local guildname = GetGuildInfo("player")
		if guildname == nil then return end
		_G["BigPictureEventFrame"]:UnregisterEvent("GUILD_ROSTER_UPDATE")
		if (BigPictureGuild) then	else BigPictureGuild = { } end
		if (BigPictureGuild[realm]) then	 else BigPictureGuild[realm] = { } end
		if (BigPictureGuild[realm][faction]) then	else BigPictureGuild[realm][faction] = { } end
		if (BigPictureGuild[realm][faction][guildname]) then	else BigPictureGuild[realm][faction][guildname] = { } end
		BPGuild = BigPictureGuild[realm][faction][guildname]
		BPGuild.realm = realm
		BPGuild.faction = faction
		BPGuild.guildname = guildname
		BPGuild.BankVal = BPGuild.BankVal or 0
		BPGuild.BankScanDate = BPGuild.BankScanDate or nil
		BPGuild.Money = BPGuild.Money or 0

	end
end

function private.FilterType(typename,subtypename)
	if get("util.BigPicture.type.all") == true then
		return true
	elseif get("util.BigPicture.type."..typename) == true then
		return true
	elseif get("util.BigPicture.type."..typename.."."..subtypename) == true then
		return true
	else
		return false
	end
end

function private.StandAlone(_,button)
	if (button == "RightButton") then
		if private.gui and private.gui:IsShown() then
			AucAdvanced.Settings.Hide()
		else
			AucAdvanced.Settings.Show()
			private.gui:ActivateTab(private.guiID)
		end
	else 
		if private.frame:GetParent() == AuctionFrame then 
			private.frame:SetParent("BigPictureBaseFrame")
			private.frame:SetPoint("TOPLEFT", BigPictureBaseFrame, "TOPLEFT")
		end
		if not BigPictureBaseFrame:IsVisible() then
			if AuctionFrame then AuctionFrame:Hide() end
			BigPictureBaseFrame:Show()
			private.frame:SetFrameStrata("HIGH")
			if (get("util.BigPicture.ScanBags") == true) then private.ScanBags() end
			private.frame.charlist.SelectBoxSetting = "Current"
			private.frame.charlist.selectbox.box:SetText("Current")
			private.UpdateFrames()
			private.frame:Show()
		else
			BigPictureBaseFrame:Hide()
		end
	end
end

--Seperated frame items from frame creation, this should allow the same code to be reused for AH UI and Standalone UI
function private.CreateFrames()
	--Create the base frame for external GUI
	local base = CreateFrame("Frame", "BigPictureBaseFrame", UIParent)
	base:SetFrameStrata("HIGH")
	base:SetBackdrop({
		bgFile = "Interface/Tooltips/ChatBubble-Background",
		edgeFile = "Interface/Tooltips/ChatBubble-BackDrop",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 32, right = 32, top = 32, bottom = 32 }
	})
	base:SetBackdropColor(0,0,0, 1)
	base:Hide()
	
	base:SetPoint("CENTER", UIParent, "CENTER")
	base:SetWidth(834.5)
	base:SetHeight(450)
	
	base:SetMovable(true)
	base:EnableMouse(true)
	base.Drag = CreateFrame("Button", nil, base)
	base.Drag:SetPoint("TOPLEFT", base, "TOPLEFT", 10,-5)
	base.Drag:SetPoint("TOPRIGHT", base, "TOPRIGHT", -10,-5)
	base.Drag:SetHeight(6)
	base.Drag:SetHighlightTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar")

	base.Drag:SetScript("OnMouseDown", function() base:StartMoving() end)
	base.Drag:SetScript("OnMouseUp", function() base:StopMovingOrSizing() end)
	
	base.DragBottom = CreateFrame("Button",nil, base)
	base.DragBottom:SetPoint("BOTTOMLEFT", base, "BOTTOMLEFT", 10,5)
	base.DragBottom:SetPoint("BOTTOMRIGHT", base, "BOTTOMRIGHT", -10,5)
	base.DragBottom:SetHeight(6)
	base.DragBottom:SetHighlightTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar")

	base.DragBottom:SetScript("OnMouseDown", function() base:StartMoving() end)
	base.DragBottom:SetScript("OnMouseUp", function() base:StopMovingOrSizing() end)

	base.Done = CreateFrame("Button", nil, base, "OptionsButtonTemplate")
	base.Done:SetPoint("BOTTOMRIGHT", base, "BOTTOMRIGHT", -10, 10)
	base.Done:SetScript("OnClick", function() base:Hide() end)
	base.Done:SetText('Done')

	base.Scan = CreateFrame("Button", nil, base, "OptionsButtonTemplate")
	base.Scan:SetPoint("BOTTOMRIGHT", base.Done, "BOTTOMLEFT", 0, 0)
	base.Scan:SetScript("OnClick", private.ScanBags)
	base.Scan:SetText("Scan Bags")
		
			
	--Create the Actual Usable Frame
	local frame = CreateFrame("Frame", "BigPictureUiFrame", base)
	private.frame = frame
	frame:Hide()
	
	private.frame:SetPoint("TOPLEFT", base, "TOPLEFT")
	private.frame:SetWidth(828)
	private.frame:SetHeight(450)	
	
	--Add Title to the Top
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", 80, -17)
	title:SetText("BigPicture") 

	--Create the Global window
	frame.gbllist = CreateFrame("Frame", "BPFrame_GBL", frame)
	frame.gbllist:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
		tile = true, tileSize = 32, edgeSize = 16,
		insets = { left = 0, right = 0, top = 0, bottom = 0 }
	})
	frame.gbllist:SetBackdropColor(0, 0, 0.0, 1)
	frame.gbllist:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -110)
	frame.gbllist:SetWidth(290)
	frame.gbllist:SetHeight(290)
	frame.gbllist.title = frame.gbllist:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.gbllist.title:SetPoint("TOPLEFT", frame.gbllist, "TOPLEFT", 10, -10)
	frame.gbllist.title:SetText("Global")

	frame.gbllist.scroller = CreateFrame("Slider", "BPGBLScroll", frame.gbllist)
	frame.gbllist.scroller:SetPoint("TOPRIGHT", frame.gbllist, "TOPRIGHT", 15,0)
	frame.gbllist.scroller:SetPoint("BOTTOM", frame.gbllist, "BOTTOM", 0,0)
	frame.gbllist.scroller:SetWidth(20)
	frame.gbllist.scroller:SetOrientation("VERTICAL")
	frame.gbllist.scroller:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
	frame.gbllist.scroller:SetMinMaxValues(1, 30)
	frame.gbllist.scroller:SetValue(1)
	frame.gbllist.scroller:SetValueStep(1)
	frame.gbllist.scroller:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
		tile = true, tileSize = 32, edgeSize = 16,
		insets = { left = 5, right = 5, top = 5, bottom = 5 }
	})
	frame.gbllist.scroller:SetBackdropColor(0, 0, 0, 0.8)
	frame.gbllist.scroller:SetScript("OnValueChanged", private.GBLScroll)
	private.createLists("BPFrame_GBL")

	--Create the Character window
	frame.charlist = CreateFrame("Frame", "BPFrame_Char", frame)
	frame.charlist:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
		tile = true, tileSize = 32, edgeSize = 16,
		insets = { left = 0, right = 0, top = 0, bottom = 0 }
	})
	frame.charlist:SetBackdropColor(0, 0, 0.0, 1)
	frame.charlist:SetPoint("TOPRIGHT", frame.gbllist, "TOPLEFT", -25, -25)
	frame.charlist:SetWidth(290)
	frame.charlist:SetHeight(265)
	frame.charlist.title = frame.charlist:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.charlist.title:SetPoint("TOPLEFT", frame.charlist, "TOPLEFT", 10, -10)
	frame.charlist.title:SetText("Character")

	local SelectBox = LibStub:GetLibrary("SelectBox")
	frame.charlist.SelectBoxSetting = "Current"
	function private.ChangeControls(obj, arg1,arg2,...)
		frame.charlist.SelectBoxSetting = arg2
		private.UpdateFrames()
	end
	
	frame.charlist.selectbox = CreateFrame("Frame", "BPCharSelectBox", frame.charlist)
	frame.charlist.selectbox.box = SelectBox:Create("BPCharSelectBox", frame.charlist.selectbox, 270, private.ChangeControls, private.CharList, "default")
	frame.charlist.selectbox.box:SetPoint("TOPRIGHT", frame.charlist, "TOPRIGHT", 15, 25)
	frame.charlist.selectbox.box.element = "selectBox"
	frame.charlist.selectbox.box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.charlist.selectbox.box:SetText("Current")


	frame.charlist.scroller = CreateFrame("Slider", "BPCharScroll", frame.charlist)
	frame.charlist.scroller:SetPoint("TOPRIGHT", frame.charlist, "TOPRIGHT", 15,0)
	frame.charlist.scroller:SetPoint("BOTTOM", frame.charlist, "BOTTOM", 0,0)
	frame.charlist.scroller:SetWidth(20)
	frame.charlist.scroller:SetOrientation("VERTICAL")
	frame.charlist.scroller:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
	frame.charlist.scroller:SetMinMaxValues(1, 30)
	frame.charlist.scroller:SetValue(1)
	frame.charlist.scroller:SetValueStep(1)
	frame.charlist.scroller:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
		tile = true, tileSize = 32, edgeSize = 16,
		insets = { left = 5, right = 5, top = 5, bottom = 5 }
	})
	frame.charlist.scroller:SetBackdropColor(0, 0, 0, 0.8)
	frame.charlist.scroller:SetScript("OnValueChanged", private.CharScroll)
	private.createLists("BPFrame_Char")
end

function private.createLists(framename)
	local frame = _G[framename]

	local function lineHide(obj)
		local id = obj.id
		local line = frame.lines[id]
		line[1]:Hide()
		line[2]:Hide()
	end

	local function lineSet(obj, text, coins, r,g,b)
		local id = obj.id
		local line = frame.lines[id]
		line[1]:SetText(text)
		if r and g and b then
			line[1]:SetTextColor(r,g,b)
		else
			line[1]:SetTextColor(1,1,1)
		end
		line[1]:Show()

		if coins then
			line[2]:SetValue(math.floor(tonumber(coins) or 0))
			line[2]:Show()
		else
			line[2]:Hide()
		end
	end

	local function lineReset(obj, text, coins)
		local id = obj.id
		local line = frame.lines[id]
		line[1]:SetText("")
		line[2]:SetValue(0)
		line[2]:Hide()
	end

	local function linesClear(obj)
		obj.pos = 0
		for i = 1, obj.max do
			obj[i]:Hide()
		end
	end

	local function linesAdd(obj, text, coins, r,g,b)
		obj.pos = obj.pos + 1
		if (obj.pos > obj.max) then return end
		obj[obj.pos]:Set(text, coins, r,g,b)
	end

	local myStrata = frame:GetFrameStrata()

	local lines = { pos = 0, max = 28, Clear = linesClear, Add = linesAdd }
	for i=1, lines.max do
		local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		if i == 1 then
			text:SetPoint("TOPLEFT", frame, "TOPLEFT", 10,-30)
		else
			text:SetPoint("TOPLEFT", lines[i-1][1], "BOTTOMLEFT", 0,0)
		end
		text:SetPoint("RIGHT", frame, "RIGHT", -8,0)
		text:SetJustifyH("LEFT")
		text:SetHeight(11)

		local coins = AucAdvanced.CreateMoney(8)
		coins:SetParent(frame)
		coins:SetPoint("RIGHT", text, "RIGHT", 0,0)
		coins:SetFrameStrata(myStrata)
		local line = { text, coins, id = i, Hide = lineHide, Set = lineSet, Reset = lineReset }
		lines[i] = line
	end
	frame.lines = lines
end

function private.relevelFrame(frame)
	return private.relevelFrames(frame:GetFrameLevel() + 2, frame:GetChildren())
end

function private.relevelFrames(myLevel, ...)
	for i = 1, select("#", ...) do
		local child = select(i, ...)
		child:SetFrameLevel(myLevel)
		private.relevelFrame(child)
	end
end

function private.UpdateFrames()
	local temp = {}
	local BPTemp = {}
	local subTotal = 0
	local grandTotal = 0
	local realm, faction, name = nil, nil, nil
	private.GblScrollList = {}
	private.CharScrollList = {}

	--Build Char list
	local frame = _G["BigPictureUiFrame"]
	local sourceValue = frame.charlist.SelectBoxSetting
	if sourceValue == "Current" then
		realm = GetRealmName()
		faction = UnitFactionGroup("player")
		name = UnitName("player")
	else
		realm, faction, name = string.split("-",sourceValue)
	end
	BPTemp = BigPicture[realm][faction][name]

	subTotal = BPTemp.Money
	if (get("util.BigPicture.ScanBags") == true) then subTotal = subTotal + BPTemp.BagsVal end
	if (get("util.BigPicture.ScanBank") == true) then subTotal = subTotal + BPTemp.BankVal end
	if (get("util.BigPicture.CalcWithBid") == 0) then subTotal = subTotal + BPTemp.AucBidVal end
	if (get("util.BigPicture.CalcWithBid") == 1) then subTotal = subTotal + BPTemp.AucBOVal end
	if (get("util.BigPicture.CalcWithBidBid") == true) then	subTotal = subTotal + BPTemp.BidBidVal end

	table.insert(private.CharScrollList,{"Auctions Totals:",nil})
	table.insert(private.CharScrollList,{"",nil})
	table.insert(private.CharScrollList,{"  Bids out",BPTemp.BidBidVal or 0})
	table.insert(private.CharScrollList,{"  Auctions Bid",BPTemp.AucBidVal or 0})
	table.insert(private.CharScrollList,{"  Auctions Buyout",BPTemp.AucBOVal or 0})
	table.insert(private.CharScrollList,{"",nil})
	table.insert(private.CharScrollList,{"Inventory Totals:",nil})
	table.insert(private.CharScrollList,{"",nil})
	if get("util.BigPicture.ScanBags") == true then
		table.insert(private.CharScrollList,{"  Total Bags",BPTemp.BagsVal or 0})
	else
		table.insert(private.CharScrollList,{"  Total Bags",0})
	end
	if get("util.BigPicture.ScanBank") == true then
		table.insert(private.CharScrollList,{"  Total Bank",BPTemp.BankVal or 0})
	else
		table.insert(private.CharScrollList,{"  Total Bank",0})
	end

	table.insert(private.CharScrollList,{"",nil})
	table.insert(private.CharScrollList,{"Base Wealth:",BPTemp.Money})
	table.insert(private.CharScrollList,{"",nil})
	table.insert(private.CharScrollList,{"Character Total:",subTotal})
	table.insert(private.CharScrollList,{"________________________________________",nil})
	table.insert(private.CharScrollList,{"",nil})
	table.insert(private.CharScrollList,{"Scans:",nil})
	if BPTemp.AucScanDate == nil then
		table.insert(private.CharScrollList,{"  Please open AH window",nil})
	else
		table.insert(private.CharScrollList,{"  Aucs: "..BPTemp.AucScanDate,nil})
	end
	if get("util.BigPicture.ScanBags") == true then
		if BPTemp.BagsScanDate == nil then
			table.insert(private.CharScrollList,{"  Please Scan Bags",nil})
		else
			table.insert(private.CharScrollList,{"  Bags: "..BPTemp.BagsScanDate,nil})
		end
	else
		table.insert(private.CharScrollList,{"  Bag Scan Off",nil})
	end
	if get("util.BigPicture.ScanBank") == true then
		if BPTemp.BankScanDate == nil then
			table.insert(private.CharScrollList,{"  Please open Bank window",nil})
		else
			table.insert(private.CharScrollList,{"  Bank: "..BPTemp.BankScanDate,nil})
		end
	else
		table.insert(private.CharScrollList,{"  Bank Scan Off",nil})
	end

	-- Build Global list	
	for realm, factionTable in pairs(BigPicture) do 
		if (temp[realm]) then
		else
			temp[realm] = { }
		end
		for faction, nameTable in pairs(factionTable) do
			if (temp[realm][faction]) then
				temp[realm][faction].Total = temp[realm][faction].Total or 0
			else
				temp[realm][faction] = { }
				temp[realm][faction].Total = 0
				temp[realm][faction].MoneyTotal = 0
				temp[realm][faction].BagsTotal = 0
				temp[realm][faction].BankTotal = 0
				temp[realm][faction].BidBidTotal = 0
				temp[realm][faction].AucBidTotal = 0
				temp[realm][faction].AucBOTotal = 0
			end
			for name, value in pairs(nameTable) do
				subTotal = value.Money
				temp[realm][faction].MoneyTotal = temp[realm][faction].MoneyTotal + value.Money
				if (get("util.BigPicture.ScanBags") == true) then
					subTotal = subTotal + value.BagsVal
					temp[realm][faction].BagsTotal = temp[realm][faction].BagsTotal + value.BagsVal
				end
				if (get("util.BigPicture.ScanBank") == true) then
					subTotal = subTotal + value.BankVal
					temp[realm][faction].BankTotal = temp[realm][faction].BankTotal + value.BankVal
				end
				if (get("util.BigPicture.CalcWithBid") == 0) then
					subTotal = subTotal + value.AucBidVal
					temp[realm][faction].AucBidTotal = temp[realm][faction].AucBidTotal + value.AucBidVal
				end
				if (get("util.BigPicture.CalcWithBid") == 1) then
					subTotal = subTotal + value.AucBOVal
					temp[realm][faction].AucBOTotal = temp[realm][faction].AucBOTotal + value.AucBOVal
				end
				if (get("util.BigPicture.CalcWithBidBid") == true) then
					subTotal = subTotal + value.BidBidVal
				end
				temp[realm][faction].BidBidTotal = temp[realm][faction].BidBidTotal + value.BidBidVal
				temp[realm][faction].Total = temp[realm][faction].Total + subTotal
			end
		end
	end
	for realm, factionTable in pairs(temp) do
		if (realm == BPChar.realm) or ((get("util.BigPicture.CalcRealm") == true) and (get("util.BigPicture.CalcFaction") == true)) then
			table.insert(private.GblScrollList,{realm..":",nil})
			for faction, nameTable in pairs(factionTable) do
				if (faction == BPChar.faction) and (get("util.BigPicture.CalcFaction") == true) then
					table.insert(private.GblScrollList,{"",nil})
					table.insert(private.GblScrollList,{"  "..faction, nameTable.Total})
					if get("util.BigPicture.ShowGblDetail") == true then
						table.insert(private.GblScrollList,{"      Cash", nameTable.MoneyTotal})
						table.insert(private.GblScrollList,{"      Bags", nameTable.BagsTotal})
						table.insert(private.GblScrollList,{"      Bank", nameTable.BankTotal})
						table.insert(private.GblScrollList,{"      Bid Out", nameTable.BidBidTotal})
						table.insert(private.GblScrollList,{"      Bids in", nameTable.AucBidTotal})
						table.insert(private.GblScrollList,{"      Buyout", nameTable.AucBOTotal})
					end
					grandTotal = grandTotal + nameTable.Total
				end
				if (faction == BPChar.faction) and (get("util.BigPicture.CalcFaction") ~= true) and (realm == BPChar.realm) then
					table.insert(private.GblScrollList,{"  "..BPChar.name, subTotal})
					if get("util.BigPicture.ShowGblDetail") == true then
						table.insert(private.GblScrollList,{"      Cash", BPChar.Money})
						table.insert(private.GblScrollList,{"      Bags", BPChar.BagsVal})
						table.insert(private.GblScrollList,{"      Bank", BPChar.BankVal})
						table.insert(private.GblScrollList,{"      Bid out", BPChar.BidBidVal})
						table.insert(private.GblScrollList,{"      Bid in", BPChar.AucBidVal})
						table.insert(private.GblScrollList,{"      Buyout", BPChar.AucBOVal})
					end
					grandTotal = grandTotal + subTotal
				end
				if (faction ~= BPChar.faction) and (get("util.BigPicture.CalcOppositeFaction") == true) and (get("util.BigPicture.CalcFaction") == true) then
					table.insert(private.GblScrollList,{"  "..faction, nameTable.Total})
					if get("util.BigPicture.ShowGblDetail") == true then
						table.insert(private.GblScrollList,{"      Cash", nameTable.MoneyTotal})
						table.insert(private.GblScrollList,{"      Bags", nameTable.BagsTotal})
						table.insert(private.GblScrollList,{"      Bank", nameTable.BankTotal})
						table.insert(private.GblScrollList,{"      Bid Out", nameTable.BidBidTotal})
						table.insert(private.GblScrollList,{"      Bids in", nameTable.AucBidTotal})
						table.insert(private.GblScrollList,{"      Buyout", nameTable.AucBOTotal})
					end
					grandTotal = grandTotal + nameTable.Total
				end
			end
		end
		table.insert(private.GblScrollList,{"",nil})
	end
	table.insert(private.GblScrollList,{"",nil})
	table.insert(private.GblScrollList,{"Grand Total:", grandTotal})
	
	
	if (get("util.BigPicture.ScanGuild") == true and BPTemp.guildname) then
		local guildname = BPTemp.guildname or nil
		if (BigPictureGuild) then	else BigPictureGuild = { } end
		if (BigPictureGuild[realm]) then	 else BigPictureGuild[realm] = { } end
		if (BigPictureGuild[realm][faction]) then	else BigPictureGuild[realm][faction] = { } end
		if (BigPictureGuild[realm][faction][guildname]) then	else BigPictureGuild[realm][faction][guildname] = { } end
		BPGuild = BigPictureGuild[realm][faction][guildname]

		if BPGuild.BankScanDate == nil then
			table.insert(private.GblScrollList,{"  Please open Guild Bank window",nil})
		else
			BPGuild.Money = BPGuild.Money or 0
			BPGuild.BankVal = BPGuild.BankVal or 0
			table.insert(private.GblScrollList,{"________________________________________",nil})
			table.insert(private.GblScrollList,{"",nil})
			table.insert(private.GblScrollList,{"Guild: |cFF00FF00<"..guildname..">|r", BPGuild.BankVal+BPGuild.Money})
			table.insert(private.GblScrollList,{"      Cash", BPGuild.Money})
			table.insert(private.GblScrollList,{"      Bank", BPGuild.BankVal})
			table.insert(private.GblScrollList,{"  Guild Scanned: "..BPGuild.BankScanDate,nil})
		end
	else
		table.insert(private.GblScrollList,{"________________________________________",nil})
		table.insert(private.GblScrollList,{"",nil})
		table.insert(private.GblScrollList,{"  Guild Bank Scan Off",nil})
	end
	
	if #private.GblScrollList > private.GscrollRows then
		table.insert(private.GblScrollList,1,{"",nil})
		table.insert(private.GblScrollList,1,{"Grand Total:", grandTotal})
	end

	private.CharScroll()
	private.GBLScroll()
end

function private.GBLScroll()
	local scrollMax = #private.GblScrollList-(private.GscrollRows-1)
	if scrollMax < 1 then scrollMax = 1 end
	BPGBLScroll:SetMinMaxValues(1,scrollMax)
	local frame = _G["BPFrame_GBL"]
	frame.lines:Clear()
	local slidePos = BPGBLScroll:GetValue()
	local size = #private.GblScrollList
	local maxList = slidePos + (private.GscrollRows-1)
	if maxList >= size then maxList = size end
	if size <= (private.GscrollRows) then BPGBLScroll:Hide() else BPGBLScroll:Show() end

	for i = slidePos, maxList do
		if private.GblScrollList[i][2] then
			frame.lines:Add((private.GblScrollList[i][1]), (private.GblScrollList[i][2]))
		else
			frame.lines:Add((private.GblScrollList[i][1]))
		end
	end
end

function private.CharScroll()
	local scrollMax = #private.CharScrollList-(private.CscrollRows-1)
	if scrollMax < 1 then scrollMax = 1 end
	BPCharScroll:SetMinMaxValues(1,scrollMax)
	local frame = _G["BPFrame_Char"]
	frame.lines:Clear()
	local slidePos = BPCharScroll:GetValue()
	local size = #private.CharScrollList
	local maxList = slidePos + (private.CscrollRows-1)
	if maxList >= size then maxList = size end
	if size <= (private.CscrollRows) then BPCharScroll:Hide() else BPCharScroll:Show() end
	
	for i = slidePos, maxList do
		if private.CharScrollList[i][2] then
			frame.lines:Add((private.CharScrollList[i][1]), (private.CharScrollList[i][2]))
		else
			frame.lines:Add((private.CharScrollList[i][1]))
		end
	end
end
-- Safe Auction UI tab creation
local function CreateBigPictureTab()
    -- Bail if AuctionFrame doesn't exist yet
    if not AuctionFrame then return end

    -- Safety frame creation
    if not private.frame then
        local frame = CreateFrame("Frame", "BigPictureFrame", AuctionFrame)
        private.frame = frame
        frame:SetAllPoints(AuctionFrame)
        frame:Hide()
    end

    -- Only create tab if it doesn't exist
    if not private.frame.BPAucTab then
        local tab = CreateFrame("Button", "AuctionFrameTabUtilBigPicture", AuctionFrame, "AuctionTabTemplate")
        private.frame.BPAucTab = tab
        tab:SetText("BigPicture")
        tab:Show()

        -- Find first available tab index
        local nextID
        for i = 1, 32 do
            if not _G["AuctionFrameTab"..i] then
                nextID = i
                break
            end
        end

        -- Fallback if none found
        if not nextID then nextID = (AuctionFrame.numTabs and AuctionFrame.numTabs + 1) or 1 end
        tab:SetID(nextID)

        -- Update tab count
        if not AuctionFrame.numTabs or AuctionFrame.numTabs < nextID then
            AuctionFrame.numTabs = nextID
        end

        -- Sync with Blizzard functions safely
        if type(PanelTemplates_SetNumTabs) == "function" then
            pcall(PanelTemplates_SetNumTabs, AuctionFrame, nextID)
        end
        if type(PanelTemplates_DeselectTab) == "function" then
            pcall(PanelTemplates_DeselectTab, tab)
        elseif tab.SetNormalTexture then
            tab:SetNormalTexture(nil)
        end

        -- Register with AucAdvanced if available
        if AucAdvanced and type(AucAdvanced.AddTab) == "function" then
            AucAdvanced.AddTab(tab, private.frame)
        end
    end
end

-- Event-based initialization to ensure AuctionFrame exists
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "Blizzard_AuctionUI" then
        CreateBigPictureTab()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-- Also create tab on AH open just in case
f:RegisterEvent("AUCTION_HOUSE_SHOW")
f:SetScript("OnEvent", function(self, event, addonName)
    CreateBigPictureTab()
    if private.frame then
        private.frame:Show()
    end
end)


  -- Hook Auction House events to show/hide frame safely
if private.frame and not private.frame.eventHooked then
    local f = CreateFrame("Frame")
    f:RegisterEvent("AUCTION_HOUSE_SHOW")
    f:RegisterEvent("AUCTION_HOUSE_CLOSED")
    f:SetScript("OnEvent", function(_, event)
        if private.frame then
            if event == "AUCTION_HOUSE_SHOW" then
                private.frame:Show()
            elseif event == "AUCTION_HOUSE_CLOSED" then
                private.frame:Hide()
            end
        end
    end)
    private.frame.eventHooked = true
end


  -- Only proceed if AuctionFrame exists
if not AuctionFrame then return end

-- Fallback if no nextID found
if not nextID then
    nextID = (AuctionFrame.numTabs and AuctionFrame.numTabs + 1) or 1
end

tab:SetID(nextID)

-- Update AuctionFrame.numTabs safely
if not AuctionFrame.numTabs or AuctionFrame.numTabs < nextID then
    AuctionFrame.numTabs = nextID
end

-- Keep PanelTemplates in sync safely
if type(PanelTemplates_SetNumTabs) == "function" then
    pcall(PanelTemplates_SetNumTabs, AuctionFrame, nextID)
end

-- Deselect the tab safely
if type(PanelTemplates_DeselectTab) == "function" then
    pcall(PanelTemplates_DeselectTab, tab)
elseif tab.SetNormalTexture then
    tab:SetNormalTexture(nil)
end

-- Register tab with Auctioneer safely
if AucAdvanced and type(AucAdvanced.AddTab) == "function" then
    if private.frame then
        AucAdvanced.AddTab(tab, private.frame)
    end
end


local BPscriptframe = CreateFrame("Frame", "BigPictureEventFrame")
	BPscriptframe:RegisterEvent("PLAYER_MONEY")
	BPscriptframe:RegisterEvent("PLAYER_ENTERING_WORLD")
	BPscriptframe:RegisterEvent("GUILD_ROSTER_UPDATE")
	BPscriptframe:RegisterEvent("AUCTION_HOUSE_SHOW")
	BPscriptframe:RegisterEvent("BANKFRAME_OPENED")
	BPscriptframe:RegisterEvent("BANKFRAME_CLOSED")
	BPscriptframe:RegisterEvent("AUCTION_HOUSE_CLOSED")
	BPscriptframe:RegisterEvent("GUILDBANKFRAME_OPENED")
	BPscriptframe:RegisterEvent("GUILDBANKFRAME_CLOSED")
	BPscriptframe:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
	BPscriptframe:SetScript("OnEvent", private.BigPicture_Events)
 	SLASH_Big_Picture1 = "/bp"
	SLASH_Big_Picture2 = "/bigpicture"
	SlashCmdList["Big_Picture"] = private.StandAlone
 
 -- Titan Panel plugin registration
local TITAN_BIGPICTURE_ID = "BigPicture"

local function TitanBigPicture_OnLoad(self)
    self.registry = {
        id = TITAN_BIGPICTURE_ID,
        menuText = "BigPicture",
        buttonTextFunction = function() return "BP: "..(BPChar.BagsVal or 0).."g" end,
        tooltipTitle = "BigPicture",
        tooltipTextFunction = function()
            return "Bags: "..(BPChar.BagsVal or 0).."g\n"..
                   "Bank: "..(BPChar.BankVal or 0).."g\n"..
                   "Auction: "..(BPChar.AucBOVal or 0).."g"
        end,
        icon = "Interface\\Icons\\INV_Misc_Bag_08", -- example icon
        iconWidth = 16,
        category = "Information",
        savedVariables = {
            ShowIcon = true,
            ShowLabelText = true,
        },
    }
    TitanPanelButton_UpdateButton(self.registry.id)
end

-- Register Titan Panel plugin
if TitanPanelButton_UpdateButton then
    TitanPanelBigPictureButton = CreateFrame("Button", "TitanPanelBigPictureButton", UIParent, "TitanPanelComboTemplate")
    TitanBigPicture_OnLoad(TitanPanelBigPictureButton)
end
