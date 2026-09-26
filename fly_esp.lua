-- fly_esp.lua — Fly + Noclip + Player ESP com PastaLib
local Pasta = loadstring(game:HttpGet("https://raw.githubusercontent.com/Ryanabcraft/PastaUI/main/PastaLib.lua"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

-- desliga instancia anterior (re-execucao limpa)
if _G.PastaFlyEsp then
	pcall(function()
		_G.PastaFlyEsp.Fly:Set(false)
	end)
	pcall(function()
		_G.PastaFlyEsp.Esp:Set(false)
	end)
end

local function getChar()
	local c = LocalPlayer.Character
	if not c then
		return nil, nil
	end
	return c, c:FindFirstChild("HumanoidRootPart"), c:FindFirstChildOfClass("Humanoid")
end

-- =============================================================================
-- FLY
-- =============================================================================
local Fly = { on = false, speed = 60, conn = nil, gyro = nil, vel = nil, debugVec = nil }
local FlyHandle = nil

local function clearFlyParts()
	if Fly.conn then
		Fly.conn:Disconnect()
		Fly.conn = nil
	end
	if Fly.gyro then
		pcall(function()
			Fly.gyro:Destroy()
		end)
		Fly.gyro = nil
	end
	if Fly.vel then
		pcall(function()
			Fly.vel:Destroy()
		end)
		Fly.vel = nil
	end
end

local function readKeys(cam)
	local dir = Vector3.zero
	local fwd = cam.CFrame.LookVector
	local right = cam.CFrame.RightVector
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		dir = dir + fwd
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		dir = dir - fwd
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		dir = dir + right
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		dir = dir - right
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.E) or UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		dir = dir + Vector3.new(0, 1, 0)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.Q) then
		dir = dir + Vector3.new(0, -1, 0)
	end
	return dir
end

local function flyStep()
	local _, hrp = getChar()
	local cam = workspace.CurrentCamera
	if not hrp or not cam or not Fly.vel or not Fly.gyro then
		return
	end
	local dir = Fly.debugVec or readKeys(cam)
	if dir.Magnitude > 0.01 then
		Fly.vel.Velocity = dir.Unit * Fly.speed
	else
		Fly.vel.Velocity = Vector3.zero
	end
	hrp.RotVelocity = Vector3.zero
	Fly.gyro.CFrame = cam.CFrame
end

local function setFly(on)
	Fly.on = on
	clearFlyParts()
	local _, hrp, hum = getChar()
	if on then
		if not (hrp and hum) then
			if FlyHandle then
				FlyHandle:Set(false)
			end
			return
		end
		hum.PlatformStand = true
		local gyro = Instance.new("BodyGyro")
		gyro.P = 9000
		gyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
		gyro.CFrame = hrp.CFrame
		gyro.Parent = hrp
		local vel = Instance.new("BodyVelocity")
		vel.MaxForce = Vector3.new(9e9, 9e9, 9e9)
		vel.Velocity = Vector3.zero
		vel.Parent = hrp
		Fly.gyro = gyro
		Fly.vel = vel
		Fly.conn = RunService.Heartbeat:Connect(function()
			if Fly.on then
				flyStep()
			end
		end)
	else
		if hum then
			hum.PlatformStand = false
		end
		if hrp then
			pcall(function()
				hrp.Velocity = Vector3.zero
				hrp.RotVelocity = Vector3.zero
			end)
		end
	end
end

-- =============================================================================
-- NOCLIP
-- =============================================================================
local Noclip = { on = false, conn = nil }

local function setNoclip(on)
	Noclip.on = on
	if Noclip.conn then
		Noclip.conn:Disconnect()
		Noclip.conn = nil
	end
	if on then
		Noclip.conn = RunService.Stepped:Connect(function()
			local c = LocalPlayer.Character
			if c then
				for _, p in ipairs(c:GetDescendants()) do
					if p:IsA("BasePart") then
						p.CanCollide = false
					end
				end
			end
		end)
	else
		local c = LocalPlayer.Character
		if c then
			for _, p in ipairs(c:GetDescendants()) do
				if p:IsA("BasePart") then
					p.CanCollide = true
				end
			end
		end
	end
end

-- =============================================================================
-- ESP
-- =============================================================================
local ESP = { on = false, names = true, chams = true, maxDist = 2000, items = {}, conns = {} }

local function clearESPPlayer(plr)
	local item = ESP.items[plr]
	if item then
		pcall(function()
			if item.Gui then
				item.Gui:Destroy()
			end
		end)
		pcall(function()
			if item.Hl then
				item.Hl:Destroy()
			end
		end)
		ESP.items[plr] = nil
	end
	if plr and plr.Character then
		local old = plr.Character:FindFirstChild("PastaESP_HL")
		if old then
			pcall(function()
				old:Destroy()
			end)
		end
	end
end

local function buildESP(plr)
	clearESPPlayer(plr)
	if plr == LocalPlayer then
		return
	end
	local c = plr.Character
	if not c then
		return
	end
	local item = {}
	if ESP.names then
		local head = c:FindFirstChild("Head") or c:FindFirstChild("HumanoidRootPart")
		if head then
			local gui = Instance.new("BillboardGui")
			gui.Name = "PastaESP"
			gui.Size = UDim2.new(0, 200, 0, 36)
			gui.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
			gui.AlwaysOnTop = true
			gui.Adornee = head
			gui.Parent = head
			local lbl = Instance.new("TextLabel")
			lbl.Size = UDim2.new(1, 0, 1, 0)
			lbl.BackgroundTransparency = 1
			lbl.Font = Enum.Font.GothamBold
			lbl.TextSize = 13
			lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
			lbl.TextStrokeTransparency = 0
			lbl.Text = plr.Name
			lbl.Parent = gui
			item.Gui = gui
			item.Label = lbl
		end
	end
	if ESP.chams then
		local hl = Instance.new("Highlight")
		hl.Name = "PastaESP_HL"
		hl.Adornee = c
		hl.FillColor = Color3.fromRGB(246, 92, 82)
		hl.OutlineColor = Color3.fromRGB(255, 255, 255)
		hl.FillTransparency = 0.6
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Parent = c
		item.Hl = hl
	end
	ESP.items[plr] = item
end

local function refreshAllESP()
	for _, plr in ipairs(Players:GetPlayers()) do
		buildESP(plr)
	end
end

local function disconnectESP()
	for _, conn in ipairs(ESP.conns) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	table.clear(ESP.conns)
end

local function setESP(on)
	ESP.on = on
	disconnectESP()
	if on then
		refreshAllESP()
		table.insert(
			ESP.conns,
			Players.PlayerAdded:Connect(function(plr)
				table.insert(
					ESP.conns,
					plr.CharacterAdded:Connect(function()
						task.wait(0.5)
						if ESP.on then
							buildESP(plr)
						end
					end)
				)
				task.wait(0.5)
				if ESP.on then
					buildESP(plr)
				end
			end)
		)
		table.insert(
			ESP.conns,
			Players.PlayerRemoving:Connect(function(plr)
				clearESPPlayer(plr)
			end)
		)
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LocalPlayer then
				table.insert(
					ESP.conns,
					plr.CharacterAdded:Connect(function()
						task.wait(0.5)
						if ESP.on then
							buildESP(plr)
						end
					end)
				)
			end
		end
		task.spawn(function()
			while ESP.on do
				local _, myHrp = getChar()
				for _, plr in ipairs(Players:GetPlayers()) do
					if plr ~= LocalPlayer and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") and ESP.items[plr] == nil then
						buildESP(plr)
					end
				end
				for plr, item in pairs(ESP.items) do
					pcall(function()
						local c = plr.Character
						local root = c and c:FindFirstChild("HumanoidRootPart")
						if not (plr.Parent and c and root and myHrp) then
							if item.Gui then
								item.Gui.Enabled = false
							end
							return
						end
						local dist = (root.Position - myHrp.Position).Magnitude
						if item.Gui then
							item.Gui.Enabled = dist <= ESP.maxDist
							if item.Label then
								item.Label.Text = plr.Name .. " [" .. math.floor(dist) .. "m]"
							end
						end
					end)
				end
				task.wait(0.2)
			end
		end)
	else
		local leftover = {}
		for plr in pairs(ESP.items) do
			table.insert(leftover, plr)
		end
		for _, plr in ipairs(leftover) do
			clearESPPlayer(plr)
		end
	end
end

LocalPlayer.CharacterAdded:Connect(function()
	task.wait(0.5)
	if Fly.on then
		setFly(true)
	end
end)

-- =============================================================================
-- UI
-- =============================================================================
local Window = Pasta:CreateWindow({ Name = "pasta", Footer = "fly + esp", ShowHUD = true })

local Move = Window:AddTab({ Name = "Movement", Icon = "Movement", Category = "Features" })
local Vis = Window:AddTab({ Name = "Visuals", Icon = "Visuals", Category = "Features" })

local flyCard = Move:AddCard({ Title = "Fly", Column = 1 })
FlyHandle = flyCard:AddToggle({ Name = "Fly", Description = "WASD + Space/Q", Keybind = "F", Callback = setFly })
flyCard:AddSlider({
	Name = "Fly Speed",
	Min = 10,
	Max = 250,
	Default = 60,
	Increment = 5,
	Suffix = " sps",
	Callback = function(v)
		Fly.speed = v
	end,
})
flyCard:AddToggle({ Name = "Noclip", Callback = setNoclip })

local espCard = Vis:AddCard({ Title = "Player ESP", Column = 1 })
local EspHandle = espCard:AddToggle({ Name = "Enable ESP", Callback = setESP })
espCard:AddToggle({
	Name = "Names",
	Default = true,
	Callback = function(v)
		ESP.names = v
		if ESP.on then
			refreshAllESP()
		end
	end,
})
espCard:AddToggle({
	Name = "Chams",
	Default = true,
	Callback = function(v)
		ESP.chams = v
		if ESP.on then
			refreshAllESP()
		end
	end,
})
espCard:AddSlider({
	Name = "Max Distance",
	Min = 100,
	Max = 9000,
	Default = 2000,
	Increment = 100,
	Suffix = " m",
	Callback = function(v)
		ESP.maxDist = v
	end,
})

_G.PastaFlyEsp = {
	Window = Window,
	Fly = FlyHandle,
	Esp = EspHandle,
	SetFly = setFly,
	SetESP = setESP,
	DebugFly = function(vec, secs)
		Fly.debugVec = vec
		task.delay(secs or 1, function()
			Fly.debugVec = nil
		end)
	end,
}

print("[FLY] pronto")
