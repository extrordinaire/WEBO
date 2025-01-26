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


local function update_inventory_parallel()
  local tasks = {}

  for _, inv in ipairs(storageList) do
    local task = function()
      local invSize = inv.size()
      local inv_name = peripheral.getName(inv)

      warehouse[inv_name] = storage:init({ size = invSize })

      for slot = 1, invSize do
        local detail = inv.getItemDetail(slot)
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

    table.insert(tasks, task)
  end

  parallel.waitForAny(unpack(tasks))

  inventory_file = fs.open("/inventory.yml", "w+")
  inventory_file.write(yml_utils.serialize({ table = inventory }))
  inventory_file.close()
end

update_inventory_parallel()

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
  -- Group turtle slots by item name
  local items_by_name = {}
  for turtle_slot = 1, 16 do
    turtle.select(turtle_slot)
    local item_info = turtle.getItemDetail(turtle_slot, true)
    if item_info then
      local name = string.lower(item_info.name):gsub(":", ".")
      if not items_by_name[name] then
        items_by_name[name] = {
          displayName = item_info.displayName,
          maxCount = item_info.maxCount,
          slots = {},
        }
      end
      table.insert(items_by_name[name].slots, { slot = turtle_slot, count = item_info.count })
    end
  end

  -- Create parallel tasks for each item type
  local tasks = {}
  for item_name, data in pairs(items_by_name) do
    local task = function()
      for _, slot_data in ipairs(data.slots) do
        local turtle_slot = slot_data.slot
        local remaining_to_push = slot_data.count

        while remaining_to_push > 0 do
          local pushed = false

          -- Try to push to existing slots with same item
          for _, inv in ipairs(storageList) do
            local inv_name = peripheral.getName(inv)
            local items = inv.list()

            -- Check existing allocations for this item
            for slot, existing_item in pairs(items) do
              if existing_item.name == data.displayName and existing_item.count < existing_item.maxCount then
                local space = existing_item.maxCount - existing_item.count
                local to_push = math.min(space, remaining_to_push)
                local transferred = inv.pullItems(TURTLE_NAME, turtle_slot, to_push, slot)

                if transferred > 0 then
                  -- Update inventory atomically for this item
                  if not inventory[item_name] then
                    inventory[item_name] = {
                      name = item_name,
                      displayName = data.displayName,
                      allocation = {},
                      count = 0,
                      maxCount = data.maxCount,
                    }
                  end

                  -- Update existing allocation or add new
                  local found = false
                  for _, alloc in ipairs(inventory[item_name].allocation) do
                    if alloc.storage == inv_name and alloc.slot == slot then
                      alloc.count = alloc.count + transferred
                      found = true
                      break
                    end
                  end
                  if not found then
                    table.insert(inventory[item_name].allocation, {
                      storage = inv_name,
                      slot = slot,
                      count = transferred,
                    })
                  end
                  inventory[item_name].count = inventory[item_name].count + transferred
                  remaining_to_push = remaining_to_push - transferred
                  pushed = true
                end
              end
              if remaining_to_push == 0 then break end
            end
            if remaining_to_push == 0 then break end

            -- Find empty slots for new allocations
            for slot = 1, inv.size() do
              if not items[slot] then
                local transferred = inv.pullItems(TURTLE_NAME, turtle_slot, remaining_to_push, slot)
                if transferred > 0 then
                  if not inventory[item_name] then
                    inventory[item_name] = {
                      name = item_name,
                      displayName = data.displayName,
                      allocation = {},
                      count = 0,
                      maxCount = data.maxCount,
                    }
                  end
                  table.insert(inventory[item_name].allocation, {
                    storage = inv_name,
                    slot = slot,
                    count = transferred,
                  })
                  inventory[item_name].count = inventory[item_name].count + transferred
                  remaining_to_push = remaining_to_push - transferred
                  pushed = true
                end
              end
              if remaining_to_push == 0 then break end
            end
            if remaining_to_push == 0 then break end
          end

          if not pushed then break end -- No more space
        end
      end
    end
    table.insert(tasks, task)
  end

  -- Execute all item processing in parallel
  parallel.waitForAll(unpack(tasks))
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
