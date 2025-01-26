local basalt = require("basalt")
local yml_utils = require("yml_utils")
local utils = require("utils")
local pretty = require "cc.pretty"

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

print("Starting..." .. TURTLE_NAME)

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
local inventory = {}
local warehouse = {}


local function update_inventory()
  for _, inv in ipairs(storageList) do
    local invSize = inv.size()

    local inv_name = peripheral.getName(inv)

    warehouse[inv_name] = storage:init({ size = invSize })

    for slot = 1, invSize do
      local detail = inv.getItemDetail(slot)
      --pretty.pretty_print(detail)
      if detail then
        warehouse[inv_name]:deposit({ slot = slot })

        local item_name = string.lower(detail.name):gsub(":", ".")
        if not inventory[item_name] then
          inventory[item_name] = {
            name = detail.name:gsub(":", "."),
            displayName = detail.displayName,
            allocation = {
              {
                storage = inv_name,
                slot = slot,
                count = detail.count,
              }
            },
            count = detail.count,
            maxCount = detail.maxCount,
          }
        else
          table.insert(inventory[item_name].allocation, {
            storage = inv_name,
            slot = slot,
            count = detail.count,
          })
          inventory[item_name].count = inventory[item_name].count + detail.count
        end
      else
        warehouse[inv_name]:withdraw({ slot = slot })
      end
    end
  end

  inventory_file = fs.open("/inventory.yml", "w+")
  inventory_file.write(yml_utils.serialize({ table = inventory }))
  inventory_file.close()
end

update_inventory()

table.sort(inventory, function(a, b)
  return a.displayName < b.displayName
end)

inventory = utils.sort_kv({
  table = inventory,
  pred = function(a, b)
    return inventory[a].displayName < inventory[b].displayName
  end
}).sorted_table

local did_load = true

local inventory_list = nil

local turtle_inventory = {}


-- Check all the turtle inventory
for i = 1, 16 do
  turtle.select(i)
  local item_info = turtle.getItemDetail()
  if item_info then
    table.insert(turtle_inventory, item_info)
  end
end

local selected_item = nil

local function retrieve_items(params)
  local to_take = math.min(params.count, inventory[params.item_name].maxCount * 16)

  if inventory[params.item_name].count < to_take then
    to_take = inventory[params.item_name].count
  end


  local retrieved = 0
  local allocation_index_to_remove = {}

  for index, allocation in ipairs(inventory[params.item_name].allocation) do
    local inv = peripheral.wrap(allocation.storage)
    local got = inv.pushItems(TURTLE_NAME, allocation.slot, to_take - retrieved)
    retrieved = retrieved + got

    if retrieved >= allocation.count then
      warehouse[allocation.storage]:withdraw({ slot = allocation.slot })
      -- TODO(maximo): remove this
      table.insert(allocation_index_to_remove, index)
    end
    if retrieved >= to_take then
      break
    end
  end

  table.sort(allocation_index_to_remove, function(a, b)
    return a > b
  end)

  for _, index in ipairs(allocation_index_to_remove) do
    table.remove(inventory[params.item_name].allocation, index)
  end

  local amount_left = inventory[params.item_name].count - retrieved

  if amount_left == 0 then
    inventory[params.item_name] = nil
  else
    inventory[params.item_name].count = amount_left
  end

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
      return string.find(nameLower, searchLower, 1, true)
          or string.find(displayNameLower, searchLower, 1, true)
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

function UPLOAD_TURTLE_INVENTORY()
  turtle_inventory = {}
  for turtle_slot = 1, 16 do
    turtle.select(turtle_slot)
    local item_info = turtle.getItemDetail(turtle_slot, true)
    if item_info then
      turtle_inventory[turtle_slot] = item_info
    end
  end

  local debug_file = fs.open("/debug.yml", 'w')
  debug_file.write(yml_utils.serialize({ table = turtle_inventory }))
  debug_file.close()

  for turtle_slot, item in pairs(turtle_inventory) do
    local remaining_to_push = item.count

    local item_name = string.lower(item.name):gsub(":", ".")

    if not inventory[item_name] then
      for inv_name, storage_unit in pairs(warehouse) do
        if storage_unit:is_full() then
          goto continue
        end

        local inv = peripheral.wrap(inv_name)
        -- Handle first slot separately
        local first_slot = storage_unit:get_empty_slot()
        local pushed_count = inv.pullItems(TURTLE_NAME, turtle_slot, remaining_to_push, first_slot)

        if pushed_count > 0 then
          -- Only update slot states if items were actually moved
          storage_unit:deposit({ slot = first_slot })

          inventory[item_name] = {
            name = item_name,
            displayName = item.displayName,
            allocation = {
              {
                storage = inv_name,
                slot = first_slot,
                count = pushed_count,
              }
            },
            count = pushed_count,
            maxCount = item.maxCount,
          }

          local inv_allocation_debug = fs.open("/inv_allocation_debug.yml", 'w')
          inv_allocation_debug.write(yml_utils.serialize({ table = inventory[item_name].allocation }))
          inv_allocation_debug.close()

          remaining_to_push = remaining_to_push - pushed_count

          -- Process remaining slots if needed
          if remaining_to_push > 0 then
            while not storage_unit:is_full() do
              local slot = storage_unit:get_empty_slot()
              local got = inv.pullItems(TURTLE_NAME, turtle_slot, remaining_to_push, slot)

              if got > 0 then
                -- Update inventory and warehouse data
                table.insert(inventory[item_name].allocation, {
                  storage = inv_name,
                  slot = slot,
                  count = got,
                })

                inventory[item_name].count = inventory[item_name].count + got
                remaining_to_push = remaining_to_push - got

                -- Update slot states
                storage_unit:deposit({ slot = slot })
                if remaining_to_push <= 0 then
                  break
                end
              end
            end
          end
        end

        ::continue::
      end
    end

    if inventory[item_name] and remaining_to_push > 0 then
      for _, allocation in ipairs(inventory[item_name].allocation) do
        if allocation.quantity == item.maxCount then
          goto continue
        end

        local inv = peripheral.wrap(allocation.storage)
        local got = inv.pullItems(TURTLE_NAME, turtle_slot, remaining_to_push, allocation.slot)
        remaining_to_push = remaining_to_push - got

        if got > 0 then
          allocation.count = allocation.count + got
          inventory[item_name].count = inventory[item_name].count + got
        end

        if remaining_to_push == 0 then
          break
        end

        ::continue::
      end

      if remaining_to_push > 0 then
        for inventory_name, storage_unit in pairs(warehouse) do
          local wrapped_storage = peripheral.wrap(inventory_name)

          if storage_unit:is_full() then
            goto continue
          end
          while not storage_unit:is_full() do
            local free_slot = storage_unit:get_empty_slot()
            local got = wrapped_storage.pullItems(TURTLE_NAME, turtle_slot, remaining_to_push, free_slot)

            inventory[item_name].count = inventory[item_name].count + got

            table.insert(inventory[item_name].allocation, {
              storage = peripheral.getName(wrapped_storage),
              slot = free_slot,
              count = got,
            })

            remaining_to_push = remaining_to_push - got

            storage_unit:deposit({ slot = free_slot })
            if remaining_to_push == 0 then
              break
            end
          end

          ::continue::
        end
      end
    end
  end

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
