-- Pasta UI Framework v2.0.0
-- Face: pasta / nursultan (790x490, sidebar, cards, HUD pills)
-- Motor: ideias da Axiom (Signal/State/Cleanup/Animation/Theme/Config/Handles)
--
-- Uso:
--   local Pasta = loadstring(game:HttpGet(".../PastaLib.lua"))()
--   local Window = Pasta:CreateWindow({ Name = "pasta", Logo = "rbxassetid://139568612294283", Scale = 1 })
--   local Tab = Window:AddTab({ Name = "Combat", Icon = "rbxassetid://7734053426", Category = "Features" })
--   local Card = Tab:AddCard({ Title = "Fighting", Column = 1 })
--   Card:AddToggle({ Name = "Aim Assist", Default = false, Flag = "aim_assist", Callback = function(v) print(v) end })

local Pasta = {}
Pasta.Version = "2.0.0"
Pasta.Windows = {}
Pasta._Destroyed = false

-- =============================================================================
-- Services
-- =============================================================================
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer

-- =============================================================================
-- Utility
-- =============================================================================
local Utility = {}

function Utility.Create(className, props)
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for k, v in pairs(props) do
			if k ~= "Parent" then
				inst[k] = v
			else
				parent = v
			end
		end
	end
	if parent ~= nil then
		inst.Parent = parent
	end
	return inst
end

function Utility.Corner(parent, radius)
	return Utility.Create("UICorner", { CornerRadius = radius or UDim.new(0, 8), Parent = parent })
end

function Utility.Stroke(parent, color, thickness, transparency)
	return Utility.Create("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

function Utility.Padding(parent, top, bottom, left, right)
	return Utility.Create("UIPadding", {
		PaddingTop = UDim.new(0, top or 12),
		PaddingBottom = UDim.new(0, bottom or 12),
		PaddingLeft = UDim.new(0, left or 12),
		PaddingRight = UDim.new(0, right or 12),
		Parent = parent,
	})
end

function Utility.SafeCallback(cb, ...)
	if not cb then
		return
	end
	local ok, err = pcall(cb, ...)
	if not ok then
		warn("[Pasta] callback error:", err)
	end
end

-- =============================================================================
-- Signal
-- =============================================================================
local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _listeners = {}, _destroyed = false }, Signal)
end

function Signal:Connect(cb)
	assert(type(cb) == "function", "Signal callback must be a function")
	assert(not self._destroyed, "Cannot connect to destroyed Signal")
	local conn = { Connected = true, _owner = self }
	function conn:Disconnect()
		if not self.Connected then
			return
		end
		self.Connected = false
		if self._owner then
			self._owner._listeners[self] = nil
		end
		self._owner = nil
	end
	self._listeners[conn] = cb
	return conn
end

function Signal:Fire(...)
	if self._destroyed then
		return
	end
	for conn, cb in pairs(self._listeners) do
		if conn.Connected then
			task.spawn(function(...)
				if conn.Connected and not self._destroyed then
					cb(...)
				end
			end, ...)
		end
	end
end

function Signal:Destroy()
	self._destroyed = true
	for conn in pairs(self._listeners) do
		conn.Connected = false
		conn._owner = nil
	end
	table.clear(self._listeners)
end

-- =============================================================================
-- State
-- =============================================================================
local State = {}
State.__index = State

function State.new(initial)
	return setmetatable({ _value = initial, Changed = Signal.new(), _destroyed = false }, State)
end

function State:Get()
	return self._value
end

function State:Set(value)
	if self._destroyed then
		return
	end
	if self._value == value then
		return
	end
	local prev = self._value
	self._value = value
	self.Changed:Fire(value, prev)
end

function State:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	self.Changed:Destroy()
	self._value = nil
end

-- =============================================================================
-- Cleanup
-- =============================================================================
local Cleanup = {}
Cleanup.__index = Cleanup

function Cleanup.new()
	return setmetatable({ _tasks = {}, _destroyed = false }, Cleanup)
end

function Cleanup:Add(item)
	if item == nil then
		return nil
	end
	if self._destroyed then
		self:_Clean(item)
		return item
	end
	table.insert(self._tasks, item)
	return item
end

function Cleanup:_Clean(item)
	local kind = typeof(item)
	if kind == "RBXScriptConnection" then
		if item.Connected then
			item:Disconnect()
		end
	elseif kind == "Instance" then
		if item:IsA("TweenBase") then
			pcall(function()
				item:Cancel()
			end)
		end
		pcall(function()
			item:Destroy()
		end)
	elseif kind == "thread" then
		pcall(task.cancel, item)
	elseif kind == "function" then
		pcall(item)
	elseif type(item) == "table" then
		if item.Disconnect then
			pcall(function()
				item:Disconnect()
			end)
		elseif item.Cancel then
			pcall(function()
				item:Cancel()
			end)
		elseif item.Destroy then
			pcall(function()
				item:Destroy()
			end)
		end
	end
end

function Cleanup:IsAlive()
	return not self._destroyed
end

function Cleanup:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	for i = #self._tasks, 1, -1 do
		pcall(function()
			self:_Clean(self._tasks[i])
		end)
		self._tasks[i] = nil
	end
end

-- =============================================================================
-- Animation (tween com cancel: nunca empilha tween no mesmo objeto)
-- =============================================================================
local Animation = {}
local _activeTweens = setmetatable({}, { __mode = "k" })

function Animation.Tween(inst, props, duration, style, direction)
	if not inst or not inst.Parent then
		return nil
	end
	local prev = _activeTweens[inst]
	if prev then
		pcall(function()
			prev:Cancel()
		end)
	end
	local tween = TweenService:Create(
		inst,
		TweenInfo.new(duration or 0.2, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		props
	)
	_activeTweens[inst] = tween
	tween.Completed:Connect(function()
		if _activeTweens[inst] == tween then
			_activeTweens[inst] = nil
		end
	end)
	tween:Play()
	return tween
end

function Animation.Cancel(inst)
	local tween = _activeTweens[inst]
	if tween then
		pcall(function()
			tween:Cancel()
		end)
		_activeTweens[inst] = nil
	end
end

-- =============================================================================
-- Icons (tabela pasta + passthrough de asset id)
-- =============================================================================
local PASTA_ICONS = {
	Search = "rbxassetid://7733911828",
	Chevron = "rbxassetid://7733717447",
	More = "rbxassetid://7734021300",
	Menu = "rbxassetid://7733993211",
	Combat = "rbxassetid://7734053426",
	Movement = "rbxassetid://7733799901",
	Visuals = "rbxassetid://7733774602",
	Player = "rbxassetid://7733954760",
	Misc = "rbxassetid://7734056411",
	Presets = "rbxassetid://7733964719",
	AutoBuy = "rbxassetid://7733942651",
	Accounts = "rbxassetid://7733765307",
	User = "rbxassetid://7733954760",
	Chart = "rbxassetid://7733749837",
	Clock = "rbxassetid://7733734762",
	Compass = "rbxassetid://7733720755",
	Signal = "rbxassetid://7734058495",
	Radar = "rbxassetid://7734053426",
	Speed = "rbxassetid://7733799901",
	Info = "rbxassetid://7733765398",
}

local Icons = {}

function Icons.Get(nameOrId)
	if nameOrId == nil or nameOrId == "" then
		return PASTA_ICONS.Info
	end
	if typeof(nameOrId) ~= "string" then
		return PASTA_ICONS.Info
	end
	if PASTA_ICONS[nameOrId] then
		return PASTA_ICONS[nameOrId]
	end
	local lower = string.lower(nameOrId)
	for k, v in pairs(PASTA_ICONS) do
		if string.lower(k) == lower then
			return v
		end
	end
	if string.find(nameOrId, "rbxasset", 1, true) then
		return nameOrId
	end
	if tonumber(nameOrId) then
		return "rbxassetid://" .. tostring(nameOrId)
	end
	return PASTA_ICONS.Info
end

function Icons.Exists(name)
	if type(name) ~= "string" then
		return false
	end
	if PASTA_ICONS[name] then
		return true
	end
	local lower = string.lower(name)
	for k in pairs(PASTA_ICONS) do
		if string.lower(k) == lower then
			return true
		end
	end
	return false
end

Pasta.Icons = Icons

-- =============================================================================
-- Theme (tokens pasta + binding vivo)
-- =============================================================================
local PASTA_DEFAULTS = {
	Background = Color3.fromRGB(12, 9, 11),
	CardBg = Color3.fromRGB(18, 13, 16),
	PillBg = Color3.fromRGB(16, 12, 14),
	SidebarActive = Color3.fromRGB(27, 16, 19),
	Border = Color3.fromRGB(36, 24, 28),
	BorderActive = Color3.fromRGB(90, 36, 42),
	Accent = Color3.fromRGB(246, 92, 82),
	AccentSoft = Color3.fromRGB(255, 165, 155),
	AccentDark = Color3.fromRGB(130, 40, 42),
	TextPrimary = Color3.fromRGB(235, 235, 235),
	TextMuted = Color3.fromRGB(120, 110, 115),
	TextDim = Color3.fromRGB(72, 64, 68),
	Divider = Color3.fromRGB(48, 36, 40),
	BadgeBg = Color3.fromRGB(25, 18, 22),
	ToggleOff = Color3.fromRGB(36, 28, 32),
	KnobOff = Color3.fromRGB(78, 68, 73),
	KnobOn = Color3.fromRGB(255, 255, 255),
	Success = Color3.fromRGB(80, 220, 140),
	Warning = Color3.fromRGB(255, 190, 76),
	Danger = Color3.fromRGB(255, 91, 121),
}

local function shallowCopy(t)
	local out = {}
	for k, v in pairs(t) do
		out[k] = v
	end
	return out
end

local ThemeManager = {}
ThemeManager.__index = ThemeManager

function ThemeManager.new(initial)
	local self = setmetatable({ Current = shallowCopy(initial or PASTA_DEFAULTS), Changed = Signal.new(), _bindings = {} }, ThemeManager)
	return self
end

function ThemeManager:Bind(inst, prop, token, transform)
	local binding = { Instance = inst, Property = prop, Token = token, Transform = transform }
	table.insert(self._bindings, binding)
	binding.Connection = inst.Destroying:Connect(function()
		for i, item in ipairs(self._bindings) do
			if item == binding then
				table.remove(self._bindings, i)
				break
			end
		end
		binding.Instance = nil
	end)
	local value = self.Current[token]
	if transform then
		value = transform(value, self.Current)
	end
	if value ~= nil then
		pcall(function()
			inst[prop] = value
		end)
	end
	return binding
end

function ThemeManager:Apply(next)
	assert(type(next) == "table", "Unknown Pasta theme")
	self.Current = shallowCopy(next)
	for i = #self._bindings, 1, -1 do
		local b = self._bindings[i]
		if not b.Instance or not b.Instance.Parent then
			if b.Connection then
				b.Connection:Disconnect()
			end
			table.remove(self._bindings, i)
		else
			local value = next[b.Token]
			if b.Transform then
				value = b.Transform(value, next)
			end
			if value ~= nil then
				pcall(function()
					b.Instance[b.Property] = value
				end)
			end
		end
	end
	self.Changed:Fire(self.Current)
end

function ThemeManager:Destroy()
	for _, b in ipairs(self._bindings) do
		if b.Connection then
			b.Connection:Disconnect()
		end
		b.Instance = nil
	end
	table.clear(self._bindings)
	self.Changed:Destroy()
end

Pasta.Theme = ThemeManager.new(PASTA_DEFAULTS)

function Pasta:CreateTheme(overrides)
	local t = shallowCopy(PASTA_DEFAULTS)
	if type(overrides) == "table" then
		for k, v in pairs(overrides) do
			t[k] = v
		end
	end
	return t
end

function Pasta:SetTheme(theme)
	if self._Destroyed then
		return
	end
	assert(type(theme) == "table", "Pasta:SetTheme espera tabela (use Pasta:CreateTheme)")
	self.Theme:Apply(theme)
end

-- =============================================================================
-- Config (memoria + filesystem opcional, igual Axiom)
-- =============================================================================
local Config = {}
Config.__index = Config

function Config.new(namespace)
	return setmetatable({
		Namespace = namespace or "PastaUI",
		Values = {},
		Profiles = {},
		AutoSave = false,
		AutoSaveProfile = "default",
		_connections = {},
		_pendingRevision = nil,
		_destroyed = false,
	}, Config)
end

function Config:Register(key, control)
	if self._destroyed then
		return control
	end
	if not key or not control then
		return control
	end
	if self._connections[key] then
		self._connections[key]:Disconnect()
	end
	self.Values[key] = control
	if control.Changed then
		self._connections[key] = control.Changed:Connect(function()
			if self.AutoSave then
				local rev = os.clock()
				self._pendingRevision = rev
				task.delay(0.35, function()
					if not self._destroyed and self._pendingRevision == rev then
						self:Save(self.AutoSaveProfile)
					end
				end)
			end
		end)
	end
	if control._OnDestroy then
		control:_OnDestroy(function()
			if self.Values[key] == control then
				self.Values[key] = nil
				if self._connections[key] then
					self._connections[key]:Disconnect()
					self._connections[key] = nil
				end
			end
		end)
	end
	return control
end

function Config:Serialize()
	local out = {}
	for key, control in pairs(self.Values) do
		local ok, value = pcall(function()
			return control:Get()
		end)
		if ok then
			if typeof(value) == "Color3" then
				value = { __type = "Color3", r = value.R, g = value.G, b = value.B }
			elseif typeof(value) == "EnumItem" then
				value = { __type = "EnumItem", enum = tostring(value.EnumType), name = value.Name }
			end
			out[key] = value
		end
	end
	return out
end

function Config:LoadTable(data)
	for key, value in pairs(data or {}) do
		local control = self.Values[key]
		if control then
			if type(value) == "table" and value.__type == "Color3" then
				value = Color3.new(value.r or 0, value.g or 0, value.b or 0)
			elseif type(value) == "table" and value.__type == "EnumItem" then
				local ok, item = pcall(function()
					return Enum[value.enum][value.name]
				end)
				if ok and item ~= nil then
					value = item
				else
					control = nil
				end
			end
			if control then
				pcall(function()
					control:Set(value)
				end)
			end
		end
	end
end

function Config:Save(profile)
	if self._destroyed then
		return nil
	end
	profile = profile or "default"
	local data = self:Serialize()
	self.Profiles[profile] = data
	if writefile then
		if makefolder then
			pcall(makefolder, self.Namespace)
		end
		pcall(writefile, self.Namespace .. "/" .. profile .. ".json", HttpService:JSONEncode(data))
	end
	return data
end

function Config:Load(profile)
	if self._destroyed then
		return false
	end
	profile = profile or "default"
	local data = self.Profiles[profile]
	if not data and readfile and isfile and isfile(self.Namespace .. "/" .. profile .. ".json") then
		local ok, result = pcall(function()
			return HttpService:JSONDecode(readfile(self.Namespace .. "/" .. profile .. ".json"))
		end)
		if ok then
			data = result
		end
	end
	self:LoadTable(data or {})
	return data ~= nil
end

function Config:EnableAutoSave(enabled, profile)
	self.AutoSave = enabled ~= false
	if profile then
		self.AutoSaveProfile = profile
	end
end

function Config:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	self.AutoSave = false
	self._pendingRevision = nil
	for key, conn in pairs(self._connections) do
		conn:Disconnect()
		self._connections[key] = nil
	end
	table.clear(self.Values)
	table.clear(self.Profiles)
end

Pasta.Config = Config.new("PastaUI")

-- =============================================================================
-- Handles
-- =============================================================================
local function makeHandle(root, state, cleanup)
	cleanup = cleanup or Cleanup.new()
	local handle = {
		Instance = root,
		Changed = state and state.Changed or nil,
		_cleanup = cleanup,
		_destroyed = false,
		_destroyCallbacks = {},
	}
	local function finalize()
		if handle._destroyed then
			return
		end
		handle._destroyed = true
		for _, cb in ipairs(handle._destroyCallbacks) do
			pcall(cb)
		end
		table.clear(handle._destroyCallbacks)
		cleanup:Destroy()
		if state then
			state:Destroy()
		end
		handle.Changed = nil
		handle.Instance = nil
	end
	cleanup:Add(root.Destroying:Connect(finalize))
	function handle:Get()
		if not self._destroyed and state then
			return state:Get()
		end
		return nil
	end
	function handle:Set(value)
		if not self._destroyed and state then
			state:Set(value)
		end
	end
	function handle:SetVisible(visible)
		if not self._destroyed and root.Parent then
			root.Visible = visible
		end
	end
	function handle:OnChanged(cb)
		if state and not self._destroyed then
			return state.Changed:Connect(cb)
		end
		return nil
	end
	function handle:_OnDestroy(cb)
		if self._destroyed then
			pcall(cb)
		else
			table.insert(self._destroyCallbacks, cb)
		end
	end
	function handle:Destroy()
		if self._destroyed then
			return
		end
		finalize()
		pcall(function()
			root:Destroy()
		end)
	end
	return handle
end

local function makeStaticHandle(root, cleanup)
	cleanup = cleanup or Cleanup.new()
	local handle = { Instance = root, _cleanup = cleanup, _destroyed = false, _destroyCallbacks = {} }
	local function finalize()
		if handle._destroyed then
			return
		end
		handle._destroyed = true
		for _, cb in ipairs(handle._destroyCallbacks) do
			pcall(cb)
		end
		table.clear(handle._destroyCallbacks)
		cleanup:Destroy()
		handle.Instance = nil
	end
	cleanup:Add(root.Destroying:Connect(finalize))
	function handle:SetVisible(visible)
		if not self._destroyed and root.Parent then
			root.Visible = visible
		end
	end
	function handle:_OnDestroy(cb)
		if self._destroyed then
			pcall(cb)
		else
			table.insert(self._destroyCallbacks, cb)
		end
	end
	function handle:Destroy()
		if self._destroyed then
			return
		end
		finalize()
		pcall(function()
			root:Destroy()
		end)
	end
	return handle
end

-- =============================================================================
-- Root / Toasts
-- =============================================================================
local function resolveParent()
	if gethui then
		local ok, result = pcall(gethui)
		if ok and result then
			return result
		end
	end
	if LocalPlayer then
		local ok, gui = pcall(function()
			return LocalPlayer:WaitForChild("PlayerGui", 5)
		end)
		if ok and gui then
			return gui
		end
	end
	return CoreGui
end

local function ensureRoot()
	if Pasta.Gui and Pasta.Gui.Parent then
		return Pasta.Gui
	end
	Pasta.Gui = nil
	Pasta.Toasts = nil
	local host = resolveParent()
	local stale = host and host:FindFirstChild("PastaFramework")
	if stale then
		pcall(function()
			stale:Destroy()
		end)
	end
	if CoreGui:FindFirstChild("PastaFramework") then
		pcall(function()
			CoreGui.PastaFramework:Destroy()
		end)
	end
	local gui = Utility.Create("ScreenGui", {
		Name = "PastaFramework",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
	})
	gui.Parent = resolveParent()
	Pasta.Gui = gui
	local toasts = Utility.Create("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -20),
		Size = UDim2.fromOffset(340, 500),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Utility.Create("UIListLayout", {
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 10),
		Parent = toasts,
	})
	Pasta.Toasts = toasts
	return gui
end

function Pasta:Notify(options)
	if self._Destroyed then
		return nil
	end
	options = options or {}
	ensureRoot()
	local t = self.Theme.Current
	local toast = Utility.Create("Frame", {
		Size = UDim2.fromOffset(0, 82),
		BackgroundColor3 = t.CardBg,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = self.Toasts,
	})
	Utility.Corner(toast, UDim.new(0, 10))
	Utility.Stroke(toast, t.Border, 1)
	Utility.Create("Frame", {
		Size = UDim2.fromOffset(4, 82),
		BackgroundColor3 = options.Color or t.Accent,
		BorderSizePixel = 0,
		Parent = toast,
	})
	Utility.Create("TextLabel", {
		Position = UDim2.fromOffset(18, 12),
		Size = UDim2.new(1, -32, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = options.Title or "pasta",
		TextColor3 = t.TextPrimary,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = toast,
	})
	Utility.Create("TextLabel", {
		Position = UDim2.fromOffset(18, 35),
		Size = UDim2.new(1, -32, 0, 34),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = options.Description or "",
		TextColor3 = t.TextMuted,
		TextSize = 11,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = toast,
	})
	Animation.Tween(toast, { Size = UDim2.fromOffset(340, 82) }, 0.3)
	task.delay(options.Duration or 4, function()
		if self._Destroyed or not toast.Parent then
			return
		end
		Animation.Tween(toast, { Size = UDim2.fromOffset(0, 82) }, 0.28)
		task.delay(0.3, function()
			if toast.Parent then
				toast:Destroy()
			end
		end)
	end)
	return toast
end

-- =============================================================================
-- Componentes (cara pasta, comportamento Axiom)
-- =============================================================================

-- Linha base pasta: titulo + descricao a esquerda, controle a direita.
local function buildRowBase(win, card, name, description, height)
	local t = win._theme.Current
	local row = Utility.Create("Frame", {
		Name = name,
		Size = UDim2.new(1, 0, 0, height or 30),
		BackgroundTransparency = 1,
		Parent = card._frame,
	})
	local textBox = Utility.Create("Frame", {
		Size = UDim2.new(1, -84, 1, 0),
		BackgroundTransparency = 1,
		Parent = row,
	})
	local title = Utility.Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1,
		Text = name,
		Font = Enum.Font.GothamMedium,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = textBox,
	})
	win._theme:Bind(title, "TextColor3", "TextPrimary")
	local descLabel = nil
	if description then
		descLabel = Utility.Create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 12),
			Position = UDim2.new(0, 0, 0, 14),
			BackgroundTransparency = 1,
			Text = description,
			Font = Enum.Font.Gotham,
			TextSize = 9,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = textBox,
		})
		win._theme:Bind(descLabel, "TextColor3", "TextMuted")
	else
		title.Position = UDim2.new(0, 0, 0.5, -7)
	end
	table.insert(card._rows, row)
	table.insert(win._searchRows, { Frame = row, Name = string.lower(name .. " " .. (description or "")), Card = card, Tab = card._tab })
	return row, title
end

local function keyNameOf(value)
	if typeof(value) == "EnumItem" then
		return value.Name
	elseif type(value) == "string" and value ~= "" then
		return value
	end
	return "-"
end

local function keyValueOf(value)
	if typeof(value) == "EnumItem" and value.EnumType == Enum.KeyCode then
		return value
	end
	if type(value) == "string" and value ~= "" and value ~= "-" then
		local ok = pcall(function()
			return Enum.KeyCode[value]
		end)
		if ok and Enum.KeyCode[value] then
			return Enum.KeyCode[value]
		end
	end
	return nil
end

-- ---- Toggle ---------------------------------------------------------------
local function buildToggle(win, card, opts)
	opts = opts or {}
	local cleanup = Cleanup.new()
	local state = State.new(opts.Default == true)
	local row = buildRowBase(win, card, opts.Name or "Toggle", opts.Description or opts.Desc, (opts.Description or opts.Desc) and 30 or 22)
	local t = win._theme.Current

	local badge = Utility.Create("TextLabel", {
		Size = UDim2.new(0, 20, 0, 14),
		Position = UDim2.new(1, -78, 0.5, -7),
		Text = opts.Keybind and keyNameOf(opts.Keybind) or "",
		Visible = opts.Keybind ~= nil,
		Font = Enum.Font.GothamBold,
		TextSize = 8.5,
		Parent = row,
	})
	win._theme:Bind(badge, "BackgroundColor3", "BadgeBg")
	win._theme:Bind(badge, "TextColor3", "TextMuted")
	Utility.Corner(badge, UDim.new(0, 3))
	local badgeStroke = Utility.Stroke(badge, t.Border, 1)
	win._theme:Bind(badgeStroke, "Color", "Border")

	local optBtn = Utility.Create("ImageButton", {
		Size = UDim2.new(0, 13, 0, 13),
		Position = UDim2.new(1, -52, 0.5, -6.5),
		BackgroundTransparency = 1,
		Image = Icons.Get("More"),
		Parent = row,
	})
	win._theme:Bind(optBtn, "ImageColor3", "TextDim")

	local switch = Utility.Create("TextButton", {
		Size = UDim2.new(0, 32, 0, 16),
		Position = UDim2.new(1, -32, 0.5, -8),
		Text = "",
		AutoButtonColor = false,
		Parent = row,
	})
	Utility.Corner(switch, UDim.new(1, 0))
	local knob = Utility.Create("Frame", {
		Size = UDim2.new(0, 12, 0, 12),
		BorderSizePixel = 0,
		Parent = switch,
	})
	Utility.Corner(knob, UDim.new(1, 0))

	local function render(value)
		local th = win._theme.Current
		Animation.Tween(switch, { BackgroundColor3 = value and th.Accent or th.ToggleOff }, 0.18)
		Animation.Tween(knob, {
			Position = value and UDim2.new(1, -14, 0.5, -6) or UDim2.new(0, 2, 0.5, -6),
			BackgroundColor3 = value and th.KnobOn or th.KnobOff,
		}, 0.18)
	end

	-- keybind interno do toggle (badge + "..." entram em listen, tecla alterna o toggle)
	local boundKey = keyValueOf(opts.Keybind)
	local listening = false

	local function setBadge()
		if boundKey then
			badge.Visible = true
			badge.Text = boundKey.Name
		elseif listening then
			badge.Visible = true
			badge.Text = "..."
		else
			badge.Visible = false
			badge.Text = ""
		end
	end

	cleanup:Add(state.Changed:Connect(function(value)
		if cleanup:IsAlive() then
			render(value)
			Utility.SafeCallback(opts.Callback, value)
		end
	end))
	cleanup:Add(switch.MouseButton1Click:Connect(function()
		if cleanup:IsAlive() then
			state:Set(not state:Get())
		end
	end))
	cleanup:Add(optBtn.MouseEnter:Connect(function()
		Animation.Tween(optBtn, { ImageColor3 = win._theme.Current.TextPrimary }, 0.15)
	end))
	cleanup:Add(optBtn.MouseLeave:Connect(function()
		Animation.Tween(optBtn, { ImageColor3 = win._theme.Current.TextDim }, 0.15)
	end))

	local function startListen()
		listening = true
		setBadge()
		badge.TextColor3 = win._theme.Current.Accent
	end
	local function stopListen()
		listening = false
		badge.TextColor3 = win._theme.Current.TextMuted
		setBadge()
	end
	cleanup:Add(optBtn.MouseButton1Click:Connect(startListen))
	cleanup:Add(badge.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			startListen()
		end
	end))
	cleanup:Add(UserInputService.InputBegan:Connect(function(input, processed)
		if not cleanup:IsAlive() then
			return
		end
		if listening then
			if input.UserInputType == Enum.UserInputType.Keyboard then
				if input.KeyCode.Name == "Escape" or input.KeyCode.Name == "Unknown" then
					boundKey = nil
				else
					boundKey = input.KeyCode
				end
				stopListen()
			end
			return
		end
		if not processed and boundKey and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == boundKey then
			state:Set(not state:Get())
		end
	end))
	cleanup:Add(win._theme.Changed:Connect(function()
		if cleanup:IsAlive() then
			render(state:Get())
		end
	end))
	cleanup:Add(function()
		Animation.Cancel(switch)
		Animation.Cancel(knob)
	end)

	render(state:Get())
	setBadge()

	local handle = makeHandle(row, state, cleanup)
	function handle:GetKeybind()
		return boundKey
	end
	function handle:SetKeybind(value)
		boundKey = keyValueOf(value)
		setBadge()
	end
	if opts.Flag then
		Pasta.Config:Register(opts.Flag, handle)
	end
	return handle
end

-- ---- Slider ---------------------------------------------------------------
local function buildSlider(win, card, opts)
	opts = opts or {}
	local cleanup = Cleanup.new()
	local min = tonumber(opts.Min) or 0
	local max = tonumber(opts.Max) or 100
	if max < min then
		min, max = max, min
	end
	local step = tonumber(opts.Increment) or 1
	local suffix = opts.Suffix or ""
	local function snap(v)
		local s = math.clamp(v, min, max)
		if step > 0 then
			s = min + math.floor((s - min) / step + 0.5) * step
		end
		return math.clamp(s, min, max)
	end
	local state = State.new(snap(tonumber(opts.Default) or min))
	local row = buildRowBase(win, card, opts.Name or "Slider", opts.Description or opts.Desc, 44)

	local valueLabel = Utility.Create("TextLabel", {
		Size = UDim2.new(0, 60, 0, 14),
		Position = UDim2.new(1, -64, 0, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})
	win._theme:Bind(valueLabel, "TextColor3", "TextPrimary")

	local track = Utility.Create("TextButton", {
		Size = UDim2.new(1, 0, 0, 6),
		Position = UDim2.new(0, 0, 1, -12),
		Text = "",
		AutoButtonColor = false,
		Parent = row,
	})
	win._theme:Bind(track, "BackgroundColor3", "ToggleOff")
	Utility.Corner(track, UDim.new(1, 0))
	local fill = Utility.Create("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BorderSizePixel = 0,
		Parent = track,
	})
	win._theme:Bind(fill, "BackgroundColor3", "Accent")
	Utility.Corner(fill, UDim.new(1, 0))
	local knob = Utility.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(0, 12, 0, 12),
		Position = UDim2.new(0, 0, 0.5, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		Parent = track,
	})
	Utility.Corner(knob, UDim.new(1, 0))

	local function textOf(v)
		if step >= 1 then
			return string.format("%d%s", math.floor(v + 0.5), suffix)
		end
		return string.format("%s%s", tostring(v), suffix)
	end

	local function render(value)
		local ratio = (max == min) and 0 or (value - min) / (max - min)
		valueLabel.Text = textOf(value)
		fill.Size = UDim2.new(ratio, 0, 1, 0)
		knob.Position = UDim2.new(ratio, 0, 0.5, 0)
	end

	local dragging = false
	local function updateFromX(x)
		local pos = track.AbsolutePosition.X
		local size = math.max(1, track.AbsoluteSize.X)
		state:Set(snap(min + math.clamp((x - pos) / size, 0, 1) * (max - min)))
	end
	cleanup:Add(track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			updateFromX(input.Position.X)
		end
	end))
	cleanup:Add(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			updateFromX(input.Position.X)
		end
	end))
	cleanup:Add(UserInputService.InputEnded:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
		end
	end))
	cleanup:Add(state.Changed:Connect(function(value)
		if cleanup:IsAlive() then
			render(value)
			Utility.SafeCallback(opts.Callback, value)
		end
	end))
	cleanup:Add(function()
		dragging = false
	end)

	render(state:Get())
	local handle = makeHandle(row, state, cleanup)
	if opts.Flag then
		Pasta.Config:Register(opts.Flag, handle)
	end
	return handle
end

-- ---- Button ---------------------------------------------------------------
local function buildButton(win, card, opts)
	opts = opts or {}
	local cleanup = Cleanup.new()
	local t = win._theme.Current
	local btn = Utility.Create("TextButton", {
		Name = opts.Name or "Button",
		Size = UDim2.new(1, 0, 0, 30),
		Text = "",
		AutoButtonColor = false,
		Parent = card._frame,
	})
	win._theme:Bind(btn, "BackgroundColor3", "CardBg")
	Utility.Corner(btn, UDim.new(0, 6))
	local stroke = Utility.Stroke(btn, t.Border, 1)
	win._theme:Bind(stroke, "Color", "Border")
	local label = Utility.Create("TextLabel", {
		Size = UDim2.new(1, -16, 1, 0),
		Position = UDim2.new(0, 8, 0, 0),
		BackgroundTransparency = 1,
		Text = opts.Name or "Button",
		Font = Enum.Font.GothamMedium,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = btn,
	})
	win._theme:Bind(label, "TextColor3", "TextPrimary")
	table.insert(card._rows, btn)
	table.insert(win._searchRows, { Frame = btn, Name = string.lower(opts.Name or "button"), Card = card, Tab = card._tab })

	cleanup:Add(btn.MouseEnter:Connect(function()
		Animation.Tween(stroke, { Color = win._theme.Current.BorderActive }, 0.15)
		Animation.Tween(label, { TextColor3 = win._theme.Current.Accent }, 0.15)
	end))
	cleanup:Add(btn.MouseLeave:Connect(function()
		Animation.Tween(stroke, { Color = win._theme.Current.Border }, 0.15)
		Animation.Tween(label, { TextColor3 = win._theme.Current.TextPrimary }, 0.15)
	end))
	cleanup:Add(btn.MouseButton1Click:Connect(function()
		if cleanup:IsAlive() then
			Utility.SafeCallback(opts.Callback)
		end
	end))
	return makeStaticHandle(btn, cleanup)
end

-- ---- Dropdown (popup preso no Main: nao clipa no scroll) -------------------
local function buildDropdown(win, card, opts)
	opts = opts or {}
	local cleanup = Cleanup.new()
	local options = opts.Options or {}
	local multi = opts.Multi == true
	local state
	if multi then
		local init = {}
		if type(opts.Default) == "table" then
			for _, v in ipairs(opts.Default) do
				init[tostring(v)] = true
			end
		end
		state = State.new(init)
	else
		state = State.new(opts.Default ~= nil and tostring(opts.Default) or tostring(options[1] or "-"))
	end

	local row = buildRowBase(win, card, opts.Name or "Dropdown", opts.Description or opts.Desc, 30)
	local preview = Utility.Create("TextButton", {
		Size = UDim2.new(0, 110, 0, 20),
		Position = UDim2.new(1, -110, 0.5, -10),
		Text = "",
		AutoButtonColor = false,
		Parent = row,
	})
	win._theme:Bind(preview, "BackgroundColor3", "BadgeBg")
	Utility.Corner(preview, UDim.new(0, 5))
	local pStroke = Utility.Stroke(preview, win._theme.Current.Border, 1)
	win._theme:Bind(pStroke, "Color", "Border")
	local pLabel = Utility.Create("TextLabel", {
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.new(0, 8, 0, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = preview,
	})
	win._theme:Bind(pLabel, "TextColor3", "TextPrimary")
	local chev = Utility.Create("ImageLabel", {
		Size = UDim2.new(0, 11, 0, 11),
		Position = UDim2.new(1, -16, 0.5, -5.5),
		BackgroundTransparency = 1,
		Image = Icons.Get("Chevron"),
		Parent = preview,
	})
	win._theme:Bind(chev, "ImageColor3", "Accent")

	local popup = nil
	local function closePopup()
		if popup then
			popup:Destroy()
			popup = nil
		end
	end
	cleanup:Add(closePopup)

	local function currentText()
		local v = state:Get()
		if multi then
			local list = {}
			for _, opt in ipairs(options) do
				if v[tostring(opt)] then
					table.insert(list, tostring(opt))
				end
			end
			if #list == 0 then
				return "-"
			end
			return table.concat(list, ", ")
		end
		return tostring(v)
	end

	local function render()
		pLabel.Text = currentText()
	end

	local function openPopup()
		if popup then
			closePopup()
			return
		end
		local main = win._main
		local absPos = preview.AbsolutePosition
		local mainPos = main.AbsolutePosition
		local rel = absPos - mainPos
		local listH = math.clamp(#options * 26 + 8, 34, 150)
		popup = Utility.Create("Frame", {
			Name = "DropdownPopup",
			Position = UDim2.new(0, rel.X + preview.AbsoluteSize.X - 140, 0, rel.Y + preview.AbsoluteSize.Y + 4),
			Size = UDim2.new(0, 140, 0, listH),
			ZIndex = 60,
			Parent = main,
		})
		win._theme:Bind(popup, "BackgroundColor3", "CardBg")
		Utility.Corner(popup, UDim.new(0, 6))
		local s = Utility.Stroke(popup, win._theme.Current.Border, 1)
		win._theme:Bind(s, "Color", "Border")
		local scroll = Utility.Create("ScrollingFrame", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			ScrollBarThickness = 0,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			ZIndex = 61,
			Parent = popup,
		})
		Utility.Padding(scroll, 4, 4, 5, 5)
		Utility.Create("UIListLayout", { Padding = UDim.new(0, 1), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
		for _, opt in ipairs(options) do
			local name = tostring(opt)
			local item = Utility.Create("TextButton", {
				Size = UDim2.new(1, 0, 0, 24),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				ZIndex = 62,
				Parent = scroll,
			})
			local dot = nil
			if multi then
				dot = Utility.Create("Frame", {
					Size = UDim2.new(0, 8, 0, 8),
					Position = UDim2.new(0, 4, 0.5, -4),
					BorderSizePixel = 0,
					ZIndex = 63,
					Parent = item,
				})
				Utility.Corner(dot, UDim.new(1, 0))
			end
			local l = Utility.Create("TextLabel", {
				Size = UDim2.new(1, multi and -20 or -8, 1, 0),
				Position = UDim2.new(0, multi and 18 or 4, 0, 0),
				BackgroundTransparency = 1,
				Text = name,
				Font = Enum.Font.GothamMedium,
				TextSize = 10.5,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 63,
				Parent = item,
			})
			local function refreshItem()
				local v = state:Get()
				local selected = multi and v[name] or tostring(v) == name
				l.TextColor3 = selected and win._theme.Current.Accent or win._theme.Current.TextPrimary
				if dot then
					dot.BackgroundColor3 = selected and win._theme.Current.Accent or win._theme.Current.ToggleOff
				end
			end
			refreshItem()
			item.MouseEnter:Connect(function()
				l.TextColor3 = win._theme.Current.Accent
			end)
			item.MouseLeave:Connect(refreshItem)
			item.MouseButton1Click:Connect(function()
				if multi then
					local v = shallowCopy(state:Get())
					v[name] = not v[name] and true or nil
					state:Set(v)
				else
					state:Set(name)
					closePopup()
				end
				refreshItem()
			end)
		end
	end

	cleanup:Add(preview.MouseButton1Click:Connect(openPopup))
	cleanup:Add(UserInputService.InputBegan:Connect(function(input)
		if popup and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			local aPos, aSize = popup.AbsolutePosition, popup.AbsoluteSize
			local bPos, bSize = preview.AbsolutePosition, preview.AbsoluteSize
			local inPopup = pos.X >= aPos.X and pos.X <= aPos.X + aSize.X and pos.Y >= aPos.Y and pos.Y <= aPos.Y + aSize.Y
			local inBtn = pos.X >= bPos.X and pos.X <= bPos.X + bSize.X and pos.Y >= bPos.Y and pos.Y <= bPos.Y + bSize.Y
			if not inPopup and not inBtn then
				closePopup()
			end
		end
	end))
	cleanup:Add(state.Changed:Connect(function(value)
		if cleanup:IsAlive() then
			render()
			if multi then
				local list = {}
				for _, opt in ipairs(options) do
					if value[tostring(opt)] then
						table.insert(list, tostring(opt))
					end
				end
				Utility.SafeCallback(opts.Callback, list)
			else
				Utility.SafeCallback(opts.Callback, value)
			end
		end
	end))

	render()
	local handle = makeHandle(row, state, cleanup)
	if opts.Flag then
		Pasta.Config:Register(opts.Flag, handle)
	end
	return handle
end

-- ---- Keybind standalone ----------------------------------------------------
local function buildKeybind(win, card, opts)
	opts = opts or {}
	local cleanup = Cleanup.new()
	local state = State.new(keyValueOf(opts.Default))
	local row = buildRowBase(win, card, opts.Name or "Keybind", opts.Description or opts.Desc, 26)

	local badgeBtn = Utility.Create("TextButton", {
		Size = UDim2.new(0, 64, 0, 20),
		Position = UDim2.new(1, -64, 0.5, -10),
		Text = "",
		AutoButtonColor = false,
		Parent = row,
	})
	win._theme:Bind(badgeBtn, "BackgroundColor3", "BadgeBg")
	Utility.Corner(badgeBtn, UDim.new(0, 5))
	local bStroke = Utility.Stroke(badgeBtn, win._theme.Current.Border, 1)
	win._theme:Bind(bStroke, "Color", "Border")
	local bLabel = Utility.Create("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 10,
		Parent = badgeBtn,
	})
	win._theme:Bind(bLabel, "TextColor3", "TextMuted")

	local listening = false
	local function render()
		local v = state:Get()
		bLabel.Text = listening and "..." or (v and v.Name or "-")
	end

	cleanup:Add(badgeBtn.MouseButton1Click:Connect(function()
		listening = true
		render()
	end))
	cleanup:Add(UserInputService.InputBegan:Connect(function(input, processed)
		if not cleanup:IsAlive() then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		if listening then
			if input.KeyCode.Name == "Escape" or input.KeyCode.Name == "Unknown" then
				state:Set(nil)
			else
				state:Set(input.KeyCode)
			end
			listening = false
			return
		end
		local v = state:Get()
		if not processed and v and input.KeyCode == v then
			Utility.SafeCallback(opts.Callback, v)
		end
	end))
	cleanup:Add(state.Changed:Connect(function(value)
		if cleanup:IsAlive() then
			render()
			Utility.SafeCallback(opts.Callback, value)
		end
	end))

	render()
	local handle = makeHandle(row, state, cleanup)
	function handle:SetKey(value)
		state:Set(keyValueOf(value))
	end
	if opts.Flag then
		Pasta.Config:Register(opts.Flag, handle)
	end
	return handle
end

-- ---- Label -----------------------------------------------------------------
local function buildLabel(win, card, opts)
	opts = opts or {}
	local cleanup = Cleanup.new()
	local text = opts.Text or opts.Name or ""
	local label = Utility.Create("TextLabel", {
		Name = "Label",
		Size = UDim2.new(1, 0, 0, 14),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = text,
		TextWrapped = true,
		Font = Enum.Font.Gotham,
		TextSize = opts.TextSize or 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card._frame,
	})
	win._theme:Bind(label, "TextColor3", opts.Muted == false and "TextPrimary" or "TextMuted")
	table.insert(card._rows, label)
	table.insert(win._searchRows, { Frame = label, Name = string.lower(text), Card = card, Tab = card._tab })
	return makeStaticHandle(label, cleanup)
end

-- =============================================================================
-- Card / Tab
-- =============================================================================
local function buildCard(win, tab, opts)
	opts = opts or {}
	local t = win._theme.Current
	local parentCol
	if (opts.Column or tab._nextCol) == 1 then
		parentCol = tab._col1
	else
		parentCol = tab._col2
	end
	tab._nextCol = (tab._nextCol == 1) and 2 or 1

	local frame = Utility.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		Parent = parentCol,
	})
	win._theme:Bind(frame, "BackgroundColor3", "CardBg")
	Utility.Corner(frame, UDim.new(0, 8))
	local stroke = Utility.Stroke(frame, t.Border, 1)
	win._theme:Bind(stroke, "Color", "Border")
	Utility.Padding(frame, 11, 13, 12, 12)
	Utility.Create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = frame })

	local header = Utility.Create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		LayoutOrder = 0,
		Parent = frame,
	})
	local title = Utility.Create("TextLabel", {
		Size = UDim2.new(1, -20, 1, 0),
		BackgroundTransparency = 1,
		Text = opts.Title or opts.Name or "Section",
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})
	win._theme:Bind(title, "TextColor3", "TextPrimary")
	local chevHit = Utility.Create("TextButton", {
		Name = "CollapseHit",
		Size = UDim2.new(0, 30, 1, 0),
		Position = UDim2.new(1, -30, 0, 0),
		BackgroundTransparency = 1,
		Text = "",
		Parent = header,
	})
	local chev = Utility.Create("ImageLabel", {
		Size = UDim2.new(0, 12, 0, 12),
		Position = UDim2.new(0.5, -6, 0.5, -6),
		BackgroundTransparency = 1,
		Image = Icons.Get("Chevron"),
		Parent = chevHit,
	})
	win._theme:Bind(chev, "ImageColor3", "Accent")

	local card = { _frame = frame, _rows = {}, _tab = tab, _win = win, _collapsed = false, Title = opts.Title or opts.Name or "Section" }
	table.insert(win._cards, { Frame = frame, Rows = card._rows, Tab = tab, Card = card })

	local function setCardCollapsed(v)
		card._collapsed = v
		for _, r in ipairs(card._rows) do
			r.Visible = not v
		end
		Animation.Tween(chev, { Rotation = v and 180 or 0 }, 0.2)
	end
	card._setCollapsed = setCardCollapsed
	function card:SetCollapsed(v)
		setCardCollapsed(v ~= false)
	end
	win._cleanup:Add(chevHit.MouseButton1Click:Connect(function()
		setCardCollapsed(not card._collapsed)
	end))
	table.insert(tab._cards, card)

	function card:AddToggle(o)
		return buildToggle(win, card, o)
	end
	function card:AddSlider(o)
		return buildSlider(win, card, o)
	end
	function card:AddButton(o)
		return buildButton(win, card, o)
	end
	function card:AddDropdown(o)
		return buildDropdown(win, card, o)
	end
	function card:AddKeybind(o)
		return buildKeybind(win, card, o)
	end
	function card:AddLabel(o)
		return buildLabel(win, card, o)
	end
	return card
end

-- =============================================================================
-- HUD (pills pasta, update com throttle)
-- =============================================================================
local function buildHUD(win, opts)
	opts = opts or {}
	local cleanup = Cleanup.new()
	local gui = ensureRoot()
	local container = Utility.Create("Frame", {
		Name = "PastaHUD",
		Size = UDim2.new(0, 600, 0, 50),
		Position = UDim2.new(0, 16, 0, 48),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Utility.Create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
		Parent = container,
	})
	win._hudScale = Utility.Create("UIScale", { Parent = container })

	local function row(name, height, order)
		local r = Utility.Create("Frame", {
			Name = name,
			Size = UDim2.new(1, 0, 0, height),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = container,
		})
		Utility.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 5),
			Parent = r,
		})
		return r
	end

	local function pill(parent, order)
		local p = Utility.Create("Frame", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			LayoutOrder = order,
			BorderSizePixel = 0,
			Parent = parent,
		})
		win._theme:Bind(p, "BackgroundColor3", "PillBg")
		Utility.Corner(p, UDim.new(0, 5))
		local s = Utility.Stroke(p, win._theme.Current.Border, 1)
		win._theme:Bind(s, "Color", "Border")
		Utility.Padding(p, 0, 0, 6, 6)
		Utility.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 5),
			Parent = p,
		})
		return p
	end

	local function divider(parent, order)
		local d = Utility.Create("Frame", {
			Size = UDim2.new(0, 1, 0, 10),
			BorderSizePixel = 0,
			LayoutOrder = order,
			Parent = parent,
		})
		win._theme:Bind(d, "BackgroundColor3", "Divider")
	end

	local function text(parent, str, order)
		local l = Utility.Create("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = str,
			Font = Enum.Font.GothamMedium,
			TextSize = 10.5,
			LayoutOrder = order,
			Parent = parent,
		})
		win._theme:Bind(l, "TextColor3", "TextPrimary")
		return l
	end

	local function icon(parent, id, order)
		local i = Utility.Create("ImageLabel", {
			Size = UDim2.new(0, 11, 0, 11),
			BackgroundTransparency = 1,
			Image = Icons.Get(id),
			ScaleType = Enum.ScaleType.Fit,
			LayoutOrder = order,
			Parent = parent,
		})
		win._theme:Bind(i, "ImageColor3", "Accent")
		return i
	end

	local topRow = row("TopRow", 22, 1)
	local bottomRow = row("BottomRow", 22, 2)

	local brandPill = pill(topRow, 1)
	local logoWrap = Utility.Create("Frame", {
		Size = UDim2.new(0, 20, 0, 20),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = brandPill,
	})
	local halo = Utility.Create("ImageLabel", {
		Size = UDim2.new(2, 0, 2, 0),
		Position = UDim2.new(-0.5, 0, -0.5, 0),
		BackgroundTransparency = 1,
		Image = "rbxassetid://5028857084",
		ImageTransparency = 0.65,
		ZIndex = 1,
		Parent = logoWrap,
	})
	win._theme:Bind(halo, "ImageColor3", "Accent")
	local brandLogo = Utility.Create("ImageLabel", {
		Size = UDim2.new(1.35, 0, 1.35, 0),
		Position = UDim2.new(-0.175, 0, -0.175, 0),
		BackgroundTransparency = 1,
		Image = opts.Logo or "rbxassetid://139568612294283",
		ScaleType = Enum.ScaleType.Fit,
		ImageColor3 = Color3.fromRGB(255, 255, 255),
		ZIndex = 2,
		Parent = logoWrap,
	})
	local logoGrad = Utility.Create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.0, win._theme.Current.AccentSoft),
			ColorSequenceKeypoint.new(0.45, win._theme.Current.Accent),
			ColorSequenceKeypoint.new(1.0, Color3.fromRGB(165, 32, 42)),
		}),
		Rotation = -35,
		Parent = brandLogo,
	})
	divider(brandPill, 2)
	local brandText = text(brandPill, opts.Brand or "pasta", 3)
	Utility.Create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.0, win._theme.Current.AccentSoft),
			ColorSequenceKeypoint.new(1.0, win._theme.Current.Accent),
		}),
		Parent = brandText,
	})

	local statsPill = pill(topRow, 2)
	icon(statsPill, "User", 1)
	text(statsPill, string.lower(LocalPlayer.Name), 2)
	divider(statsPill, 3)
	icon(statsPill, "Chart", 4)
	local fpsLabel = text(statsPill, "0 Fps", 5)
	divider(statsPill, 6)
	icon(statsPill, "Clock", 7)
	local timeLabel = text(statsPill, "00:00:00", 8)

	local posPill = pill(bottomRow, 1)
	icon(posPill, "Compass", 1)
	divider(posPill, 2)
	local posLabel = text(posPill, "0, 0, 0", 3)

	local pingPill = pill(bottomRow, 2)
	icon(pingPill, "Signal", 1)
	divider(pingPill, 2)
	local pingLabel = text(pingPill, "0 Ping", 3)

	local tickPill = pill(bottomRow, 3)
	icon(tickPill, "Radar", 1)
	divider(tickPill, 2)
	local tickLabel = text(tickPill, "20.0 Ticks", 3)

	local speedPill = pill(bottomRow, 4)
	icon(speedPill, "Speed", 1)
	divider(speedPill, 2)
	local speedLabel = text(speedPill, "0.0 Bps", 3)

	-- throttle: fps/time 1s, resto 0.25s (antigo fazia tudo todo frame)
	local fpsCount, fpsClock = 0, os.clock()
	local slowAccum, lastPos, lastPosClock = 0, Vector3.zero, os.clock()
	cleanup:Add(RunService.RenderStepped:Connect(function(dt)
		if not container.Parent then
			return
		end
		fpsCount = fpsCount + 1
		local now = os.clock()
		if now - fpsClock >= 1 then
			fpsLabel.Text = string.format("%d Fps", fpsCount)
			fpsCount = 0
			fpsClock = now
			timeLabel.Text = os.date("%H:%M:%S")
		end
		slowAccum = slowAccum + dt
		if slowAccum < 0.25 then
			return
		end
		slowAccum = 0
		local ok, ping = pcall(function()
			return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
		end)
		if ok and ping then
			pingLabel.Text = string.format("%d Ping", math.floor(ping))
		end
		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local p = hrp.Position
			posLabel.Text = string.format("%d, %d, %d", math.floor(p.X), math.floor(p.Y), math.floor(p.Z))
			local deltaT = now - lastPosClock
			if deltaT > 0 then
				local dist = (Vector3.new(p.X, 0, p.Z) - Vector3.new(lastPos.X, 0, lastPos.Z)).Magnitude
				speedLabel.Text = string.format("%.1f Bps", dist / math.max(deltaT, 0.001))
				lastPos = p
				lastPosClock = now
			end
		else
			posLabel.Text = "0, 0, 0"
			speedLabel.Text = "0.0 Bps"
		end
	end))

	local hud = {}
	function hud:SetVisible(v)
		container.Visible = v
	end
	function hud:Destroy()
		cleanup:Destroy()
		pcall(function()
			container:Destroy()
		end)
	end
	hud._cleanup = cleanup
	hud.Instance = container
	return hud
end

-- =============================================================================
-- Window
-- =============================================================================
local function centerPosition(size)
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
	return UDim2.new(0.5, -math.floor(size.X.Offset / 2), 0.5, -math.floor(size.Y.Offset / 2)), vp
end

function Pasta:CreateWindow(opts)
	assert(not self._Destroyed, "Pasta foi destruida")
	opts = opts or {}
	ensureRoot()
	local theme = self.Theme
	local cleanup = Cleanup.new()
	local winSize = opts.Size or UDim2.fromOffset(790, 490)

	local gui = self.Gui
	local main = Utility.Create("Frame", {
		Name = "PastaWindow",
		Size = winSize,
		BackgroundColor3 = theme.Current.Background,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		Parent = gui,
	})
	theme:Bind(main, "BackgroundColor3", "Background")
	Utility.Corner(main, UDim.new(0, 12))
	local mainStroke = Utility.Stroke(main, theme.Current.Border, 1.2)
	theme:Bind(mainStroke, "Color", "Border")
	local startPos = centerPosition(winSize)
	main.Position = startPos

	local glow = Utility.Create("ImageLabel", {
		Name = "GlowBackdrop",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, -45, 0, -45),
		Size = UDim2.new(1, 90, 1, 90),
		ZIndex = 0,
		Image = "rbxassetid://5028857084",
		ImageTransparency = 0.83,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(24, 24, 276, 276),
		Parent = main,
	})
	theme:Bind(glow, "ImageColor3", "AccentDark")

	local win = {
		_main = main,
		_glow = glow,
		_theme = theme,
		_cleanup = cleanup,
		_gui = gui,
		_userScale = math.clamp(tonumber(opts.Scale) or 1, 0.5, 1.25),
		_scale = 1,
		Tabs = {},
		_searchRows = {},
		_cards = {},
		_categories = {},
		_tabEntries = {},
		_visible = true,
		_sidebarCollapsed = false,
		_size = winSize,
		_homePos = startPos,
	}

	-- escala responsiva (celular): UIScale cabe a janela no viewport
	local uiScale = Utility.Create("UIScale", { Parent = main })
	local function applyScale()
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
		local fit = math.min(vp.X / (win._size.X.Offset + 48), vp.Y / (win._size.Y.Offset + 48))
		local s = math.clamp(math.min(fit, 1) * win._userScale, 0.45, 1.25)
		win._scale = s
		uiScale.Scale = s
		if win._hudScale then
			win._hudScale.Scale = math.clamp(s, 0.6, 1)
		end
	end
	win._applyScale = applyScale
	applyScale()
	local _cam = workspace.CurrentCamera
	if _cam then
		cleanup:Add(_cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if cleanup:IsAlive() then
				applyScale()
			end
		end))
	end

	-- ---- TopBar (unica area de drag: clique em toggle/search nao move) ----
	local topBar = Utility.Create("Frame", {
		Name = "TopBar",
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundTransparency = 1,
		Parent = main,
	})

	local logoHolder = Utility.Create("Frame", {
		Name = "LogoHolder",
		Size = UDim2.new(0, 64, 0, 64),
		Position = UDim2.new(0, 52, 0, -4),
		BackgroundTransparency = 1,
		Parent = topBar,
	})
	local halo = Utility.Create("ImageLabel", {
		Size = UDim2.new(2.1, 0, 2.1, 0),
		Position = UDim2.new(-0.55, 0, -0.55, 0),
		BackgroundTransparency = 1,
		Image = "rbxassetid://5028857084",
		ImageTransparency = 0.58,
		ZIndex = 1,
		Parent = logoHolder,
	})
	theme:Bind(halo, "ImageColor3", "Accent")
	-- sem sombra deslocada no logo: a franja vermelha parecia defeito
	local logoImg = Utility.Create("ImageLabel", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Image = opts.Logo or "rbxassetid://139568612294283",
		ScaleType = Enum.ScaleType.Fit,
		ImageColor3 = Color3.fromRGB(255, 255, 255),
		ZIndex = 3,
		Parent = logoHolder,
	})
	Utility.Create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.0, Color3.fromRGB(255, 175, 165)),
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(246, 92, 82)),
			ColorSequenceKeypoint.new(1.0, Color3.fromRGB(165, 32, 42)),
		}),
		Rotation = -35,
		Parent = logoImg,
	})

	local searchBox = Utility.Create("Frame", {
		Size = UDim2.new(0, 250, 0, 26),
		Position = UDim2.new(0, 185, 0, 15),
		BorderSizePixel = 0,
		Parent = topBar,
	})
	theme:Bind(searchBox, "BackgroundColor3", "CardBg")
	Utility.Corner(searchBox, UDim.new(0, 6))
	local searchStroke = Utility.Stroke(searchBox, theme.Current.Border, 1)
	theme:Bind(searchStroke, "Color", "Border")
	local searchIcon = Utility.Create("ImageLabel", {
		Size = UDim2.new(0, 13, 0, 13),
		Position = UDim2.new(0, 9, 0.5, -6.5),
		BackgroundTransparency = 1,
		Image = Icons.Get("Search"),
		Parent = searchBox,
	})
	theme:Bind(searchIcon, "ImageColor3", "TextMuted")
	local searchInput = Utility.Create("TextBox", {
		PlaceholderText = "Search something",
		Font = Enum.Font.Gotham,
		TextSize = 11,
		Text = "",
		Position = UDim2.new(0, 30, 0, 0),
		Size = UDim2.new(1, -36, 1, 0),
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Parent = searchBox,
	})
	theme:Bind(searchInput, "PlaceholderColor3", "TextMuted")
	theme:Bind(searchInput, "TextColor3", "TextPrimary")

	local menuBtn = Utility.Create("ImageButton", {
		Size = UDim2.new(0, 17, 0, 17),
		Position = UDim2.new(1, -32, 0.5, -8.5),
		BackgroundTransparency = 1,
		Image = Icons.Get("Menu"),
		Parent = topBar,
	})
	theme:Bind(menuBtn, "ImageColor3", "TextMuted")

	-- ---- Sidebar ----
	local sidebar = Utility.Create("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, 155, 1, -58),
		Position = UDim2.new(0, 14, 0, 54),
		BackgroundTransparency = 1,
		Parent = main,
	})
	Utility.Create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = sidebar })

	-- ---- Footer ----
	local footer = Utility.Create("Frame", {
		Size = UDim2.new(0, 160, 0, 28),
		Position = UDim2.new(0, 18, 1, -38),
		BackgroundTransparency = 1,
		Parent = main,
	})
	local userLabel = Utility.Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 13),
		BackgroundTransparency = 1,
		Text = string.lower(LocalPlayer.Name),
		Font = Enum.Font.GothamBold,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = footer,
	})
	theme:Bind(userLabel, "TextColor3", "TextMuted")
	local subLabel = Utility.Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 11),
		Position = UDim2.new(0, 0, 0, 13),
		BackgroundTransparency = 1,
		Text = opts.Footer or "pasta framework v2",
		Font = Enum.Font.Gotham,
		TextSize = 7.5,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = footer,
	})
	theme:Bind(subLabel, "TextColor3", "TextDim")

	-- ---- Content ----
	local content = Utility.Create("Frame", {
		Name = "Content",
		Size = UDim2.new(1, -195, 1, -62),
		Position = UDim2.new(0, 182, 0, 54),
		BackgroundTransparency = 1,
		Parent = main,
	})

	-- ---- Search ----
	local function applySearch()
		local q = string.lower(searchInput.Text or "")
		for _, r in ipairs(win._searchRows) do
			local match = (q == "" or string.find(r.Name, q, 1, true) ~= nil)
			r.Frame.Visible = match
			if match and q ~= "" and r.Card and r.Card._collapsed and r.Card._setCollapsed then
				r.Card._setCollapsed(false)
			end
		end
		for _, c in ipairs(win._cards) do
			if c.Card and c.Card._collapsed and q == "" then
				for _, rowFrame in ipairs(c.Rows) do
					rowFrame.Visible = false
				end
			end
		end
		for _, c in ipairs(win._cards) do
			if q == "" then
				c.Frame.Visible = true
			else
				local any = false
				for _, rowFrame in ipairs(c.Rows) do
					if rowFrame.Visible then
						any = true
						break
					end
				end
				c.Frame.Visible = any
			end
		end
		for _, entry in ipairs(win._tabEntries) do
			if q == "" then
				entry.Button.Visible = true
			else
				local any = false
				for _, card in ipairs(entry.Tab._cards) do
					for _, rowFrame in ipairs(card._rows) do
						if rowFrame.Visible then
							any = true
							break
						end
					end
					if any then
						break
					end
				end
				entry.Button.Visible = any
			end
		end
		for _, cat in ipairs(win._categories) do
			if q == "" then
				cat.Header.Visible = true
			else
				local any = false
				for _, entry in ipairs(cat.Entries) do
					if entry.Button.Visible then
						any = true
						break
					end
				end
				cat.Header.Visible = any
			end
		end
		if q ~= "" and win.ActiveTab then
			local activeVisible = false
			for _, e in ipairs(win._tabEntries) do
				if e.Tab == win.ActiveTab and e.Button.Visible then
					activeVisible = true
					break
				end
			end
			if not activeVisible then
				for _, e in ipairs(win._tabEntries) do
					if e.Button.Visible then
						win:SelectTab(e.Tab)
						break
					end
				end
			end
		end
	end
	cleanup:Add(searchInput:GetPropertyChangedSignal("Text"):Connect(applySearch))
	win._applySearch = applySearch

	-- ---- Tabs ----
	function win:AddTab(tabOpts)
		tabOpts = tabOpts or {}
		local category = tabOpts.Category or "Features"
		local catObj = nil
		for _, c in ipairs(self._categories) do
			if c.Name == category then
				catObj = c
				break
			end
		end
		if not catObj then
			self._sideOrder = (self._sideOrder or 0) + 1
			local header = Utility.Create("TextLabel", {
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				Text = "   " .. string.upper(category),
				Font = Enum.Font.GothamBold,
				TextSize = 9,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = self._sideOrder,
				Parent = sidebar,
			})
			theme:Bind(header, "TextColor3", "TextDim")
			header.Visible = not self._sidebarCollapsed
			catObj = { Name = category, Header = header, Entries = {} }
			table.insert(self._categories, catObj)
		end

		self._sideOrder = (self._sideOrder or 0) + 1
		local isFirst = (#self.Tabs == 0)
		local btn = Utility.Create("TextButton", {
			Size = UDim2.new(1, -4, 0, 29),
			BackgroundTransparency = isFirst and 0 or 1,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = self._sideOrder,
			Parent = sidebar,
		})
		theme:Bind(btn, "BackgroundColor3", "SidebarActive")
		Utility.Corner(btn, UDim.new(0, 6))
		local stroke = Utility.Stroke(btn, theme.Current.BorderActive, 1)
		stroke.Transparency = isFirst and 0 or 1
		local iconImg = Utility.Create("ImageLabel", {
			Size = UDim2.new(0, 14, 0, 14),
			Position = UDim2.new(0, 9, 0.5, -7),
			BackgroundTransparency = 1,
			Image = Icons.Get(tabOpts.Icon),
			Parent = btn,
		})
		theme:Bind(iconImg, "ImageColor3", isFirst and "Accent" or "TextMuted")
		local titleLbl = Utility.Create("TextLabel", {
			Size = UDim2.new(1, -32, 1, 0),
			Position = UDim2.new(0, 30, 0, 0),
			BackgroundTransparency = 1,
			Text = tabOpts.Name or "Tab",
			Font = Enum.Font.GothamMedium,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = btn,
		})
		theme:Bind(titleLbl, "TextColor3", isFirst and "TextPrimary" or "TextMuted")
		titleLbl.Visible = not self._sidebarCollapsed

		local page = Utility.Create("Frame", {
			Name = tabOpts.Name or "Tab",
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Visible = isFirst,
			Parent = content,
		})
		local col1 = Utility.Create("ScrollingFrame", {
			Size = UDim2.new(0.485, 0, 1, 0),
			BackgroundTransparency = 1,
			ScrollBarThickness = 0,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			Parent = page,
		})
		Utility.Create("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = col1 })
		local col2 = Utility.Create("ScrollingFrame", {
			Size = UDim2.new(0.485, 0, 1, 0),
			Position = UDim2.new(0.515, 0, 0, 0),
			BackgroundTransparency = 1,
			ScrollBarThickness = 0,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			Parent = page,
		})
		Utility.Create("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = col2 })

		local tab = { Name = tabOpts.Name or "Tab", _page = page, _col1 = col1, _col2 = col2, _nextCol = 1, _cards = {}, _win = self, _button = btn }
		function tab:AddCard(o)
			return buildCard(self._win, tab, o)
		end
		function tab:Select()
			self._win:SelectTab(tab)
		end

		local entry = { Button = btn, Icon = iconImg, Title = titleLbl, Stroke = stroke, Tab = tab }
		table.insert(catObj.Entries, entry)
		table.insert(self._tabEntries, entry)
		table.insert(self.Tabs, tab)
		if isFirst then
			self.ActiveTab = tab
		end

		cleanup:Add(btn.MouseEnter:Connect(function()
			if self.ActiveTab ~= tab then
				Animation.Tween(titleLbl, { TextColor3 = theme.Current.TextPrimary }, 0.15)
				Animation.Tween(iconImg, { ImageColor3 = theme.Current.TextPrimary }, 0.15)
			end
		end))
		cleanup:Add(btn.MouseLeave:Connect(function()
			if self.ActiveTab ~= tab then
				Animation.Tween(titleLbl, { TextColor3 = theme.Current.TextMuted }, 0.15)
				Animation.Tween(iconImg, { ImageColor3 = theme.Current.TextMuted }, 0.15)
			end
		end))
		cleanup:Add(btn.MouseButton1Click:Connect(function()
			self:SelectTab(tab)
		end))
		return tab
	end

	function win:GetTab(name)
		for _, tab in ipairs(self.Tabs) do
			if tab.Name == name then
				return tab
			end
		end
		return nil
	end

	function win:SelectTab(tab)
		if self.ActiveTab == tab then
			return
		end
		for _, e in ipairs(self._tabEntries) do
			local active = (e.Tab == tab)
			e.Tab._page.Visible = active
			Animation.Tween(e.Button, { BackgroundTransparency = active and 0 or 1 }, 0.18)
			Animation.Tween(e.Stroke, { Transparency = active and 0 or 1 }, 0.18)
			Animation.Tween(e.Icon, { ImageColor3 = active and theme.Current.Accent or theme.Current.TextMuted }, 0.18)
			Animation.Tween(e.Title, { TextColor3 = active and theme.Current.TextPrimary or theme.Current.TextMuted }, 0.18)
		end
		self.ActiveTab = tab
		self:_applySearch()
	end

	-- re-pinta botoes das tabs quando o tema muda (tween direto nao sobrevive ao Apply)
	cleanup:Add(theme.Changed:Connect(function()
		local th = theme.Current
		for _, e in ipairs(win._tabEntries) do
			local active = (e.Tab == win.ActiveTab)
			e.Button.BackgroundColor3 = th.SidebarActive
			e.Stroke.Color = th.BorderActive
			e.Icon.ImageColor3 = active and th.Accent or th.TextMuted
			e.Title.TextColor3 = active and th.TextPrimary or th.TextMuted
		end
	end))

	-- ---- Botao fechar (X) + pill de reabrir ----
	local closeBtn = Utility.Create("TextButton", {
		Name = "CloseBtn",
		Size = UDim2.new(0, 17, 0, 17),
		Position = UDim2.new(1, -56, 0.5, -8.5),
		BackgroundTransparency = 1,
		Text = "X",
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		Parent = topBar,
	})
	theme:Bind(closeBtn, "TextColor3", "TextMuted")
	cleanup:Add(closeBtn.MouseEnter:Connect(function()
		Animation.Tween(closeBtn, { TextColor3 = theme.Current.Accent }, 0.15)
	end))
	cleanup:Add(closeBtn.MouseLeave:Connect(function()
		Animation.Tween(closeBtn, { TextColor3 = theme.Current.TextMuted }, 0.15)
	end))
	local pill = Utility.Create("TextButton", {
		Name = "PastaReopen",
		Size = UDim2.new(0, 110, 0, 28),
		Position = UDim2.new(0.5, -55, 0, 12),
		Visible = false,
		Text = opts.Name or opts.Brand or "pasta",
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		AutoButtonColor = false,
		Parent = gui,
	})
	theme:Bind(pill, "BackgroundColor3", "PillBg")
	theme:Bind(pill, "TextColor3", "TextPrimary")
	Utility.Corner(pill, UDim.new(0, 14))
	local pillStroke = Utility.Stroke(pill, theme.Current.Border, 1)
	theme:Bind(pillStroke, "Color", "BorderActive")
	win._pill = pill
	cleanup:Add(pill.MouseButton1Click:Connect(function()
		win:Show()
	end))
	cleanup:Add(closeBtn.MouseButton1Click:Connect(function()
		win:Close()
	end))

	-- ---- Sidebar collapse (menu button agora faz algo) ----
	cleanup:Add(menuBtn.MouseEnter:Connect(function()
		Animation.Tween(menuBtn, { ImageColor3 = theme.Current.TextPrimary }, 0.15)
	end))
	cleanup:Add(menuBtn.MouseLeave:Connect(function()
		Animation.Tween(menuBtn, { ImageColor3 = theme.Current.TextMuted }, 0.15)
	end))
	local function setCollapsed(collapsed)
		win._sidebarCollapsed = collapsed
		Animation.Tween(sidebar, { Size = UDim2.new(0, collapsed and 44 or 155, 1, -58) }, 0.25)
		for _, e in ipairs(win._tabEntries) do
			e.Title.Visible = not collapsed
		end
		for _, c in ipairs(win._categories) do
			c.Header.Visible = not collapsed
		end
		Animation.Tween(content, {
			Size = collapsed and UDim2.new(1, -84, 1, -62) or UDim2.new(1, -195, 1, -62),
			Position = collapsed and UDim2.new(0, 71, 0, 54) or UDim2.new(0, 182, 0, 54),
		}, 0.25)
		Animation.Tween(footer, { Position = collapsed and UDim2.new(0, 14, 1, -38) or UDim2.new(0, 18, 1, -38) }, 0.25)
	end
	win._setCollapsed = setCollapsed
	cleanup:Add(menuBtn.MouseButton1Click:Connect(function()
		setCollapsed(not win._sidebarCollapsed)
	end))

	-- ---- Drag pela TopBar (sem jump, com clamp) ----
	do
		local dragging, dragInput, startInput, startCenter = false, nil, nil, nil
		local function viewport()
			local cam = workspace.CurrentCamera
			if cam then
				return cam.ViewportSize
			end
			return Vector2.new(1920, 1080)
		end
		local function frameCenter(pos, vp)
			return Vector2.new(pos.X.Scale * vp.X + pos.X.Offset, pos.Y.Scale * vp.Y + pos.Y.Offset)
		end
		cleanup:Add(topBar.InputBegan:Connect(function(input)
			if dragging then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				dragInput = input
				startInput = Vector2.new(input.Position.X, input.Position.Y)
				startCenter = frameCenter(main.Position, viewport())
			end
		end))
		cleanup:Add(UserInputService.InputChanged:Connect(function(input)
			if not dragging then
				return
			end
			if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			if input.UserInputType == Enum.UserInputType.Touch and dragInput.UserInputType == Enum.UserInputType.Touch and input ~= dragInput then
				return
			end
			local vp = viewport()
			local delta = (Vector2.new(input.Position.X, input.Position.Y) - startInput) / math.max(win._scale or 1, 0.01)
			local half = main.AbsoluteSize / 2
			local target = startCenter + delta
			local minX, maxX = half.X + 8, vp.X - half.X - 8
			local minY, maxY = half.Y + 8, vp.Y - half.Y - 8
			local x = (minX <= maxX) and math.clamp(target.X, minX, maxX) or vp.X / 2
			local y = (minY <= maxY) and math.clamp(target.Y, minY, maxY) or vp.Y / 2
			local sx, sy = main.Position.X.Scale, main.Position.Y.Scale
			main.Position = UDim2.new(sx, math.round(x - sx * vp.X), sy, math.round(y - sy * vp.Y))
			win._homePos = main.Position
		end))
		cleanup:Add(UserInputService.InputEnded:Connect(function(input)
			if input == dragInput then
				dragging = false
				dragInput = nil
			end
		end))
		cleanup:Add(function()
			dragging = false
			dragInput = nil
		end)
	end

	-- ---- Show / Hide sem leak ----
	function win:SetVisible(v, instant)
		if self._visible == v then
			return
		end
		self._visible = v
		if v then
			main.Visible = true
			if instant then
				main.Position = self._homePos
			else
				Animation.Tween(main, { Position = self._homePos }, 0.3, Enum.EasingStyle.Cubic)
				Animation.Tween(glow, { ImageTransparency = 0.83 }, 0.3)
			end
		else
			if instant then
				main.Visible = false
			else
				local down = UDim2.new(self._homePos.X.Scale, self._homePos.X.Offset, self._homePos.Y.Scale, self._homePos.Y.Offset + 30)
				local tw = Animation.Tween(main, { Position = down }, 0.3, Enum.EasingStyle.Cubic)
				Animation.Tween(glow, { ImageTransparency = 1 }, 0.3)
				if tw then
					local conn = nil
					conn = tw.Completed:Connect(function()
						conn:Disconnect()
						if not self._visible then
							main.Visible = false
							main.Position = self._homePos
						end
					end)
				else
					main.Visible = false
				end
			end
		end
	end
	function win:Show()
		self:SetVisible(true)
		if self._pill then
			self._pill.Visible = false
		end
	end
	function win:Hide()
		self:SetVisible(false)
	end
	function win:ToggleVisibility()
		self:SetVisible(not self._visible)
		if self._visible and self._pill then
			self._pill.Visible = false
		end
	end
	function win:Close()
		self:SetVisible(false)
		if self._pill then
			self._pill.Visible = true
		end
	end

	local toggleKey = opts.ToggleKey or Enum.KeyCode.RightShift
	cleanup:Add(UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == toggleKey then
			win:ToggleVisibility()
		end
	end))

	function win:SetHUDVisible(v)
		if self.HUD then
			self.HUD:SetVisible(v)
		end
	end

	function win:Destroy()
		for i, w in ipairs(Pasta.Windows) do
			if w == self then
				table.remove(Pasta.Windows, i)
				break
			end
		end
		cleanup:Destroy()
		if self.HUD then
			pcall(function()
				self.HUD:Destroy()
			end)
			self.HUD = nil
		end
		pcall(function()
			main:Destroy()
		end)
		if self._pill then
			pcall(function()
				self._pill:Destroy()
			end)
			self._pill = nil
		end
	end

	win._sidebarCollapsed = win._scale < 0.68
	if win._sidebarCollapsed then
		sidebar.Size = UDim2.new(0, 44, 1, -58)
		content.Size = UDim2.new(1, -84, 1, -62)
		content.Position = UDim2.new(0, 71, 0, 54)
		footer.Position = UDim2.new(0, 14, 1, -38)
	end
	win.HUD = buildHUD(win, { Brand = opts.Name or opts.Brand or "pasta", Logo = opts.Logo })
	win.HUD:SetVisible(opts.ShowHUD ~= false)
	win._applyScale()
	cleanup:Add(function()
		pcall(function()
			win.HUD:Destroy()
		end)
	end)

	table.insert(Pasta.Windows, win)
	return win
end

function Pasta:Destroy()
	if self._Destroyed then
		return
	end
	self._Destroyed = true
	while #self.Windows > 0 do
		local w = table.remove(self.Windows)
		pcall(function()
			w:Destroy()
		end)
	end
	if self.Gui then
		pcall(function()
			self.Gui:Destroy()
		end)
		self.Gui = nil
		self.Toasts = nil
	end
end

return Pasta
