local expect = require "cc.expect"
local utils = require "utils"

--- @class Storage
--- @field size number The size of the storage
--- @field occupied_slots boolean[]
local storage = {
  size = 0,
  occupied_slots = {},
}

--- @param params {size: number}
--- @return Storage
function storage:init(params)
  expect.expect(1, params, "table")
  expect.field(params, "size", "number")

  local initialized_occupied_slots = {}
  for i = 1, params.size do
    table.insert(initialized_occupied_slots, false)
  end

  local obj = {
    size = params.size,
    occupied_slots = initialized_occupied_slots,
  }

  setmetatable(obj, self)
  self.__index = self
  return obj
end

--- @param params {slot: number}
function storage:deposit(params)
  expect.expect(1, params, "table")
  expect.field(params, "slot", "number")

  if self.occupied_slots[params.slot] then
    return false
  end

  self.occupied_slots[params.slot] = true
  return true
end

--- @param params {slot: number}
function storage:withdraw(params)
  expect.expect(1, params, "table")
  expect.field(params, "slot", "number")

  if not self.occupied_slots[params.slot] then
    return false
  end

  self.occupied_slots[params.slot] = false
  return true
end

--- @return boolean
function storage:is_full()
  return utils.table_every({
    table = self.occupied_slots,
    pred = function(v) return v end,
  })
end

--- @return boolean
function storage:is_empty()
  return utils.table_every({
    table = self.occupied_slots,
    pred = function(v) return not v end,
  })
end

--- @return number?
function storage:get_empty_slot()
  for i, v in ipairs(self.occupied_slots) do
    if not v then
      return i
    end
  end
  return nil
end

return storage
