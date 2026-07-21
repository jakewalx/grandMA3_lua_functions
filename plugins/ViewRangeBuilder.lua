local pluginName, componentName, signalTable, my_handle = select(1,...), select(2,...), select(3,...), select(4,...)

-- ===========================================================================
-- ViewRangeBuilder
--
-- Asks for a starting view number, then for each view from that number up to
-- +10 (11 candidate views total) lets the user type a comma separated list
-- of pool types to include. Computes a grid layout for whichever pools were
-- picked and (once CreateWindow below is filled in against a confirmed
-- object model) builds each view accordingly, with a 1-row view-selector
-- strip along the bottom of every created view.
--
-- STATUS: layout/selection logic is complete and safe to run. The actual
-- View/Window object creation in CreateWindow() is a placeholder -- it only
-- prints what it would do. Fill it in once the real View/Window class and
-- property names are confirmed (see ViewInspector.lua).
-- ===========================================================================

-- ===== Configuration =====

local VIEW_RANGE_SIZE = 11 -- start view .. start view + 10, inclusive
local GROUPS_COLUMNS = 10
local BASE_CONTENT_ROWS = 10
local MIN_ROWS_PER_STACK_ITEM = 2
local STACK_COLUMNS_WHEN_GROUPS = 10
local FOOTER_ROWS = 1
local PRESET_TYPE_ALL = 21 -- "ALL-21" preset type filter (ALL-21..ALL-25 are the unfiltered preset types)

-- Pool types selectable per view, keyed by the token typed in the popup.
-- `priority` controls top-to-bottom stacking order when more than one is
-- selected for a view. `groups` is handled separately as the fixed-width
-- left-hand block.
local POOL_TYPES = {
    groups        = { label = "Groups",         isGroups = true },
    presets       = { label = "Presets",        priority = 1 },
    macros        = { label = "Macros",         priority = 2 },
    sequences     = { label = "Sequences",      priority = 3 },
    appearances   = { label = "Appearances",    priority = 4 },
    plugins       = { label = "Plugins",        priority = 5 },
    layoutview    = { label = "Layout View",    priority = 6 },
    view3d        = { label = "3D View",        priority = 7 },
    layoutpool    = { label = "Layout Pool",    priority = 8 },
    selectiongrid = { label = "Selection Grid", priority = 9 },
}

local POOL_KEY_ORDER = {
    "groups", "presets", "macros", "sequences", "appearances",
    "plugins", "layoutview", "view3d", "layoutpool", "selectiongrid",
}

-- ===== Helpers =====

local function Trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function ParsePoolList(text)
    local selected = {}
    if text == nil then
        return selected
    end
    for token in text:gmatch("[^,]+") do
        local key = Trim(token):lower()
        if key ~= "" then
            if POOL_TYPES[key] then
                selected[key] = true
            else
                ErrPrintf("Unknown pool type '" .. key .. "' -- ignored. Valid keys: groups, presets, macros, sequences, appearances, plugins, layoutview, view3d, layoutpool, selectiongrid")
            end
        end
    end
    return selected
end

local function IsEmptySelection(selected)
    for _ in pairs(selected) do
        return false
    end
    return true
end

-- Computes a grid layout (in cells) for the given set of selected pool keys.
-- Returns an array of { key, x, y, w, h } blocks plus .footer/.totalCols/.totalRows.
local function ComputeLayout(selected)
    local stackKeys = {}
    for _, key in ipairs(POOL_KEY_ORDER) do
        if key ~= "groups" and selected[key] then
            stackKeys[#stackKeys + 1] = key
        end
    end
    table.sort(stackKeys, function(a, b) return POOL_TYPES[a].priority < POOL_TYPES[b].priority end)

    local hasGroups = selected.groups == true
    local stackCount = #stackKeys

    local contentRows = BASE_CONTENT_ROWS
    if stackCount * MIN_ROWS_PER_STACK_ITEM > contentRows then
        contentRows = stackCount * MIN_ROWS_PER_STACK_ITEM
    end

    local layout = {}
    local stackX, stackW

    if hasGroups then
        layout[#layout + 1] = { key = "groups", x = 0, y = 0, w = GROUPS_COLUMNS, h = contentRows }
        stackX = GROUPS_COLUMNS
        stackW = STACK_COLUMNS_WHEN_GROUPS
    else
        stackX = 0
        stackW = GROUPS_COLUMNS + STACK_COLUMNS_WHEN_GROUPS
    end

    if stackCount > 0 then
        local baseRows = math.floor(contentRows / stackCount)
        local extra = contentRows % stackCount
        local y = 0
        for i, key in ipairs(stackKeys) do
            local rows = baseRows + (i <= extra and 1 or 0)
            layout[#layout + 1] = { key = key, x = stackX, y = y, w = stackW, h = rows }
            y = y + rows
        end
    end

    local totalCols = GROUPS_COLUMNS + STACK_COLUMNS_WHEN_GROUPS
    layout.totalCols = totalCols
    layout.totalRows = contentRows + FOOTER_ROWS
    layout.footer = { x = 0, y = contentRows, w = totalCols, h = FOOTER_ROWS }

    return layout
end

-- Tries a text input dialog with progressively fewer arguments, since the
-- exact required signature hasn't been confirmed against a live console.
local function SafeTextInput(title, value)
    local attempts = {
        function() return TextInput(title, value, 0, 0) end,
        function() return TextInput(title, value) end,
        function() return TextInput(title) end,
    }
    for _, attempt in ipairs(attempts) do
        local ok, result = pcall(attempt)
        if ok then
            return result
        end
    end
    return nil
end

local function AskStartView()
    local value = SafeTextInput("View Range Builder -- start view number", "1001")
    if value == nil or Trim(tostring(value)) == "" then
        return nil
    end
    return tonumber(value)
end

local function AskViewPools(viewNumber)
    local title = "View " .. viewNumber .. " -- pools (comma list, blank = skip): groups,presets,macros,sequences,appearances,plugins,layoutview,view3d,layoutpool,selectiongrid"
    return SafeTextInput(title, "")
end

-- Placeholder -- prints the intended action instead of creating anything.
-- Replace the body once the real View/Window class and property names are
-- confirmed (see ViewInspector.lua and its output).
local function CreateWindow(viewNumber, label, poolKey, x, y, w, h)
    local suffix = ""
    if poolKey == "presets" then
        suffix = " (preset type " .. PRESET_TYPE_ALL .. " / ALL)"
    end
    Printf(string.format("  [preview] %-14s x=%-3d y=%-3d w=%-3d h=%-3d%s", label, x, y, w, h, suffix))
end

local function BuildView(viewNumber, selected, allViewNumbers)
    local layout = ComputeLayout(selected)
    Printf(string.format("View %d (%dx%d):", viewNumber, layout.totalCols, layout.totalRows))

    for _, block in ipairs(layout) do
        CreateWindow(viewNumber, POOL_TYPES[block.key].label, block.key, block.x, block.y, block.w, block.h)
    end

    CreateWindow(viewNumber, "View strip", nil, layout.footer.x, layout.footer.y, layout.footer.w, layout.footer.h)
end

-- ===== Entry points =====

function Main(display_handle, args)
    local startView = AskStartView()
    if startView == nil then
        Printf(tostring(pluginName) .. ": cancelled -- no start view number given")
        return
    end

    local viewNumbers = {}
    local viewSelections = {}

    for offset = 0, VIEW_RANGE_SIZE - 1 do
        local viewNumber = startView + offset
        local text = AskViewPools(viewNumber)
        if text ~= nil and Trim(text) ~= "" then
            local selected = ParsePoolList(text)
            if not IsEmptySelection(selected) then
                viewNumbers[#viewNumbers + 1] = viewNumber
                viewSelections[viewNumber] = selected
            end
        end
    end

    if #viewNumbers == 0 then
        Printf(tostring(pluginName) .. ": no views selected, nothing to do")
        return
    end

    Printf(tostring(pluginName) .. ": building " .. #viewNumbers .. " view(s): " .. table.concat(viewNumbers, ", "))

    for _, viewNumber in ipairs(viewNumbers) do
        BuildView(viewNumber, viewSelections[viewNumber], viewNumbers)
    end

    Printf(tostring(pluginName) .. ": layout preview complete. Window/view creation is currently preview-only -- see the STATUS note at the top of this file.")
end

function Cleanup()
end

function Execute(type, ...)
end

return Main, Cleanup, Execute
