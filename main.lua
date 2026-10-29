-- // M7 Reanimation — Standalone
-- // Extracted & rebuilt from the M7 payload (animation category only)
-- // Optimized for Delta / mobile executors
-- // Load this whole file and run. No key, no auth, no websocket.

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local player           = Players.LocalPlayer
local playerGui        = player:WaitForChild("PlayerGui")

----------------------------------------------------------------------
-- // Config
----------------------------------------------------------------------
local CONFIG_FILE = "m7_reanimation.json"
local SOURCE_URL  = "https://ib2.dev/absent/animations/"

-- // M7 palette (pulled from the payload theme table)
local C = {
	Bg          = Color3.fromRGB(4, 6, 10),
	Chrome      = Color3.fromRGB(5, 7, 11),
	Surface     = Color3.fromRGB(9, 12, 18),
	Surface2    = Color3.fromRGB(12, 16, 24),
	Hover       = Color3.fromRGB(14, 18, 27),
	Border      = Color3.fromRGB(31, 39, 55),
	BorderSoft  = Color3.fromRGB(19, 25, 36),
	Text        = Color3.fromRGB(245, 247, 252),
	Muted       = Color3.fromRGB(153, 161, 178),
	VMuted      = Color3.fromRGB(113, 122, 140),
	Dim         = Color3.fromRGB(74, 83, 99),
	Accent      = Color3.fromRGB(151, 57, 255),
	AccentText  = Color3.fromRGB(179, 111, 255),
	Good        = Color3.fromRGB(107, 231, 132),
	Bad         = Color3.fromRGB(238, 96, 96),
}

----------------------------------------------------------------------
-- // Small utils
----------------------------------------------------------------------
local function trim(s)
	return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function nameFromUrl(url)
	local tail = tostring(url or ""):gsub("^.*/", "")
	tail = tail:gsub("%.lua$", ""):gsub("%.html$", "")
	tail = tail:gsub("[%-_]+", " ")
	trim(tail)
	if tail == "" then
		return tostring(url or "animation")
	end
	return tail
end

-- // fn78/fn75 equivalent: resolve relative urls against a base
local function normalizeUrl(path, base)
	path = trim(path)
	if path == "" then
		return nil
	end
	if path:sub(1, 2) == "//" then
		return "https:" .. path
	end
	local proto = path:match("^(%a+):")
	if proto and proto:lower() ~= "http" and proto:lower() ~= "https" then
		return nil
	end
	if not path:find("^https?://") then
		base = tostring(base or SOURCE_URL)
		if path:sub(1, 1) == "/" then
			local host = base:match("^(https?://[^/]+)") or "https://ib2.dev"
			return host .. path
		end
		local dir = base:match("^(.*)/") or base
		return dir .. "/" .. path:gsub("^%./", "")
	end
	return (path:gsub("([^:/])//", "%1/"))
end

local function keyFromInput(input)
	if not input then
		return nil
	end
	if input.KeyCode and input.KeyCode ~= Enum.KeyCode.Unknown then
		return input.KeyCode.Name
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		return "MouseButton1"
	end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		return "MouseButton2"
	end
	return nil
end

----------------------------------------------------------------------
-- // Persistence (favorites / custom anims / keybinds)
----------------------------------------------------------------------
local state = {
	catalog   = {},
	custom    = {},
	favs      = {},
	keys      = {},
	activeUrl = nil,
	activeName = nil,
	lastUrl   = nil,
	lastName  = nil,
	loaded    = false,
	loading   = false,
	filter    = "all",   -- all | fav | own
	search    = "",
	popupOpen = false,
	capturing = nil,     -- url currently waiting for a keybind
}

local function loadConfig()
	if type(isfile) ~= "function" or type(readfile) ~= "function" then
		return
	end
	local ok = pcall(function()
		if isfile(CONFIG_FILE) then
			local Http = game:GetService("HttpService")
			local data = Http:JSONDecode(readfile(CONFIG_FILE))
			if type(data) == "table" then
				if type(data.favs)   == "table" then state.favs  = data.favs end
				if type(data.custom) == "table" then state.custom = data.custom end
				if type(data.keys)   == "table" then state.keys  = data.keys end
				if type(data.lastUrl) == "string" then
					state.lastUrl  = data.lastUrl
					state.lastName = data.lastName
				end
			end
		end
	end)
	return ok
end

local function saveConfig()
	if type(writefile) ~= "function" then
		return false
	end
	local Http = game:GetService("HttpService")
	local ok = pcall(function()
		writefile(CONFIG_FILE, Http:JSONEncode({
			favs     = state.favs,
			custom   = state.custom,
			keys     = state.keys,
			lastUrl  = state.lastUrl,
			lastName = state.lastName,
		}))
	end)
	return ok
end

loadConfig()

----------------------------------------------------------------------
-- // List building (catalog + custom, dedupe by url, favs first)
----------------------------------------------------------------------
local function buildList()
	local seen, out = {}, {}
	local function push(entry, isCustom)
		if type(entry) ~= "table" or type(entry.url) ~= "string" then
			return
		end
		local url = normalizeUrl(entry.url) or entry.url
		if seen[url] then
			return
		end
		seen[url] = true
		out[#out + 1] = {
			name   = trim(entry.name) ~= "" and trim(entry.name) or nameFromUrl(url),
			url    = url,
			custom = isCustom == true,
		}
	end
	for _, e in ipairs(state.catalog) do push(e, false) end
	for _, e in ipairs(state.custom)  do push(e, true)  end
	table.sort(out, function(a, b)
		local fa = state.favs[a.url] == true
		local fb = state.favs[b.url] == true
		if fa ~= fb then
			return fa
		end
		return tostring(a.name):lower() < tostring(b.name):lower()
	end)
	return out
end

----------------------------------------------------------------------
-- // Catalog loader — same source, same fallback paths, same parser
----------------------------------------------------------------------
local refreshList -- forward-declared (UI rebuild)

local function loadCatalog(force)
	if state.loading then
		return
	end
	if state.loaded and not force then
		return
	end
	state.loading = true
	notify("loading source...", 2)
	task.spawn(function()
		local countBefore = #state.catalog
		for _, path in ipairs({
			SOURCE_URL,
			SOURCE_URL .. "index.html",
			SOURCE_URL .. "animations.json",
			SOURCE_URL .. "list.json",
			SOURCE_URL .. "manifest.json",
		}) do
			local ok, body = pcall(function()
				return game:HttpGet(path)
			end)
			if ok and type(body) == "string" and body ~= "" then
				local function add(name, url)
					url = normalizeUrl(url, path)
					if not url then
						return
					end
					for _, e in ipairs(state.catalog) do
						if e.url == url then
							return
						end
					end
					state.catalog[#state.catalog + 1] = {
						name = trim(name) ~= "" and trim(name) or nameFromUrl(url),
						url  = url,
					}
				end
				for name, url in body:gmatch('%["(.-)"%]%s*=%s*"([^"]+)"') do
					add(name, url)
				end
				for name, url in body:gmatch("%['(.-)'%]%s*=%s*'([^']+)'") do
					add(name, url)
				end
				for url in body:gmatch('[Hh][Rr][Ee][Ff]%s*=%s*"([^"]+)"') do
					add(nameFromUrl(url), url)
				end
				for url in body:gmatch("[Hh][Rr][Ee][Ff]%s*=%s*'([^']+)'") do
					add(nameFromUrl(url), url)
				end
				if #state.catalog > countBefore then
					break
				end
			end
		end
		state.loaded  = #state.catalog > 0
		state.loading = false
		notify(state.loaded and ("loaded " .. tostring(#state.catalog) .. " source animations") or "catalog unavailable", 2.4)
		if refreshList then
			refreshList()
		end
	end)
end

----------------------------------------------------------------------
-- // Core: run / stop
----------------------------------------------------------------------
local function stopLocalTracks()
	local char = player.Character
	if not char then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		pcall(function()
			track:Stop(0)
		end)
	end
end

local function runReanimation(url, name)
	url = normalizeUrl(url)
	if not url then
		notify("invalid animation url", 2)
		return false
	end
	local display = trim(name) ~= "" and trim(name) or nameFromUrl(url)
	state.activeUrl  = url
	state.activeName = display
	state.lastUrl    = url
	state.lastName   = display
	saveConfig()
	notify("loading source...", 2)
	if refreshList then
		refreshList()
	end
	task.spawn(function()
		local ok, err = pcall(function()
			local response = game:HttpGet(url)
			local chunk = loadstring(response)
			if type(chunk) ~= "function" then
				error("loadstring unavailable")
			end
			chunk()
		end)
		notify(ok and ("running " .. tostring(state.activeName)) or ("failed: " .. tostring(err):sub(1, 42)), ok and 1.8 or 3)
		if refreshList then
			refreshList()
		end
	end)
	return true
end

local function stopReanimation()
	stopLocalTracks()
	state.activeUrl  = nil
	state.activeName = nil
	notify("stopped local tracks", 1.6)
	if refreshList then
		refreshList()
	end
	return true
end

local function replayReanimation()
	if state.lastUrl then
		return runReanimation(state.lastUrl, state.lastName)
	end
	notify("nothing to replay", 1.6)
	return false
end

local function randomReanimation()
	local list = buildList()
	if #list == 0 then
		notify("nothing to play", 1.6)
		return false
	end
	local pick = list[math.random(1, #list)]
	return runReanimation(pick.url, pick.name)
end

local function addCustom(name, url)
	url = normalizeUrl(url)
	if not url then
		notify("invalid url", 1.8)
		return false
	end
	for _, e in ipairs(state.custom) do
		if e.url == url then
			notify("already added", 1.6)
			return false
		end
	end
	state.custom[#state.custom + 1] = {
		name = trim(name) ~= "" and trim(name) or nameFromUrl(url),
		url  = url,
	}
	saveConfig()
	notify("added", 1.4)
	if refreshList then
		refreshList()
	end
	return true
end

local function removeCustom(url)
	for i, e in ipairs(state.custom) do
		if e.url == url then
			table.remove(state.custom, i)
			state.favs[url] = nil
			state.keys[url] = nil
			saveConfig()
			if refreshList then
				refreshList()
			end
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
-- // Lookup for commands: exact url -> exact name -> partial
----------------------------------------------------------------------
local function findAnimation(query)
	query = trim(query):lower()
	if query == "" then
		return nil
	end
	local list = buildList()
	for _, e in ipairs(list) do
		if e.url:lower() == query then
			return e
		end
	end
	for _, e in ipairs(list) do
		if e.name:lower() == query then
			return e
		end
	end
	for _, e in ipairs(list) do
		if e.name:lower():find(query, 1, true) or e.url:lower():find(query, 1, true) then
			return e
		end
	end
	return nil
end

----------------------------------------------------------------------
-- // UI — mobile-first, touch sized
----------------------------------------------------------------------
local guiParent
do
	local ok, coreGui = pcall(function()
		return game:GetService("CoreGui")
	end)
	guiParent = (ok and coreGui) or playerGui
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "M7ReanimationStandalone"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 999
screenGui.Parent = guiParent

-- viewport scaling (phones land around 0.75–0.95, tablets near 1)
local uiScale = Instance.new("UIScale")
uiScale.Scale = 1
uiScale.Parent = screenGui

local function rescale()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local vp = cam.ViewportSize
	if vp.X <= 0 or vp.Y <= 0 then
		return
	end
	uiScale.Scale = math.clamp(math.min(vp.X / 720, vp.Y / 820), 0.62, 1)
end
rescale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end

-- toast
local toastLabel
do
	local toast = Instance.new("TextLabel")
	toast.Name = "Toast"
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.Position = UDim2.new(0.5, 0, 0, 54)
	toast.Size = UDim2.new(0, 320, 0, 30)
	toast.BackgroundColor3 = C.Chrome
	toast.BackgroundTransparency = 0.06
	toast.BorderSizePixel = 0
	toast.Font = Enum.Font.GothamMedium
	toast.Text = ""
	toast.TextColor3 = C.Text
	toast.TextSize = 12
	toast.TextTruncate = Enum.TextTruncate.AtEnd
	toast.ZIndex = 400
	toast.Visible = false
	toast.Parent = screenGui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = toast
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.BorderSoft
	stroke.Thickness = 1
	stroke.Transparency = 0.4
	stroke.Parent = toast
	toastLabel = toast
end

local toastToken = 0
function notify(msg, time)
	toastToken = toastToken + 1
	local token = toastToken
	toastLabel.Text = tostring(msg or "")
	toastLabel.Visible = true
	task.delay(tonumber(time) or 2, function()
		if token == toastToken then
			toastLabel.Visible = false
		end
	end)
end

-- small instance helper
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
		LineJoinMode = Enum.LineJoinMode.Round,
	}, parent)
end

----------------------------------------------------------------------
-- // Floating toggle button (open/close)
----------------------------------------------------------------------
local toggleBtn = mk("TextButton", {
	Name = "M7ReanimToggle",
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

----------------------------------------------------------------------
-- // Popup window
----------------------------------------------------------------------
local POPUP_W, POPUP_H = 340, 470

local popup = mk("Frame", {
	Name = "ReanimationPopup",
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

-- title bar (drag handle)
local titleBar = mk("Frame", {
	Name = "TitleBar",
	Size = UDim2.new(1, 0, 0, 40),
	BackgroundColor3 = C.Surface,
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	ZIndex = 201,
}, popup)
corner(titleBar, 12)
mk("Frame", { -- square off bottom corners of title bar
	Size = UDim2.new(1, 0, 0, 12),
	Position = UDim2.new(0, 0, 1, -12),
	BackgroundColor3 = C.Surface,
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	ZIndex = 201,
}, titleBar)

mk("TextLabel", {
	Size = UDim2.new(1, -90, 1, 0),
	Position = UDim2.new(0, 12, 0, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "reanimation",
	TextColor3 = C.Text,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	ZIndex = 203,
}, titleBar)

local statusDot = mk("Frame", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -76, 0.5, 0),
	Size = UDim2.new(0, 8, 0, 8),
	BackgroundColor3 = C.Dim,
	BorderSizePixel = 0,
	ZIndex = 203,
}, titleBar)
corner(statusDot, 999)

local statusText = mk("TextLabel", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -88, 0.5, 0),
	Size = UDim2.new(0, 120, 1, 0),
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

-- dragging (touch + mouse)
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

-- body container
local body = mk("Frame", {
	Size = UDim2.new(1, 0, 1, -40),
	Position = UDim2.new(0, 0, 0, 40),
	BackgroundTransparency = 1,
	ZIndex = 202,
}, popup)

-- control row: replay | stop | random | load
local controls = mk("Frame", {
	Size = UDim2.new(1, -16, 0, 34),
	Position = UDim2.new(0, 8, 0, 8),
	BackgroundTransparency = 1,
	ZIndex = 203,
}, body)
mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 6),
}, controls)

local function controlButton(text, accent, callback)
	local b = mk("TextButton", {
		Size = UDim2.new(0.25, -5, 1, 0),
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
	b.Activated:Connect(callback)
	return b
end

controlButton("replay", false, function()
	replayReanimation()
end)
controlButton("stop", false, function()
	stopReanimation()
end)
controlButton("random", false, function()
	randomReanimation()
end)
controlButton("source", false, function()
	state.loaded = false
	loadCatalog(true)
end)

-- search box
local searchBox = mk("TextBox", {
	Size = UDim2.new(1, -16, 0, 34),
	Position = UDim2.new(0, 8, 0, 48),
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
	TextTruncate = Enum.TextTruncate.AtEnd,
	ZIndex = 203,
}, body)
corner(searchBox, 8)
stroke(searchBox, C.BorderSoft, 0.5, 1)
do
	local pad = mk("UIPadding", {}, searchBox)
	pad.PaddingLeft = UDim.new(0, 10)
end

-- custom add row: name | url | add
local addRow = mk("Frame", {
	Size = UDim2.new(1, -16, 0, 34),
	Position = UDim2.new(0, 8, 0, 88),
	BackgroundTransparency = 1,
	ZIndex = 203,
}, body)
mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 6),
}, addRow)

local nameBox = mk("TextBox", {
	Size = UDim2.new(0.32, -4, 1, 0),
	BackgroundColor3 = C.Surface,
	BackgroundTransparency = 0.12,
	BorderSizePixel = 0,
	ClearTextOnFocus = false,
	Font = Enum.Font.GothamMedium,
	PlaceholderText = "name",
	PlaceholderColor3 = C.Dim,
	Text = "",
	TextColor3 = C.Text,
	TextSize = 11,
	TextTruncate = Enum.TextTruncate.AtEnd,
	ZIndex = 204,
}, addRow)
corner(nameBox, 8)
stroke(nameBox, C.BorderSoft, 0.5, 1)

local urlBox = mk("TextBox", {
	Size = UDim2.new(0.48, -4, 1, 0),
	BackgroundColor3 = C.Surface,
	BackgroundTransparency = 0.12,
	BorderSizePixel = 0,
	ClearTextOnFocus = false,
	Font = Enum.Font.GothamMedium,
	PlaceholderText = "https://...",
	PlaceholderColor3 = C.Dim,
	Text = "",
	TextColor3 = C.Text,
	TextSize = 11,
	TextTruncate = Enum.TextTruncate.AtEnd,
	ZIndex = 204,
}, addRow)
corner(urlBox, 8)
stroke(urlBox, C.BorderSoft, 0.5, 1)

local addBtn = mk("TextButton", {
	Size = UDim2.new(0.2, 0, 1, 0),
	BackgroundColor3 = C.Accent,
	BackgroundTransparency = 0.05,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	Text = "+ add",
	TextColor3 = C.AccentText,
	TextSize = 11,
	AutoButtonColor = false,
	ZIndex = 204,
}, addRow)
corner(addBtn, 8)

addBtn.Activated:Connect(function()
	local url = trim(urlBox.Text)
	if url == "" then
		notify("enter a url first", 1.6)
		return
	end
	if addCustom(nameBox.Text, url) then
		nameBox.Text = ""
		urlBox.Text = ""
	end
end)

-- filter tabs: all / fav / own
local filterRow = mk("Frame", {
	Size = UDim2.new(1, -16, 0, 28),
	Position = UDim2.new(0, 8, 0, 128),
	BackgroundTransparency = 1,
	ZIndex = 203,
}, body)
mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 6),
}, filterRow)

local filterButtons = {}
local function setFilter(f)
	state.filter = f
	for name, btn in pairs(filterButtons) do
		btn.BackgroundColor3 = name == f and C.Surface2 or C.Surface
		btn.TextColor3 = name == f and C.AccentText or C.Muted
	end
	if refreshList then
		refreshList()
	end
end

for i, f in ipairs({ "all", "fav", "own" }) do
	local b = mk("TextButton", {
		LayoutOrder = i,
		Size = UDim2.new(0, 58, 1, 0),
		BackgroundColor3 = C.Surface,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = f,
		TextColor3 = C.Muted,
		TextSize = 11,
		AutoButtonColor = false,
		ZIndex = 204,
	}, filterRow)
	corner(b, 8)
	filterButtons[f] = b
	b.Activated:Connect(function()
		setFilter(f)
	end)
end

-- list scroll frame
local scroll = mk("ScrollingFrame", {
	Size = UDim2.new(1, -16, 1, -166),
	Position = UDim2.new(0, 8, 0, 162),
	BackgroundColor3 = C.Bg,
	BackgroundTransparency = 0.3,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = C.Dim,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 203,
}, body)
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
local ROW_H = 44

local function makeRow(entry, index)
	local row = mk("Frame", {
		LayoutOrder = index,
		Size = UDim2.new(1, -4, 0, ROW_H),
		BackgroundColor3 = C.Surface2,
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
		ZIndex = 205,
	}, scroll)
	corner(row, 8)

	local isActive = state.activeUrl == entry.url
	local isFav = state.favs[entry.url] == true

	mk("TextLabel", {
		Size = UDim2.new(1, -118, 0, 18),
		Position = UDim2.new(0, 8, 0, 5),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = entry.name,
		TextColor3 = isActive and C.AccentText or C.Text,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 206,
	}, row)

	mk("TextLabel", {
		Size = UDim2.new(1, -118, 0, 14),
		Position = UDim2.new(0, 8, 0, 24),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = entry.url,
		TextColor3 = C.Dim,
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 206,
	}, row)

	-- fav toggle
	local favBtn = mk("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -86, 0.5, 0),
		Size = UDim2.new(0, 26, 0, 26),
		BackgroundColor3 = C.Surface,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = isFav and "★" or "☆",
		TextColor3 = isFav and C.AccentText or C.VMuted,
		TextSize = 14,
		AutoButtonColor = false,
		ZIndex = 207,
	}, row)
	corner(favBtn, 6)

	favBtn.Activated:Connect(function()
		if state.favs[entry.url] == true then
			state.favs[entry.url] = nil
		else
			state.favs[entry.url] = true
		end
		saveConfig()
		refreshList()
	end)

	-- keybind capture
	local boundKey = state.keys[entry.url]
	local keyBtn = mk("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -56, 0.5, 0),
		Size = UDim2.new(0, 26, 0, 26),
		BackgroundColor3 = C.Surface,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = boundKey and boundKey:sub(1, 4) or "key",
		TextColor3 = boundKey and C.Text or C.Dim,
		TextSize = 9,
		AutoButtonColor = false,
		ZIndex = 207,
	}, row)
	corner(keyBtn, 6)

	keyBtn.Activated:Connect(function()
		if state.capturing == entry.url then
			state.capturing = nil
			keyBtn.Text = boundKey and boundKey:sub(1, 4) or "key"
			keyBtn.TextColor3 = boundKey and C.Text or C.Dim
			return
		end
		state.capturing = entry.url
		keyBtn.Text = "..."
		keyBtn.TextColor3 = C.AccentText
		notify("press a key (tap again to clear)", 2.4)
	end)

	-- custom delete
	if entry.custom then
		local delBtn = mk("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -86, 0.5, -14),
			Size = UDim2.new(0, 26, 0, 12),
			BackgroundColor3 = C.Surface,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Text = "del",
			TextColor3 = C.Bad,
			TextSize = 8,
			AutoButtonColor = false,
			ZIndex = 207,
			Visible = false,
		}, row)
		corner(delBtn, 4)
		delBtn.Visible = true
		delBtn.Position = UDim2.new(1, -86, 0.5, 14)
		favBtn.Position = UDim2.new(1, -86, 0.5, -14)
		favBtn.Size = UDim2.new(0, 26, 0, 26)
		delBtn.Activated:Connect(function()
			removeCustom(entry.url)
		end)
	end

	-- play button
	local playBtn = mk("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.new(0, 42, 0, 28),
		BackgroundColor3 = isActive and C.Accent or C.Surface2,
		BackgroundTransparency = isActive and 0.05 or 0.1,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = isActive and "live" or "play",
		TextColor3 = isActive and C.AccentText or C.Text,
		TextSize = 10,
		AutoButtonColor = false,
		ZIndex = 207,
	}, row)
	corner(playBtn, 7)

	playBtn.Activated:Connect(function()
		if state.activeUrl == entry.url then
			return
		end
		runReanimation(entry.url, entry.name)
	end)

	return row
end

local function updateStatus()
	if state.activeUrl then
		statusDot.BackgroundColor3 = C.Good
		statusText.Text = "running " .. tostring(state.activeName or "")
	else
		statusDot.BackgroundColor3 = C.Dim
		statusText.Text = "idle"
	end
end

local function passesFilter(entry)
	if state.filter == "fav" and state.favs[entry.url] ~= true then
		return false
	end
	if state.filter == "own" and not entry.custom then
		return false
	end
	local q = trim(state.search):lower()
	if q ~= "" then
		if not entry.name:lower():find(q, 1, true)
			and not entry.url:lower():find(q, 1, true) then
			return false
		end
	end
	return true
end

function refreshList()
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local list = buildList()
	local shown = 0
	for _, entry in ipairs(list) do
		if shown >= 80 then
			break
		end
		if passesFilter(entry) then
			shown = shown + 1
			makeRow(entry, shown)
		end
	end
	if shown == 0 then
		local empty = mk("TextLabel", {
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Text = state.loading and "loading source..." or "no animations",
			TextColor3 = C.Dim,
			TextSize = 11,
			ZIndex = 206,
		}, scroll)
		empty.LayoutOrder = 1
	end
	updateStatus()
end

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	state.search = searchBox.Text
	refreshList()
end)

----------------------------------------------------------------------
-- // Keybind capture + global keybind trigger
----------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	-- capture mode
	if state.capturing then
		local keyName = keyFromInput(input)
		if keyName then
			local url = state.capturing
			state.capturing = nil
			if keyName == "Escape" then
				state.keys[url] = nil
			else
				-- one key per animation: clear duplicate bindings
				for otherUrl, otherKey in pairs(state.keys) do
					if otherUrl ~= url and otherKey == keyName then
						state.keys[otherUrl] = nil
					end
				end
				state.keys[url] = keyName
			end
			saveConfig()
			notify(keyName == "Escape" and "keybind cleared" or ("bound " .. keyName), 1.6)
			refreshList()
		end
		return
	end

	-- trigger mode
	if gameProcessed then
		return
	end
	local keyName = keyFromInput(input)
	if not keyName or keyName == "Escape" then
		return
	end
	for url, bound in pairs(state.keys) do
		if bound == keyName then
			runReanimation(url)
			return
		end
	end
end)

-- // clear capture if popup closes
closeBtn.Activated:Connect(function()
	state.capturing = nil
	state.popupOpen = false
	popup.Visible = false
end)

local function setPopup(open)
	state.capturing = nil
	state.popupOpen = open
	popup.Visible = open
	if open then
		loadCatalog(false)
		refreshList()
	end
end

toggleBtn.Activated:Connect(function()
	setPopup(not state.popupOpen)
end)

-- // toggle button drag (reposition anywhere on screen)
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

-- // stop local tracks when the character dies / respawns
player.CharacterAdded:Connect(function()
	-- fresh character: nothing to stop, external scripts re-apply themselves
	updateStatus()
end)

----------------------------------------------------------------------
-- // Command interface (getgenv / _G / shared)
----------------------------------------------------------------------
local function runCommand(args)
	args = trim(args):lower()
	if args == "" then
		setPopup(true)
		return true
	end
	if args == "stop" or args == "off" then
		return stopReanimation()
	end
	if args == "replay" then
		return replayReanimation()
	end
	if args == "random" then
		return randomReanimation()
	end
	if args == "toggle" or args == "open" or args == "close" then
		setPopup(args ~= "close")
		return true
	end
	local addPrefix = args:match("^add%s+")
	if addPrefix then
		local url = trim(args:sub(#addPrefix + 1))
		if url ~= "" then
			return addCustom("", url)
		end
		return false
	end
	-- direct url?
	if args:find("^https?://") then
		return runReanimation(args)
	end
	-- name lookup
	local found = findAnimation(args)
	if found then
		return runReanimation(found.url, found.name)
	end
	notify("not found", 1.6)
	return false
end

local api = {
	state       = state,
	run         = runReanimation,
	stop        = stopReanimation,
	replay      = replayReanimation,
	random      = randomReanimation,
	add         = addCustom,
	remove      = removeCustom,
	refresh     = function() loadCatalog(true) end,
	open        = function() setPopup(true) end,
	close       = function() setPopup(false) end,
	toggle      = function() setPopup(not state.popupOpen) end,
	command     = runCommand,
	notify      = notify,
	buildList   = buildList,
}

local envTargets = {}
pcall(function()
	local genv = getgenv and getgenv()
	if type(genv) == "table" then
		envTargets[#envTargets + 1] = genv
	end
end)
pcall(function()
	if type(shared) == "table" then
		envTargets[#envTargets + 1] = shared
	end
end)
pcall(function()
	envTargets[#envTargets + 1] = _G
end)

for _, env in ipairs(envTargets) do
	env.Reanimation       = api
	env.Reanim            = api
	env.M7Reanimation     = api
end

----------------------------------------------------------------------
-- // Boot
----------------------------------------------------------------------
setFilter("all")
refreshList()
loadCatalog(false)
notify("reanimation loaded — tap R to open", 3)
