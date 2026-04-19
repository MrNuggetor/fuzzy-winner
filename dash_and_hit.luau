-- Combat Ability System
-- Built as a complete, server-authoritative system for a Roblox combat experience
-- Uses metatables for the ability framework so we can easily extend it later with new moves
-- Everything is in one script as requested - no modules, no extra files
-- RemoteEvents handle input cleanly from client (Q for Dash, E for Uppercut)
-- Includes player data, per-ability cooldowns, and a simple stun status effect system
-- Physics-based movement and knockback to feel responsive and fair
-- By EnnyDaBat (Roblox: EnnyDaBat | Discord: nuggyzee | X: EnnyDaBat)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

-- Create RemoteEvents for client input (Q and E style actions)
-- We check if they already exist so the script can be restarted safely in Studio
local dashEvent = ReplicatedStorage:FindFirstChild("DashEvent")
if not dashEvent then
	dashEvent = Instance.new("RemoteEvent")
	dashEvent.Name = "DashEvent"
	dashEvent.Parent = ReplicatedStorage
end

local uppercutEvent = ReplicatedStorage:FindFirstChild("UppercutEvent")
if not uppercutEvent then
	uppercutEvent = Instance.new("RemoteEvent")
	uppercutEvent.Name = "UppercutEvent"
	uppercutEvent.Parent = ReplicatedStorage
end

-- Core constants for tuning - kept here so values are easy to tweak without hunting
local DASH_SPEED = 95
local DASH_DURATION = 0.35
local DASH_KNOCKBACK_POWER = 45
local DASH_HIT_RANGE = 6
local UPPERCUT_RADIUS = 12
local UPPERCUT_DAMAGE = 18
local UPPERCUT_LAUNCH_POWER = 65
local UPPERCUT_STUN_DURATION = 1.4
local DASH_COOLDOWN = 3
local UPPERCUT_COOLDOWN = 5.5

-- Player data storage - simple table per player
-- We store cooldowns and status effects here so each player has their own state
local playerData = {}

local function getOrCreatePlayerData(player)
	if not playerData[player] then
		playerData[player] = {
			cooldowns = {}, -- ability name -> last use time
			statusEffects = {
				stunEndTime = 0, -- timestamp when stun should end
			},
		}
	end
	return playerData[player]
end

-- Ability framework using metatables (OOP style without being overkill)
-- This base class lets every ability share the cooldown check logic
local Ability = {}
Ability.__index = Ability

function Ability.new(name, cooldownTime)
	local self = setmetatable({}, Ability)
	self.name = name
	self.cooldownTime = cooldownTime
	return self
end

function Ability:CanUse(player)
	local data = getOrCreatePlayerData(player)
	local lastUse = data.cooldowns[self.name] or 0
	return os.clock() - lastUse >= self.cooldownTime
end

function Ability:Use(player)
	if not self:CanUse(player) then
		return false
	end

	local data = getOrCreatePlayerData(player)
	data.cooldowns[self.name] = os.clock()
	self:Activate(player)
	return true
end

-- Dash ability - specific implementation
local DashAbility = setmetatable({}, Ability)
DashAbility.__index = DashAbility

function DashAbility.new()
	local self = Ability.new("Dash", DASH_COOLDOWN)
	setmetatable(self, DashAbility)
	return self
end

function DashAbility:Activate(player)
	performDash(player)
end

-- Uppercut ability - AOE launch + stun
local UppercutAbility = setmetatable({}, Ability)
UppercutAbility.__index = UppercutAbility

function UppercutAbility.new()
	local self = Ability.new("Uppercut", UPPERCUT_COOLDOWN)
	setmetatable(self, UppercutAbility)
	return self
end

function UppercutAbility:Activate(player)
	performUppercut(player)
end

-- Helper to apply knockback using physics (respects Roblox physics engine)
local function applyKnockback(rootPart, direction, power)
	if not rootPart or not rootPart.Parent then
		return
	end

	-- Add a bit of upward force so it feels more impactful
	local knockVec = direction * power + Vector3.new(0, 20, 0)
	rootPart.AssemblyLinearVelocity = knockVec
end

-- Status effect system - currently only stun but built to be expandable
-- We use an end timestamp instead of task.delay so overlapping stuns take the longest one
local function applyStun(player, duration)
	if not player then
		return
	end

	local data = getOrCreatePlayerData(player)
	local endTime = os.clock() + duration

	if endTime > (data.statusEffects.stunEndTime or 0) then
		data.statusEffects.stunEndTime = endTime
	end
end

-- Central status updater - runs every frame so we can cleanly manage WalkSpeed
local function updatePlayerStatuses()
	for player, data in pairs(playerData) do
		local character = player.Character
		if not character then
			continue
		end

		local humanoid = character:FindFirstChild("Humanoid")
		if not humanoid then
			continue
		end

		local isStunned = (data.statusEffects.stunEndTime or 0) > os.clock()

		if isStunned then
			if humanoid.WalkSpeed > 0 then
				humanoid.WalkSpeed = 0
			end
		else
			-- Only reset if it was set to 0 by us (preserves other scripts that might change speed)
			if humanoid.WalkSpeed == 0 then
				humanoid.WalkSpeed = 16
			end
		end
	end
end

-- Quick validation helper so we don't spam nil checks in every ability
local function validateCharacter(player)
	if not player or not player.Character then
		return nil, nil
	end

	local character = player.Character
	local humanoid = character:FindFirstChild("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not root or humanoid.Health <= 0 then
		return nil, nil
	end

	return character, root, humanoid
end

-- Get nearby humanoids for AOE (used by uppercut)
local function getNearbyHumanoids(centerPos, radius, excludeCharacter)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterDescendantsInstances = {excludeCharacter}
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.MaxParts = 50

	local parts = Workspace:GetPartBoundsInRadius(centerPos, radius, overlapParams)
	local hitHumanoids = {}

	for _, part in ipairs(parts) do
		local model = part.Parent
		local humanoid = model:FindFirstChild("Humanoid")
		local hitRoot = model:FindFirstChild("HumanoidRootPart")

		if humanoid and hitRoot and humanoid.Health > 0 and not hitHumanoids[humanoid] then
			hitHumanoids[humanoid] = hitRoot
		end
	end

	return hitHumanoids
end

-- Core dash logic - CFrame direction + physics velocity + hit detection
function performDash(player)
	local character, root, humanoid = validateCharacter(player)
	if not character or not root then
		return
	end

	local data = getOrCreatePlayerData(player)
	if data.statusEffects.stunEndTime and data.statusEffects.stunEndTime > os.clock() then
		return -- can't dash while stunned
	end

	-- Get forward direction from character's facing
	local moveDirection = root.CFrame.LookVector

	-- Create LinearVelocity for smooth physics-based dash
	local attachment = Instance.new("Attachment")
	attachment.Parent = root

	local linearVel = Instance.new("LinearVelocity")
	linearVel.Attachment0 = attachment
	linearVel.VectorVelocity = moveDirection * DASH_SPEED
	linearVel.MaxForce = 20000 -- strong enough to feel snappy
	linearVel.Parent = root

	-- Auto cleanup after dash duration
	Debris:AddItem(attachment, DASH_DURATION + 0.1)
	Debris:AddItem(linearVel, DASH_DURATION + 0.1)

	-- Hit detection loop during the dash (intermediate style - checks every frame)
	--Note: If the player hits a dummy or NPC, it'll not take damage and be knocked back
	task.spawn(function()
		local startTime = os.clock()
		while os.clock() - startTime < DASH_DURATION do
			for _, otherPlayer in ipairs(Players:GetPlayers()) do
				if otherPlayer == player then
					continue
				end

				local otherChar = otherPlayer.Character
				if not otherChar then
					continue
				end

				local otherRoot = otherChar:FindFirstChild("HumanoidRootPart")
				local otherHum = otherChar:FindFirstChild("Humanoid")

				if otherRoot and otherHum and otherHum.Health > 0 then
					local distance = (otherRoot.Position - root.Position).Magnitude
					if distance < DASH_HIT_RANGE then
						otherHum:TakeDamage(12)
						local hitDir = (otherRoot.Position - root.Position).Unit
						applyKnockback(otherRoot, hitDir, DASH_KNOCKBACK_POWER)
					end
				end
			end
			task.wait(0.05)
		end
	end)

	-- Optional debug for testing
	print(player.Name .. " used Dash")
end

-- Uppercut logic - AOE around player with launch, damage, and stun
function performUppercut(player)
	local character, root, humanoid = validateCharacter(player)
	if not character or not root then
		return
	end

	local data = getOrCreatePlayerData(player)
	if data.statusEffects.stunEndTime and data.statusEffects.stunEndTime > os.clock() then
		return -- can't use while stunned
	end

	local hitHumanoids = getNearbyHumanoids(root.Position, UPPERCUT_RADIUS, character)

	for hitHum, hitRoot in pairs(hitHumanoids) do
		hitHum:TakeDamage(UPPERCUT_DAMAGE)

		-- Launch upward with some random horizontal for variety
		local launchDir = Vector3.new(
			(math.random() - 0.5) * 15,
			UPPERCUT_LAUNCH_POWER,
			(math.random() - 0.5) * 15
		)
		applyKnockback(hitRoot, launchDir.Unit, UPPERCUT_LAUNCH_POWER)

		-- Apply stun to the victim
		local victimPlayer = Players:GetPlayerFromCharacter(hitHum.Parent)
		if victimPlayer then
			applyStun(victimPlayer, UPPERCUT_STUN_DURATION)
		end
	end

	-- Optional debug for testing
	print(player.Name .. " used Uppercut - hit a target(s)")
end

-- Player setup when they join
Players.PlayerAdded:Connect(function(player)
	getOrCreatePlayerData(player)

	player.CharacterAdded:Connect(function()
		-- Reset cooldowns and status when character respawns
		local data = getOrCreatePlayerData(player)
		data.cooldowns = {}
		data.statusEffects.stunEndTime = 0
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	playerData[player] = nil
end)

-- Connect the RemoteEvents for input
dashEvent.OnServerEvent:Connect(function(player)
	local dashAbility = DashAbility.new() -- we can recreate safely since it's lightweight
	dashAbility:Use(player)
end)

uppercutEvent.OnServerEvent:Connect(function(player)
	local uppercutAbility = UppercutAbility.new()
	uppercutAbility:Use(player)
end)

-- Start the status effect updater
RunService.Heartbeat:Connect(updatePlayerStatuses)

-- For demo/testing in a live place:
-- 1. Put this script in ServerScriptService
-- 2. Create a LocalScript inside StarterPlayerScripts called "AbilityInputHandler"
-- 3. Paste this into the LocalScript:
--    local ReplicatedStorage = game:GetService("ReplicatedStorage")
--    local UserInputService = game:GetService("UserInputService")
--    local dashEvent = ReplicatedStorage:WaitForChild("DashEvent")
--    local uppercutEvent = ReplicatedStorage:WaitForChild("UppercutEvent")
--
--    UserInputService.InputBegan:Connect(function(input, gameProcessed)
--        if gameProcessed then return end
--        if input.KeyCode == Enum.KeyCode.Q then
--            dashEvent:FireServer()
--        elseif input.KeyCode == Enum.KeyCode.E then
--            uppercutEvent:FireServer()
--        end
--    end)

--I've already done that for you 😁. You can use Q/E to test it in-game.
--
-- Drop a default character in the place and test Q/E in Play mode.
-- The system is now fully ready for combat testing.
