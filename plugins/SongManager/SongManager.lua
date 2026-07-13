--[[
	Song Manager  --  grandMA3 Lua Plugin
	--------------------------------------

	Per-song control over show elements: sequences, macros, executor pages,
	timecodes, and any other pool you want to manage (presets, groups,
	filters, effects, ...). Each song gets its own block of pool numbers,
	its own executor page and bump buttons, a BPM reference, and a
	template view that is kept scrolled to that song's objects.

	INSTALL
	  1. In grandMA3: Pool > Plugins > right click an empty slot > "Store Plugin".
	  2. Right click the new plugin > "Edit" and paste this entire file in.
	  3. Assign the plugin to an executor / macro button and press it to open
	     the menu.

	SYNTAX ASSUMPTIONS - PLEASE VERIFY ON YOUR CONSOLE
	  A handful of command-line templates below are the most likely correct
	  syntax for grandMA3 but were written without access to a live console
	  to test against, and different software versions have changed some
	  command names over time. They are all collected in COMMANDS below so
	  they're easy to find and adjust in one place if something doesn't
	  behave the way you expect:
	    - COMMANDS.loadView    ("Load View n")       - recalls a view onto a display
	    - COMMANDS.revealPool  ("SelectDrag ...")     - scrolls an open pool window
	    - COMMANDS.speedMasterAt ("SpeedMaster n At bpm") - sets a Speed Master's BPM
	  Everything else (Store / Label / Delete / Assign .. At Executor / Page /
	  Store View .. /o) is standard, well documented grandMA3 command syntax.

	  Two more assumptions, not command syntax but still worth a look: Set
	  List auto-advance passes seconds*1000 to Timer() assuming its delay is
	  in milliseconds, and tap tempo assumes Time() returns milliseconds.

	Version 1.0
]]

-- ===================================================================
-- CONFIG: centralised command templates (see note above)
-- ===================================================================

local COMMANDS = {
	loadView       = 'Load View %d',
	revealPool     = 'SelectDrag %s',
	speedMasterAt  = 'SpeedMaster %d At %s',
}

local DB_VAR = "SongManagerDB"
local MYVIEWS_VAR = "SongManagerMyViews"
local LASTTAP_VAR = "SongManagerLastTap"

-- ===================================================================
-- Small utilities
-- ===================================================================

local function sanitize(str)
	str = tostring(str or "")
	return (str:gsub('"', "'"))
end

local function trim(str)
	return (tostring(str or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function isBlank(str)
	return str == nil or trim(str) == ""
end

local function round(n)
	return math.floor(n + 0.5)
end

-- ===================================================================
-- Serialization (plain Lua table <-> string, stored inside a variable)
-- ===================================================================

local serializeValue

local function serializeTable(tbl)
	local isArray = true
	local n = 0
	for k, _ in pairs(tbl) do
		n = n + 1
		if type(k) ~= "number" then isArray = false end
	end
	local parts = {}
	if isArray and n == #tbl then
		for _, v in ipairs(tbl) do
			parts[#parts + 1] = serializeValue(v)
		end
	else
		for k, v in pairs(tbl) do
			local key
			if type(k) == "string" then
				key = "[" .. string.format("%q", k) .. "]"
			else
				key = "[" .. tostring(k) .. "]"
			end
			parts[#parts + 1] = key .. "=" .. serializeValue(v)
		end
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

serializeValue = function(v)
	local t = type(v)
	if t == "string" then
		return string.format("%q", v)
	elseif t == "number" or t == "boolean" then
		return tostring(v)
	elseif t == "table" then
		return serializeTable(v)
	end
	return "nil"
end

local function deserialize(str)
	if isBlank(str) then return nil end
	local chunk = load("return " .. str)
	if not chunk then return nil end
	local ok, result = pcall(chunk)
	if ok then return result end
	return nil
end

-- ===================================================================
-- Default data model
-- ===================================================================

local function defaultSettings()
	return {
		templateViews = { { view = 173, scope = "global" } },
		poolTypes = {
			{ key = "sequence", label = "Sequence",  class = "Sequence", enabled = true,  start = 1,   block = 1, builtin = true },
			{ key = "macro",    label = "Macro",     class = "Macro",    enabled = true,  start = 101, block = 5, builtin = true },
			{ key = "page",     label = "Page",      class = "Page",     enabled = true,  start = 1,   block = 1, builtin = true },
			{ key = "timecode", label = "TimeCode",  class = "TimeCode", enabled = true,  start = 1,   block = 1, builtin = true },
		},
		executor = { start = 101, block = 1, bumpKey = "sequence" },
		bpmRef = {
			executor = 100,
			speedMasterNum = 1,
			multipliers = { 0.125, 0.25, 0.5, 1, 2, 4, 8 },
		},
		setList = { enabled = false, sequenceNum = 200, gap = 0 },
		clearProgrammerBeforeStore = true,
		initialized = false,
	}
end

local function defaultDB()
	return {
		version = 1,
		settings = defaultSettings(),
		songs = {},
		currentSongId = nil,
		nextId = 1,
	}
end

-- ===================================================================
-- Persistence
-- ===================================================================

local DB = nil

local function loadDB()
	local raw = GetVar(GlobalVars(), DB_VAR)
	local tbl = deserialize(raw)
	if type(tbl) == "table" and tbl.settings and tbl.songs then
		return tbl
	end
	return defaultDB()
end

local function saveDB()
	SetVar(GlobalVars(), DB_VAR, serializeTable(DB))
end

-- ===================================================================
-- UI helpers
-- ===================================================================

local function menu(title, items)
	if #items == 0 then return nil, nil end
	local popTable = { title = title, items = {} }
	for _, label in ipairs(items) do
		table.insert(popTable.items, { "str", label })
	end
	local idx, val = PopupInput(popTable)
	if not idx or idx == 0 then return nil, nil end
	return idx, val
end

local function ask(title, default)
	local v = TextInput(title, default ~= nil and tostring(default) or "")
	if v == nil then return nil end
	return v
end

local function askNumber(title, default)
	local v = ask(title, default)
	if v == nil then return nil end
	local n = tonumber(v)
	return n
end

local function confirm(title, message)
	return Confirm(title, message, nil, true) == true
end

local function info(title, message)
	Confirm(title, message, nil, false)
end

-- ===================================================================
-- Command execution helpers
-- ===================================================================

local function runCmd(str)
	local result = Cmd(str)
	if result ~= "Ok" then
		ErrPrintf(string.format("SongManager: '%s' -> %s", str, tostring(result)))
	end
	return result
end

local function findPoolType(key)
	for _, pt in ipairs(DB.settings.poolTypes) do
		if pt.key == key then return pt end
	end
	return nil
end

local function poolTarget(pt, num)
	if pt.poolId then
		return pt.class .. " " .. tostring(pt.poolId) .. "." .. tostring(num)
	end
	return pt.class .. " " .. tostring(num)
end

local function storeAndLabel(target, name)
	if DB.settings.clearProgrammerBeforeStore then
		runCmd("ClearAll")
	end
	runCmd("Store " .. target .. " /o")
	runCmd('Label ' .. target .. ' "' .. sanitize(name) .. '"')
end

local function deleteTarget(target)
	runCmd("Delete " .. target)
end

-- ===================================================================
-- Pool number / executor allocation
-- ===================================================================

local function allocatePoolNumber(pt)
	pt.next = pt.next or pt.start
	local num = pt.next
	pt.next = pt.next + pt.block
	return num
end

local function allocateExecutor()
	local ex = DB.settings.executor
	ex.next = ex.next or ex.start
	local num = ex.next
	ex.next = ex.next + ex.block
	return num
end

-- ===================================================================
-- Song build / teardown
-- ===================================================================

local function buildSong(song)
	local undo = CreateUndo("Song Manager: Build " .. song.shortName)
	for _, pt in ipairs(DB.settings.poolTypes) do
		if pt.enabled and song.pools[pt.key] then
			storeAndLabel(poolTarget(pt, song.pools[pt.key]), song.shortName)
		end
	end
	if song.executor and DB.settings.executor.bumpKey then
		local bumpPt = findPoolType(DB.settings.executor.bumpKey)
		if bumpPt and song.pools[bumpPt.key] then
			runCmd("Assign " .. poolTarget(bumpPt, song.pools[bumpPt.key]) .. " At Executor " .. song.executor)
		end
	end
	if undo then CloseUndo(undo) end
end

local function deleteSongObjects(song)
	for _, pt in ipairs(DB.settings.poolTypes) do
		local num = song.pools[pt.key]
		if num then
			deleteTarget(poolTarget(pt, num))
		end
	end
	if song.executor then
		runCmd("Delete Executor " .. song.executor)
	end
end

-- ===================================================================
-- Views
-- ===================================================================

local function getActiveTemplateViews()
	local views = {}
	for _, tv in ipairs(DB.settings.templateViews) do
		table.insert(views, tv.view)
	end
	local myViewsRaw = GetVar(UserVars(), MYVIEWS_VAR)
	if not isBlank(myViewsRaw) then
		for numStr in tostring(myViewsRaw):gmatch("%d+") do
			table.insert(views, tonumber(numStr))
		end
	end
	return views
end

local function refreshTemplateViews(song)
	for _, pt in ipairs(DB.settings.poolTypes) do
		if pt.enabled and song.pools[pt.key] then
			runCmd(string.format(COMMANDS.revealPool, poolTarget(pt, song.pools[pt.key])))
		end
	end
	for _, viewNum in ipairs(getActiveTemplateViews()) do
		runCmd("Store View " .. viewNum .. " /o")
	end
end

local function loadTemplateViewOnThisDisplay()
	local views = getActiveTemplateViews()
	if #views == 0 then
		info("Song Manager", "No template views configured.")
		return
	end
	local labels = {}
	for _, v in ipairs(views) do table.insert(labels, "View " .. v) end
	local idx = menu("Load Template View", labels)
	if not idx then return end
	runCmd(string.format(COMMANDS.loadView, views[idx]))
end

-- ===================================================================
-- BPM reference
-- ===================================================================

local function ensureBpmRefObjects()
	local ref = DB.settings.bpmRef
	runCmd("Store SpeedMaster " .. ref.speedMasterNum .. " /o")
	runCmd("Assign SpeedMaster " .. ref.speedMasterNum .. " At Executor " .. ref.executor)
end

local function applyBPM(baseBpm, multiplier)
	local ref = DB.settings.bpmRef
	local value = baseBpm * multiplier
	runCmd(string.format(COMMANDS.speedMasterAt, ref.speedMasterNum, string.format("%.2f", value)))
	return value
end

local function multiplierLabel(m)
	if m == 0.125 then return "x 1/8" end
	if m == 0.25 then return "x 1/4" end
	if m == 0.5 then return "x 1/2" end
	return "x " .. tostring(m)
end

local function tapTempo()
	local now = Time()
	local last = tonumber(GetVar(UserVars(), LASTTAP_VAR))
	SetVar(UserVars(), LASTTAP_VAR, tostring(now))
	if last and now > last then
		local deltaMs = now - last
		if deltaMs > 200 and deltaMs < 3000 then
			return round(60000 / deltaMs)
		end
	end
	return nil
end

local function currentSong()
	if not DB.currentSongId then return nil end
	for _, s in ipairs(DB.songs) do
		if s.id == DB.currentSongId then return s end
	end
	return nil
end

local function bpmReferenceMenu()
	ensureBpmRefObjects()
	while true do
		local song = currentSong()
		local baseLabel = song and (song.shortName .. " (" .. tostring(song.bpm) .. " BPM)") or "no active song"
		local items = { "Active song: " .. baseLabel }
		local ref = DB.settings.bpmRef
		for _, m in ipairs(ref.multipliers) do
			table.insert(items, multiplierLabel(m))
		end
		table.insert(items, "Tap Tempo")
		table.insert(items, "Enter BPM Manually")
		table.insert(items, "Back")
		local idx, val = menu("BPM Reference", items)
		if not idx or val == "Back" then return end
		if val == "Tap Tempo" then
			local bpm = tapTempo()
			if bpm then
				runCmd(string.format(COMMANDS.speedMasterAt, ref.speedMasterNum, tostring(bpm)))
				info("Tap Tempo", "BPM: " .. tostring(bpm))
			end
		elseif val == "Enter BPM Manually" then
			local bpm = askNumber("Enter BPM", song and song.bpm or 120)
			if bpm then
				runCmd(string.format(COMMANDS.speedMasterAt, ref.speedMasterNum, string.format("%.2f", bpm)))
			end
		elseif idx >= 2 and idx <= 1 + #ref.multipliers then
			local m = ref.multipliers[idx - 1]
			local base = song and song.bpm or askNumber("Base BPM", 120)
			if base then
				local value = applyBPM(base, m)
				info("BPM Reference", string.format("%s -> %.2f BPM", multiplierLabel(m), value))
			end
		end
	end
end

-- ===================================================================
-- Set List (auto-advance)
-- ===================================================================

local function songIndexById(id)
	for i, s in ipairs(DB.songs) do
		if s.id == id then return i end
	end
	return nil
end

local gotoSong -- forward declaration

local function scheduleAutoAdvance(song)
	if not DB.settings.setList.enabled then return end
	local gap = song.gap or DB.settings.setList.gap or 0
	if gap <= 0 then return end
	Timer(function()
		local idx = songIndexById(song.id)
		if idx and DB.songs[idx + 1] then
			gotoSong(DB.songs[idx + 1].id)
		end
	end, gap * 1000, 1)
end

-- ===================================================================
-- Song activation
-- ===================================================================

gotoSong = function(id)
	local song
	for _, s in ipairs(DB.songs) do
		if s.id == id then song = s break end
	end
	if not song then return end

	DB.currentSongId = song.id
	saveDB()

	local pagePt = findPoolType("page")
	if pagePt and pagePt.enabled and song.pools.page then
		runCmd("Page " .. song.pools.page)
	end

	refreshTemplateViews(song)
	ensureBpmRefObjects()
	applyBPM(song.bpm, 1)

	if DB.settings.setList.enabled and song.startMacro then
		runCmd("Go+ Macro " .. song.startMacro)
	end

	scheduleAutoAdvance(song)

	Printf(string.format("SongManager: now playing '%s' (%d BPM)", song.shortName, song.bpm))
end

-- ===================================================================
-- Song CRUD
-- ===================================================================

local function allocateSongPools()
	local pools = {}
	for _, pt in ipairs(DB.settings.poolTypes) do
		if pt.enabled then
			pools[pt.key] = allocatePoolNumber(pt)
		end
	end
	return pools
end

local function addSongWizard()
	local shortName = ask("Song Short Name", "")
	if isBlank(shortName) then return end
	local fullName = ask("Full Song Name (optional)", shortName)
	if fullName == nil then fullName = shortName end
	if isBlank(fullName) then fullName = shortName end
	local bpm = askNumber("BPM", 120)
	if not bpm then return end

	local song = {
		id = DB.nextId,
		shortName = trim(shortName),
		name = trim(fullName),
		bpm = bpm,
		pools = {},
		notes = "",
		gap = 0,
		startMacro = nil,
	}
	DB.nextId = DB.nextId + 1

	local useAuto = confirm("Pool Numbers", "Use auto-assigned pool numbers for this song?")
	if useAuto then
		song.pools = allocateSongPools()
	else
		for _, pt in ipairs(DB.settings.poolTypes) do
			if pt.enabled then
				local suggested = pt.next or pt.start
				local n = askNumber(pt.label .. " Number", suggested)
				if n then
					song.pools[pt.key] = round(n)
					if pt.next == nil or n >= pt.next then
						pt.next = round(n) + pt.block
					end
				end
			end
		end
	end
	song.executor = allocateExecutor()
	song.startMacro = song.pools.macro

	table.insert(DB.songs, song)
	buildSong(song)
	saveDB()
	info("Song Manager", "Song '" .. song.shortName .. "' created.")
end

local function editSongMenu(song)
	while true do
		local items = {
			"Short Name: " .. song.shortName,
			"Full Name: " .. song.name,
			"BPM: " .. tostring(song.bpm),
			"Set List Gap (s): " .. tostring(song.gap or 0),
			"Notes: " .. (isBlank(song.notes) and "(none)" or song.notes),
			"Activate (Go To This Song)",
			"Rebuild Objects (re-store / re-label)",
			"Delete Song",
			"Back",
		}
		local idx, val = menu("Edit Song: " .. song.shortName, items)
		if not idx or val == "Back" then return end

		if idx == 1 then
			local v = ask("Short Name", song.shortName)
			if not isBlank(v) then song.shortName = trim(v) end
		elseif idx == 2 then
			local v = ask("Full Name", song.name)
			if not isBlank(v) then song.name = trim(v) end
		elseif idx == 3 then
			local v = askNumber("BPM", song.bpm)
			if v then song.bpm = v end
		elseif idx == 4 then
			local v = askNumber("Set List Gap in seconds (0 = manual advance)", song.gap or 0)
			if v then song.gap = v end
		elseif idx == 5 then
			local v = ask("Notes", song.notes)
			if v ~= nil then song.notes = v end
		elseif val == "Activate (Go To This Song)" then
			gotoSong(song.id)
		elseif val == "Rebuild Objects (re-store / re-label)" then
			buildSong(song)
			refreshTemplateViews(song)
			info("Song Manager", "Objects rebuilt for '" .. song.shortName .. "'.")
		elseif val == "Delete Song" then
			if confirm("Delete Song", "Delete '" .. song.shortName .. "' and its show objects? This cannot be undone.") then
				deleteSongObjects(song)
				for i, s in ipairs(DB.songs) do
					if s.id == song.id then table.remove(DB.songs, i) break end
				end
				if DB.currentSongId == song.id then DB.currentSongId = nil end
				saveDB()
				return
			end
		end
		saveDB()
	end
end

local function songListLabels()
	local items = {}
	for _, s in ipairs(DB.songs) do
		local marker = (DB.currentSongId == s.id) and "> " or "  "
		table.insert(items, marker .. s.shortName .. " (" .. tostring(s.bpm) .. " BPM)")
	end
	return items
end

local function goToSongMenu()
	if #DB.songs == 0 then
		info("Song Manager", "No songs yet. Use 'New Song' first.")
		return
	end
	local idx = menu("Go To Song", songListLabels())
	if not idx then return end
	gotoSong(DB.songs[idx].id)
end

local function manageSongsMenu()
	while true do
		if #DB.songs == 0 then
			info("Song Manager", "No songs yet.")
			addSongWizard()
			if #DB.songs == 0 then return end
		end
		local items = songListLabels()
		table.insert(items, "+ New Song")
		table.insert(items, "Back")
		local idx, val = menu("Songs", items)
		if not idx or val == "Back" then return end
		if val == "+ New Song" then
			addSongWizard()
		else
			editSongMenu(DB.songs[idx])
		end
	end
end

-- ===================================================================
-- Set list navigation menu
-- ===================================================================

local function setListMenu()
	while true do
		local sl = DB.settings.setList
		local items = {
			"Enabled: " .. tostring(sl.enabled),
			"Default Gap (s): " .. tostring(sl.gap),
			"Next Song",
			"Previous Song",
			"Back",
		}
		local idx, val = menu("Set List", items)
		if not idx or val == "Back" then return end
		if idx == 1 then
			sl.enabled = not sl.enabled
		elseif idx == 2 then
			local v = askNumber("Default Gap in seconds", sl.gap)
			if v then sl.gap = v end
		elseif val == "Next Song" then
			local i = DB.currentSongId and songIndexById(DB.currentSongId)
			if i and DB.songs[i + 1] then
				gotoSong(DB.songs[i + 1].id)
			elseif DB.songs[1] then
				gotoSong(DB.songs[1].id)
			end
		elseif val == "Previous Song" then
			local i = DB.currentSongId and songIndexById(DB.currentSongId)
			if i and i > 1 and DB.songs[i - 1] then
				gotoSong(DB.songs[i - 1].id)
			end
		end
		saveDB()
	end
end

-- ===================================================================
-- Settings menus
-- ===================================================================

local function poolTypesMenu()
	while true do
		local items = {}
		for _, pt in ipairs(DB.settings.poolTypes) do
			table.insert(items, string.format("%s [%s] start=%d block=%d", pt.label, pt.enabled and "on" or "off", pt.start, pt.block))
		end
		table.insert(items, "+ Add Pool Type")
		table.insert(items, "Back")
		local idx, val = menu("Pool Types", items)
		if not idx or val == "Back" then return end

		if val == "+ Add Pool Type" then
			local label = ask("Pool Type Label (e.g. 'Preset Pool 25')", "")
			if not isBlank(label) then
				local class = ask("MA3 Command Class Keyword (e.g. Preset, Group, Filter, Effect)", "")
				if not isBlank(class) then
					local poolId = nil
					if trim(class):lower() == "preset" then
						poolId = askNumber("Preset Pool ID", 25)
					end
					local start = askNumber("Starting Number", 1)
					local block = askNumber("Numbers Per Song (block size)", 1)
					if start and block then
						local key = trim(label):lower():gsub("[^%w]+", "_")
						table.insert(DB.settings.poolTypes, {
							key = key, label = trim(label), class = trim(class),
							poolId = poolId, enabled = true, start = round(start), block = round(block),
							builtin = false,
						})
					end
				end
			end
		else
			local pt = DB.settings.poolTypes[idx]
			if pt then
				local subItems = {
					"Toggle Enabled (currently " .. (pt.enabled and "on" or "off") .. ")",
					"Set Start Number",
					"Set Block Size",
				}
				if not pt.builtin then table.insert(subItems, "Remove Pool Type") end
				table.insert(subItems, "Back")
				local sIdx, sVal = menu(pt.label, subItems)
				if sVal == "Toggle Enabled (currently " .. (pt.enabled and "on" or "off") .. ")" then
					pt.enabled = not pt.enabled
				elseif sVal == "Set Start Number" then
					local n = askNumber("Start Number", pt.start)
					if n then pt.start = round(n); pt.next = nil end
				elseif sVal == "Set Block Size" then
					local n = askNumber("Block Size", pt.block)
					if n then pt.block = round(n) end
				elseif sVal == "Remove Pool Type" then
					if confirm("Remove Pool Type", "Remove '" .. pt.label .. "'? Existing songs keep their stored numbers but new songs won't allocate any.") then
						table.remove(DB.settings.poolTypes, idx)
					end
				end
			end
		end
		saveDB()
	end
end

local function templateViewsMenu()
	while true do
		local items = {}
		for _, tv in ipairs(DB.settings.templateViews) do
			table.insert(items, "View " .. tv.view .. " (" .. tv.scope .. ")")
		end
		table.insert(items, "+ Add Template View")
		table.insert(items, "My Personal Views: " .. (GetVar(UserVars(), MYVIEWS_VAR) or "(none)"))
		table.insert(items, "Load A Template View On This Display")
		table.insert(items, "Back")
		local idx, val = menu("Template Views", items)
		if not idx or val == "Back" then return end

		if val == "+ Add Template View" then
			local v = askNumber("View Number", 173)
			if v then
				table.insert(DB.settings.templateViews, { view = round(v), scope = "global" })
			end
		elseif val:match("^My Personal Views") then
			local v = ask("Comma-separated view numbers just for you (this operator profile)", GetVar(UserVars(), MYVIEWS_VAR))
			if v ~= nil then SetVar(UserVars(), MYVIEWS_VAR, v) end
		elseif val == "Load A Template View On This Display" then
			loadTemplateViewOnThisDisplay()
		elseif idx <= #DB.settings.templateViews then
			local tv = DB.settings.templateViews[idx]
			if confirm("Remove Template View", "Remove View " .. tv.view .. " from the managed list?") then
				table.remove(DB.settings.templateViews, idx)
			end
		end
		saveDB()
	end
end

local function executorSettingsMenu()
	while true do
		local ex = DB.settings.executor
		local items = {
			"Start Executor: " .. ex.start,
			"Block Size: " .. ex.block,
			"Bump Button Pool Type: " .. ex.bumpKey,
			"Back",
		}
		local idx, val = menu("Executor / Bump Buttons", items)
		if not idx or val == "Back" then return end
		if idx == 1 then
			local n = askNumber("Starting Executor Number", ex.start)
			if n then ex.start = round(n); ex.next = nil end
		elseif idx == 2 then
			local n = askNumber("Executors Per Song (block size)", ex.block)
			if n then ex.block = round(n) end
		elseif idx == 3 then
			local labels = {}
			for _, pt in ipairs(DB.settings.poolTypes) do table.insert(labels, pt.label) end
			local pIdx = menu("Which pool gets the bump button?", labels)
			if pIdx then ex.bumpKey = DB.settings.poolTypes[pIdx].key end
		end
		saveDB()
	end
end

local function bpmSettingsMenu()
	while true do
		local ref = DB.settings.bpmRef
		local items = {
			"BPM Executor: " .. ref.executor,
			"Speed Master Number: " .. ref.speedMasterNum,
			"Back",
		}
		local idx, val = menu("BPM Reference Settings", items)
		if not idx or val == "Back" then return end
		if idx == 1 then
			local n = askNumber("BPM Reference Executor Number", ref.executor)
			if n then ref.executor = round(n) end
		elseif idx == 2 then
			local n = askNumber("Speed Master Pool Number", ref.speedMasterNum)
			if n then ref.speedMasterNum = round(n) end
		end
		saveDB()
	end
end

local function resetMenu()
	while true do
		local items = {
			"Reset Settings Only (keep songs & show objects)",
			"Full Reset (delete ALL managed show objects & songs)",
			"Back",
		}
		local idx, val = menu("Reset", items)
		if not idx or val == "Back" then return end

		if val:match("^Reset Settings Only") then
			if confirm("Reset Settings", "Reset all Song Manager settings to defaults? Songs are kept.") then
				local kept = DB.songs
				local keptCurrent = DB.currentSongId
				DB = defaultDB()
				DB.songs = kept
				DB.currentSongId = keptCurrent
				saveDB()
				info("Song Manager", "Settings reset to defaults.")
			end
		elseif val:match("^Full Reset") then
			if confirm("Full Reset", "This deletes every sequence / macro / page / timecode / other pool object this plugin created for every song, plus the BPM reference and template views. This CANNOT be undone. Continue?") then
				local typed = ask('Type DELETE to confirm', "")
				if trim(typed or "") == "DELETE" then
					local undo = CreateUndo("Song Manager: Full Reset")
					for _, song in ipairs(DB.songs) do
						deleteSongObjects(song)
					end
					if DB.settings.setList.sequenceNum then
						deleteTarget("Sequence " .. DB.settings.setList.sequenceNum)
					end
					deleteTarget("SpeedMaster " .. DB.settings.bpmRef.speedMasterNum)
					runCmd("Delete Executor " .. DB.settings.bpmRef.executor)
					for _, tv in ipairs(DB.settings.templateViews) do
						deleteTarget("View " .. tv.view)
					end
					if undo then CloseUndo(undo) end
					DelVar(GlobalVars(), DB_VAR)
					DB = defaultDB()
					saveDB()
					info("Song Manager", "Full reset complete.")
					return
				else
					info("Song Manager", "Reset cancelled - confirmation text did not match.")
				end
			end
		end
	end
end

local function settingsMenu()
	while true do
		local items = {
			"Template Views",
			"Pool Types",
			"Executor / Bump Buttons",
			"BPM Reference",
			"Set List",
			"Reset",
			"Back",
		}
		local idx, val = menu("Settings", items)
		if not idx or val == "Back" then return end
		if val == "Template Views" then templateViewsMenu()
		elseif val == "Pool Types" then poolTypesMenu()
		elseif val == "Executor / Bump Buttons" then executorSettingsMenu()
		elseif val == "BPM Reference" then bpmSettingsMenu()
		elseif val == "Set List" then setListMenu()
		elseif val == "Reset" then resetMenu()
		end
	end
end

-- ===================================================================
-- First run setup wizard
-- ===================================================================

local function setupWizard()
	info("Song Manager - Setup",
		"Welcome! Let's configure starting pool numbers before you add songs.\n" ..
		"You can change all of this later from Settings.")

	for _, pt in ipairs(DB.settings.poolTypes) do
		local use = confirm(pt.label, "Manage " .. pt.label .. " pool objects per song?")
		pt.enabled = use
		if use then
			local start = askNumber(pt.label .. " - Starting Number", pt.start)
			if start then pt.start = round(start) end
			local block = askNumber(pt.label .. " - Numbers Per Song", pt.block)
			if block then pt.block = round(block) end
		end
	end

	local viewNum = askNumber("Template View Number To Manage (e.g. 173)", 173)
	if viewNum then
		DB.settings.templateViews = { { view = round(viewNum), scope = "global" } }
	end

	local execStart = askNumber("Starting Executor Number For Bump Buttons", DB.settings.executor.start)
	if execStart then DB.settings.executor.start = round(execStart) end

	local bpmExec = askNumber("BPM Reference Executor Number", DB.settings.bpmRef.executor)
	if bpmExec then DB.settings.bpmRef.executor = round(bpmExec) end

	DB.settings.initialized = true
	saveDB()
	info("Song Manager", "Setup complete. Use 'Songs' to add your first song.")
end

-- ===================================================================
-- Main menu
-- ===================================================================

local function mainMenu()
	while true do
		local song = currentSong()
		local header = song and ("Now Playing: " .. song.shortName .. " (" .. song.bpm .. " BPM)") or "No song active"
		local items = {
			header,
			"Songs (New / Edit / Delete)",
			"Go To Song",
			"BPM Reference",
			"Set List",
			"Settings",
			"Exit",
		}
		local idx, val = menu("Song Manager", items)
		if not idx or val == "Exit" then return end

		if val == "Songs (New / Edit / Delete)" then manageSongsMenu()
		elseif val == "Go To Song" then goToSongMenu()
		elseif val == "BPM Reference" then bpmReferenceMenu()
		elseif val == "Set List" then setListMenu()
		elseif val == "Settings" then settingsMenu()
		end
	end
end

-- ===================================================================
-- Entry point
-- ===================================================================

local function Main()
	DB = loadDB()
	if not DB.settings.initialized then
		setupWizard()
	end
	mainMenu()
	saveDB()
end

local ok, err = pcall(Main)
if not ok then
	ErrPrintf("SongManager Error: " .. tostring(err))
end
