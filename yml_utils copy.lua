local yml_utils = {}

function deep_copy_table(orig)
  local copy = {}
  for k, v in pairs(orig) do
    if type(v) == "table" then
      copy[k] = deep_copy_table(v) -- Recursively copy nested tables
    else
      copy[k] = v
    end
  end
  return copy
end

-- Example usage:
local original = { a = 1, b = { x = 10, y = 20 }, c = 3 }
local duplicated = deep_copy_table(original)


function yml_utils.serialize(params)
  local indent = params.indent or 0

  local yml = ""
  for key, value in pairs(params.table) do
    local processed_value = value
    if (processed_value == nil) then
      processed_value = "null" .. "\n"
    elseif (type(processed_value) == "number") then
      processed_value = tostring(processed_value) .. "\n"
    elseif (type(processed_value) == "string") then
      processed_value = "\"" .. processed_value .. "\"" .. "\n"
    elseif (type(processed_value) == "boolean") then
      processed_value = tostring(processed_value) .. "\n"
    elseif (type(processed_value) == "table") then
      processed_value = "\n" .. yml_utils.serialize({ table = value, indent = indent + 1 })
    end
    yml = yml .. string.rep("\t", indent) .. key .. ": " .. processed_value
  end

  return yml
end

function yml_utils.parse(yml)
  local result = {}
  local lines = {}
  -- Split YAML string into lines
  for line in yml:gmatch("[^\n]+") do
    table.insert(lines, line)
  end

  -- This stack will hold references to the current nested table at each indent level
  local stack = { result }

  -- We track the current indentation level
  local current_indent = 0
  -- Keep track of the last key we encountered (in case we need to create a nested table)
  local previous_key = nil

  for _, line in ipairs(lines) do
    -- Skip empty or whitespace-only lines
    if line:match("^%s*$") then
      goto continue
    end

    -- Count leading spaces; each 2 spaces = 1 indentation level (naive assumption!)
    local leading_spaces = line:match("^(%s*)") or ""
    local indent = #leading_spaces / 2

    -- Attempt to split into "key: value"
    local key, value = line:match("^%s*(.-):%s*(.*)")

    -- If we didn't find a `:` at all, handle it as needed (very naive fallback)
    if not key then
      key = line:match("^%s*(.-)%s*$") -- e.g. just store the raw line?
      value = ""
    end

    -- If we've gone *deeper* than current_indent, create a new nested table
    if indent > current_indent then
      -- We assume we've only gone one level deeper
      -- Create a new table for the previous key (unless that was a value)
      if previous_key then
        local new_table = {}
        stack[#stack][previous_key] = new_table
        table.insert(stack, new_table)
        current_indent = indent
      end
      -- If we've gone *shallower*, pop from the stack until we match the indent
    elseif indent < current_indent then
      while current_indent > indent do
        table.remove(stack)
        current_indent = current_indent - 1
      end
    end

    -- Now we are at the correct level in the stack
    if value == "" then
      -- Means the key has no immediate value => create a table for it
      local new_table = {}
      stack[#stack][key] = new_table
      previous_key = key
    else
      -- We have something after the colon. Convert it if needed.
      if value == "null" then
        stack[#stack][key] = nil
      elseif tonumber(value) then
        stack[#stack][key] = tonumber(value)
      else
        -- Remove surrounding quotes if present
        stack[#stack][key] = value:match('^"(.*)"$') or value
      end
      previous_key = key
    end

    ::continue::
  end

  return result
end

return yml_utils
