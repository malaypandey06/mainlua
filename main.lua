-- language: Lua (Luau), file: main.lua
-- target: Roblox client (Delta / mobile executors)
-- catalog: https://raw.githubusercontent.com/Rootleak/Animations/main/animations.json
-- format:  return { ["name"] = <number id>, ... }
-- usage:   loadstring(game:HttpGet("RAW_URL_OF_THIS_FILE"))()

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService      = game:GetService("HttpService")
local StarterGui       = game:GetService("StarterGui")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------------
-- // Config
----------------------------------------------------------------------
local CONFIG_FILE   = "reanim_standalone.json"
local CATALOG_URL   = "https://raw.githubusercontent.com/Rootleak/Animations/main/animations.json"

-- Fallback catalog: used if the remote fetch fails.
-- Names must not collide with remote ones — remote always wins on merge.
local FALLBACK_CATALOG = {
	{ name = "Griddy",    id = 8916572099 },
	{ name = "Macarena",  id = 18553106741 },
	{ name = "Backflip",  id = 18550514533 },
	{ name = "Floss",     id = 9003921069 },
	{ name = "Orange Justice", id = 11212163754 },
	{ name = "Smeeze",    id = 18553199244 },
	{ name = "Billy Bounce",   id = 8917592832 },
	{ name = "Electro Shuffle", id = 9116910876 },
}

local C = {
	Bg          = Color3.fromRGB(4, 6, 10),
	Chrome      = Color3.fromRGB(5, 7, 11),
	Surface     = Color3.fromRGB(9, 12, 18),
	Surface2    = Color3.fromRGB(12, 16, 24),
	Border      = Color3.fromRGB(31, 39, 55),
	BorderSoft  = Color3.fromRGB(19, 25, 36),
	Text        = Color3.fromRGB(245, 247, 252),
	Muted       = Color3.fromRGB(153, 161, 178),
	Dim         = Color3.fromRGB(74, 83, 99),
	Accent      = Color3.fromRGB(151, 57, 255),
	AccentText  = Color3.fromRGB(179, 111, 255),
	Good        = Color3.fromRGB(107, 231, 132),
	Bad         = Color3.fromRGB(238, 96, 96),
}

----------------------------------------------------------------------
-- // State
----------------------------------------------------------------------
local state = {
	catalog   = {},     -- [{name, id}]
	byName    = {},     -- lowercase name -> entry
	loading   = false,
	loaded    = false,
	activeId  = nil,
	activeName = nil,
	track     = nil,
	search    = "",
	popupOpen = false,
	lastId    = nil,
	lastName  = nil,
}

----------------------------------------------------------------------
-- // Utils
----------------------------------------------------------------------
local function trim(s)
	return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function pushToast(title, text)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = tostring(title or ""),
			Text = tostring(text or ""),
			Duration = 3,
		})
	end)
end

----------------------------------------------------------------------
-- // Catalog fetch
----------------------------------------------------------------------
local function buildIndex()
	state.byName = {}
	for _, entry in ipairs(state.catalog) do
		local key = entry.name:lower()
		if state.byName[key] == nil then
			state.byName[key] = entry
		end
	end
	table.sort(state.catalog, function(a, b)
		return a.name:lower() < b.name:lower()
	end)
end

local function mergeEntry(name, id, seen)
	name = trim(name)
	if name == "" or type(id) ~= "number" or id <= 0 then
		return
	end
	local key = name:lower()
	if seen[key] then
		return
	end
	seen[key] = true
	state.catalog[#state.catalog + 1] = { name = name, id = math.floor(id) }
end

local function loadCatalog()
	if state.loading then
		return
	end
	state.loading = true

	task.spawn(function()
		local ok, result = pcall(function()
			return game:HttpGet(CATALOG_URL)
		end)

		if not ok or type(result) ~= "string" or #result < 10 then
			-- remote failed; seed fallback only
			if #state.catalog == 0 then
				local seen = {}
				for _, e in ipairs(FALLBACK_CATALOG) do
					mergeEntry(e.name, e.id, seen)
				end
			end
			state.loaded  = #state.catalog > 0
			state.loading = false
			pushToast("reanimation", state.loaded and ("fallback: " .. #state.catalog .. " anims") or "catalog failed")
			return
		end

		local okParse, tbl = pcall(function()
			return loadstring(result)()
		end)

		if not okParse or type(tbl) ~= "table" then
			if #state.catalog == 0 then
				local seen = {}
				for _, e in ipairs(FALLBACK_CATALOG) do
					mergeEntry(e.name, e.id, seen)
				end
			end
			state.loaded  = #state.catalog > 0
			state.loading = false
			pushToast("reanimation", state.loaded and ("fallback: " .. #state.catalog .. " anims") or "parse failed")
			return
		end

		-- merge remote over existing (remote wins on dupes by lowercase name)
		local seen = {}
		for name, id in pairs(tbl) do
			mergeEntry(name, tonumber(id), seen)
		end

		if #state.catalog == 0 then
			for _, e in ipairs(FALLBACK_CATALOG) do
				mergeEntry(e.name, e.id, seen)
			end
		end

		buildIndex()
		state.loaded  = #state.catalog > 0
		state.loading = false
		pushToast("reanimation", "loaded " .. #state.catalog .. " anims")
	end)
end

----------------------------------------------------------------------
-- // Reanimation core (plays an animation locally)
----------------------------------------------------------------------
local function stopActive()
	if state.track then
		pcall(function()
			state.track:Stop(0.1)
		end)
		pcall(function()
			state.track:Destroy()
		end)
		state.track = nil
	end
	state.activeId   = nil
	state.activeName = nil
end

local function playAnim(entry)
	if type(entry) ~= "table" or type(entry.id) ~= "number" then
		return false
	end
	local char = player.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		pushToast("reanimation", "character not ready")
		return false
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end

	stopActive()

	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. tostring(entry.id)

	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	anim:Destroy()

	if not ok or not track then
		pushToast("reanimation", "load failed: " .. tostring(entry.name))
		return false
	end

	track.Priority = Enum.AnimationPriority.Action4
	track.Looped   = true

	local okPlay = pcall(function()
		track:Play(0.15)
	end)

	if not okPlay then
		pushToast("reanimation", "play failed: " .. tostring(entry.name))
		return false
	end

	state.track      = track
	state.activeId   = entry.id
	state.activeName = entry.name
	state.lastId     = entry.id
	state.lastName   = entry.name

	track.Stopped:Connect(function()
		if state.track == track then
			state.activeId   = nil
			state.activeName = nil
			state.track      = nil
		end
	end)

	pushToast("reanimation", "playing " .. entry.name)
	return true
end

local function findEntry(query)
	query = trim(query):lower()
	if query == "" then
		return nil
	end
	if state.byName[query] then
		return state.byName[query]
	end
	for _, e in ipairs(state.catalog) do
		if e.name:lower():find(query, 1, true) then
			return e
		end
	end
	return nil
end

----------------------------------------------------------------------
-- // UI
----------------------------------------------------------------------
local guiParent
do
	local ok, coreGui = pcall(function()
		return game:GetService("CoreGui")
	end)
	guiParent = (ok and coreGui) or playerGui
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ReanimStandalone"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 999
screenGui.Parent = guiParent

local uiScale = Instance.new("UIScale")
uiScale.Scale = 1
uiScale.Parent = screenGui

local function rescale()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize
	if vp.X <= 0 or vp.Y <= 0 then return end
	uiScale.Scale = math.clamp(math.min(vp.X / 720, vp.Y / 820), 0.62, 1)
end
rescale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end

local function mk(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function corner(parent, r)
	return mk("UICorner", { CornerRadius = UDim.new(0, r or 8) }, parent)
end

local function stroke(parent, color, transparency, thickness)
	return mk("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = color or C.BorderSoft,
		Thickness = thickness or 1,
		Transparency = transparency or 0.4,
	}, parent)
end

-- toggle button
local toggleBtn = mk("TextButton", {
	Name = "Toggle",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 12, 1, -12),
	Size = UDim2.new(0, 46, 0, 46),
	BackgroundColor3 = C.Chrome,
	BackgroundTransparency = 0.06,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	Text = "R",
	TextColor3 = C.AccentText,
	TextSize = 20,
	AutoButtonColor = false,
	ZIndex = 300,
}, screenGui)
corner(toggleBtn, 12)
stroke(toggleBtn, C.Border, 0.3, 1)

-- popup
local POPUP_W, POPUP_H = 340, 500

local popup = mk("Frame", {
	Name = "Popup",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(0, POPUP_W, 0, POPUP_H),
	BackgroundColor3 = C.Chrome,
	BackgroundTransparency = 0.04,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Visible = false,
	ZIndex = 200,
}, screenGui)
corner(popup, 12)
stroke(popup, C.Border, 0.25, 1)

-- title bar
local titleBar = mk("Frame", {
	Size = UDim2.new(1, 0, 0, 40),
	BackgroundColor3 = C.Surface,
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	ZIndex = 201,
}, popup)
corner(titleBar, 12)
mk("Frame", {
	Size = UDim2.new(1, 0, 0, 12),
	Position = UDim2.new(0, 0, 1, -12),
	BackgroundColor3 = C.Surface,
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	ZIndex = 201,
}, titleBar)

mk("TextLabel", {
	Size = UDim2.new(1, -80, 1, 0),
	Position = UDim2.new(0, 12, 0, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "reanimation",
	TextColor3 = C.Text,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 203,
}, titleBar)

local statusLabel = mk("TextLabel", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -50, 0.5, 0),
	Size = UDim2.new(0, 140, 1, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "idle",
	TextColor3 = C.Muted,
	TextSize = 10,
	TextXAlignment = Enum.TextXAlignment.Right,
	TextTruncate = Enum.TextTruncate.AtEnd,
	ZIndex = 203,
}, titleBar)

local closeBtn = mk("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -8, 0.5, 0),
	Size = UDim2.new(0, 30, 0, 30),
	BackgroundColor3 = C.Surface2,
	BackgroundTransparency = 0.2,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	Text = "X",
	TextColor3 = C.Muted,
	TextSize = 12,
	AutoButtonColor = false,
	ZIndex = 204,
}, titleBar)
corner(closeBtn, 8)

-- drag popup
do
	local dragging, dragStart, startPos
	titleBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			dragStart = input.Position
			startPos = popup.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.InputState.End then
					dragging = false
				end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseMovement) then
			local delta = input.Position - dragStart
			popup.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)
end

-- controls row
local controls = mk("Frame", {
	Size = UDim2.new(1, -16, 0, 34),
	Position = UDim2.new(0, 8, 0, 48),
	BackgroundTransparency = 1,
	ZIndex = 203,
}, popup)
mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 6),
}, controls)

local function controlBtn(text, accent, cb)
	local b = mk("TextButton", {
		Size = UDim2.new(0.33, -4, 1, 0),
		BackgroundColor3 = accent and C.Accent or C.Surface2,
		BackgroundTransparency = accent and 0.05 or 0.15,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = text,
		TextColor3 = accent and C.AccentText or C.Text,
		TextSize = 11,
		AutoButtonColor = false,
		ZIndex = 204,
	}, controls)
	corner(b, 8)
	stroke(b, accent and C.Accent or C.BorderSoft, 0.4, 1)
	b.Activated:Connect(cb)
	return b
end

controlBtn("stop", false, function()
	stopActive()
	statusLabel.Text = "idle"
	pushToast("reanimation", "stopped")
end)
controlBtn("replay", false, function()
	if state.lastId then
		playAnim({ name = state.lastName, id = state.lastId })
	else
		pushToast("reanimation", "nothing to replay")
	end
end)
controlBtn("random", true, function()
	if #state.catalog == 0 then
		pushToast("reanimation", "catalog empty")
		return
	end
	local pick = state.catalog[math.random(1, #state.catalog)]
	playAnim(pick)
end)

-- search box
local searchBox = mk("TextBox", {
	Size = UDim2.new(1, -16, 0, 34),
	Position = UDim2.new(0, 8, 0, 88),
	BackgroundColor3 = C.Surface,
	BackgroundTransparency = 0.12,
	BorderSizePixel = 0,
	ClearTextOnFocus = false,
	Font = Enum.Font.GothamMedium,
	PlaceholderText = "search reanimations",
	PlaceholderColor3 = C.Dim,
	Text = "",
	TextColor3 = C.Text,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 203,
}, popup)
corner(searchBox, 8)
stroke(searchBox, C.BorderSoft, 0.5, 1)
mk("UIPadding", { PaddingLeft = UDim.new(0, 10) }, searchBox)

-- scroll list
local scroll = mk("ScrollingFrame", {
	Size = UDim2.new(1, -16, 1, -214),
	Position = UDim2.new(0, 8, 0, 130),
	BackgroundColor3 = C.Bg,
	BackgroundTransparency = 0.3,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = C.Dim,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 203,
}, popup)
corner(scroll, 8)
stroke(scroll, C.BorderSoft, 0.55, 1)
mk("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 4),
}, scroll)
mk("UIPadding", {
	PaddingTop = UDim.new(0, 4),
	PaddingBottom = UDim.new(0, 4),
	PaddingLeft = UDim.new(0, 4),
	PaddingRight = UDim.new(0, 4),
}, scroll)

----------------------------------------------------------------------
-- // List rows
----------------------------------------------------------------------
local ROW_H = 40

local function refreshList()
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local query = trim(state.search):lower()
	local shown  = 0

	for _, entry in ipairs(state.catalog) do
		if query ~= "" and not entry.name:lower():find(query, 1, true) then
			continue
		end
		shown = shown + 1
		if shown > 120 then
			break
		end

		local isActive = state.activeId == entry.id and state.activeName == entry.name

		local row = mk("Frame", {
			LayoutOrder = shown,
			Size = UDim2.new(1, -4, 0, ROW_H),
			BackgroundColor3 = C.Surface2,
			BackgroundTransparency = 0.18,
			BorderSizePixel = 0,
			ZIndex = 205,
		}, scroll)
		corner(row, 8)

		mk("TextLabel", {
			Size = UDim2.new(1, -60, 1, 0),
			Position = UDim2.new(0, 10, 0, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = entry.name,
			TextColor3 = isActive and C.AccentText or C.Text,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 206,
		}, row)

		local playBtn = mk("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.new(0, 46, 0, 26),
			BackgroundColor3 = isActive and C.Accent or C.Surface,
			BackgroundTransparency = isActive and 0.06 or 0.1,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Text = isActive and "live" or "play",
			TextColor3 = isActive and C.AccentText or C.Text,
			TextSize = 10,
			AutoButtonColor = false,
			ZIndex = 207,
		}, row)
		corner(playBtn, 6)

		playBtn.Activated:Connect(function()
			playAnim(entry)
			statusLabel.Text = "playing " .. entry.name
			refreshList()
		end)
	end

	if shown == 0 then
		local empty = mk("TextLabel", {
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Text = state.loading and "loading catalog..." or (state.loaded and "no matches" or "catalog unavailable"),
			TextColor3 = C.Dim,
			TextSize = 11,
			ZIndex = 206,
		}, scroll)
		empty.LayoutOrder = 1
	end

	if state.activeName then
		statusLabel.Text = "playing " .. state.activeName
	else
		statusLabel.Text = state.loaded and ("idle - " .. #state.catalog .. " anims") or "idle"
	end
end

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	state.search = searchBox.Text
	refreshList()
end)

----------------------------------------------------------------------
-- // Popup open/close
----------------------------------------------------------------------
local function setPopup(open)
	state.popupOpen = open
	popup.Visible = open
	if open then
		refreshList()
	end
end

closeBtn.Activated:Connect(function()
	setPopup(false)
end)

toggleBtn.Activated:Connect(function()
	setPopup(not state.popupOpen)
end)

-- toggle drag
do
	local dragging, dragStart, startPos
	toggleBtn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			dragStart = input.Position
			startPos = toggleBtn.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.InputState.End then
					dragging = false
				end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseMovement) then
			local delta = input.Position - dragStart
			toggleBtn.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)
end

----------------------------------------------------------------------
-- // Public API
----------------------------------------------------------------------
local api = {
	state = state,
	play  = playAnim,
	find  = findEntry,
	stop  = function()
		stopActive()
		refreshList()
	end,
	open  = function() setPopup(true) end,
	close = function() setPopup(false) end,
	refresh = function()
		state.catalog = {}
		state.byName  = {}
		state.loaded  = false
		loadCatalog()
	end,
}

local envTargets = {}
pcall(function()
	local genv = getgenv and getgenv()
	if type(genv) == "table" then envTargets[#envTargets + 1] = genv end
end)
pcall(function()
	if type(shared) == "table" then envTargets[#envTargets + 1] = shared end
end)
pcall(function() envTargets[#envTargets + 1] = _G end)

for _, env in ipairs(envTargets) do
	env.Reanim = api
	env.Reanimation = api
end

----------------------------------------------------------------------
-- // Boot
----------------------------------------------------------------------
refreshList()
loadCatalog()
pushToast("reanimation", "loading catalog...")

-- stop local tracks on respawn
player.CharacterAdded:Connect(function()
	stopActive()
end)
