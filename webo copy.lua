local expect = require "cc.expect"

local basalt = require("basalt")

local utils = require("utils")

local inventory_shard = require "inventory_shard"
local storage = require("warehouse")

local modem = peripheral.find("modem")

while not modem do
  print("No modem found. Please attach a modem to the turtle.")
  read()
  modem = peripheral.find("modem")
end

TURTLE_NAME = modem.getNameLocal()
while not TURTLE_NAME do
  print("No turtle name found. Please check that the modem is available, and that it is turned on.")
  read()
  TURTLE_NAME = modem.getNameLocal()
end

print("Starting... " .. TURTLE_NAME)

-- Find all other storage peripherals (that implement :list() and :size())
local storageList = {}
for _, name in ipairs(peripheral.getNames()) do
  local pType = peripheral.getType(name) or "unknown"
  local inv = peripheral.wrap(name)
  if inv and inv.list and inv.size then
    table.insert(storageList, inv)
    --print("Found storage: " .. name .. " (" .. pType .. ")")
  end
end

if #storageList == 0 then
  print("No storage chests found. Make sure they're connected via a modem.")
  return
end

local inventory_file = fs.open("/inventory.yml", "r")
--- @type table<string, InventoryShard>
local inventory = {}
--- @type table<string, Storage>
local warehouse = {}


local function update_inventory_parallel()
  local tasks = {}
  --- @type table<string, table<string,InventoryShard>>
  local task_results = {}

  for _, inv in ipairs(storageList) do
    local task = function()
      local inv_size = inv.size()
      --- @type string
      local inv_name = peripheral.getName(inv)
      --- @type table<string, InventoryShard>
      local local_inventory = {}

      warehouse[inv_name] = storage:init({ size = inv_size })

      for slot = 1, inv_size do
        local detail = inv.getItemDetail(slot)
        if detail then
          warehouse[inv_name]:deposit({ slot = slot })

          local item_name = string.lower(detail.name):gsub(":", ".")
          if not local_inventory[item_name] then
            local_inventory[item_name] = inventory_shard:init({
              name = detail.name:gsub(":", "."),
              displayName = detail.displayName,
              maxCount = detail.maxCount,
            })
          end

          local_inventory[item_name]:register_allocation({
            storage = inv_name,
            slot = slot,
            count = detail.count,
          })
        else
          warehouse[inv_name]:withdraw({ slot = slot })
        end
      end

      task_results[inv_name] = local_inventory
    end

    table.insert(tasks, task)
  end

  parallel.waitForAll(unpack(tasks))

  for _, local_inventory in pairs(task_results) do
    for item_name, inventory_shard in pairs(local_inventory) do
      if not inventory[item_name] then
        inventory[item_name] = inventory_shard
      else
        for _, alloc in ipairs(inventory_shard.allocations) do
          inventory[item_name]:register_allocation(alloc)
        end
      end
    end
  end

  inventory_file = fs.open("/inventory.json", "w+")
  inventory_file.write(textutils.serializeJSON(inventory))
  inventory_file.close()
end

update_inventory_parallel()

table.sort(inventory, function(a, b)
  return a.displayName < b.displayName
end)

--- @type table<string, InventoryShard>
inventory = utils.sort_kv({
  table = inventory,
  pred = function(a, b)
    return inventory[a].displayName < inventory[b].displayName
  end
}).sorted_table

local did_load = true

local inventory_list = nil

--- @type table<string, InventoryShard>
local turtle_inventory = {}
--- @type Storage
local turtle_warehouse = storage:init({ size = 16 })


-- Check all the turtle inventory

function UPDATE_TURTLE_INVENTORY()
  turtle_inventory = {} --- fix this so we do not have to recreate it every time
  for i = 1, 16 do
    turtle.select(i)
    local item_info = turtle.getItemDetail(i, true)
    if item_info then
      local item_name = string.lower(item_info.name):gsub(":", ".")

      if not turtle_inventory[item_name] then
        turtle_inventory[item_name] = inventory_shard:init({
          name = item_name,
          displayName = item_info.displayName,
          maxCount = item_info.maxCount,
        })
      end

      turtle_inventory[item_name]:register_allocation({
        storage = TURTLE_NAME,
        slot = i,
        count = item_info.count,
      })

      turtle_warehouse:deposit({ slot = i })
    else
      turtle_warehouse:withdraw({ slot = i })
    end
  end
end

UPDATE_TURTLE_INVENTORY()

local selected_item = nil

--- @param params {item_name: string, count: number}
--- @return number retrieved
local function retrieve_items(params)
  expect.expect(1, params, "table")
  expect.field(params, "item_name", "string")
  expect.field(params, "count", "number")

  local retrieved = 0

  if not inventory[params.item_name] then
    return retrieved
  end

  local unallocation_remainder = inventory[params.item_name]:unallocate_item({
    extract = function(extract_params)
      local inv = peripheral.wrap(extract_params.from.storage)
      if not inv then
        return 0
      end

      local turtle_free_slot = turtle_warehouse:get_empty_slot()
      if not turtle_free_slot then
        return 0
      end

      local debug_file = fs.open("./debug.json", "w")
      debug_file.write(textutils.serializeJSON({
        from = extract_params.from,
        item_name = params.item_name,
        inventory = inventory,
        turtle_inventory = turtle_inventory,
      }))
      debug_file.close()

      local extracted_items = inv.pushItems(TURTLE_NAME, extract_params.from.slot, extract_params.from.count,
        turtle_free_slot)

      if extracted_items > 0 then
        if not turtle_inventory[params.item_name] then
          turtle_inventory[params.item_name] = inventory_shard:init({
            name = params.item_name,
            displayName = inventory[params.item_name].displayName,
            maxCount = inventory[params.item_name].maxCount,
          })
        end
        turtle_inventory[params.item_name]:register_allocation({
          storage = TURTLE_NAME,
          slot = 0,
          count = extracted_items,
        })
        turtle_warehouse:deposit({ slot = turtle_free_slot })
      end

      retrieved = retrieved + extracted_items

      return extracted_items
    end,
    on_remove_allocation = function(remove_params)
      warehouse[remove_params.storage]:withdraw({ slot = remove_params.slot })
    end,
    item_count = params.count,
  })

  UPDATE_LIST()

  return retrieved
end

local main = basalt.createFrame()

local inventory_scroll = main
    :addScrollableFrame()
    :setPosition(1, 2)
    :setSize("parent.w", "parent.h - 1")
    :setDirection("vertical")

inventory_list = inventory_scroll
    :addList()
    :setSize("parent.w", "parent.h")


local search_text = ""


local quantity_modal = main
    :addFrame()
    :setSize("parent.w - 4", "parent.h - 4")
    :setPosition(3, 3)
    :hide()

local quantity_modal_dismisser = quantity_modal
    :addButton()
    :setText("\215")
    :setPosition("parent.w-1", "1")
    :setSize(1, 1)
    :setBackground(colors.red)
    :setForeground(colors.white)
    :onClick(
      function(self, event)
        quantity_modal:hide()
      end)

local quantity_text = quantity_modal
    :addLabel()
    :setText("You can pick up to X")
    :setPosition(2, 2)
    :setSize("parent.w-2", 2)

local quantity_input = quantity_modal
    :addInput()
    :setPosition(2, 4)
    :setInputType("number")
    :setDefaultText("Quantity")
    :setInputLimit(20)
    :setSize("parent.w-2", 1)

local selected_quantity = nil

local quantity_confirm = quantity_modal
    :addButton()
    :setBackground(colors.lime)
    :setForeground(colors.white)
    :setText("Confirm")
    :setPosition("parent.w-self.w", "parent.h-self.h")
    :onClick(
      function()
        if selected_item and selected_quantity then
          retrieve_items(
            {
              item_name = selected_item.name,
              count = selected_quantity,
            }
          )

          quantity_modal:hide()
        end
      end)

local function on_change_quantity_input(self, event, value)
  selected_quantity = tonumber(value)

  if not selected_quantity then
    selected_quantity = 0
    quantity_confirm:setBackground(colors.red)
    quantity_confirm:setForeground(colors.white)
  end

  if selected_quantity > 0 then
    quantity_confirm:setBackground(colors.lime)
    quantity_confirm:setForeground(colors.white)
  else
    quantity_confirm:setBackground(colors.red)
    quantity_confirm:setForeground(colors.white)
  end
end

quantity_input:onChange(on_change_quantity_input)

function UPDATE_LIST()
  if inventory_list then
    inventory_list:clear()
  end

  local searchLower = search_text:lower()

  inventory_list:setOffset(0, 0)


  local results = utils.filter({
    table = inventory,
    pred = function(v)
      -- Safely turn both v.name and v.displayName to lower-case
      local nameLower        = (v.name or ""):lower()
      local displayNameLower = (v.displayName or ""):lower()

      -- Plain search (4th arg = true) to avoid pattern matching
      return (string.find(nameLower, searchLower, 1, true) ~= nil)
          or (string.find(displayNameLower, searchLower, 1, true) ~= nil)
    end
  })

  table.sort(results, function(a, b)
    return a.name < b.name
  end)

  if inventory_list then
    inventory_list:clear()

    for _, item in pairs(results) do
      local item_text = item.displayName .. " " .. item.count
      local item_entry = inventory_list
          :addItem(item_text, colors.black, colors.white, item)

      item_entry:onSelect(
        function(self, event, _item)
          selected_item = _item.args[1]
          quantity_modal:show()
          quantity_text:setText("You can pick up to " ..
            math.min(selected_item.count, selected_item.maxCount * 16) .. " of " .. selected_item
            .displayName)
        end)
    end
  end
end

--- @return {storage: string, slot: number}?
function GET_EMPTY_SLOT()
  local empty_slot = nil

  for storage_name, storage in pairs(warehouse) do
    local local_empty_slot = storage:get_empty_slot()
    if local_empty_slot then
      empty_slot = {
        storage = storage_name,
        slot = local_empty_slot,
      }
      break
    end
  end

  return empty_slot
end

function UPLOAD_TURTLE_INVENTORY()
  UPDATE_TURTLE_INVENTORY()
  --- @type function[]
  local tasks = {}
  for item_name, turtle_shard in pairs(turtle_inventory) do
    local inventory_shard_task = function()
      if not inventory[item_name] then
        inventory[item_name] = inventory_shard:init({
          name = item_name,
          displayName = turtle_shard.displayName,
          maxCount = turtle_shard.maxCount,
        })
      end

      local unallocation_remainder = turtle_shard:unallocate_item({
        extract = function(extract_params)
          local extracted = 0

          local allocated_items = inventory[item_name]:allocate_item({
            item_count = turtle_shard.count,
            insert = function(insert_params)
              local debug_file = fs.open("./debug_extract.json", "w")
              debug_file.write(textutils.serializeJSON({
                extract_params = extract_params,
                insert_params = insert_params,
                turtle_inventory = turtle_inventory,
              }))
              debug_file.close()

              local wrapped_inventory = peripheral.wrap(insert_params.to.storage)
              if not wrapped_inventory then
                return 0
              end

              local unallocated = wrapped_inventory.pullItems(
                TURTLE_NAME,
                extract_params.from.slot,
                extract_params.from.count,
                insert_params.to.slot
              )

              return unallocated
            end,
            allocate = function(params)
              local allocations = {}
              local remainder = params.item_count

              for _, allocation in ipairs(turtle_shard.allocations) do
                local slots = math.ceil(allocation.count / turtle_shard.maxCount)
                --- @type {slot: number, storage: string}[]
                local reserved_slots = {}

                for _ = 1, slots do
                  local empty_slot = GET_EMPTY_SLOT()
                  if empty_slot then
                    warehouse[empty_slot.storage]:deposit({ slot = empty_slot.slot })
                    table.insert(reserved_slots, empty_slot)
                  end
                end

                for _, reserved_slot in ipairs(reserved_slots) do
                  local reserved_allocation = {
                    storage = reserved_slot.storage,
                    slot = reserved_slot.slot,
                    count = 0,
                  }
                  table.insert(allocations, reserved_allocation)
                end
              end

              return allocations, remainder
            end,
          })

          extracted = allocated_items

          return extracted
        end,
        on_remove_allocation = function(params)
          turtle_warehouse:withdraw({ slot = params.slot })
        end,
        item_count = turtle_inventory[item_name].count,
      })
    end
    table.insert(tasks, inventory_shard_task)
  end

  parallel.waitForAll(unpack(tasks))

  local debug_inventory_file = fs.open("debug_inventory_file.json", "w")
  debug_inventory_file.write(textutils.serializeJSON({ inventory, warehouse }))
  debug_inventory_file.close()

  local debug_inventory_turtle_file = fs.open("debug_inventory_turtle_file.json", "w")
  debug_inventory_turtle_file.write(textutils.serializeJSON({ turtle_inventory, turtle_warehouse }))
  debug_inventory_turtle_file.close()

  UPDATE_LIST()
end

UPDATE_LIST()

local top_bar_flex = main
    :addFlexbox()
    :setPosition(1, 1)
    :setBackground(colors.black)
    :setSize("parent.w", 1)
    :setDirection("row")
    :setWrap("nowrap")
    :setSpacing(0)

local search_bar_frame = top_bar_flex
    :addFrame()
    :setSize("parent.w-5", 1)


local upload_button_frame = top_bar_flex
    :addFrame()

local upload_button = upload_button_frame
    :addButton()
    :setText("\24")
    :setSize(5, 1)
    :setBackground(colors.blue)
    :setForeground(colors.white)
    :onClick(
      function()
        UPLOAD_TURTLE_INVENTORY()
      end)

local search_input = search_bar_frame
    :addInput()
    :setInputType("text")
    :setDefaultText("Search...")
    :setInputLimit(20)
    :setSize("parent.w", 1)

local search_clear_button = search_bar_frame
    :addButton()
    :setText("\xd7")
    :setSize(1, 1)
    :setPosition("parent.w", 1)
    :setBackground(colors.red)
    :setForeground(colors.white)
    :hide()
    :onClick(
      function(self, event)
        search_input:setValue("")
        search_text = ""
        UPDATE_LIST()
      end)

search_input:onChange(
  function(self, event, value)
    search_text = tostring(value)
    if string.len(search_text) > 0 then
      search_clear_button:show()
    else
      search_clear_button:hide()
    end

    UPDATE_LIST()
  end)


basalt.autoUpdate()
