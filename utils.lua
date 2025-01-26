local expect = require "cc.expect"
local expect, field = expect.expect, expect.field

local utils = {}

-- filter function: takes a table and a predicate function
-- @param params: table with keys: table, pred: () => boolean
function utils.filter(params)
  local result = {}
  for i, v in pairs(params.table) do
    if params.pred(v, i) then
      table.insert(result, v)
    end
  end
  return result
end

-- sort function: takes a table and a predicate function
-- @param params: table with keys: table, pred: (key_a, key_b) => boolean
function utils.sort_kv(params)
  local keys = {}
  for k in pairs(params.table) do
    table.insert(keys, k)
  end

  -- Sort keys based on the associated values
  table.sort(keys, params.pred)

  local sorted_table = {}
  for _, k in ipairs(keys) do
    sorted_table[k] = params.table[k]
  end

  return { sorted_table = sorted_table, sorted_keys = keys }
end

-- find function: takes a table and a predicate function
-- @param params: array-like table with keys: table, pred: () => boolean
function utils.find_and_remove(params)
  for i, v in ipairs(params.table) do
    if params.pred(v, i) then
      table.remove(params.table, i)
      return v
    end
  end
end

-- getter function: retrieves the network peripheral name
function utils.get_own_peripheral_name()
  local myID = os.getComputerID() -- e.g. 2, 5, etc.
  for _, name in ipairs(peripheral.getNames()) do
    -- Make sure it's actually a turtle
    if peripheral.hasType(name, "turtle") then
      -- Ask that turtle for its ID
      local theirID = peripheral.call(name, "getComputerID")
      if theirID == myID then
        return name -- found ourselves
      end
    end
  end

  print("Could not find own turtle peripheral name")

  return nil
end

function utils.table_reduce(params)
  expect(1, params, "table")
  field(params, "table", "table")
  field(params, "reducer", "function")
  field(params, "initial_value", "any")

  local result = params.initial_value
  for _, v in ipairs(params.table) do
    result = params.reducer(result, v)
  end
  return result
end

function utils.table_every(params)
  expect(1, params, "table")
  field(params, "table", "table")
  field(params, "pred", "function")

  for _, v in ipairs(params.table) do
    if not params.pred(v) then
      return false
    end
  end
  return true
end

function utils.table_any(params)
  expect(1, params, "table")
  field(params, "table", "table")
  field(params, "pred", "function")

  for _, v in ipairs(params.table) do
    if params.pred(v) then
      return true
    end
  end
  return false
end

function utils.table_find(params)
  expect(1, params, "table")
  field(params, "table", "table")
  field(params, "pred", "function")

  for _, v in ipairs(params.table) do
    if params.pred(v) then
      return v
    end
  end
  return nil
end

return utils
