local expect = require "cc.expect"
local utils = require("utils")

--- @alias Allocation {storage: string, count: number, slot: number}

--- @class InventoryShard
--- @field name string The code name of the item
--- @field displayName string The display name of the item
--- @field allocations Allocation[]
--- @field count number The current item count in the shard
--- @field maxCount number The maximum item count the shard can hold
local inventory_shard = {
  name = "unnamed",
  displayName = "unnamed",
  allocations = {},
  count = 0,
  maxCount = math.huge,
}

--- @param params {name: string, displayName: string, maxCount: number}
--- @return InventoryShard
function inventory_shard:init(params)
  expect.expect(1, params, "table")
  expect.field(params, "name", "string")
  expect.field(params, "displayName", "string")
  expect.field(params, "maxCount", "number")

  local obj = {
    name = params.name,
    displayName = params.displayName,
    allocations = {},
    count = 0,
    maxCount = params.maxCount,
  }

  setmetatable(obj, self)
  self.__index = self
  return obj
end

--- Registers an allocation in the shard
--- @param params {storage: string, count: number, slot: number}
function inventory_shard:register_allocation(params)
  expect.expect(1, params, "table")
  expect.field(params, "storage", "string")
  expect.field(params, "count", "number")
  expect.field(params, "slot", "number")

  table.insert(self.allocations, {
    storage = params.storage,
    count = params.count,
    slot = params.slot,
  })

  self.count = self.count + params.count
end

--- Allocates an item in the shard
--- @alias InsertFunction fun(params: {to: Allocation}): number
--- @alias AllocateFunction fun(params: {item_count: number}): Allocation[], number
--- @param params {item_count: number, insert: InsertFunction, allocate: AllocateFunction}
--- @return number remainder
function inventory_shard:allocate_item(params)
  expect.expect(1, params, "table")
  expect.field(params, "item_count", "number")
  expect.field(params, "insert", "function")
  expect.field(params, "allocate", "function")

  local remainder = params.item_count

  for _, allocation in ipairs(self.allocations) do
    if allocation.count < self.maxCount then
      local to_insert = math.min(self.maxCount - allocation.count, remainder)

      local inserted = params.insert({ to = { storage = allocation.storage, count = to_insert, slot = allocation.slot } })

      allocation.count = allocation.count + inserted
      self.count = self.count + inserted
      remainder = remainder - inserted
    end
  end

  if remainder > 0 then
    local ready_allocations, allocation_remainder = params.allocate({ item_count = remainder })

    for _, allocation in ipairs(ready_allocations) do
      local to_insert = math.min(self.maxCount - allocation.count, remainder)
      local inserted = params.insert({ to = { storage = allocation.storage, count = to_insert, slot = allocation.slot } })

      if inserted > 0 then
        self:register_allocation({
          storage = allocation.storage,
          count = inserted,
          slot = allocation.slot,
        })
      end

      remainder = remainder - inserted
    end

    remainder = remainder + allocation_remainder
  end


  return remainder
end

--- Unallocates an item in the shard
--- @alias ExtractFunction fun(params: {from: Allocation}): number
--- @alias OnRemoveAllocation fun(params: {storage: string, slot: number})
--- @param params {item_count: number, extract: ExtractFunction, on_remove_allocation: OnRemoveAllocation}
function inventory_shard:unallocate_item(params)
  expect.expect(1, params, "table")
  expect.field(params, "item_count", "number")
  expect.field(params, "extract", "function")
  expect.field(params, "on_remove_allocation", "function")

  local remainder = params.item_count

  local allocations_to_remove = {}

  for allocation_index, allocation in ipairs(self.allocations) do
    local to_unallocate = math.min(allocation.count, remainder)

    local unallocated = params.extract({ from = { storage = allocation.storage, count = to_unallocate, slot = allocation.slot } })

    allocation.count = allocation.count - unallocated
    self.count = self.count - unallocated

    if allocation.count == 0 then
      table.insert(allocations_to_remove, allocation_index)
    end

    remainder = remainder - unallocated
  end

  for i = #allocations_to_remove, 1, -1 do
    params.on_remove_allocation({
      storage = self.allocations[allocations_to_remove[i]].storage,
      slot = self.allocations[allocations_to_remove[i]].slot,
    })
    table.remove(self.allocations, allocations_to_remove[i])
  end

  allocations_to_remove = nil

  return remainder
end

--- Merges allocations in the shard
--- @alias MoveFunction fun(params: {from: Allocation, to: Allocation}): number
--- @param params {move: MoveFunction, on_remove_allocation: OnRemoveAllocation}
function inventory_shard:merge_allocations(params)
  expect.expect(1, params, "table")
  expect.field(params, "move", "function")
  expect.field(params, "on_remove_allocation", "function")

  local remainder = 0

  --- @type Allocation[]
  local incomplete_allocations = utils.filter({
    table = self.allocations,
    --- @param allocation Allocation
    pred = function(allocation)
      return allocation.count < self.maxCount
    end,
  })

  local current_pick_index = #incomplete_allocations
  local current_drop_index = 1

  local allocations_to_remove = {}

  while current_drop_index < current_pick_index do
    local pick = incomplete_allocations[current_pick_index]
    local drop = incomplete_allocations[current_drop_index]

    local to_merge = math.min(self.maxCount - drop.count, pick.count)

    local merged = params.move({ from = { storage = pick.storage, count = to_merge, slot = pick.slot }, to = { storage = drop.storage, count = to_merge, slot = drop.slot } })

    pick.count = pick.count - merged
    drop.count = drop.count + merged

    if pick.count == 0 then
      current_pick_index = current_pick_index - 1
      table.insert(allocations_to_remove, current_pick_index)
    end

    if drop.count == self.maxCount then
      current_drop_index = current_drop_index + 1
    end

    remainder = remainder + (to_merge - merged)
  end

  for i = #allocations_to_remove, 1, -1 do
    params.on_remove_allocation({
      storage = self.allocations[allocations_to_remove[i]].storage,
      slot = self.allocations[allocations_to_remove[i]].slot,
    })
    table.remove(self.allocations, allocations_to_remove[i])
  end

  allocations_to_remove = nil

  return remainder
end

return inventory_shard
