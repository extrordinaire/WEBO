-- storageManager.lua
-- Text-based program to:
--   (1) Send all items from an "entry barrel" to a network of storage containers
--   (2) Search for partial item matches, list them (by type and total count)
--   (3) Retrieve all or partial amounts of any matched item(s) into the barrel

-----------------------------
--     USER CONFIG
-----------------------------
local BARREL_NAME = "minecraft:barrel_0" -- Change if needed to match your setup

-----------------------------
--     SETUP
-----------------------------
local barrel = peripheral.wrap(BARREL_NAME)
if not barrel then
  error("Could not wrap barrel: " .. tostring(BARREL_NAME))
end

-- Find all other storage peripherals (that implement :list() and :size())
local storageList = {}
for _, name in ipairs(peripheral.getNames()) do
  if name ~= BARREL_NAME then
    local pType = peripheral.getType(name) or "unknown"
    local inv = peripheral.wrap(name)
    if inv and inv.list and inv.size then
      table.insert(storageList, inv)
      print("Found storage: " .. name .. " (" .. pType .. ")")
    end
  end
end

if #storageList == 0 then
  print("No storage chests found. Make sure they're connected via a modem.")
end

-----------------------------
--   SEND / RETRIEVE
-----------------------------

--- Sends all items from the barrel to the storages.
local function sendAllItems()
  local barrelSize = barrel.size()
  for slot = 1, barrelSize do
    local detail = barrel.getItemDetail(slot)
    if detail then
      local qty = detail.count
      -- Keep pushing until we've moved all items out of this slot
      if qty > 0 then
        for _, inv in ipairs(storageList) do
          qty = qty - barrel.pushItems(peripheral.getName(inv), slot, qty)
          if qty <= 0 then break end
        end
      end
    end
  end
end

--- Gathers (and returns) a table of all items matching `searchText`, grouped by item.name.
--- Each entry is { name=..., displayName=..., count=... } with total from all storages.
local function findMatches(searchText)
  local results = {}
  local lowerSearch = string.lower(searchText)

  for _, inv in ipairs(storageList) do
    local invSize = inv.size()
    for slot = 1, invSize do
      local detail = inv.getItemDetail(slot)
      if detail then
        -- Partial match check (name or displayName)
        local lowerName = string.lower(detail.name or "")
        local lowerDisp = string.lower(detail.displayName or "")
        if string.find(lowerName, lowerSearch) or string.find(lowerDisp, lowerSearch) then
          local key = detail.name
          if not results[key] then
            results[key] = {
              name        = detail.name,
              displayName = detail.displayName,
              count       = 0,
            }
          end
          results[key].count = results[key].count + detail.count
        end
      end
    end
  end

  return results
end

--- Retrieves up to `amount` of the item with name `itemName` from storages into the barrel.
--- Returns the total number actually retrieved.
local function retrieveItem(itemName, amount)
  local remaining = amount
  local retrieved = 0

  for _, inv in ipairs(storageList) do
    if remaining <= 0 then break end
    local invSize = inv.size()
    for slot = 1, invSize do
      if remaining <= 0 then break end
      local detail = inv.getItemDetail(slot)
      if detail and detail.name == itemName then
        local stackCount = detail.count
        -- The max we can pull from this slot
        local toPull = math.min(remaining, stackCount)
        local pushed = inv.pushItems(BARREL_NAME, slot, toPull)
        retrieved = retrieved + pushed
        remaining = remaining - pushed
      end
    end
  end

  return retrieved
end

--- Given a table of grouped results, let the user choose
---   A) retrieve ALL of those items
---   B) select one item to retrieve
--- And (optionally) specify how many to retrieve of that item.
local function chooseRetrieval(results)
  -- Convert results dict into a sorted list
  local sortedKeys = {}
  for k, _ in pairs(results) do
    table.insert(sortedKeys, k)
  end

  if #sortedKeys == 0 then
    print("No matching items found.")
    return
  end

  -- Sort by displayName
  table.sort(sortedKeys, function(a, b)
    return (results[a].displayName or "") < (results[b].displayName or "")
  end)

  print("Matched the following item types:")
  local indexMap = {}
  for i, key in ipairs(sortedKeys) do
    local r = results[key]
    print(string.format("%d) %s (%s) x%d",
      i, r.displayName, r.name, r.count))
    indexMap[i] = key
  end

  print("\n[A] Retrieve ALL of these item types (everything)")
  print("[Or enter a number 1-" .. #sortedKeys .. ", to choose one item type]")
  write("Choice: ")
  local choice = read()

  -- If user typed "A", retrieve ALL
  if choice:lower() == "a" then
    print("Retrieving ALL matches...")
    for _, key in ipairs(sortedKeys) do
      local r = results[key]
      local got = retrieveItem(key, r.count) -- attempt to retrieve entire count
      print(string.format("  Got %d of %s", got, r.displayName))
    end
    print("All retrievals complete.")
    return
  end

  -- Otherwise, parse as an index
  local idx = tonumber(choice)
  if not idx or not indexMap[idx] then
    print("Invalid input. Returning to main menu.")
    return
  end

  -- Retrieve a specific item
  local key = indexMap[idx]
  local info = results[key]
  print(string.format("Selected: %s (%s). Available: %d",
    info.displayName, info.name, info.count))
  write("How many do you want to retrieve? (up to " .. info.count .. "): ")
  local amtStr = read()
  local amt = tonumber(amtStr) or 0
  if amt < 1 then
    print("Invalid amount. Returning to main menu.")
    return
  end
  if amt > info.count then
    amt = info.count -- just cap it
  end

  local got = retrieveItem(key, amt)
  print(string.format("Retrieved %d of %s.", got, info.displayName))
end

-----------------------------
--   MAIN LOOP (Text UI)
-----------------------------
while true do
  print("\n--== Storage Manager ==--")
  print("[1] Send all from barrel to storage")
  print("[2] Search & retrieve items (partial match)")
  print("[q] Quit")
  write("Select an option: ")
  local choice = read()

  if choice == "1" then
    print("Sending all items from barrel to storage...")
    sendAllItems()
    print("Done.")
  elseif choice == "2" then
    write("Enter a search term (partial match): ")
    local term = read()
    local results = findMatches(term)
    chooseRetrieval(results)
  elseif choice == "q" or choice == "Q" then
    print("Quitting...")
    break
  else
    print("Invalid choice, please try again.")
  end
end
