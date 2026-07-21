local pluginName, componentName, signalTable, my_handle = select(1,...), select(2,...), select(3,...), select(4,...)

-- ===========================================================================
-- ViewInspector
--
-- Diagnostic helper for ViewRangeBuilder.lua. Dumps the class and every
-- property of a given View object and its window children so the real
-- View/Window property names (position, size, pool link, filter type) can
-- be confirmed against a live console before ViewRangeBuilder's CreateWindow
-- placeholder is filled in with real object creation calls.
--
-- Usage: build one sample view by hand (e.g. Store View 1001) containing a
-- Group pool window, a Preset pool window filtered to an ALL preset type, a
-- Macro pool window, and a bottom view-button strip, then:
--   Call Plugin <this plugin's pool number> "1001"
-- and copy the Command Line History / Log output back.
-- ===========================================================================

local function DumpProperties(handle, indent)
    local count = PropertyCount(handle)
    if not count then return end
    for i = 0, count - 1 do
        local name = PropertyName(handle, i)
        local ok, value = pcall(Get, handle, name)
        if ok then
            Printf(indent .. tostring(name) .. " = " .. tostring(value))
        else
            Printf(indent .. tostring(name) .. " = <error reading value>")
        end
    end
end

local function DumpTree(handle, indent, maxDepth)
    indent = indent or ""
    maxDepth = maxDepth or 5
    if not handle then
        Printf(indent .. "<nil handle>")
        return
    end
    Printf(indent .. "== " .. tostring(GetClass(handle)) .. " (index " .. tostring(Index(handle)) .. ") ==")
    DumpProperties(handle, indent .. "  ")
    if maxDepth > 0 then
        local childCount = Count(handle)
        if childCount and childCount > 0 then
            for i = 0, childCount - 1 do
                local ok, child = pcall(Ptr, handle, i)
                if ok then
                    DumpTree(child, indent .. "    ", maxDepth - 1)
                else
                    Printf(indent .. "    <could not get child " .. tostring(i) .. ">")
                end
            end
        end
    end
end

function Main(display_handle, args)
    local viewNumber = args
    if viewNumber == nil or viewNumber == "" then
        viewNumber = "1001"
    end

    Printf(tostring(pluginName) .. ": inspecting View " .. tostring(viewNumber))

    local viewHandle = GetObject("View " .. tostring(viewNumber))
    if viewHandle == nil then
        local ok, found = pcall(Find, Root(), tostring(viewNumber), "View")
        if ok then
            viewHandle = found
        end
    end

    if viewHandle == nil then
        ErrPrintf("Could not find View " .. tostring(viewNumber) .. " -- make sure it exists (Store View " .. tostring(viewNumber) .. ") and try again, e.g. Call Plugin <name> \"1001\"")
        return
    end

    DumpTree(viewHandle, "", 6)
    Printf(tostring(pluginName) .. ": done. Copy everything above (from the Command Line History / Log window) and send it back.")
end

function Cleanup()
end

function Execute(type, ...)
end

return Main, Cleanup, Execute
