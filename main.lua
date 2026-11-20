if not shared then return warn("No shared, no script.") end
if not Drawing then return warn("Drawing library not available.") end

local playersService     = game:GetService("Players")
local runService         = game:GetService("RunService")
local userInputService   = game:GetService("UserInputService")
local coreGui            = game:GetService("CoreGui")
local workspaceService   = game:GetService("Workspace")
local guiService         = game:GetService("GuiService")
local tweenService       = game:GetService("TweenService")

local localPlayer = playersService.LocalPlayer
local camera      = workspaceService.CurrentCamera
local guiInset    = guiService:GetGuiInset()

-- Module table
local Holeware = {
    name = "Holeware", esp = false, aimbot = false,
    teamCheck = true, fov = 150, smoothness = 0.25,
}

if shared.Holeware then
    pcall(function() shared.Holeware.destroy() end)
end
shared.Holeware = Holeware

-- Palette (Neverlose-inspired)
local COLORS = {
    bg        = Color3.fromRGB(14, 14, 18),
    panel     = Color3.fromRGB(20, 20, 26),
    sidebar   = Color3.fromRGB(16, 16, 22),
    header    = Color3.fromRGB(24, 24, 32),
    accent    = Color3.fromRGB(157, 123, 255),
    text      = Color3.fromRGB(230, 230, 240),
    textDim   = Color3.fromRGB(120, 120, 140),
    toggleOff = Color3.fromRGB(40, 40, 52),
    knobOff   = Color3.fromRGB(120, 120, 140),
    stroke    = Color3.fromRGB(45, 45, 60),
    danger    = Color3.fromRGB(255, 90, 90),
}
local ESP_COLOR = Color3.fromRGB(255, 60, 60)

-- State
local espObjects, connections, guiRefs = {}, {}, {}
local tabContents, tabButtons = {}, {}

-- Util
local drawingNew = Drawing.new
local function newDrawing(class, props)
    local d = drawingNew(class)
    for k, v in pairs(props) do d[k] = v end
    return d
end

local function isTeammate(player)
    if not Holeware.teamCheck then return false end
    return localPlayer.Team ~= nil and localPlayer.Team == player.Team
end

-- Tab switching (forward-declared so closures can capture it)
local function switchTab(name)
    for n, frame in pairs(tabContents) do frame.Visible = (n == name) end
    for n, api in pairs(tabButtons) do api.setActive(n == name) end
end

-- ============ ESP ============
local function createEsp(player)
    espObjects[player] = {
        box      = newDrawing("Square", {Thickness = 1, Color = ESP_COLOR, Filled = false, Visible = false}),
        name     = newDrawing("Text",   {Size = 14, Center = true, Outline = true, Color = Color3.new(1,1,1), Visible = false}),
        healthBg = newDrawing("Square", {Thickness = 1, Filled = true, Color = Color3.fromRGB(30,30,30), Visible = false}),
        healthFg = newDrawing("Square", {Thickness = 1, Filled = true, Color = Color3.fromRGB(60,220,100), Visible = false}),
    }
    return espObjects[player]
end

local function destroyEsp(player)
    local objs = espObjects[player]
    if not objs then return end
    for _, d in pairs(objs) do pcall(function() d:Remove() end) end
    espObjects[player] = nil
end

local function updateEsp()
    for _, player in ipairs(playersService:GetPlayers()) do
        if player == localPlayer or isTeammate(player) then destroyEsp(player); continue end
        local ch  = player.Character
        local head = ch and ch:FindFirstChild("Head")
        local root = ch and ch:FindFirstChild("HumanoidRootPart")
        local hum  = ch and ch:FindFirstChildOfClass("Humanoid")
        if head and root and hum and hum.Health > 0 then
            local objs = espObjects[player] or createEsp(player)
            local topPos, onScreen = camera:WorldToViewportPoint(head.Position + Vector3.new(0, 1, 0))
            local botPos = camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))
            if onScreen then
                local h = math.abs(topPos.Y - botPos.Y)
                local w = h * 0.55
                objs.box.Size     = Vector2.new(w, h)
                objs.box.Position = Vector2.new(topPos.X - w/2, topPos.Y)
                objs.box.Visible  = true
                objs.name.Position = Vector2.new(topPos.X, topPos.Y - 18)
                objs.name.Text     = player.Name
                objs.name.Visible  = true
                local ratio = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                objs.healthBg.Size     = Vector2.new(3, h)
                objs.healthBg.Position = Vector2.new(topPos.X - w/2 - 6, topPos.Y)
                objs.healthBg.Visible  = true
                objs.healthFg.Size     = Vector2.new(3, h * ratio)
                objs.healthFg.Position = Vector2.new(topPos.X - w/2 - 6, topPos.Y + (h - h * ratio))
                objs.healthFg.Visible  = true
            else
                for _, d in pairs(objs) do d.Visible = false end
            end
        else
            destroyEsp(player)
        end
    end
end

-- ============ AimBot ============
local function getClosestTarget()
    local mousePos = userInputService:GetMouseLocation()
    local closest, dist = nil, Holeware.fov
    for _, player in ipairs(playersService:GetPlayers()) do
        if player == localPlayer or isTeammate(player) then continue end
        local ch = player.Character
        if not ch then continue end
        local head = ch:FindFirstChild("Head")
        local hum  = ch:FindFirstChildOfClass("Humanoid")
        if not head or not hum or hum.Health <= 0 then continue end
        local sp, onScreen = camera:WorldToViewportPoint(head.Position)
        if not onScreen then continue end
        local d = (Vector2.new(sp.X, sp.Y) - mousePos).Magnitude
        if d < dist then closest, dist = head, d end
    end
    return closest
end

local function aimAt(target)
    local sp, onScreen = camera:WorldToViewportPoint(target.Position)
    if not onScreen then return end
    local mousePos = userInputService:GetMouseLocation()
    local delta = Vector2.new(sp.X, sp.Y) - mousePos
    local mag = delta.Magnitude
    if mag < 1 or mag > Holeware.fov then return end
    local move = delta.Unit * math.max(mag * Holeware.smoothness, 1)
    if type(mousemoverel) == "function" then
        pcall(mousemoverel, move.X, move.Y)
    end
end

-- ============ FOV Circle ============
local fovCircle
local function updateFovCircle()
    if Holeware.aimbot then
        if not fovCircle then
            fovCircle = newDrawing("Circle", {
                Thickness = 1, Filled = false, Color = ESP_COLOR,
                Transparency = 0.6, NumSides = 64,
            })
        end
        fovCircle.Position = userInputService:GetMouseLocation()
        fovCircle.Radius   = Holeware.fov
        fovCircle.Visible  = true
    elseif fovCircle then
        fovCircle.Visible = false
    end
end

-- ============ GUI ============
local function createGui()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "HolewareGui"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = (gethui and gethui()) or coreGui
    guiRefs.screenGui = screenGui

    local main = Instance.new("Frame")
    main.Size = UDim2.fromOffset(460, 340)
    main.Position = UDim2.new(0, 20, 0, 20)
    main.BackgroundColor3 = COLORS.panel
    main.BorderSizePixel = 0
    main.ClipsDescendants = true
    main.Active = true
    main.Parent = screenGui
    guiRefs.main = main

    local mc = Instance.new("UICorner"); mc.CornerRadius = UDim.new(0, 8); mc.Parent = main
    local ms = Instance.new("UIStroke"); ms.Color = COLORS.stroke; ms.Thickness = 1; ms.Transparency = 0.3; ms.Parent = main

    -- Header
    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 40)
    header.BackgroundColor3 = COLORS.header
    header.BorderSizePixel = 0
    header.Parent = main

    local hb = Instance.new("Frame")
    hb.Size = UDim2.new(1, 0, 0, 1); hb.Position = UDim2.new(0, 0, 1, -1)
    hb.BackgroundColor3 = COLORS.stroke; hb.BorderSizePixel = 0; hb.Parent = header

    local logo = Instance.new("Frame")
    logo.Size = UDim2.fromOffset(10, 10); logo.Position = UDim2.fromOffset(16, 15)
    logo.BackgroundColor3 = COLORS.accent; logo.Parent = header
    local lc = Instance.new("UICorner"); lc.CornerRadius = UDim.new(1, 0); lc.Parent = logo

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(0, 200, 1, 0); title.Position = UDim2.fromOffset(34, 0)
    title.BackgroundTransparency = 1; title.Text = "HOLEWARE"
    title.TextColor3 = COLORS.text; title.Font = Enum.Font.GothamBold
    title.TextSize = 14; title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    local ver = Instance.new("TextLabel")
    ver.Size = UDim2.fromOffset(60, 40); ver.Position = UDim2.new(1, -100, 0, 0)
    ver.BackgroundTransparency = 1; ver.Text = "v1.0"
    ver.TextColor3 = COLORS.textDim; ver.Font = Enum.Font.Gotham; ver.TextSize = 11
    ver.TextXAlignment = Enum.TextXAlignment.Right; ver.Parent = header

    local close = Instance.new("TextButton")
    close.Size = UDim2.fromOffset(28, 28); close.Position = UDim2.new(1, -34, 0, 6)
    close.BackgroundTransparency = 1; close.Text = "×"
    close.TextColor3 = COLORS.textDim; close.Font = Enum.Font.GothamBold
    close.TextSize = 20; close.Parent = header
    close.MouseEnter:Connect(function() close.TextColor3 = COLORS.danger end)
    close.MouseLeave:Connect(function() close.TextColor3 = COLORS.textDim end)
    close.MouseButton1Click:Connect(function() Holeware.destroy() end)

    -- Drag
    local dragging, dragStart, startPos = false, nil, nil
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging, dragStart, startPos = true, input.Position, main.Position
        end
    end)
    connections[#connections+1] = userInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                     startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    connections[#connections+1] = userInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)

    -- Sidebar
    local sidebar = Instance.new("Frame")
    sidebar.Size = UDim2.new(0, 110, 1, -40); sidebar.Position = UDim2.fromOffset(0, 40)
    sidebar.BackgroundColor3 = COLORS.sidebar; sidebar.BorderSizePixel = 0; sidebar.Parent = main

    local sb = Instance.new("Frame")
    sb.Size = UDim2.new(0, 1, 1, 0); sb.Position = UDim2.new(1, -1, 0, 0)
    sb.BackgroundColor3 = COLORS.stroke; sb.BorderSizePixel = 0; sb.Parent = sidebar

    -- Content
    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -110, 1, -40); content.Position = UDim2.fromOffset(110, 40)
    content.BackgroundTransparency = 1; content.ClipsDescendants = true; content.Parent = main

    local function makeTabContent(name)
        local f = Instance.new("Frame")
        f.Size = UDim2.new(1, -20, 1, -20); f.Position = UDim2.fromOffset(10, 10)
        f.BackgroundTransparency = 1; f.Visible = false; f.Parent = content
        tabContents[name] = f
        return f
    end

    local function makeTabButton(text, y, name)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -16, 0, 32); btn.Position = UDim2.fromOffset(8, y)
        btn.BackgroundTransparency = 1; btn.Text = ""; btn.Parent = sidebar
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 4); c.Parent = btn

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -20, 1, 0); lbl.Position = UDim2.fromOffset(16, 0)
        lbl.BackgroundTransparency = 1; lbl.Text = text
        lbl.TextColor3 = COLORS.textDim; lbl.Font = Enum.Font.GothamMedium
        lbl.TextSize = 13; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = btn

        local ind = Instance.new("Frame")
        ind.Size = UDim2.new(0, 3, 0.5, 0); ind.Position = UDim2.new(0, 0, 0.25, 0)
        ind.BackgroundColor3 = COLORS.accent; ind.BackgroundTransparency = 1
        ind.BorderSizePixel = 0; ind.Parent = btn
        local ic = Instance.new("UICorner"); ic.CornerRadius = UDim.new(1, 0); ic.Parent = ind

        local setActive
        setActive = function(active)
            if active then
                btn.BackgroundTransparency = 0
                btn.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
                lbl.TextColor3 = COLORS.text
                ind.BackgroundTransparency = 0
            else
                btn.BackgroundTransparency = 1
                lbl.TextColor3 = COLORS.textDim
                ind.BackgroundTransparency = 1
            end
        end

        btn.MouseEnter:Connect(function()
            if ind.BackgroundTransparency == 1 then lbl.TextColor3 = Color3.fromRGB(180,180,200) end
        end)
        btn.MouseLeave:Connect(function()
            if ind.BackgroundTransparency == 1 then lbl.TextColor3 = COLORS.textDim end
        end)

        tabButtons[name] = { setActive = setActive }
        btn.MouseButton1Click:Connect(function() switchTab(name) end)
    end

    -- Toggle switch
    local function makeToggle(parent, text, initial, onChange, y)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 36); row.Position = UDim2.fromOffset(0, y)
        row.BackgroundTransparency = 1; row.Parent = parent

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -60, 1, 0); lbl.BackgroundTransparency = 1
        lbl.Text = text; lbl.TextColor3 = COLORS.text
        lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 13
        lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = row

        local sw = Instance.new("Frame")
        sw.Size = UDim2.fromOffset(38, 20); sw.Position = UDim2.new(1, -38, 0.5, -10)
        sw.BackgroundColor3 = COLORS.toggleOff; sw.BorderSizePixel = 0; sw.Parent = row
        local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(1, 0); sc.Parent = sw

        local knob = Instance.new("Frame")
        knob.Size = UDim2.fromOffset(16, 16); knob.Position = UDim2.fromOffset(2, 2)
        knob.BackgroundColor3 = COLORS.knobOff; knob.BorderSizePixel = 0; knob.Parent = sw
        local kc = Instance.new("UICorner"); kc.CornerRadius = UDim.new(1, 0); kc.Parent = knob

        local state = initial
        local function update()
            if state then
                sw.BackgroundColor3   = COLORS.accent
                knob.Position         = UDim2.new(1, -18, 0, 2)
                knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            else
                sw.BackgroundColor3   = COLORS.toggleOff
                knob.Position         = UDim2.fromOffset(2, 2)
                knob.BackgroundColor3 = COLORS.knobOff
            end
        end
        update()

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.fromScale(1, 1); btn.BackgroundTransparency = 1
        btn.Text = ""; btn.ZIndex = 2; btn.Parent = row
        btn.MouseButton1Click:Connect(function()
            state = not state; update(); onChange(state)
        end)
        return row
    end

    -- Slider
    local function makeSlider(parent, text, initial, min, max, step, onChange, y)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 48); row.Position = UDim2.fromOffset(0, y)
        row.BackgroundTransparency = 1; row.Parent = parent

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -60, 0, 18); lbl.BackgroundTransparency = 1
        lbl.Text = text; lbl.TextColor3 = COLORS.text
        lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 13
        lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = row

        local val = Instance.new("TextLabel")
        val.Size = UDim2.fromOffset(60, 18); val.Position = UDim2.new(1, -60, 0, 0)
        val.BackgroundTransparency = 1; val.Text = tostring(initial)
        val.TextColor3 = COLORS.accent; val.Font = Enum.Font.GothamBold
        val.TextSize = 13; val.TextXAlignment = Enum.TextXAlignment.Right; val.Parent = row

        local track = Instance.new("Frame")
        track.Size = UDim2.new(1, 0, 0, 4); track.Position = UDim2.new(0, 0, 0, 32)
        track.BackgroundColor3 = COLORS.toggleOff; track.BorderSizePixel = 0; track.Parent = row
        local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(1, 0); tc.Parent = track

        local pct0 = (initial - min) / (max - min)
        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(pct0, 0, 1, 0); fill.BackgroundColor3 = COLORS.accent
        fill.BorderSizePixel = 0; fill.Parent = track
        local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(1, 0); fc.Parent = fill

        local knob = Instance.new("Frame")
        knob.Size = UDim2.fromOffset(12, 12); knob.Position = UDim2.new(pct0, -6, 0.5, -6)
        knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        knob.BorderSizePixel = 0; knob.Parent = track
        local kc = Instance.new("UICorner"); kc.CornerRadius = UDim.new(1, 0); kc.Parent = knob

        local current, dragging = initial, false
        local function setValue(v)
            current = math.clamp(v, min, max)
            local p = (current - min) / (max - min)
            fill.Size = UDim2.new(p, 0, 1, 0)
            knob.Position = UDim2.new(p, -6, 0.5, -6)
            val.Text = tostring(math.floor(current * 100) / 100)
            onChange(current)
        end
        local function updateFromX(mx)
            local ax, aw = track.AbsolutePosition.X, track.AbsoluteSize.X
            if aw <= 0 then return end
            local p = math.clamp((mx - ax) / aw, 0, 1)
            local raw = min + p * (max - min)
            setValue(math.floor(raw / step + 0.5) * step)
        end

        local hit = Instance.new("TextButton")
        hit.Size = UDim2.new(1, 16, 0, 20); hit.Position = UDim2.new(0, -8, 0.5, -10)
        hit.BackgroundTransparency = 1; hit.Text = ""; hit.ZIndex = 2; hit.Parent = track
        hit.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true; updateFromX(input.Position.X)
            end
        end)
        connections[#connections+1] = userInputService.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                updateFromX(input.Position.X)
            end
        end)
        connections[#connections+1] = userInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end)
        return row
    end

    local function makeSection(parent, text, y)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, 0, 0, 18); l.Position = UDim2.fromOffset(0, y)
        l.BackgroundTransparency = 1; l.Text = text
        l.TextColor3 = COLORS.textDim; l.Font = Enum.Font.GothamBold
        l.TextSize = 11; l.TextXAlignment = Enum.TextXAlignment.Left; l.Parent = parent
    end

    -- Sidebar tabs
    makeTabButton("Combat",  16, "Combat")
    makeTabButton("Visuals", 52, "Visuals")

    -- Combat tab
    local combat = makeTabContent("Combat")
    makeSection(combat, "AIMBOT", 0)
    makeToggle(combat, "Aim Assist", Holeware.aimbot,
        function(v) Holeware.aimbot = v end, 24)
    makeToggle(combat, "Team Check", Holeware.teamCheck,
        function(v) Holeware.teamCheck = v end, 64)
    makeSection(combat, "PARAMETERS", 116)
    makeSlider(combat, "FOV", Holeware.fov, 20, 800, 10,
        function(v) Holeware.fov = v end, 140)
    makeSlider(combat, "Smoothness", Holeware.smoothness, 0.05, 1, 0.05,
        function(v) Holeware.smoothness = v end, 196)

    -- Visuals tab
    local visuals = makeTabContent("Visuals")
    makeSection(visuals, "ESP", 0)
    makeToggle(visuals, "Player ESP", Holeware.esp,
        function(v) Holeware.esp = v end, 24)

    switchTab("Combat")

    -- Open animation
    main.Size = UDim2.fromOffset(414, 306)
    tweenService:Create(main, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = UDim2.fromOffset(460, 340)
    }):Play()
end

-- ============ Destroy ============
function Holeware.destroy()
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    connections = {}

    local toRemove = {}
    for p in pairs(espObjects) do toRemove[#toRemove+1] = p end
    for _, p in ipairs(toRemove) do destroyEsp(p) end

    if fovCircle then
        pcall(function() fovCircle:Remove() end)
        fovCircle = nil
    end
    if guiRefs.screenGui then
        pcall(function() guiRefs.screenGui:Destroy() end)
    end
    if shared.Holeware == Holeware then shared.Holeware = nil end
end

-- ============ Main loop ============
connections[#connections+1] = runService.RenderStepped:Connect(function()
    if Holeware.esp then
        updateEsp()
    else
        local toRemove = {}
        for p in pairs(espObjects) do toRemove[#toRemove+1] = p end
        for _, p in ipairs(toRemove) do destroyEsp(p) end
    end

    updateFovCircle()

    if Holeware.aimbot then
        local t = getClosestTarget()
        if t then aimAt(t) end
    end
end)

connections[#connections+1] = playersService.PlayerRemoving:Connect(function(player)
    destroyEsp(player)
end)

connections[#connections+1] = workspaceService:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    if workspaceService.CurrentCamera then camera = workspaceService.CurrentCamera end
end)

createGui()
