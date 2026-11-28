local ADDON, ns = ...

local _, CLASS = UnitClass("player")

-- Class buffs: one slot per entry. An entry lists the spell's names (a later name is used when an
-- earlier one isn't known, e.g. a renamed rank). Spells are cast by name so the game always uses
-- your highest known rank. `exclusive` ties entries together that can't be up at the same time
-- (armors, aspects, blessings, shields): when any of them is on you, all of them count as active.
-- `ally` marks buffs that can be cast on other players: with a friendly target selected the button
-- reflects whether that target has the buff. `weapon` marks weapon imbues, which are tracked on the weapon instead of as an aura.
local CLASS_BUFFS = {
	WARRIOR = { { "Battle Shout" } },
	PRIEST = { { "Power Word: Fortitude", ally = true }, { "Divine Spirit", ally = true }, { "Shadow Protection", ally = true }, { "Inner Fire" } },
	MAGE = {
		{ "Arcane Intellect", ally = true },
		{ "Mage Armor", exclusive = "armor" },
		{ "Ice Armor", "Frost Armor", exclusive = "armor" },
	},
	DRUID = { { "Mark of the Wild", ally = true }, { "Thorns", ally = true }, { "Omen of Clarity" } },
	PALADIN = {
		{ "Blessing of Might", exclusive = "blessing", ally = true },
		{ "Blessing of Wisdom", exclusive = "blessing", ally = true },
		{ "Blessing of Kings", exclusive = "blessing", ally = true },
		{ "Blessing of Salvation", exclusive = "blessing", ally = true },
	},
	SHAMAN = {
		{ "Lightning Shield", "Water Shield", exclusive = "shield" },
		{ "Rockbiter Weapon", weapon = true },
		{ "Flametongue Weapon", weapon = true },
		{ "Frostbrand Weapon", weapon = true },
		{ "Windfury Weapon", weapon = true },
	},
	WARLOCK = {
		{ "Fel Armor", exclusive = "armor" },
		{ "Demon Armor", "Demon Skin", exclusive = "armor" },
		{ "Unending Breath", ally = true },
		-- the button creates a Soulstone, then uses the one in your bags; it is active while the
		-- Soulstone Resurrection buff you cast is on your target, on you, or on a party member
		{ "Create Soulstone", ally = true, soulstone = true, aura = "Soulstone Resurrection" },
	},
	HUNTER = {
		{ "Aspect of the Hawk", "Aspect of the Dragonhawk", exclusive = "aspect" },
		{ "Aspect of the Monkey", exclusive = "aspect" },
		{ "Aspect of the Cheetah", exclusive = "aspect" },
		{ "Aspect of the Pack", exclusive = "aspect" },
		{ "Aspect of the Beast", exclusive = "aspect" },
		{ "Aspect of the Wild", exclusive = "aspect" },
		{ "Aspect of the Viper", exclusive = "aspect" },
		{ "Trueshot Aura" },
	},
	ROGUE = {},
}

-- Soulstone items, weakest to strongest
local SOULSTONES = { 5232, 16892, 16893, 16895, 16896, 22116 }
local SOULSTONE_RANK = {}
for rank, id in ipairs(SOULSTONES) do SOULSTONE_RANK[id] = rank end
local soulstoneItem -- best Soulstone in the bags

-- every spell name in each exclusive group, for the player's class
local EXCLUSIVE_NAMES = {}
for _, entry in ipairs(CLASS_BUFFS[CLASS] or {}) do
	if entry.exclusive then
		local list = EXCLUSIVE_NAMES[entry.exclusive] or {}
		EXCLUSIVE_NAMES[entry.exclusive] = list
		for _, n in ipairs(entry) do list[#list + 1] = n end
	end
end
-- Tracking spells from professions and racials (Find Minerals/Herbs/Fish: Mining, Herbalism, Fishing;
-- Find Treasure: Dwarf). Each button counts as active only while its own tracking is on, so you can switch.
local TRACKING = {
	{ "Find Minerals" },
	{ "Find Herbs" },
	{ "Find Fish" },
	{ "Find Treasure" },
}
-- one slot per entry in the longest class list
local MAX_CLASS_SLOTS = 0
for _, list in pairs(CLASS_BUFFS) do MAX_CLASS_SLOTS = math.max(MAX_CLASS_SLOTS, #list) end

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

-- "Scroll of Protection" -> armor (the name uses a different word than the tooltip)
local SCROLL_NAME_STAT = { protection = "armor" }

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
	{ key = "tracking", label = "Tracking (Find Minerals, ...)" },
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
for i = 1, #TRACKING do SLOTS[#SLOTS + 1] = { key = "track" .. i, group = "tracking", label = TRACKING[i][1], spell = true } end

local CREATE_TINT = { 0.6, 0.45, 1 } -- same tint as ConsumableBar's Create Healthstone button
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
	scanTarget = true, -- check a friendly target for ally-castable buffs instead of yourself
	soulstoneParty = true, -- the Soulstone button also counts as active when a party member has your Soulstone
	activeMode = "DIM", -- a buff already on you: DIM (dim + time left), HIDE (hide its button), OFF (ignore)
	hiddenBuffs = {}, -- class buff family -> true when the player turned it off
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
local itemSlots = {} -- slot key -> { itemID=, aura= }, filled from the bags
local spellSlots = {} -- slot key -> { spellID=, spellName=, aura= }, filled from the spellbook
local misses = {} -- itemID -> failed tooltip reads
local analysis = {} -- itemID -> { cat=, rank=, aura= } (false when not a candidate)
local needsRetry = false
local editMode = false
local retries = 0

local function Movable() return editMode or not db.locked end

ns.GROUPS, ns.SLOTS, ns.DEFAULTS = GROUPS, SLOTS, DEFAULTS
ns.CLASS, ns.CLASS_BUFFS, ns.MAX_CLASS_SLOTS = CLASS, CLASS_BUFFS, MAX_CLASS_SLOTS

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
	elseif subclass == SUB_SCROLL or name:lower():find("^scroll of ") then
		-- stat and amount from the tooltip ("increases your armor by 300"), else from the name
		local stat, amount
		for s in pairs(SCROLL_SLOT) do
			amount = useText:match("increases[%a%s]-" .. s .. "[%a%s]- by (%d+)")
			if amount then
				stat = s
				break
			end
		end
		if not stat then
			local word = name:lower():match("^scroll of (%a+)")
			stat = word and (SCROLL_NAME_STAT[word] or word)
			amount = useText:match("by (%d+)")
		end
		if stat and SCROLL_SLOT[stat] then cat, rank = SCROLL_SLOT[stat], tonumber(amount) or itemRank end
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

	local result = { cat = cat, rank = rank, minLevel = minLevel or 0, aura = (GetItemSpell and GetItemSpell(id)) or name }
	analysis[id] = result
	return result
end

-- First spell of a family the player knows: spellID, name
local function FirstKnown(family)
	for _, spellName in ipairs(family) do
		local id = SpellIDByName(spellName)
		if id and SpellKnown(id) then return id, spellName end
	end
end

-- Bag contents -> one best item per category
local function ScanItems()
	needsRetry = false
	local best = {}
	local playerLevel = UnitLevel("player")
	local seen = {}
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, (NumSlots(bag) or 0) do
			local id = SlotItemID(bag, slot)
			if id and not seen[id] then
				seen[id] = true
				local info = Analyze(id)
				if info and info.minLevel <= playerLevel then
					local cur = best[info.cat]
					-- exact ties: stack size decides (smaller first unless set to LARGE)
					local better = not cur or info.rank > cur.rank
					if not better and info.rank == cur.rank then
						local n, curN = GetItemCount(id) or 0, GetItemCount(cur.id) or 0
						better = db.stackPref == "LARGE" and n > curN or db.stackPref ~= "LARGE" and n < curN
					end
					if better then best[info.cat] = { id = id, rank = info.rank, aura = info.aura } end
				end
			end
		end
	end
	soulstoneItem = nil
	for id, rank in pairs(SOULSTONE_RANK) do
		if (GetItemCount(id) or 0) > 0 and (not soulstoneItem or rank > SOULSTONE_RANK[soulstoneItem]) then soulstoneItem = id end
	end
	wipe(itemSlots)
	for cat, b in pairs(best) do itemSlots[cat] = { itemID = b.id, aura = b.aura } end
end

-- Spellbook -> class buffs and tracking spells the player knows
local function ScanSpells()
	wipe(spellSlots)
	for i, family in ipairs(CLASS_BUFFS[CLASS] or {}) do
		local id, name = FirstKnown(family)
		if id then
			spellSlots["class" .. i] = { spellID = id, spellName = name, aura = family.aura or name, familyKey = family[1],
				weapon = family.weapon, ally = family.ally, exclusive = family.exclusive, soulstone = family.soulstone }
		end
	end
	for i, family in ipairs(TRACKING) do
		local id, name = FirstKnown(family)
		if id then spellSlots["track" .. i] = { spellID = id, spellName = name, aura = name, familyKey = family[1] } end
	end
end

---------------------------------------------------------------------------
-- Active buff state
---------------------------------------------------------------------------
-- Auras are read once per unit per update pass (BeginPass) into name -> expiration, so checking
-- every button is a table lookup.
local passAuras, passTarget = {}, false

local function ReadAuras(unit)
	local t = {}
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for i = 1, 64 do
			local d = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
			if not d then break end
			if d.name and t[d.name] == nil then t[d.name] = d.expirationTime or 0 end
		end
	else
		for i = 1, 64 do
			local n, _, _, _, _, exp = UnitBuff(unit, i)
			if not n then break end
			if t[n] == nil then t[n] = exp or 0 end
		end
	end
	return t
end

local function BeginPass()
	passAuras = {}
	-- a friendly player (not you) is targeted: ally-castable buffs are checked on them
	passTarget = db.scanTarget and UnitExists("target") and UnitIsPlayer("target") and not UnitIsUnit("target", "player")
		and UnitCanAssist("player", "target") and not UnitIsDeadOrGhost("target") and true or false
end

-- Returns active, secondsLeft (nil for no timer)
local function AuraState(unit, name)
	local auras = passAuras[unit]
	if not auras then
		auras = ReadAuras(unit)
		passAuras[unit] = auras
	end
	local expires = auras[name]
	if expires == nil then return false end
	if expires > 0 then return true, expires - GetTime() end
	return true
end

-- Weapon imbues, oils, stones and poisons all share the weapon's one temporary enchant, so
-- they count as active once every weapon you could enchant already has one.
local function WeaponsBuffed()
	local hasMain, mainExp, _, _, hasOff, offExp = GetWeaponEnchantInfo()
	if not hasMain then return false end
	local dual = OffhandHasWeapon and OffhandHasWeapon()
	if dual and not hasOff then return false end
	local left = mainExp and mainExp / 1000
	if dual and offExp and (not left or offExp / 1000 < left) then left = offExp / 1000 end
	return true, left
end

-- Does a group member carry a Soulstone cast by you? Only looked at while in a group.
local function PartyHasMySoulstone(name)
	if not IsInGroup() then return false end
	local raid = IsInRaid()
	local prefix, count = raid and "raid" or "party", raid and GetNumGroupMembers() or GetNumSubgroupMembers()
	for i = 1, count do
		local unit = prefix .. i
		if UnitExists(unit) and not UnitIsUnit(unit, "player") then
			for j = 1, 64 do
				local n, src
				if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
					local d = C_UnitAuras.GetAuraDataByIndex(unit, j, "HELPFUL")
					if not d then break end
					n, src = d.name, d.sourceUnit
				else
					local caster
					n, _, _, _, _, _, caster = UnitBuff(unit, j)
					if not n then break end
					src = caster
				end
				if n == name and src and UnitIsUnit(src, "player") then return true end
			end
		end
	end
	return false
end

local function IsActive(b)
	if b.soulstone and db.soulstoneParty and PartyHasMySoulstone(b.aura) then return true end
	if b.key == "weaponBuff" or b.weaponImbue then return WeaponsBuffed() end
	if b.ally and passTarget then return AuraState("target", b.aura) end
	if b.exclusive then
		-- any member of the group being up counts for all of them
		for _, name in ipairs(EXCLUSIVE_NAMES[b.exclusive] or {}) do
			local active, left = AuraState("player", name)
			if active then return true, left end
		end
		return false
	end
	if not b.aura then return false end
	return AuraState("player", b.aura)
end

local function FormatTime(sec)
	if sec >= 3600 then return string.format("%dh", math.ceil(sec / 3600)) end
	if sec >= 60 then return string.format("%dm", math.ceil(sec / 60)) end
	return string.format("%d", math.max(sec, 0))
end

-- Sets b.active (never in combat; a failed read counts as inactive). Needs BeginPass first.
local function Evaluate(b)
	if db.activeMode == "OFF" or InCombatLockdown() or not (b.itemID or b.spellID) then
		b.active = false
		return false
	end
	local ok, active, remaining = pcall(IsActive, b)
	b.active = ok and active or false
	return b.active, remaining
end

-- The countdown text is the only thing that needs a timer. Gaining or losing a buff is
-- event driven, so the ticker only runs while a countdown is on screen, once a second.
local Layout, UpdateActiveStates -- defined below
local ticking = false
local function SyncTicker(need)
	if need and not ticking then
		ticking = true
		local acc = 0
		bar:SetScript("OnUpdate", function(_, elapsed)
			acc = acc + elapsed
			if acc < 1 then return end
			acc = 0
			UpdateActiveStates()
		end)
	elseif not need and ticking then
		ticking = false
		bar:SetScript("OnUpdate", nil)
	end
end

-- DIM mode: dims a buff that is already on you (or your target) and shows its time left.
-- Returns true while a countdown is shown. Other modes never dim.
local function ApplyActive(b)
	if InCombatLockdown() or not (b.itemID or b.spellID) then return false end
	if db.activeMode ~= "DIM" then
		b.icon:SetAlpha(1)
		b.timer:SetText("")
		return false
	end
	local active, remaining = Evaluate(b)
	b.icon:SetAlpha(active and 0.45 or 1)
	local showTime = active and remaining
	b.timer:SetText(showTime and FormatTime(remaining) or "")
	return showTime and true or false
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

local function UpdateCooldown(b)
	local start, duration
	if b.itemID then
		start, duration = GetItemCooldown(b.itemID)
	elseif b.spellID then
		start, duration = SpellCooldown(b.spellID)
	else
		return
	end
	if start and duration and duration > 0 then
		b.cooldown:SetCooldown(start, duration)
	else
		b.cooldown:Clear()
	end
end

-- Icon, count and cooldown (the active/dim state is ApplyActive's job)
local function UpdateButton(b)
	local id = b.itemID
	b.icon:SetVertexColor(1, 1, 1)
	if id then
		local _, _, _, _, icon = GetItemInfoInstant(id)
		b.icon:SetTexture(icon)
		local n = db.showCount and GetItemCount(id) or 0
		b.count:SetText(n > 1 and n or "")
	elseif b.spellID then
		b.icon:SetTexture(SpellTexture(b.spellID))
		b.count:SetText("")
		-- the Soulstone "create" button is tinted
		if b.soulstone then
			b.icon:SetDesaturated(true)
			b.icon:SetVertexColor(unpack(CREATE_TINT))
			b.icon:SetAlpha(1)
			UpdateCooldown(b)
			return
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
	b.icon:SetDesaturated(false)
	b.icon:SetAlpha(1)
	UpdateCooldown(b)
end
ns.UpdateButton = UpdateButton

-- What a click does. Items are used directly; weapon buffs also apply to the weapon (left click
-- main hand, right click off hand); class buffs go on a friendly target, otherwise on you.
local function SetClickAttributes(b)
	for _, a in ipairs({ "type", "item", "macrotext", "type2", "macrotext2" }) do b:SetAttribute(a, nil) end
	if b.itemID then
		if b.soulstone then
			b:SetAttribute("type", "macro")
			b:SetAttribute("macrotext", "/use [@target,help,nodead][@player] item:" .. b.itemID)
		elseif b.key == "weaponBuff" then
			b:SetAttribute("type", "macro")
			b:SetAttribute("macrotext", "/use item:" .. b.itemID .. "\n/use 16")
			b:SetAttribute("type2", "macro")
			b:SetAttribute("macrotext2", "/use item:" .. b.itemID .. "\n/use 17")
		else
			b:SetAttribute("type", "item")
			b:SetAttribute("item", "item:" .. b.itemID)
		end
	elseif b.spellName and b.weaponImbue then
		-- imbues go on your own weapon: left click main hand, right click off hand
		b:SetAttribute("type", "macro")
		b:SetAttribute("macrotext", "/cast " .. b.spellName)
		b:SetAttribute("type2", "macro")
		b:SetAttribute("macrotext2", "/cast " .. b.spellName .. "\n/use 17")
	elseif b.spellName then
		b:SetAttribute("type", "macro")
		b:SetAttribute("macrotext", "/cast [@target,help,nodead][@player] " .. b.spellName)
	end
end

-- Resizes, repositions and re-targets the secure buttons. Protected, so never in combat.
local needsLayout = false
local function SlotData(slot) return (slot.spell and spellSlots or itemSlots)[slot.key] end

function Layout()
	if InCombatLockdown() then
		needsLayout = true
		return
	end
	needsLayout = false
	BeginPass()

	local size, spacing = db.size, db.spacing
	bar:SetScale(db.scale)
	ApplyPosition()

	local shown, needTicker = 0, false
	local hideActive = db.activeMode == "HIDE" and not Movable()
	for _, slot in ipairs(SLOTS) do
		local b = buttons[slot.key]
		local s = SlotData(slot)
		b.itemID = s and s.itemID
		b.spellID = s and s.spellID
		b.spellName = s and s.spellName
		b.aura = s and s.aura
		b.weaponImbue = s and s.weapon
		b.exclusive = s and s.exclusive
		b.ally = s and s.ally
		b.soulstone = s and s.soulstone
		-- a Soulstone in the bags is used; without one the button creates it
		if b.soulstone and soulstoneItem then b.itemID = soulstoneItem; b.spellID = nil end
		-- HIDE mode: a buff that is already on you leaves the bar until it fades
		if s and hideActive then Evaluate(b) else b.active = false end
		-- class slots only ever appear when you know the spell
		local visible = db.show[slot.group]
			and (s or (not db.hideEmpty and not slot.spell))
			and not (slot.spell and s and db.hiddenBuffs[s.familyKey])
			and not b.active
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
			UpdateButton(b)
			if ApplyActive(b) then needTicker = true end
		else
			b:Hide()
			SetClickAttributes(b) -- a hidden button must not keep a stale action
		end
	end
	SyncTicker(needTicker)

	local n = math.max(shown, 1)
	bar:SetSize(n * size + (n - 1) * spacing, size)
	bar.overlay:SetShown(Movable())
	if not Movable() and ns.IsSelected() then ns.SetSelected(false) end
	bar:SetShown(shown > 0 or Movable())
end

-- Same buttons, fresh icons/counts/cooldowns/active state (no re-layout)
local function RefreshButtons()
	if InCombatLockdown() then return end
	BeginPass()
	local needTicker = false
	for _, slot in ipairs(SLOTS) do
		local b = buttons[slot.key]
		if b:IsShown() then
			UpdateButton(b)
			if ApplyActive(b) then needTicker = true end
		end
	end
	SyncTicker(needTicker)
end

-- What is on the bar, so an unchanged bar skips the re-layout
local lastSignature
local function Signature()
	local t = {}
	for i, slot in ipairs(SLOTS) do
		local s = SlotData(slot)
		t[i] = s and (s.itemID or s.spellID) or 0
		if s and s.soulstone then t[i] = t[i] .. ":" .. (soulstoneItem or 0) end
	end
	return table.concat(t, ",")
end

-- items / spells: which scans to redo
local function Refresh(items, spells)
	-- nothing touches bags, tooltips or auras in combat; PLAYER_REGEN_ENABLED re-runs this
	if InCombatLockdown() then return end
	if items then ScanItems() end
	if spells then ScanSpells() end
	local sig = Signature()
	if sig ~= lastSignature or needsLayout then
		lastSignature = sig
		Layout()
	else
		RefreshButtons()
	end
	if needsRetry and retries < 15 then
		retries = retries + 1
		C_Timer.After(1, function() ns.Refresh(true, false) end)
	elseif not needsRetry then
		retries = 0
	end
end

-- Debounced; no arguments rescans everything
local pending, pendingItems, pendingSpells
function ns.Refresh(items, spells)
	if not db or InCombatLockdown() then return end
	if items == nil and spells == nil then items, spells = true, true end
	pendingItems = pendingItems or items
	pendingSpells = pendingSpells or spells
	if pending then return end
	pending = true
	C_Timer.After(0.1, function()
		pending = false
		local i, sp = pendingItems, pendingSpells
		pendingItems, pendingSpells = nil, nil
		Refresh(i, sp)
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

-- Re-reads auras: dims buttons, or re-lays-out when buffs come and go in HIDE mode
function UpdateActiveStates()
	if not db or not bar or InCombatLockdown() then return end
	BeginPass()
	if db.activeMode == "HIDE" and not Movable() then
		local changed = false
		for _, slot in ipairs(SLOTS) do
			local b = buttons[slot.key]
			if b.itemID or b.spellID then
				local was = b.active and true or false
				Evaluate(b)
				if (b.active and true or false) ~= was then changed = true end
			end
		end
		if changed then Layout() end
		return
	end
	local needTicker = false
	for _, slot in ipairs(SLOTS) do
		local b = buttons[slot.key]
		if b:IsShown() and ApplyActive(b) then needTicker = true end
	end
	SyncTicker(needTicker)
end

-- Aura events come in bursts, so they are folded into one update
local activePending = false
function ns.UpdateAllActive()
	if activePending then return end
	activePending = true
	C_Timer.After(0.05, function()
		activePending = false
		UpdateActiveStates()
	end)
end

local function UpdateCooldowns()
	if InCombatLockdown() then return end
	for _, slot in ipairs(SLOTS) do
		local b = buttons[slot.key]
		if b:IsShown() then UpdateCooldown(b) end
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
		local s = SlotData(slot)
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
		if db.activeMode == nil and db.showActive == false then db.activeMode = "OFF" end
		db.showActive = nil
		CopyDefaults(db, DEFAULTS)
		events:UnregisterEvent("ADDON_LOADED")
		Build()
		-- pcall: an event this client doesn't know must not stop the rest registering
		for _, e in ipairs({
			"PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED",
			"GET_ITEM_INFO_RECEIVED", "BAG_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED",
			"BAG_UPDATE_DELAYED", -- fires once after any change to what is in the bags
			"UNIT_INVENTORY_CHANGED", -- weapon enchants
			"UNIT_AURA", "GROUP_ROSTER_UPDATE",
		}) do
			pcall(events.RegisterEvent, events, e)
		end
		if ns.BuildOptions then ns.BuildOptions() end
	elseif event == "UNIT_AURA" then
		if arg1 == "player" or (arg1 == "target" and db.scanTarget)
			or (db.soulstoneParty and CLASS == "WARLOCK" and (arg1:find("^party%d") or arg1:find("^raid%d"))) then
			ns.UpdateAllActive()
		end
	elseif event == "GROUP_ROSTER_UPDATE" then
		if db.soulstoneParty and CLASS == "WARLOCK" then ns.UpdateAllActive() end
	elseif event == "PLAYER_TARGET_CHANGED" then
		if db.scanTarget then ns.UpdateAllActive() end
	elseif event == "UNIT_INVENTORY_CHANGED" then
		if arg1 == "player" then ns.UpdateAllActive() end
	elseif event == "BAG_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" then
		UpdateCooldowns()
	elseif event == "BAG_UPDATE_DELAYED" then
		ns.Refresh(true, false)
	elseif event == "SPELLS_CHANGED" then
		ns.Refresh(false, true)
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		-- only matters while we are waiting on item data
		if needsRetry then ns.Refresh(true, false) end
	else
		-- login, level up, leaving combat: rescan everything
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
