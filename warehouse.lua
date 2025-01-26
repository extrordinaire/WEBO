local expect = require "cc.expect"
local expect, field = expect.expect, expect.field

local utils = require "utils"

local storage = {
  size = nil,
  occupied_slots = {},
}

function storage:init(params)
  expect(1, params, "table")
  field(params, "size", "number")

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

function storage:deposit(params)
  expect(1, params, "table")
  field(params, "slot", "number")

  if self.occupied_slots[params.slot] then
    return false
  end

  self.occupied_slots[params.slot] = true
  return true
end

function storage:withdraw(params)
  expect(1, params, "table")
  field(params, "slot", "number")

  if not self.occupied_slots[params.slot] then
    return false
  end

  self.occupied_slots[params.slot] = false
  return true
end

function storage:is_full()
  return utils.table_every({
    table = self.occupied_slots,
    pred = function(v) return v end,
  })
end

function storage:is_empty()
  return utils.table_every({
    table = self.occupied_slots,
    pred = function(v) return not v end,
  })
end

function storage:get_empty_slot()
  for i, v in ipairs(self.occupied_slots) do
    if not v then
      return i
    end
  end
  return nil
end

return storage
