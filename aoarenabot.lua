-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
Game = Game or nil
InAction = InAction or false

Logs = Logs or {}

colors = {
  red = "\27[31m",
  green = "\27[32m",
  blue = "\27[34m",
  reset = "\27[0m",
  gray = "\27[90m"
}

function addLog(msg, text) -- Function definition commented for performance, can be used for debugging
  Logs[msg] = Logs[msg] or {}
  table.insert(Logs[msg], text)
end

function calculateDistance(x1, y1, x2, y2)
  return math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
end

function inRange(x1, y1, x2, y2, range)
  return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end
function findSafeRetreat(player, gameState)
  local directions = {
    Up = {x = 0, y = -1},
    Down = {x = 0, y = 1},
    Left = {x = -1, y = 0},
    Right = {x = 1, y = 0},
    UpRight = {x = 1, y = -1},
    UpLeft = {x = -1, y = -1},
    DownRight = {x = 1, y = 1},
    DownLeft = {x = -1, y = 1}
  }
  
  local safestDirection = "Stay"
  local maxDistanceToThreat = 0

  -- Evaluate each direction to find the one that maximizes distance from all other players.
  for dirName, dirVector in pairs(directions) do
    local newX = (player.x + dirVector.x + gameState.Width) % gameState.Width
    local newY = (player.y + dirVector.y + gameState.Height) % gameState.Height
    local minDistanceToAnyPlayer = math.huge

    -- Calculate the distance from the new position to all other players.
    for _, otherPlayer in pairs(gameState.Players) do
      if otherPlayer.id ~= player.id then
        local distance = calculateDistance(newX, newY, otherPlayer.x, otherPlayer.y)
        minDistanceToAnyPlayer = math.min(minDistanceToAnyPlayer, distance)
      end
    end

    -- Choose the direction that maximizes the minimum distance to any player.
    if minDistanceToAnyPlayer > maxDistanceToThreat then
      maxDistanceToThreat = minDistanceToAnyPlayer
      safestDirection = dirName
    end
  end

  return safestDirection
end

-- Decides the next action with a defensive strategy.
function decideNextAction()
  local player = LatestGameState.Players[ao.id]
  local targetInRange = false
  local safeDirection = "Stay"
  local minDistance = math.huge

  -- Check for players within attack range.
  for target, state in pairs(LatestGameState.Players) do
    if target ~= ao.id and inRange(player.x, player.y, state.x, state.y, 1) then
      targetInRange = true
      -- Calculate distance to potentially move away from the player.
      local distance = calculateDistance(player.x, player.y, state.x, state.y)
      if distance < minDistance then
        minDistance = distance
        safeDirection = getOppositeDirection(player.x, player.y, state.x, state.y)
      end
    end
  end

  -- If energy is low or a player is within range, move to a safer location.
  if player.energy <= 5 or targetInRange then
    print(colors.red .. "Moving to a safer location: " .. safeDirection .. colors.reset)
    ao.send({Target = Game, Action = "PlayerMove", Direction = safeDirection})
  else
    -- If no immediate threat and energy is sufficient, consider attacking.
    print(colors.red .. "No immediate threat detected. Holding position." .. colors.reset)
    -- Placeholder for potential strategic actions when safe.
  end
  InAction = false
end

-- Helper function to calculate the distance between two points.
function calculateDistance(x1, y1, x2, y2)
  return math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
end

-- Helper function to determine the opposite direction from a threat.
function getOppositeDirection(px, py, tx, ty)
  local dx = px - tx
  local dy = py - ty
  local directions = {
    Up = {x = 0, y = -1},
    Down = {x = 0, y = 1},
    Left = {x = -1, y = 0},
    Right = {x = 1, y = 0},
    UpRight = {x = 1, y = -1},
    UpLeft = {x = -1, y = -1},
    DownRight = {x = 1, y = 1},
    DownLeft = {x = -1, y = 1},
    Stay = {x = 0, y = 0}
  }
  -- Determine the best direction to move away from the threat.
  local bestDirection = "Stay"
  local maxDistance = 0
  for dir, vec in pairs(directions) do
    local newDistance = calculateDistance(px + vec.x, py + vec.y, tx, ty)
    if newDistance > maxDistance then
      maxDistance = newDistance
      bestDirection = dir
    end
  end
  return bestDirection
end
-- Handler to print game announcements and trigger game state updates.
Handlers.add(
  "PrintAnnouncements",
  Handlers.utils.hasMatchingTag("Action", "Announcement"),
  function (msg)
    if msg.Event == "Started-Waiting-Period" then
      ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
      InAction = true
      -- print("Getting game state...")
      ao.send({Target = Game, Action = "GetGameState"})
    elseif InAction then
      print("Previous action still in progress. Skipping.")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
  end
)

-- Handler to trigger game state updates.
Handlers.add(
  "GetGameStateOnTick",
  Handlers.utils.hasMatchingTag("Action", "Tick"),
  function ()
    if not InAction then
      InAction = true
      print(colors.gray .. "Getting game state..." .. colors.reset)
      ao.send({Target = Game, Action = "GetGameState"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
  "AutoPay",
  Handlers.utils.hasMatchingTag("Action", "AutoPay"),
  function (msg)
    print("Auto-paying confirmation fees.")
    ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1"})
  end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
  "UpdateGameState",
  Handlers.utils.hasMatchingTag("Action", "GameState"),
  function (msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("Game state updated. Print \'LatestGameState\' for detailed view.")
  end
)

-- Handler to decide the next best action.
Handlers.add(
  "decideNextAction",
  Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
  function ()
    if LatestGameState.GameMode ~= "Playing" then 
      InAction = false
      return 
    end
    print("Deciding next action.")
    decideNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
  end
)
Handlers.add(
  "ReturnAttack",
  Handlers.utils.hasMatchingTag("Action", "Hit"),
  function (msg)
    if not InAction then
      InAction = true
      local player = LatestGameState.Players[ao.id]
      local playerEnergy = player.energy
      local playerHealth = player.health

      if playerEnergy == nil then
        print(colors.red .. "Unable to read energy." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy."})
      elseif playerEnergy == 0 then
        print(colors.red .. "Player has insufficient energy." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Player has no energy."})
      else
        if playerHealth <= (100 / AverageMaxStrengthHitsToKill) then
          local safeDirection = findSafeRetreat(player, LatestGameState)
          print(colors.red .. "Health is low, retreating towards " .. safeDirection .. "." .. colors.reset)
          ao.send({Target = Game, Action = "PlayerMove", Direction = safeDirection})
        else
          print(colors.red .. "Health is sufficient, returning attack." .. colors.reset)
          ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(playerEnergy)})
        end
      end
      InAction = false
      ao.send({Target = ao.id, Action = "Tick"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)
