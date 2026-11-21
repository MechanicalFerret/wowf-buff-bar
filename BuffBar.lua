local ADDON, ns = ...

local CLASS = select(2, UnitClass("player"))

-- Class buffs: one slot per family, each family lists alternative spells in priority order.
-- Spells are cast by name so the game always uses your highest known rank.
local CLASS_BUFFS = {
	WARRIOR = { { "Battle Shout" } },
	PRIEST = { { "Power Word: Fortitude" }, { "Divine Spirit" }, { "Shadow Protection" }, { "Inner Fire" } },
	MAGE = { { "Arcane Intellect" }, { "Mage Armor", "Ice Armor", "Frost Armor" } },
	DRUID = { { "Mark of the Wild" }, { "Thorns" }, { "Omen of Clarity" } },
	PALADIN = { { "Blessing of Might" }, { "Blessing of Wisdom" }, { "Blessing of Kings" }, { "Blessing of Salvation" } },
	SHAMAN = { { "Lightning Shield", "Water Shield" } },
	WARLOCK = { { "Fel Armor", "Demon Armor", "Demon Skin" }, { "Unending Breath" } },
	HUNTER = { { "Aspect of the Hawk", "Aspect of the Dragonhawk" }, { "Trueshot Aura" } },
	ROGUE = {},
}
local MAX_CLASS_SLOTS = 4

-- Scroll stat (as written in the tooltip) -> slot
local SCROLL_STATS = {
	{ key = "scrollAgility", stat = "agility", label = "Scroll of Agility" },
	{ key = "scrollIntellect", stat = "intellect", label = "Scroll of Intellect" },
	{ key = "scrollProtection", stat = "armor", label = "Scroll of Protection" },
	{ key = "scrollSpirit", stat = "spirit", label = "Scroll of Spirit" },
	{ key = "scrollStamina", stat = "stamina", label = "Scroll of Stamina" },
	{ key = "scrollStrength", stat = "strength", label = "Scroll of Strength" },
}
local SCROLL_SLOT = {}
for _, s in ipairs(SCROLL_STATS) do SCROLL_SLOT[s.stat] = s.key end

-- Settings groups (one checkbox each)
local GROUPS = {
	{ key = "class", label = "Class buffs" },
	{ key = "flask", label = "Flasks" },
	{ key = "battleElixir", label = "Battle elixirs" },
	{ key = "guardianElixir", label = "Guardian elixirs" },
	{ key = "scrolls", label = "Scrolls" },
	{ key = "weaponBuff", label = "Weapon buffs" },
	{ key = "buffPotion", label = "Buff potions" },
	{ key = "other", label = "Other buffs" },
}

-- Bar order. Item slots are filled from your bags, class slots from your spellbook.
local SLOTS = {}
for i = 1, MAX_CLASS_SLOTS do SLOTS[#SLOTS + 1] = { key = "class" .. i, group = "class", label = "Class buff", spell = true } end
SLOTS[#SLOTS + 1] = { key = "flask", group = "flask", label = "Flask" }
SLOTS[#SLOTS + 1] = { key = "battleElixir", group = "battleElixir", label = "Battle Elixir" }
SLOTS[#SLOTS + 1] = { key = "guardianElixir", group = "guardianElixir", label = "Guardian Elixir" }
for _, s in ipairs(SCROLL_STATS) do SLOTS[#SLOTS + 1] = { key = s.key, group = "scrolls", label = s.label } end
SLOTS[#SLOTS + 1] = { key = "weaponBuff", group = "weaponBuff", label = "Weapon buff" }
SLOTS[#SLOTS + 1] = { key = "buffPotion", group = "buffPotion", label = "Buff Potion" }
SLOTS[#SLOTS + 1] = { key = "other", group = "other", label = "Other buff" }

local EMPTY_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local DEFAULTS = {
	direction = "LTR", -- LTR: grows right, anchored on its left edge; RTL: grows left, anchored on its right edge
	size = 36,
	spacing = 4,
	scale = 1,
	locked = true,
	hideEmpty = true,
	showCount = true,
	showTooltip = true,
	showActive = true, -- dim a buff that is already on you and show its time left
	stackPref = "SMALL", -- tie between equal items: SMALL uses up the smaller stack first, LARGE the larger
	show = {},
	pos = { 0, -250 }, -- anchor edge: x, y from the screen centre, in UIParent units
}
for _, g in ipairs(GROUPS) do DEFAULTS.show[g.key] = true end

local CLASS_CONSUMABLE = 0
local SUB_ELIXIR, SUB_FLASK, SUB_SCROLL, SUB_POTION, SUB_FOOD, SUB_BANDAGE = 2, 3, 4, 1, 5, 7
local GUARDIAN_WORDS = { "armor", "stamina", "defense", "health", "resist", "regenerat", "mana every" }

local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
local GetItemCooldown = (C_Item and C_Item.GetItemCooldown) or GetItemCooldown
local GetItemSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
local NumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local function SlotItemID(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		local info = C_Container.GetContainerItemInfo(bag, slot)
		return info and info.itemID
	end
	return GetContainerItemID and GetContainerItemID(bag, slot)
end
local function SpellTexture(id)
	return (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or (GetSpellTexture and GetSpellTexture(id))
end
local function SpellIDByName(name)
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(name)
		return info and info.spellID
	end
	return select(7, GetSpellInfo(name))
end
local function SpellKnown(id)
	if IsPlayerSpell then return IsPlayerSpell(id) end
	return IsSpellKnown and IsSpellKnown(id)
end
local function SpellCooldown(id)
	if C_Spell and C_Spell.GetSpellCooldown then
		local info = C_Spell.GetSpellCooldown(id)
		if info then return info.startTime, info.duration end
		return
	end
	return GetSpellCooldown(id)
end

local db
local bar
local buttons = {}
local slots = {} -- slot key -> { itemID=, aura= } or { spellID=, spellName=, aura= }
local misses = {} -- itemID -> failed tooltip reads
local analysis = {} -- itemID -> { cat=, rank=, aura= } (false when not a candidate)
local needsRetry = false
local editMode = false
local retries = 0

local function Movable() return editMode or not db.locked end

ns.GROUPS, ns.SLOTS, ns.DEFAULTS = GROUPS, SLOTS, DEFAULTS

local function CopyDefaults(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			CopyDefaults(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

---------------------------------------------------------------------------
-- Item analysis (tooltip based)
---------------------------------------------------------------------------
local scanTip = CreateFrame("GameTooltip", "BuffBarScanTip", UIParent, "GameTooltipTemplate")

-- Works out which slot an item belongs to and how it ranks. Returns a table, false (not ours),
-- or false with needsRetry set when the client hasn't loaded the item yet.
local function Analyze(id)
	local cached = analysis[id]
	if cached ~= nil then return cached end

	local _, _, _, _, _, class, subclass = GetItemInfoInstant(id)
	if class == nil then
		needsRetry = true
		return false
	end
	if class ~= CLASS_CONSUMABLE or subclass == SUB_FOOD or subclass == SUB_BANDAGE then
		analysis[id] = false
		return false
	end

	-- the item cache can be cold at login; don't cache a result from a placeholder tooltip
	local name, _, _, ilvl, minLevel = GetItemInfo(id)
	if not name then
		needsRetry = true
		return false
	end

	scanTip:SetOwner(UIParent, "ANCHOR_NONE")
	scanTip:ClearLines()
	scanTip:SetHyperlink("item:" .. id)
	local lines = scanTip:NumLines()
	if lines == 0 then
		needsRetry = true
		return false
	end

	local use, all = {}, {}
	for i = 2, lines do
		local fs = _G["BuffBarScanTipTextLeft" .. i]
		local text = fs and fs:GetText()
		if text then
			text = text:lower()
			all[#all + 1] = text
			if text:find("^use:") then use[#use + 1] = text end
		end
	end
	local useText, allText = table.concat(use, " "), table.concat(all, " ")

	local cat, rank
	local itemRank = (ilvl or 0) + (minLevel or 0) / 1000
	if useText == "" then
		cat = nil
	elseif useText:find("restores") or useText:find("heals") then
		cat = nil -- health, mana and rejuvenation items belong to Consumable Bar
	elseif subclass == SUB_FLASK or name:lower():find("^flask") then
		cat, rank = "flask", itemRank
	elseif subclass == SUB_ELIXIR then
		if allText:find("battle elixir", 1, true) then
			cat = "battleElixir"
		elseif allText:find("guardian elixir", 1, true) then
			cat = "guardianElixir"
		else
			-- clients without the Battle/Guardian label: guess from what the elixir does
			cat = "battleElixir"
			for _, w in ipairs(GUARDIAN_WORDS) do
				if useText:find(w, 1, true) then
					cat = "guardianElixir"
					break
				end
			end
		end
		rank = itemRank
	elseif subclass == SUB_SCROLL then
		local stat, amount = useText:match("increases your (%a+) by (%d+)")
		if not stat then stat, amount = useText:match("increases (%a+) by (%d+)") end
		if stat and SCROLL_SLOT[stat] then cat, rank = SCROLL_SLOT[stat], tonumber(amount) end
	elseif useText:find("weapon", 1, true) then
		cat, rank = "weaponBuff", itemRank
	elseif subclass == SUB_POTION then
		cat, rank = "buffPotion", itemRank
	elseif useText:find("increases", 1, true) or useText:find("grants", 1, true) or useText:find("immune", 1, true) then
		cat, rank = "other", itemRank
	end

	if not cat then
		-- the tooltip may not be complete yet: only give up on the item after a few tries
		misses[id] = (misses[id] or 0) + 1
		if misses[id] < 4 then
			needsRetry = true
			return false
		end
		analysis[id] = false
		return false
	end

	local result = { cat = cat, rank = rank, aura = (GetItemSpell and GetItemSpell(id)) or name }
	analysis[id] = result
	return result
end

local function Scan()
	local best = {}
	local function consider(cat, id, value, aura)
		local cur = best[cat]
		-- exact ties: stack size decides (smaller first unless set to LARGE)
		local better = not cur or value > cur.value
		if not better and value == cur.value then
			local n, curN = GetItemCount(id) or 0, GetItemCount(cur.id) or 0
			better = db.stackPref == "LARGE" and n > curN or db.stackPref ~= "LARGE" and n < curN
		end
		if better then best[cat] = { id = id, value = value, aura = aura } end
	end

	local playerLevel = UnitLevel("player")
	local seen = {}
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, (NumSlots(bag) or 0) do
			local id = SlotItemID(bag, slot)
			if id and not seen[id] then
				seen[id] = true
				local info = Analyze(id)
				if info then
					local _, _, _, _, minLevel = GetItemInfo(id)
					if (minLevel or 0) <= playerLevel then consider(info.cat, id, info.rank, info.aura) end
				end
			end
		end
	end

	wipe(slots)
	for cat, b in pairs(best) do slots[cat] = { itemID = b.id, aura = b.aura } end

	for i, family in ipairs(CLASS_BUFFS[CLASS] or {}) do
		if i > MAX_CLASS_SLOTS then break end
		for _, spellName in ipairs(family) do
			local id = SpellIDByName(spellName)
			if id and SpellKnown(id) then
				slots["class" .. i] = { spellID = id, spellName = spellName, aura = spellName }
				break
			end
		end
	end
end

---------------------------------------------------------------------------
-- Active buff state
---------------------------------------------------------------------------
local function FindAura(name)
	if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
		local d = C_UnitAuras.GetAuraDataBySpellName("player", name, "HELPFUL")
		if d then return true, d.expirationTime end
		return false
	end
	if AuraUtil and AuraUtil.FindAuraByName then
		local n, _, _, _, _, exp = AuraUtil.FindAuraByName(name, "player", "HELPFUL")
		if n then return true, exp end
		return false
	end
	return false
end

-- Returns active, secondsLeft (nil for no timer)
local function IsActive(b)
	if b.key == "weaponBuff" then
		local hasMain, mainExp, _, _, hasOff, offExp = GetWeaponEnchantInfo()
		if hasMain then return true, mainExp and mainExp / 1000 end
		if hasOff then return true, offExp and offExp / 1000 end
		return false
	end
	if not b.aura then return false end
	local found, expires = FindAura(b.aura)
	if not found then return false end
	if expires and expires > 0 then return true, expires - GetTime() end
	return true
end

local function FormatTime(sec)
	if sec >= 3600 then return string.format("%dh", math.ceil(sec / 3600)) end
	if sec >= 60 then return string.format("%dm", math.ceil(sec / 60)) end
	return string.format("%d", math.max(sec, 0))
end

-- Dims a buff that is already on you and shows its time left. Never in combat.
local function UpdateActive(b)
	if InCombatLockdown() then return end
	if not (b.itemID or b.spellID) then return end
	local active, remaining = false, nil
	if db.showActive then active, remaining = IsActive(b) end
	b.icon:SetAlpha(active and 0.45 or 1)
	b.timer:SetText((active and remaining) and FormatTime(remaining) or "")
end

---------------------------------------------------------------------------
-- Bar
---------------------------------------------------------------------------
-- The bar is anchored by one edge (left when growing right, right when growing left)
-- so adding or removing buttons only extends the free side.
local function AnchorPoint() return db.direction == "RTL" and "RIGHT" or "LEFT" end

local function ApplyPosition()
	local x, y = db.pos[1], db.pos[2]
	local scale = bar:GetScale()
	bar:ClearAllPoints()
	bar:SetPoint(AnchorPoint(), UIParent, "CENTER", x / scale, y / scale)
end

-- Reads the anchor edge's current screen position into db.pos
local function CapturePosition()
	local edge = db.direction == "RTL" and bar:GetRight() or bar:GetLeft()
	local _, cy = bar:GetCenter()
	if not edge then return end
	local ratio = bar:GetEffectiveScale() / UIParent:GetEffectiveScale()
	db.pos = {
		edge * ratio - UIParent:GetWidth() / 2,
		cy * ratio - UIParent:GetHeight() / 2,
	}
end

local function SavePosition()
	CapturePosition()
	ApplyPosition()
end

local function CreateButton(slot)
	local b = CreateFrame("Button", "BuffBarButton" .. slot.key, bar, "SecureActionButtonTemplate")
	b.key, b.slot = slot.key, slot
	b:RegisterForClicks("AnyUp", "AnyDown")

	b.icon = b:CreateTexture(nil, "BACKGROUND")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	b.count:SetPoint("BOTTOMRIGHT", -2, 2)
	b.timer = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	b.timer:SetPoint("TOP", 0, -3)

	b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cooldown:SetAllPoints()

	-- same border, pressed and hover textures as the stock action buttons
	b:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
	b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:GetPushedTexture():SetAllPoints()

	b:SetScript("OnEnter", function(self)
		if not db.showTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		if self.itemID then
			GameTooltip:SetHyperlink("item:" .. self.itemID)
		elseif self.spellID then
			GameTooltip:SetSpellByID(self.spellID)
		else
			GameTooltip:SetText(self.slot.label)
			GameTooltip:AddLine("None in your bags.", 0.7, 0.7, 0.7)
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Using a bar item or ability in combat is the one thing allowed to update the bar.
	-- Protected so a restricted cooldown or count value can never raise an error.
	b:HookScript("PostClick", function(self)
		if InCombatLockdown() then
			C_Timer.After(0.2, function() pcall(ns.UpdateButton, self) end)
		end
	end)
	return b
end

local function UpdateButton(b)
	local id = b.itemID
	if id then
		local _, _, _, _, icon = GetItemInfoInstant(id)
		b.icon:SetTexture(icon)
		b.icon:SetDesaturated(false)
		b.icon:SetAlpha(1)
		local n = GetItemCount(id) or 0
		b.count:SetText((db.showCount and n > 1) and n or "")
		local start, duration = GetItemCooldown(id)
		if start and duration and duration > 0 then
			b.cooldown:SetCooldown(start, duration)
		else
			b.cooldown:Clear()
		end
	elseif b.spellID then
		b.icon:SetTexture(SpellTexture(b.spellID))
		b.icon:SetDesaturated(false)
		b.icon:SetAlpha(1)
		b.count:SetText("")
		local start, duration = SpellCooldown(b.spellID)
		if start and duration and duration > 0 then
			b.cooldown:SetCooldown(start, duration)
		else
			b.cooldown:Clear()
		end
	else
		b.icon:SetTexture(EMPTY_ICON)
		b.icon:SetDesaturated(true)
		b.icon:SetAlpha(0.4)
		b.count:SetText("")
		b.timer:SetText("")
		b.cooldown:Clear()
		return
	end
	pcall(UpdateActive, b)
end
ns.UpdateButton = UpdateButton

-- What a click does. Items are used directly; weapon buffs also apply to the weapon (left click
-- main hand, right click off hand); class buffs go on a friendly target, otherwise on you.
local function SetClickAttributes(b)
	for _, a in ipairs({ "type", "item", "macrotext", "type2", "macrotext2" }) do b:SetAttribute(a, nil) end
	if b.itemID then
		if b.key == "weaponBuff" then
			b:SetAttribute("type", "macro")
			b:SetAttribute("macrotext", "/use item:" .. b.itemID .. "\n/use 16")
			b:SetAttribute("type2", "macro")
			b:SetAttribute("macrotext2", "/use item:" .. b.itemID .. "\n/use 17")
		else
			b:SetAttribute("type", "item")
			b:SetAttribute("item", "item:" .. b.itemID)
		end
	elseif b.spellName then
		b:SetAttribute("type", "macro")
		b:SetAttribute("macrotext", "/cast [@target,help,nodead][@player] " .. b.spellName)
	end
end

-- Resizes, repositions and re-targets the secure buttons. Protected, so never in combat.
local needsLayout = false
local function Layout()
	if InCombatLockdown() then
		needsLayout = true
		return
	end
	needsLayout = false

	local size, spacing = db.size, db.spacing
	bar:SetScale(db.scale)
	ApplyPosition()

	local shown = 0
	for _, slot in ipairs(SLOTS) do
		local b = buttons[slot.key]
		local s = slots[slot.key]
		b.itemID = s and s.itemID
		b.spellID = s and s.spellID
		b.spellName = s and s.spellName
		b.aura = s and s.aura
		-- class slots only ever appear when you know the spell
		local visible = db.show[slot.group] and (s or (not db.hideEmpty and not slot.spell))
		if visible then
			local offset = shown * (size + spacing)
			b:ClearAllPoints()
			if db.direction == "RTL" then
				b:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -offset, 0)
			else
				b:SetPoint("TOPLEFT", bar, "TOPLEFT", offset, 0)
			end
			b:SetSize(size, size)
			local border = b:GetNormalTexture()
			border:ClearAllPoints()
			border:SetPoint("CENTER", 0, -size / 36)
			border:SetSize(size * 64 / 36, size * 64 / 36)
			SetClickAttributes(b)
			b:Show()
			shown = shown + 1
		else
			b:Hide()
			SetClickAttributes(b)
		end
		UpdateButton(b)
	end

	local n = math.max(shown, 1)
	bar:SetSize(n * size + (n - 1) * spacing, size)
	bar.overlay:SetShown(Movable())
	if not Movable() and ns.IsSelected() then ns.SetSelected(false) end
	bar:SetShown(shown > 0 or Movable())
end

local function Refresh()
	-- nothing touches bags, tooltips or auras in combat; PLAYER_REGEN_ENABLED re-runs this
	if InCombatLockdown() then return end
	needsRetry = false
	Scan()
	Layout()
	if needsRetry and retries < 15 then
		retries = retries + 1
		C_Timer.After(1, ns.Refresh)
	elseif not needsRetry then
		retries = 0
	end
end

local pending
function ns.Refresh()
	if not db or InCombatLockdown() then return end
	if pending then return end
	pending = true
	C_Timer.After(0.1, function()
		pending = nil
		Refresh()
	end)
end

-- Settings changes: re-layout only, items stay the same
function ns.ApplySettings()
	if db then Layout() end
end

function ns.GetDB() return db end

-- Switches the growth direction without moving the bar on screen
function ns.SetDirection(dir)
	if db.direction == dir then return end
	if InCombatLockdown() then
		print("Buff Bar: can't change direction in combat.")
		return
	end
	db.direction = dir
	CapturePosition()
	Layout()
end

function ns.ResetPosition()
	db.pos = { DEFAULTS.pos[1], DEFAULTS.pos[2] }
	if bar then ApplyPosition() end
end

function ns.SetLocked(locked)
	db.locked = locked and true or false
	Layout()
end

local function UpdateCooldowns()
	if InCombatLockdown() then return end
	for _, slot in ipairs(SLOTS) do
		local b = buttons[slot.key]
		if b:IsShown() then UpdateButton(b) end
	end
end

-- Edit Mode style highlight: blue when available, gold when selected (opens the settings dialog)
local selected, ignoreClear = false, false

function ns.IsSelected() return selected end

function ns.SetSelected(sel)
	selected = sel and true or false
	local o = bar.overlay
	local r, g, b = 0.4, 0.7, 1
	if selected then r, g, b = 1, 0.82, 0 end
	o.fill:SetColorTexture(0.25, 0.55, 1, selected and 0.45 or 0.3)
	for _, e in ipairs(o.edges) do e:SetColorTexture(r, g, b, 1) end
	if selected then
		if EditModeManagerFrame and EditModeManagerFrame.ClearSelectedSystem then
			ignoreClear = true
			pcall(EditModeManagerFrame.ClearSelectedSystem, EditModeManagerFrame)
			ignoreClear = false
		end
		if ns.ShowEditDialog then ns.ShowEditDialog(bar) end
	elseif ns.HideEditDialog then
		ns.HideEditDialog()
	end
end

local function Build()
	bar = CreateFrame("Frame", "BuffBarFrame", UIParent)
	bar:SetMovable(true)
	bar:SetClampedToScreen(true)
	bar:SetFrameStrata("MEDIUM")

	-- Covers the buttons while the bar is movable so dragging never uses an item
	local o = CreateFrame("Frame", nil, bar)
	o:SetPoint("TOPLEFT", -3, 3)
	o:SetPoint("BOTTOMRIGHT", 3, -3)
	o:SetFrameLevel(bar:GetFrameLevel() + 20)
	o:EnableMouse(true)
	o:RegisterForDrag("LeftButton")
	o:Hide()
	o.fill = o:CreateTexture(nil, "OVERLAY")
	o.fill:SetAllPoints()
	o.edges = {}
	for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
		{ "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local e = o:CreateTexture(nil, "OVERLAY")
		e:SetPoint(p[1])
		e:SetPoint(p[2])
		if p[3] then e:SetHeight(2) else e:SetWidth(2) end
		o.edges[i] = e
	end
	local label = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("CENTER")
	label:SetText("Buff Bar")
	o:SetScript("OnMouseDown", function() ns.SetSelected(true) end)
	o:SetScript("OnDragStart", function()
		ns.SetSelected(true)
		if not InCombatLockdown() then bar:StartMoving() end
	end)
	o:SetScript("OnDragStop", function()
		bar:StopMovingOrSizing()
		if not InCombatLockdown() then SavePosition() end
	end)
	bar.overlay = o
	ns.SetSelected(false)

	for _, slot in ipairs(SLOTS) do buttons[slot.key] = CreateButton(slot) end
	ApplyPosition()

	-- time left on active buffs
	local acc = 0
	bar:SetScript("OnUpdate", function(_, elapsed)
		acc = acc + elapsed
		if acc < 0.5 then return end
		acc = 0
		if InCombatLockdown() then return end
		for _, slot in ipairs(SLOTS) do
			local b = buttons[slot.key]
			if b:IsShown() then pcall(UpdateActive, b) end
		end
	end)

	-- Show the drag overlay whenever the game's Edit Mode is open
	if EditModeManagerFrame then
		local function sync(active)
			editMode = active
			Layout()
		end
		hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function() sync(true) end)
		hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function() sync(false) end)
		if EditModeManagerFrame.ClearSelectedSystem then
			-- another Edit Mode element was picked
			hooksecurefunc(EditModeManagerFrame, "ClearSelectedSystem", function()
				if selected and not ignoreClear then ns.SetSelected(false) end
			end)
		end
		if EditModeManagerFrame.IsEditModeActive and EditModeManagerFrame:IsEditModeActive() then editMode = true end
	end
end

function ns.Debug()
	local function p(...) print("|cff33ff99BBar:|r", ...) end
	p("retry pending:", tostring(needsRetry), "retries:", retries, "level:", UnitLevel("player"), "class:", tostring(CLASS))
	for _, slot in ipairs(SLOTS) do
		local s = slots[slot.key]
		if s then
			p(slot.key, "->", s.itemID and ("item " .. s.itemID) or ("spell " .. tostring(s.spellName)), "aura:", tostring(s.aura))
		end
	end
	local seen = {}
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, (NumSlots(bag) or 0) do
			local id = SlotItemID(bag, slot)
			if id and not seen[id] then
				seen[id] = true
				local _, _, _, _, _, class, sub = GetItemInfoInstant(id)
				if class == CLASS_CONSUMABLE or class == nil then
					local a = analysis[id]
					local r = a == nil and "NOT ANALYSED" or (a == false and "rejected" or
						string.format("cat=%s rank=%s aura=%s", tostring(a.cat), tostring(a.rank), tostring(a.aura)))
					local name, _, _, ilvl, minLevel = GetItemInfo(id)
					p(id, name or "(name not loaded)", "class", tostring(class), "sub", tostring(sub), "ilvl", tostring(ilvl),
						"minLvl", tostring(minLevel), r, "misses", misses[id] or 0)
				end
			end
		end
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		BuffBarDB = BuffBarDB or {}
		db = BuffBarDB
		CopyDefaults(db, DEFAULTS)
		events:UnregisterEvent("ADDON_LOADED")
		Build()
		-- pcall: an event this client doesn't know must not stop the rest registering
		for _, e in ipairs({
			"PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED",
			"GET_ITEM_INFO_RECEIVED", "BAG_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED",
			-- any way an item can arrive, leave or move
			"BAG_UPDATE", "BAG_UPDATE_DELAYED", "ITEM_PUSH", "BAG_NEW_ITEMS_UPDATED",
			"UNIT_INVENTORY_CHANGED", "ITEM_LOCK_CHANGED",
		}) do
			pcall(events.RegisterEvent, events, e)
		end
		if ns.BuildOptions then ns.BuildOptions() end
	elseif event == "UNIT_INVENTORY_CHANGED" and arg1 ~= "player" then
		return
	elseif event == "BAG_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" then
		UpdateCooldowns()
	elseif event == "PLAYER_REGEN_ENABLED" then
		ns.Refresh()
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		-- only matters while we are waiting on item data
		if needsRetry then ns.Refresh() end
	else
		if event == "PLAYER_ENTERING_WORLD" then
			-- bags and item data can still be filling in right after login
			C_Timer.After(3, ns.Refresh)
		end
		ns.Refresh()
	end
end)

SLASH_BUFFBAR1 = "/bbar"
SLASH_BUFFBAR2 = "/buffbar"
SlashCmdList.BUFFBAR = function(input)
	if not db then return end
	input = (input or ""):lower():match("^%s*(.-)%s*$")
	if input == "lock" then
		ns.SetLocked(true)
	elseif input == "unlock" then
		ns.SetLocked(false)
	elseif input == "debug" then
		ns.Debug()
	elseif input == "reset" then
		ns.ResetPosition()
	elseif ns.OpenOptions then
		ns.OpenOptions()
	end
end
