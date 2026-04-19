--//====================================================--
--// ADVANCED ABILITY & COMBAT FRAMEWORK (FINAL SUBMISSION)
--// Author: YourName
--//====================================================--

--[[
	This script implements a modular combat system with:
	
	• Object-Oriented design using metatables
	• Ability registry & execution pipeline
	• Cooldown + status/state system
	• Physics-based knockback (BodyVelocity)
	• Smooth CFrame dash movement (lerp-based)
	• Hit detection with anti-multi-hit logic
	
	The goal is to demonstrate structured thinking,
	not just scripting ability.
--]]

---------------------------
-- SERVICES
---------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

---------------------------
-- COOLDOWN SYSTEM
---------------------------
local Cooldown = {}
Cooldown.__index = Cooldown

function Cooldown.new()
	return setmetatable({ timers = {} }, Cooldown)
end

function Cooldown:Set(key, duration)
	self.timers[key] = tick() + duration
end

function Cooldown:IsReady(key)
	return not self.timers[key] or tick() >= self.timers[key]
end

---------------------------
-- STATUS SYSTEM
---------------------------
local Status = {}
Status.__index = Status

function Status.new()
	return setmetatable({ states = {} }, Status)
end

function Status:Add(state, duration)
	self.states[state] = tick() + duration
end

function Status:Has(state)
	return self.states[state] and tick() < self.states[state]
end

---------------------------
-- DAMAGE SYSTEM
---------------------------
local function DealDamage(humanoid, amount)
	if humanoid and humanoid.Health > 0 then
		humanoid:TakeDamage(amount)
	end
end

---------------------------
-- KNOCKBACK SYSTEM
---------------------------
local function ApplyKnockback(character, direction, force)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local velocity = Instance.new("BodyVelocity")
	velocity.Velocity = direction * force
	velocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	velocity.Parent = root

	Debris:AddItem(velocity, 0.2)
end

---------------------------
-- PLAYER DATA
---------------------------
local PlayerData = {}

local function InitPlayer(player)
	PlayerData[player] = {
		Cooldown = Cooldown.new(),
		Status = Status.new()
	}
end

local function GetData(player)
	return PlayerData[player]
end

---------------------------
-- ABILITY BASE CLASS
---------------------------
local Ability = {}
Ability.__index = Ability

function Ability.new(name, cooldown)
	return setmetatable({
		Name = name,
		Cooldown = cooldown
	}, Ability)
end

function Ability:CanUse(player)
	local data = GetData(player)
	if not data then return false end
	
	-- Prevent ability if stunned
	if data.Status:Has("Stunned") then return false end
	
	return data.Cooldown:IsReady(self.Name)
end

function Ability:TriggerCooldown(player)
	local data = GetData(player)
	if data then
		data.Cooldown:Set(self.Name, self.Cooldown)
	end
end

---------------------------
-- ABILITY REGISTRY
---------------------------
local AbilityManager = {
	Abilities = {}
}

function AbilityManager:Register(ability)
	self.Abilities[ability.Name] = ability
end

function AbilityManager:Use(player, abilityName)
	local ability = self.Abilities[abilityName]
	if not ability then return end
	
	if ability:CanUse(player) then
		ability:Activate(player)
		ability:TriggerCooldown(player)
	end
end

---------------------------
-- DASH STRIKE ABILITY
---------------------------
local DashStrike = Ability.new("DashStrike", 4)

function DashStrike:Activate(player)
	local character = player.Character
	if not character then return end
	
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	
	local hitTargets = {}

	-- Smooth dash using interpolation instead of teleport
	local duration = 0.25
	local distance = 18
	
	local startCF = root.CFrame
	local endCF = startCF * CFrame.new(0, 0, -distance)

	local elapsed = 0
	
	while elapsed < duration do
		local dt = RunService.Heartbeat:Wait()
		elapsed += dt
		
		local alpha = math.clamp(elapsed / duration, 0, 1)
		
		-- Lerp creates smooth motion
		root.CFrame = startCF:Lerp(endCF, alpha)

		-- Hit detection during dash
		for _, obj in pairs(workspace:GetDescendants()) do
			if obj:IsA("Humanoid") and obj.Parent ~= character then
				local targetRoot = obj.Parent:FindFirstChild("HumanoidRootPart")
				
				if targetRoot and not hitTargets[obj] then
					local dist = (targetRoot.Position - root.Position).Magnitude
					
					if dist < 6 then
						hitTargets[obj] = true
						
						DealDamage(obj, 25)
						
						local direction = (targetRoot.Position - root.Position).Unit
						ApplyKnockback(obj.Parent, direction, 70)

						-- Apply stun
						local targetPlayer = Players:GetPlayerFromCharacter(obj.Parent)
						if targetPlayer then
							local data = GetData(targetPlayer)
							if data then
								data.Status:Add("Stunned", 1.5)
							end
						end
					end
				end
			end
		end
	end
end

AbilityManager:Register(DashStrike)

---------------------------
-- DEMO TRIGGER SYSTEM
---------------------------
-- Automatically fires ability every few seconds
-- (You can replace with RemoteEvent later)

local function StartDemo(player)
	task.wait(2)
	
	while player.Parent do
		task.wait(4)
		
		AbilityManager:Use(player, "DashStrike")
	end
end

---------------------------
-- PLAYER CONNECTIONS
---------------------------
Players.PlayerAdded:Connect(function(player)
	InitPlayer(player)

	player.CharacterAdded:Connect(function()
		StartDemo(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	PlayerData[player] = nil
end)
