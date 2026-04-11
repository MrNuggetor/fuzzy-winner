--// Smart Kill Brick System

local brick = script.Parent
local debounce = {}

-- Settings
local DAMAGE = 100
local COOLDOWN = 2
local PUSH_FORCE = 50

-- Optional whitelist (players who won't be harmed)
local whitelist = {
    ["BuilderMan"] = true
}

-- Function to apply knockback
local function applyKnockback(character, hitPart)
    local root = character:FindFirstChild("HumanoidRootPart")
    if root then
        local direction = (root.Position - hitPart.Position).Unit
        root.Velocity = direction * PUSH_FORCE + Vector3.new(0, 25, 0)
    end
end

-- Main touch event
brick.Touched:Connect(function(hit)
    local character = hit.Parent
    local humanoid = character and character:FindFirstChild("Humanoid")

    if humanoid then
        local player = game.Players:GetPlayerFromCharacter(character)

        -- Ignore whitelisted players
        if player and whitelist[player.Name] then
            return
        end

        -- Debounce check
        if debounce[character] then return end
        debounce[character] = true

        -- Damage logic
        humanoid:TakeDamage(DAMAGE)

        -- Knockback effect
        applyKnockback(character, brick)

        -- Optional warning print
        print(character.Name .. " touched the danger brick!")

        -- Cooldown reset
        task.delay(COOLDOWN, function()
            debounce[character] = nil
        end)
    end
end)