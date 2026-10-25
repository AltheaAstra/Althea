-- AltheaOS Window Manager for Roblox
-- Place this file as a ModuleScript named "AltheaOSWindowManager" in ReplicatedStorage.
-- Require it from LocalScripts and register all app windows with the same manager.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local WindowManager = {}
WindowManager.__index = WindowManager

local managerCache = setmetatable({}, { __mode = "k" })

local COLORS = {
    bar = Color3.fromRGB(14, 20, 30),
    barStroke = Color3.fromRGB(60, 78, 98),
    tab = Color3.fromRGB(25, 35, 49),
    tabActive = Color3.fromRGB(38, 57, 75),
    text = Color3.fromRGB(238, 243, 249),
    muted = Color3.fromRGB(154, 170, 188),
    accent = Color3.fromRGB(222, 190, 126),
    danger = Color3.fromRGB(210, 91, 91),
    button = Color3.fromRGB(31, 43, 59),
}

local function make(className, parent, props)
    local object = Instance.new(className)
    for key, value in pairs(props or {}) do
        object[key] = value
    end
    object.Parent = parent
    return object
end

local function addCorner(parent, radius)
    return make("UICorner", parent, { CornerRadius = UDim.new(0, radius or 8) })
end

local function addStroke(parent, color, thickness, transparency)
    return make("UIStroke", parent, {
        Color = color or COLORS.barStroke,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
    })
end

local function setZTree(guiObject, zIndex, depth)
    depth = depth or 0
    guiObject.ZIndex = zIndex + depth
    for _, child in ipairs(guiObject:GetChildren()) do
        if child:IsA("GuiObject") then
            setZTree(child, zIndex, depth + 1)
        end
    end
end

local function getViewportSize()
    local camera = workspace.CurrentCamera
    if camera then
        return camera.ViewportSize
    end
    return Vector2.new(1280, 720)
end

local function getTopLeftInset()
    local ok, inset = pcall(function()
        local topLeft = GuiService:GetGuiInset()
        return topLeft
    end)
    if ok and typeof(inset) == "Vector2" then
        return inset
    end
    return Vector2.new(0, 0)
end

local function isPointerBegin(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

function WindowManager.new(playerGui)
    playerGui = playerGui or Players.LocalPlayer:WaitForChild("PlayerGui")

    if managerCache[playerGui] then
        return managerCache[playerGui]
    end

    -- Remove stale shell/effect from earlier script versions so duplicated UI or blur cannot remain stuck.
    local staleShell = playerGui:FindFirstChild("AltheaOS_Shell")
    if staleShell then
        staleShell:Destroy()
    end
    local currentCamera = workspace.CurrentCamera
    if currentCamera then
        local staleBlur = currentCamera:FindFirstChild("AltheaOS_LocalBlur")
        if staleBlur and staleBlur:IsA("BlurEffect") then
            staleBlur:Destroy()
        end
    end
    local staleLightingBlur = Lighting:FindFirstChild("AltheaOS_LocalBlur")
    if staleLightingBlur and staleLightingBlur:IsA("BlurEffect") then
        staleLightingBlur:Destroy()
    end

    local self = setmetatable({}, WindowManager)
    self.playerGui = playerGui
    self.windows = {}
    self.openOrder = {}
    self.activeName = nil
    self.minimized = {}
    self.maximized = {}
    self.interaction = nil

    local screenGui = make("ScreenGui", playerGui, {
        Name = "AltheaOS_Shell",
        ResetOnSpawn = false,
        -- Keep controls in Roblox's safe UI area and never attempt to hide CoreGui.
        IgnoreGuiInset = false,
        DisplayOrder = 1000,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    self.screenGui = screenGui

    self.shade = make("TextButton", screenGui, {
        Name = "ModalShield",
        Size = UDim2.fromScale(1, 1),
        Position = UDim2.fromScale(0, 0),
        BackgroundColor3 = Color3.fromRGB(3, 7, 12),
        BackgroundTransparency = 0.42,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Active = true,
        Modal = true,
        Visible = false,
        ZIndex = 2,
    })

    self.topBar = make("Frame", screenGui, {
        Name = "OS_BottomTabDock",
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 12, 1, -10),
        Size = UDim2.new(1, -24, 0, 46),
        BackgroundColor3 = COLORS.bar,
        BackgroundTransparency = 0.02,
        BorderSizePixel = 0,
        Visible = true,
        ZIndex = 500,
    })
    addStroke(self.topBar, COLORS.barStroke, 1, 0.15)

    make("TextLabel", self.topBar, {
        Name = "Brand",
        Position = UDim2.fromOffset(16, 5),
        Size = UDim2.fromOffset(142, 23),
        BackgroundTransparency = 1,
        Text = "ALTHEA OS",
        TextColor3 = COLORS.accent,
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 501,
    })
    make("TextLabel", self.topBar, {
        Name = "Subtitle",
        Position = UDim2.fromOffset(17, 26),
        Size = UDim2.fromOffset(142, 14),
        BackgroundTransparency = 1,
        Text = "ROCKET SCIENCE SYSTEM",
        TextColor3 = COLORS.muted,
        Font = Enum.Font.GothamMedium,
        TextSize = 8,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 501,
    })

    self.tabs = make("ScrollingFrame", self.topBar, {
        Name = "WindowTabs",
        Position = UDim2.new(0, 168, 0, 4),
        Size = UDim2.new(1, -230, 1, -8),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.X,
        ScrollingDirection = Enum.ScrollingDirection.X,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = COLORS.accent,
        ZIndex = 501,
    })
    self.tabLayout = make("UIListLayout", self.tabs, {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        VerticalAlignment = Enum.VerticalAlignment.Center,
    })

    -- Separate simulation controls from the app tabs. This strip lives above the bottom dock.
    self.simulationBar = make("Frame", screenGui, {
        Name = "OS_SimulationBar",
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 12, 1, -62),
        Size = UDim2.new(1, -24, 0, 40),
        BackgroundColor3 = COLORS.bar,
        BackgroundTransparency = 0.02,
        BorderSizePixel = 0,
        Visible = true,
        ZIndex = 490,
    })
    addCorner(self.simulationBar, 9)
    addStroke(self.simulationBar, COLORS.barStroke, 1, 0.15)

    make("TextLabel", self.simulationBar, {
        Name = "SimulationTitle",
        Position = UDim2.fromOffset(12, 0),
        Size = UDim2.fromOffset(112, 40),
        BackgroundTransparency = 1,
        Text = "SIMULATION",
        TextColor3 = COLORS.accent,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 491,
    })
    self.simulationStatus = make("TextLabel", self.simulationBar, {
        Name = "SimulationStatus",
        Position = UDim2.fromOffset(122, 0),
        Size = UDim2.new(1, -420, 1, 0),
        BackgroundTransparency = 1,
        Text = "READY  •  SIMULATION UI",
        TextColor3 = COLORS.muted,
        Font = Enum.Font.GothamMedium,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 491,
    })

    self.simulationEvents = {
        Run = Instance.new("BindableEvent"),
        Pause = Instance.new("BindableEvent"),
        Reset = Instance.new("BindableEvent"),
    }
    for eventName, eventObject in pairs(self.simulationEvents) do
        eventObject.Name = "Simulation" .. eventName .. "Requested"
        eventObject.Parent = screenGui
    end

    local function makeSimulationButton(name, text, xOffset, buttonColor)
        local button = make("TextButton", self.simulationBar, {
            Name = name,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, xOffset, 0.5, 0),
            Size = UDim2.fromOffset(66, 28),
            BackgroundColor3 = buttonColor or COLORS.button,
            BorderSizePixel = 0,
            Text = text,
            TextColor3 = COLORS.text,
            Font = Enum.Font.GothamBold,
            TextSize = 10,
            AutoButtonColor = true,
            ZIndex = 492,
        })
        addCorner(button, 7)
        addStroke(button, COLORS.barStroke, 1, 0.25)
        return button
    end

    local function updateSimulationStatusWidth()
        local availableWidth = math.max(0, self.simulationBar.AbsoluteSize.X - 442)
        self.simulationStatus.Size = UDim2.fromOffset(availableWidth, 40)
    end
    self.simulationBar:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateSimulationStatusWidth)
    task.defer(updateSimulationStatusWidth)

    self.simRunButton = makeSimulationButton("SimulationRun", "RUN", -222, Color3.fromRGB(39, 91, 77))
    self.simPauseButton = makeSimulationButton("SimulationPause", "PAUSE", -148, COLORS.button)
    self.simResetButton = makeSimulationButton("SimulationReset", "RESET", -74, COLORS.button)
    self.simRunButton.Activated:Connect(function()
        self.simulationStatus.Text = "RUN REQUESTED  •  CONNECT ENGINE TO SIMULATE"
        self.simulationEvents.Run:Fire()
    end)
    self.simPauseButton.Activated:Connect(function()
        self.simulationStatus.Text = "PAUSE REQUESTED  •  CONNECT ENGINE TO SIMULATE"
        self.simulationEvents.Pause:Fire()
    end)
    self.simResetButton.Activated:Connect(function()
        self.simulationStatus.Text = "RESET REQUESTED  •  CONNECT ENGINE TO SIMULATE"
        self.simulationEvents.Reset:Fire()
    end)

    -- App launcher stays accessible while a modal window is open, so players can open more tabs.
    self.launchButton = make("TextButton", self.topBar, {
        Name = "AppLauncherButton",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -12, 0, 7),
        Size = UDim2.fromOffset(34, 34),
        BackgroundColor3 = COLORS.tabActive,
        BorderSizePixel = 0,
        Text = "+",
        TextColor3 = COLORS.accent,
        TextSize = 24,
        Font = Enum.Font.GothamMedium,
        AutoButtonColor = true,
        ZIndex = 502,
    })
    addCorner(self.launchButton, 8)
    addStroke(self.launchButton, COLORS.barStroke, 1, 0.2)

    self.launchMenu = make("Frame", screenGui, {
        Name = "OS_AppLauncherMenu",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -12, 1, -116),
        Size = UDim2.fromOffset(244, 250),
        BackgroundColor3 = COLORS.bar,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 700,
    })
    addCorner(self.launchMenu, 10)
    addStroke(self.launchMenu, COLORS.barStroke, 1, 0.05)
    make("TextLabel", self.launchMenu, {
        Name = "MenuTitle",
        Position = UDim2.fromOffset(12, 8),
        Size = UDim2.new(1, -24, 0, 22),
        BackgroundTransparency = 1,
        Text = "OPEN AN APP",
        TextColor3 = COLORS.accent,
        TextSize = 11,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 701,
    })
    self.launchList = make("ScrollingFrame", self.launchMenu, {
        Name = "AvailableApps",
        Position = UDim2.fromOffset(7, 36),
        Size = UDim2.new(1, -14, 1, -43),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = COLORS.accent,
        ZIndex = 701,
    })
    self.launchListLayout = make("UIListLayout", self.launchList, {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 5),
    })
    self.launchButton.Activated:Connect(function()
        self.launchMenu.Visible = not self.launchMenu.Visible
    end)

    -- Parent the post-effect to CurrentCamera so this remains a per-player UI effect.
    local blurParent = workspace.CurrentCamera or Lighting
    self.blur = blurParent:FindFirstChild("AltheaOS_LocalBlur")
    if not self.blur or not self.blur:IsA("BlurEffect") then
        self.blur = Instance.new("BlurEffect")
        self.blur.Name = "AltheaOS_LocalBlur"
    end
    self.blur.Size = 0
    self.blur.Parent = blurParent

    workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        local currentCamera = workspace.CurrentCamera
        if currentCamera and self.blur then
            self.blur.Parent = currentCamera
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        self:_handleInputChanged(input)
    end)
    UserInputService.InputEnded:Connect(function(input)
        self:_handleInputEnded(input)
    end)
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then
            return
        end
        if input.KeyCode == Enum.KeyCode.Escape and self.activeName then
            local record = self.windows[self.activeName]
            if record and record.options.EscapeCloses ~= false then
                self:CloseWindow(self.activeName)
            end
        end
    end)

    managerCache[playerGui] = self
    return self
end

function WindowManager:_makeControlButton(header, name, text, xOffset, color)
    local button = make("TextButton", header, {
        Name = name,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, xOffset, 0.5, 0),
        Size = UDim2.fromOffset(34, 32),
        BackgroundColor3 = color or COLORS.button,
        BorderSizePixel = 0,
        Text = text,
        TextColor3 = COLORS.text,
        TextSize = 17,
        Font = Enum.Font.GothamMedium,
        AutoButtonColor = true,
    })
    addCorner(button, 7)
    addStroke(button, COLORS.barStroke, 1, 0.25)
    button.ZIndex = header.ZIndex + 1
    return button
end

function WindowManager:_makeTab(record)
    local tab = make("TextButton", self.tabs, {
        Name = "Tab_" .. record.name:gsub("[^%w_]", ""),
        Size = UDim2.fromOffset(158, 34),
        BackgroundColor3 = COLORS.tab,
        BorderSizePixel = 0,
        Text = record.name,
        TextColor3 = COLORS.muted,
        TextSize = 11,
        Font = Enum.Font.GothamMedium,
        AutoButtonColor = true,
        LayoutOrder = #self.openOrder,
        ZIndex = 502,
    })
    addCorner(tab, 8)
    local stroke = addStroke(tab, COLORS.barStroke, 1, 0.45)
    record.tabButton = tab
    record.tabStroke = stroke
    tab.Activated:Connect(function()
        self:ActivateWindow(record.name)
    end)
end

function WindowManager:_ensureTab(record)
    if record.tabButton and record.tabButton.Parent then
        return
    end
    self:_makeTab(record)
end

function WindowManager:_makeLauncherItem(record)
    local item = make("TextButton", self.launchList, {
        Name = "Launch_" .. record.name:gsub("[^%w_]", ""),
        Size = UDim2.new(1, -4, 0, 34),
        BackgroundColor3 = COLORS.tab,
        BorderSizePixel = 0,
        Text = "  " .. record.name,
        TextColor3 = COLORS.text,
        TextSize = 11,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Left,
        AutoButtonColor = true,
        LayoutOrder = record.launchOrder,
        ZIndex = 702,
    })
    addCorner(item, 7)
    addStroke(item, COLORS.barStroke, 1, 0.45)
    record.launchItem = item
    item.Activated:Connect(function()
        self.launchMenu.Visible = false
        self:OpenWindow(record.name)
    end)
end

function WindowManager:RegisterWindow(name, frame, options)
    assert(type(name) == "string" and name ~= "", "RegisterWindow needs a name")
    assert(frame and frame:IsA("GuiObject"), "RegisterWindow needs a GuiObject window frame")
    options = options or {}

    if self.windows[name] then
        self:CloseWindow(name)
        local old = self.windows[name]
        if old then
            if old.frame then
                old.frame.Visible = false
            end
            if old.launchItem then
                old.launchItem:Destroy()
            end
        end
        self.windows[name] = nil
    end

    local header = options.Header or frame:FindFirstChild("Header")
    local closeButton = options.CloseButton or (header and header:FindFirstChild("CloseButton"))

    local record = {
        name = name,
        frame = frame,
        header = header,
        closeButton = closeButton,
        options = options,
        tabButton = nil,
        tabStroke = nil,
        originalSize = frame.Size,
        originalPosition = frame.Position,
        originalAnchorPoint = frame.AnchorPoint,
    }
    self.windows[name] = record
    record.launchOrder = #self.launchList:GetChildren() + 1
    self:_makeLauncherItem(record)

    -- Put app windows into one shared ScreenGui so the OS can control focus and layering.
    frame.Parent = self.screenGui
    frame.Visible = false
    frame.Active = true
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    -- Leave a reserved zone at the bottom for Simulation and Tabs.
    frame.Position = UDim2.new(0.5, 0, 0.5, -56)
    frame.Size = UDim2.new(0.97, 0, 1, -124)
    setZTree(frame, 10)

    if header and header:IsA("GuiObject") then
        header.Active = true
        -- Reserve enough room for the minimize / maximize / close controls.
        for _, child in ipairs(header:GetChildren()) do
            if child:IsA("TextLabel") then
                child.Size = UDim2.new(1, -150, child.Size.Y.Scale, child.Size.Y.Offset)
            end
        end

        local minimizeButton = self:_makeControlButton(header, "OS_MinimizeButton", "—", -102)
        local maximizeButton = self:_makeControlButton(header, "OS_MaximizeButton", "□", -60)
        record.minimizeButton = minimizeButton
        record.maximizeButton = maximizeButton
        minimizeButton.Activated:Connect(function()
            self:MinimizeWindow(name)
        end)
        maximizeButton.Activated:Connect(function()
            self:ToggleMaximize(name)
        end)

        if not closeButton then
            closeButton = self:_makeControlButton(header, "OS_CloseButton", "×", -16, COLORS.danger)
            record.closeButton = closeButton
        else
            closeButton.AnchorPoint = Vector2.new(1, 0.5)
            closeButton.Position = UDim2.new(1, -14, 0.5, 0)
            closeButton.ZIndex = header.ZIndex + 1
        end
        closeButton.Activated:Connect(function()
            self:CloseWindow(name)
        end)

        header.InputBegan:Connect(function(input)
            if not isPointerBegin(input) or self.maximized[name] then
                return
            end
            self.interaction = {
                kind = "drag",
                record = record,
                inputType = input.UserInputType,
                inputObject = input,
                pointerStart = Vector2.new(input.Position.X, input.Position.Y),
                absolutePositionStart = frame.AbsolutePosition,
            }
        end)
    end

    local resizeHandle = make("TextButton", frame, {
        Name = "OS_ResizeHandle",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -5, 1, -5),
        Size = UDim2.fromOffset(24, 24),
        BackgroundColor3 = COLORS.button,
        BackgroundTransparency = 0.12,
        BorderSizePixel = 0,
        Text = "◢",
        TextColor3 = COLORS.accent,
        TextSize = 13,
        Font = Enum.Font.GothamBold,
        AutoButtonColor = true,
    })
    addCorner(resizeHandle, 6)
    addStroke(resizeHandle, COLORS.barStroke, 1, 0.25)
    resizeHandle.ZIndex = 100
    record.resizeHandle = resizeHandle
    resizeHandle.InputBegan:Connect(function(input)
        if not isPointerBegin(input) or self.maximized[name] then
            return
        end
        self.interaction = {
            kind = "resize",
            record = record,
            inputType = input.UserInputType,
            inputObject = input,
            pointerStart = Vector2.new(input.Position.X, input.Position.Y),
            sizeStart = frame.AbsoluteSize,
            absolutePositionStart = frame.AbsolutePosition,
        }
    end)

    return record
end

function WindowManager:_reorderTabs()
    for index, name in ipairs(self.openOrder) do
        local record = self.windows[name]
        if record and record.tabButton then
            record.tabButton.LayoutOrder = index
        end
    end
end

function WindowManager:_refresh()
    local activeRecord = self.activeName and self.windows[self.activeName] or nil
    local hasActiveWindow = activeRecord ~= nil and not self.minimized[self.activeName]

    for name, record in pairs(self.windows) do
        local isOpen = table.find(self.openOrder, name) ~= nil
        local isActive = hasActiveWindow and name == self.activeName and isOpen
        record.frame.Visible = isActive
        if record.tabButton then
            record.tabButton.BackgroundColor3 = isActive and COLORS.tabActive or COLORS.tab
            record.tabButton.TextColor3 = isActive and COLORS.text or COLORS.muted
            if record.tabStroke then
                record.tabStroke.Color = isActive and COLORS.accent or COLORS.barStroke
                record.tabStroke.Transparency = isActive and 0.05 or 0.45
            end
        end
    end

    -- Bottom navigation stays available so users can always open an app from the + menu.
    self.topBar.Visible = true
    self.simulationBar.Visible = true
    local modal = hasActiveWindow and activeRecord.options.Modal == true
    self.shade.Visible = modal
    self.blur.Size = modal and (tonumber(activeRecord.options.BlurSize) or 16) or 0
end

function WindowManager:OpenWindow(name)
    local record = self.windows[name]
    if not record then
        warn("AltheaOS: window is not registered: " .. tostring(name))
        return false
    end

    if not table.find(self.openOrder, name) then
        table.insert(self.openOrder, name)
        self:_ensureTab(record)
        self:_reorderTabs()
    end

    self.minimized[name] = false
    self.activeName = name
    self.launchMenu.Visible = false
    self:_refresh()

    task.defer(function()
        if record.tabButton and self.tabs then
            local tabX = record.tabButton.AbsolutePosition.X - self.tabs.AbsolutePosition.X
            local tabRight = tabX + record.tabButton.AbsoluteSize.X
            local scrollX = self.tabs.CanvasPosition.X
            local viewportWidth = self.tabs.AbsoluteSize.X
            if tabRight > scrollX + viewportWidth then
                self.tabs.CanvasPosition = Vector2.new(math.max(0, tabRight - viewportWidth + 8), 0)
            elseif tabX < scrollX then
                self.tabs.CanvasPosition = Vector2.new(math.max(0, tabX), 0)
            end
        end
    end)
    return true
end

function WindowManager:ActivateWindow(name)
    if not table.find(self.openOrder, name) then
        return self:OpenWindow(name)
    end
    self.minimized[name] = false
    self.activeName = name
    self:_refresh()
    return true
end

function WindowManager:CloseWindow(name)
    local record = self.windows[name]
    if not record then
        return false
    end

    local index = table.find(self.openOrder, name)
    if index then
        table.remove(self.openOrder, index)
    end
    self.minimized[name] = nil
    if self.maximized[name] then
        local bounds = record.restoreBounds
        if bounds then
            record.frame.AnchorPoint = bounds.anchorPoint
            record.frame.Position = bounds.position
            record.frame.Size = bounds.size
        end
        self.maximized[name] = false
        record.restoreBounds = nil
        if record.maximizeButton then
            record.maximizeButton.Text = "□"
        end
    end
    if record.tabButton then
        record.tabButton:Destroy()
        record.tabButton = nil
        record.tabStroke = nil
    end
    record.frame.Visible = false

    if self.activeName == name then
        self.activeName = nil
        for i = #self.openOrder, 1, -1 do
            local candidate = self.openOrder[i]
            if not self.minimized[candidate] then
                self.activeName = candidate
                break
            end
        end
    end
    self:_reorderTabs()
    self:_refresh()
    return true
end

function WindowManager:MinimizeWindow(name)
    if not table.find(self.openOrder, name) then
        return false
    end
    self.minimized[name] = true
    if self.activeName == name then
        self.activeName = nil
        for i = #self.openOrder, 1, -1 do
            local candidate = self.openOrder[i]
            if candidate ~= name and not self.minimized[candidate] then
                self.activeName = candidate
                break
            end
        end
    end
    self:_refresh()
    return true
end

function WindowManager:ToggleMaximize(name)
    local record = self.windows[name]
    if not record or not table.find(self.openOrder, name) then
        return false
    end

    local frame = record.frame
    if self.maximized[name] then
        local bounds = record.restoreBounds
        if bounds then
            frame.AnchorPoint = bounds.anchorPoint
            frame.Position = bounds.position
            frame.Size = bounds.size
        else
            frame.AnchorPoint = record.originalAnchorPoint
            frame.Position = record.originalPosition
            frame.Size = record.originalSize
        end
        self.maximized[name] = false
    else
        record.restoreBounds = {
            anchorPoint = frame.AnchorPoint,
            position = frame.Position,
            size = frame.Size,
        }
        frame.AnchorPoint = Vector2.new(0.5, 0.5)
        frame.Position = UDim2.new(0.5, 0, 0.5, -56)
        frame.Size = UDim2.new(1, -24, 1, -124)
        self.maximized[name] = true
    end
    if record.maximizeButton then
        record.maximizeButton.Text = self.maximized[name] and "❐" or "□"
    end
    return true
end

function WindowManager:_handleInputChanged(input)
    local state = self.interaction
    if not state then
        return
    end

    local isMove = state.inputType == Enum.UserInputType.MouseButton1
        and input.UserInputType == Enum.UserInputType.MouseMovement
    local isTouchMove = state.inputType == Enum.UserInputType.Touch
        and input.UserInputType == Enum.UserInputType.Touch
        and input == state.inputObject
    if not isMove and not isTouchMove then
        return
    end

    local currentPointer = Vector2.new(input.Position.X, input.Position.Y)
    local delta = currentPointer - state.pointerStart
    local frame = state.record.frame
    local viewport = getViewportSize()
    local topLeftInset = getTopLeftInset()

    if state.kind == "drag" then
        if self.maximized[state.record.name] then
            return
        end
        -- Normalize to top-left positioning so dragging still works after resizing.
        local leftX = state.absolutePositionStart.X + delta.X - topLeftInset.X
        local topY = state.absolutePositionStart.Y + delta.Y - topLeftInset.Y
        leftX = math.clamp(leftX, 0, math.max(0, viewport.X - frame.AbsoluteSize.X))
        local bottomReserved = 118
        local maxTop = math.max(8, viewport.Y - topLeftInset.Y - frame.AbsoluteSize.Y - bottomReserved)
        topY = math.clamp(topY, 8, maxTop)
        frame.AnchorPoint = Vector2.new(0, 0)
        frame.Position = UDim2.fromOffset(leftX, topY)
    elseif state.kind == "resize" then
        if self.maximized[state.record.name] then
            return
        end
        local minWidth = math.min(540, math.max(280, viewport.X - 24))
        local minHeight = math.min(300, math.max(220, viewport.Y - 132))
        local maxHeight = math.max(minHeight, viewport.Y - 132)
        local newWidth = math.clamp(state.sizeStart.X + delta.X, minWidth, math.max(minWidth, viewport.X - 24))
        local newHeight = math.clamp(state.sizeStart.Y + delta.Y, minHeight, maxHeight)
        frame.AnchorPoint = Vector2.new(0, 0)
        frame.Position = UDim2.fromOffset(
            math.max(0, state.absolutePositionStart.X - topLeftInset.X),
            math.max(8, state.absolutePositionStart.Y - topLeftInset.Y)
        )
        frame.Size = UDim2.fromOffset(newWidth, newHeight)
    end
end

function WindowManager:_handleInputEnded(input)
    local state = self.interaction
    if not state then
        return
    end
    if (state.inputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1)
        or (state.inputType == Enum.UserInputType.Touch and input.UserInputType == Enum.UserInputType.Touch) then
        self.interaction = nil
    end
end

return WindowManager
