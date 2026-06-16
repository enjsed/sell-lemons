if _G.MatchaCleanup then pcall(_G.MatchaCleanup) end
local ScriptActive = true

local mfloor, mabs            = math.floor, math.abs
local msin                    = math.sin
local tinsert                 = table.insert
local ipairs_, pairs_         = ipairs, pairs
local tostring_, tonumber_    = tostring, tonumber
local pcall_                  = pcall
local task_wait, task_spawn   = task.wait, task.spawn
local tick_                   = tick
local sformat                 = string.format
local Vec2, Vec3              = Vector2.new, Vector3.new
local CF                      = CFrame.new
local C3rgb                   = Color3.fromRGB

local function clamp(x, a, b)
    if x < a then return a elseif x > b then return b else return x end
end

local DEBUG = false
local rprint = print
local print = function(...)
    if DEBUG then rprint(...) end
end

local Players, RunService, Workspace, player, camera
local initAttempts = 0
while not player and initAttempts < 50 do
    initAttempts = initAttempts + 1
    pcall_(function()
        Players    = game:GetService("Players")
        RunService = game:GetService("RunService")
        Workspace  = game:GetService("Workspace")
        player     = Players.LocalPlayer
        if player then camera = Workspace.CurrentCamera end
    end)
    if not player then task_wait(0.1) end
end
if not player then warn("[Hub] No LocalPlayer"); return end
if not camera then camera = Workspace.CurrentCamera end

local GuiService; pcall_(function() GuiService = game:GetService("GuiService") end)

setrobloxinput(true)

local mouse = nil
pcall_(function() mouse = player:GetMouse() end)

local errCounts = {}
local function reportErr(tag, err)
    local msg = "[" .. tag .. "] " .. tostring_(err)
    local n = (errCounts[msg] or 0) + 1
    errCounts[msg] = n
    if n <= 3 or n % 50 == 0 then
        rprint("[Hub][ERROR]" .. msg .. (n > 1 and ("  (x" .. n .. ")") or ""))
    end
end
local function _wrap(tag, fn)
    task_spawn(function()
        while ScriptActive do
            local ok, err = pcall_(fn)
            if ok then break end
            reportErr(tag, err)
            task_wait(0.5)
        end
    end)
end

-- ===== UI SYNC FUNCTIONS =====
local UIRef = { win = nil, t = {} }

local function syncFromUI() 
    -- No-op for now, can be extended later
end

local function syncToUI()
    pcall_(function() 
        if UIRef.t.AutoBuy then 
            UIRef.t.AutoBuy:SetValue(autoBuyActive) 
        end 
    end)
    pcall_(function() 
        if UIRef.t.LemonFarm then 
            UIRef.t.LemonFarm:SetValue(lemonFarmActive) 
        end 
    end)
    pcall_(function() 
        if UIRef.t.AutoStand then 
            UIRef.t.AutoStand:SetValue(autoStandActive) 
        end 
    end)
    pcall_(function() 
        if UIRef.t.CashFarm then 
            UIRef.t.CashFarm:SetValue(cashFarmActive) 
        end 
    end)
    pcall_(function() 
        if UIRef.t.AutoRebirth then 
            UIRef.t.AutoRebirth:SetValue(autoRebirthActive) 
        end 
    end)
    pcall_(function() 
        if UIRef.t.AutoDeal then 
            UIRef.t.AutoDeal:SetValue(autoDealActive) 
        end 
    end)
end

-- ===== FEATURE TOGGLES =====
local autoBuyActive    = false
local skipDecorActive  = false
local lemonFarmActive  = false
local cashFarmActive   = true
local autoStandActive  = false
local autoDealActive   = true
local autoRebirthActive = false
local keyEspActive      = false
local _standIsTapping  = false

local buyBlacklist    = {}
local failedButtons   = {}
local buyAttempt      = {}

local keyMemo = {}
pcall_(function() setmetatable(keyMemo, { __mode = "k" }) end)

local function getButtonKey(v)
    if not v then return nil end
    local k = keyMemo[v]
    if k then return k end
    local pos = v.Position
    if not pos then return nil end
    k = sformat("%d,%d,%d", mfloor(pos.X + 0.5), mfloor(pos.Y + 0.5), mfloor(pos.Z + 0.5))
    keyMemo[v] = k
    return k
end

local function resetBuyBlacklist()
    buyBlacklist  = {}
    failedButtons = {}
    buyAttempt    = {}
    print("[Hub] Blacklist RESET!")
end

local function buyReady(key, v)
    local a = buyAttempt[key]
    if not a then return true end
    if v and a.inst and a.inst ~= v then
        buyAttempt[key] = nil
        return true
    end
    return tick_() >= a.next
end

local function markBuyFail(key, v)
    local a = buyAttempt[key]
    if not a then a = { n = 0, next = 0 }; buyAttempt[key] = a end
    a.inst = v or a.inst
    a.n = a.n + 1
    local d = 0.35 * (2 ^ (a.n - 1))
    if d > 4 then d = 4 end
    if a.n >= 6 then d = 20 end
    a.next = tick_() + d
end

-- ===== HELPER FUNCTIONS =====
local function normalizeColor(c)
    local r, g, b = c.R, c.G, c.B
    if r <= 1 and g <= 1 and b <= 1 then
        r, g, b = r * 255, g * 255, b * 255
    end
    return r, g, b
end

local function isGreyedOut(v)
    local ok, color3 = pcall_(function() return v.Color end)
    if not ok or not color3 then return false end
    local r, g, b = normalizeColor(color3)
    return mabs(r - g) < 14 and mabs(g - b) < 14 and mabs(r - b) < 14 and mabs(r - 102) <= 22
end

local decorFolderMemo = {}
local function _isDecorBtn(btn, key)
    if not btn then return false end
    key = key or getButtonKey(btn)
    local inDecor = key and decorFolderMemo[key]
    if inDecor == nil then
        inDecor = false
        pcall_(function()
            local cur, prev = btn.Parent, nil
            for _ = 1, 8 do
                if not cur then break end
                local nm = tostring_(cur.Name)
                if nm == "Buttons" then
                    if prev == "Decor" then inDecor = true end
                    return
                end
                prev = nm
                cur = cur.Parent
            end
        end)
        if key then decorFolderMemo[key] = inDecor end
    end
    if inDecor then return true end
    local red = false
    pcall_(function()
        local c = btn.Color
        if c then
            local r, g, b = normalizeColor(c)
            if r >= 140 and g <= 75 and b <= 75 then red = true end
        end
    end)
    return red
end

-- ===== STAND FUNCTIONS =====
local STAND_NAMES = {"Lemon Stand", "LemonDash", "Lemon Depot", "Lemon Trading", "Lemon Labs", "Lemon Robotics", "Lemon Republic", "LemonX"}
local standEnabled = {}
for _, name in ipairs(STAND_NAMES) do
    standEnabled[name] = true
end

local STAND_ORDER = {"stand", "dash", "depot", "trading", "labs", "robotics", "republic", "lemonx"}

local function standRank(low)
    for i = 1, #STAND_ORDER do
        if low:find(STAND_ORDER[i], 1, true) then return i end
    end
    return 99
end

local function _standPartPos(c)
    local pos
    pcall_(function() pos = c.Position end)
    if pos then return pos end
    pcall_(function()
        for _, d in ipairs_(c:GetDescendants()) do
            if d:IsA("BasePart") then pos = d.Position; return end
        end
    end)
    if not pos then pcall_(function() if c.PrimaryPart then pos = c.PrimaryPart.Position end end) end
    return pos
end

local function _standUpgradePos(folder, nm)
    local pos
    pcall_(function()
        local n2 = folder:FindFirstChild(nm)
        local n3 = n2 and n2:FindFirstChild(nm)
        if n3 then pos = _standPartPos(n3) end
    end)
    if not pos then
        pcall_(function()
            for _, d in ipairs_(folder:GetDescendants()) do
                if tostring_(d.ClassName) == "ProximityPrompt" and tostring_(d.Name) == "Prompt" and d.Parent then
                    pos = _standPartPos(d.Parent); break
                end
            end
        end)
    end
    return pos
end

local function getStandLocations()
    local out = {}
    if not myTycoon then return out end
    local pur, loc
    pcall_(function() pur = myTycoon:FindFirstChild("Purchases") end)
    pcall_(function() loc = myTycoon:FindFirstChild("Locations") end)
    if not pur then return out end
    for _, folder in ipairs_(pur:GetChildren()) do
        local nm = tostring_(folder.Name)
        local low = nm:lower()
        local rank = standRank(low)
        if rank < 99 and not low:find("ground") then
            local pos = _standUpgradePos(folder, nm)
            local lpos = nil
            if loc then
                local lc = loc:FindFirstChild(nm)
                if lc then lpos = _standPartPos(lc) end
            end
            if pos and lpos then
                local d = lpos - pos
                local m = d.Magnitude
                if m > 0.1 then
                    local step = m < 6 and m or 6
                    pos = pos + (d / m) * step
                end
            elseif not pos then
                pos = lpos
            end
            if pos then tinsert(out, {name = nm, pos = pos, rank = rank}) end
        end
    end
    table.sort(out, function(a, b) return a.rank < b.rank end)
    return out
end

-- ===== TYCOON FUNCTIONS =====
local myTycoon = nil
local tycoonCache = { value = nil, time = 0 }

local function findMyTycoon()
    local now = tick_()
    if tycoonCache.value and (now - tycoonCache.time) < 2 then
        if tycoonCache.value and tycoonCache.value.Parent then
            return tycoonCache.value
        end
    end
    
    local pname = player.Name
    for _, tycoon in ipairs_(Workspace:GetChildren()) do
        if tostring_(tycoon.Name):find("Tycoon") then
            local owner = tycoon:FindFirstChild("Owner")
            if owner then
                local ov; pcall_(function() ov = owner.Value end)
                if ov == player or (ov and tostring_(ov):find(pname, 1, true)) then
                    tycoonCache.value = tycoon
                    tycoonCache.time = now
                    return tycoon
                end
            end
        end
    end
    
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local hp; pcall_(function() hp = hrp and hrp.Position end)
    if hp then
        local best, bestD
        for _, tycoon in ipairs_(Workspace:GetChildren()) do
            if tostring_(tycoon.Name):find("Tycoon") then
                local pur = tycoon:FindFirstChild("Purchases")
                if pur then
                    pcall_(function()
                        for _, d in ipairs_(pur:GetDescendants()) do
                            if d.Name == "Button" and d:IsA("BasePart") and d.Parent then
                                local dd = (d.Position - hp).Magnitude
                                if not bestD or dd < bestD then bestD = dd; best = tycoon end
                            end
                        end
                    end)
                end
            end
        end
        if best and bestD and bestD < 300 then
            tycoonCache.value = best
            tycoonCache.time = now
            return best
        end
    end
    tycoonCache.value = nil
    tycoonCache.time = now
    return nil
end
myTycoon = findMyTycoon()

-- ===== ESP FUNCTIONS =====
local ESP = { keys = {
    { path = {"Map", "Sewer", "CashVine", "VineKey"},      name = "VINE KEY",     rgb = {110, 245, 180} },
    { path = {"Map", "Sewer", "SewerAlien", "UFOKey"},     name = "UFO KEY",      rgb = {170, 130, 255} },
    { path = {"Map", "Sewer", "DoorsRed",    "Lever (Red)",    "Root", "Lever"}, name = "RED LEVER",    rgb = {255, 95,  95}  },
    { path = {"Map", "Sewer", "DoorsPurple", "Lever (Purple)", "Root", "Lever"}, name = "PURPLE LEVER", rgb = {200, 120, 255} },
    { path = {"Map", "Sewer", "DoorsGreen",  "Lever (Green)",  "Root", "Lever"}, name = "GREEN LEVER",  rgb = {120, 255, 130} },
    { path = {"Map", "Sewer", "DoorsBlue",   "Lever (Blue)",   "Root", "Lever"}, name = "BLUE LEVER",   rgb = {90,  175, 255} },
} }

local drawObjs = {}
local function D(typ, props)
    local obj = Drawing.new(typ)
    for k, v in pairs_(props) do pcall_(function() obj[k] = v end) end
    tinsert(drawObjs, obj)
    return obj
end

local _espFont = (Drawing.Fonts and (Drawing.Fonts.Monospace or Drawing.Fonts.System)) or nil
for i = 1, #ESP.keys do
    local k = ESP.keys[i]
    local col = C3rgb(k.rgb[1], k.rgb[2], k.rgb[3])
    k.glow  = D("Square", {Filled = false, Thickness = 4, Corner = 5, Rounding = 5, Size = Vec2(0, 0), Position = Vec2(0, 0), Color = col, Transparency = 0, Visible = false, ZIndex = 6})
    k.box   = D("Square", {Filled = false, Thickness = 2, Corner = 4, Rounding = 4, Size = Vec2(0, 0), Position = Vec2(0, 0), Color = col, Transparency = 0, Visible = false, ZIndex = 8})
    k.label = D("Text",   {Text = "", FontSize = 14, Size = 14, Font = _espFont, Center = true, Outline = true, OutlineColor = C3rgb(0, 0, 0), Color = col, Transparency = 0, Visible = false, ZIndex = 9})
end

local function _espHide(k)
    k.glow.Visible = false
    k.box.Visible = false
    k.label.Visible = false
end

function ESP.update()
    if not keyEspActive then
        for i = 1, #ESP.keys do _espHide(ESP.keys[i]) end
        return
    end
    if CFG.slow then 
        local n = tick_()
        if (n - (ESP.throt or 0)) < 0.016 then return end
        ESP.throt = n 
    end
    local vp; pcall_(function() vp = camera.ViewportSize end)
    if not vp then return end
    local chr = player.Character
    local hrp = chr and chr:FindFirstChild("HumanoidRootPart")
    local hp; pcall_(function() hp = hrp and hrp.Position end)
    
    for i = 1, #ESP.keys do
        local k = ESP.keys[i]
        if not (k.ref and k.ref.Parent) and (tick_() - (k.refT or 0) > 0.5) then
            k.refT = tick_()
            local cur = Workspace
            pcall_(function() 
                for _, seg in ipairs_(k.path) do 
                    cur = cur and cur:FindFirstChild(seg) 
                end 
            end)
            k.ref = cur
        end
        if k.ref and k.ref.Parent then
            local pos; pcall_(function() pos = k.ref.Position end)
            if pos then
                local sp, con; pcall_(function() sp, con = WorldToScreen(pos) end)
                if sp and con and sp.X >= 0 and sp.X <= vp.X and sp.Y >= 0 and sp.Y <= vp.Y then
                    local dist = hp and mfloor((pos - hp).Magnitude) or 0
                    k.box.Position = Vec2(sp.X - 30, sp.Y - 15)
                    k.box.Size = Vec2(60, 30)
                    k.box.Visible = true
                    k.glow.Position = Vec2(sp.X - 32, sp.Y - 17)
                    k.glow.Size = Vec2(64, 34)
                    k.glow.Visible = true
                    k.label.Text = k.name .. "  " .. dist .. "m"
                    k.label.Position = Vec2(sp.X, sp.Y - 30)
                    k.label.Visible = true
                else
                    _espHide(k)
                end
            else
                _espHide(k)
            end
        else
            _espHide(k)
        end
    end
end

-- ===== CFG =====
local CFG = {
    buyWindow = 0.45,
    afkDelay  = 6,
    zoomTicks = 22,
    zoomStep  = 1,
    standRest = 60,
    vineCd    = 4 * 3600,
    buyStuck  = 6,
    cheerY    = 0.85,
    exitY     = 0.76,
    slow      = false,
}

local S = {
    lastUser = tick_(), 
    pmx = 0, 
    pmy = 0, 
    keyDown = {}, 
    lastFire = {},
    stopSaved = nil,
}

-- ===== LSM (Lemon System Manager) =====
local LSM = { 
    mode = "classic", 
    annAfk = false, 
    annBuy = false,
    zoomedIn = false,
    zoomInT = 0,
    lastBot = 0,
    standBusyT = 0,
    standPassT = 0,
    buySweepT = 0,
    standNextT = 0,
    anchor = nil,
    anchorCam = nil,
}

function LSM.zoom(dir)
    if type(mousescroll) ~= "function" then return end
    if not _windowFocused() then return end
    LSM.zoomGen = (LSM.zoomGen or 0) + 1
    local gen = LSM.zoomGen
    LSM.zoomedIn = dir > 0
    for _ = 1, CFG.zoomTicks do
        if LSM.zoomGen ~= gen then return end
        LSM.lastBot = tick_()
        pcall_(mousescroll, CFG.zoomStep * dir)
        task_wait(0.02)
    end
end

function LSM.tiltDown()
    if not _windowFocused() then return false end
    if type(mouse2press) ~= "function" or type(mouse2release) ~= "function"
       or type(mousemoverel) ~= "function" then return false end
    local ok = false
    pcall_(function()
        LSM.lastBot = tick_()
        mouse2press()
        for _ = 1, 6 do
            mousemoverel(0, 250)
            LSM.lastBot = tick_()
            task_wait(0.02)
        end
        mouse2release()
        ok = true
    end)
    pcall_(function() mouse2release() end)
    return ok
end

function LSM.returnHome()
    local a = LSM.anchor
    LSM.anchor = nil
    if a then
        pcall_(function()
            local chr = player.Character
            local h = chr and chr:FindFirstChild("HumanoidRootPart")
            if h then
                h.CFrame = CF(a.X, a.Y + 1, a.Z)
                h.AssemblyLinearVelocity = Vec3(0, 0, 0)
            end
        end)
    end
    LSM.zoom(-1)
    LSM.lastBot = tick_()
    if a and LSM.anchorCam then
        pcall_(function()
            camera.lookAt(a + LSM.anchorCam, a)
        end)
    end
    LSM.anchorCam = nil
end

-- ===== UI FUNCTIONS =====
local function toggleFeature(slot)
    if not UX.fire("slot" .. slot) then return end
    if     slot == 1 then autoBuyActive   = not autoBuyActive
    elseif slot == 2 then lemonFarmActive = not lemonFarmActive
    elseif slot == 3 then autoStandActive = not autoStandActive
    elseif slot == 4 then cashFarmActive  = not cashFarmActive
    elseif slot == 5 then 
        if S.stopSaved then
            autoBuyActive, lemonFarmActive, cashFarmActive = S.stopSaved.ab, S.stopSaved.lf, S.stopSaved.cf
            autoStandActive, autoRebirthActive, autoDealActive = S.stopSaved.as, S.stopSaved.ar, S.stopSaved.ad
            S.stopSaved = nil
        else
            S.stopSaved = {
                ab = autoBuyActive, lf = lemonFarmActive, cf = cashFarmActive,
                as = autoStandActive, ar = autoRebirthActive, ad = autoDealActive,
            }
            autoBuyActive, lemonFarmActive, cashFarmActive, autoStandActive, autoRebirthActive = false, false, false, false, false
            autoDealActive = false
            resetBuyBlacklist()
        end
        syncToUI()
        return
    else return end
    syncToUI()
    print("[Hub] toggle slot " .. slot)
end

local UX = {}
function UX.fire(id)
    local now = tick_()
    if S.lastFire[id] and (now - S.lastFire[id]) < 0.30 then return false end
    S.lastFire[id] = now
    return true
end

local function _windowFocused()
    if type(isrbxactive) ~= "function" then return true end
    local ok, r = pcall_(isrbxactive)
    if not ok then return true end
    return r ~= false
end

-- ===== STATUS UI =====
local statusTx = D("Text", {Text = "", FontSize = 13, Size = 13, Font = (Drawing.Fonts.Monospace or Drawing.Fonts.System), Center = false, Outline = true, Visible = false, ZIndex = 5, Color = C3rgb(236, 238, 242)})
local statusTx2 = D("Text", {Text = "", FontSize = 13, Size = 13, Font = (Drawing.Fonts.Monospace or Drawing.Fonts.System), Center = false, Outline = true, Visible = false, ZIndex = 5, Color = C3rgb(196, 198, 206)})
local statusTx3 = D("Text", {Text = "", FontSize = 13, Size = 13, Font = (Drawing.Fonts.Monospace or Drawing.Fonts.System), Center = false, Outline = true, Visible = false, ZIndex = 5, Color = C3rgb(196, 198, 206)})
local statusTx4 = D("Text", {Text = "", FontSize = 13, Size = 13, Font = (Drawing.Fonts.Monospace or Drawing.Fonts.System), Center = false, Outline = true, Visible = false, ZIndex = 5, Color = C3rgb(196, 198, 206)})
local statusTx5 = D("Text", {Text = "", FontSize = 13, Size = 13, Font = (Drawing.Fonts.Monospace or Drawing.Fonts.System), Center = false, Outline = true, Visible = false, ZIndex = 5, Color = C3rgb(196, 198, 206)})

local stUI = { lbl = {}, dot = {} }
stUI.panel = D("Square", {Size = Vec2(0, 0), Position = Vec2(0, 0), Filled = true, Thickness = 1, Corner = 10, Rounding = 10, Color = C3rgb(15, 15, 18), Transparency = 0.5, Visible = false, ZIndex = 2})
stUI.ln = D("Square", {Size = Vec2(0, 0), Position = Vec2(0, 0), Filled = false, Thickness = 1, Corner = 10, Rounding = 10, Color = C3rgb(236, 238, 242), Transparency = 0.18, Visible = false, ZIndex = 3})
stUI.title = D("Text", {Text = "SELL LEMONS", FontSize = 10, Size = 10, Font = (Drawing.Fonts.Monospace or Drawing.Fonts.System), Center = true, Outline = true, Visible = false, ZIndex = 5, Color = C3rgb(236, 238, 242), Transparency = 0.7})

for i = 1, 5 do
    stUI.lbl[i] = D("Text", {Text = "", FontSize = 13, Size = 13, Font = (Drawing.Fonts.Monospace or Drawing.Fonts.System), Center = false, Outline = true, Visible = false, ZIndex = 5, Color = C3rgb(142, 144, 152)})
    stUI.dot[i] = D("Circle", {Radius = 3, NumSides = 12, Filled = true, Position = Vec2(0, 0), Color = C3rgb(255, 200, 40), Transparency = 1, Visible = false, ZIndex = 4})
end

function S.stLine(valObj, i, fullTxt)
    local lbl, val = tostring_(fullTxt):match("^(.-)%s+|%s+(.+)$")
    if not lbl then lbl, val = "", tostring_(fullTxt) end
    local y = S.stY
    local L, dt = stUI.lbl[i], stUI.dot[i]
    L.Text = lbl
    L.Position = Vec2(S.stX + 28, y)
    L.Visible = true
    valObj.Text = val
    valObj.Position = Vec2(S.stX + 122, y)
    valObj.Visible = true
    local up = val:upper()
    if up:find("READY") or up:find("FARMING") or up:find("GO", 1, true) then
        dt.Color = C3rgb(240, 242, 246)
        dt.Transparency = 0.45 + 0.45 * math.sin(tick_() * 5)
    elseif up:find("PAUSED") or up:find("WAIT") or up:find("IDLE") or up:find("STARTS IN")
        or up:match("^%d+:%d") or up == "--" or up:find("SOON") then
        dt.Color = C3rgb(120, 122, 130)
        dt.Transparency = 0.82
    else
        dt.Color = C3rgb(200, 202, 210)
        dt.Transparency = 0.92
    end
    dt.Position = Vec2(S.stX + 16, y + 7)
    dt.Visible = true
    S.stY = y + 19
end

function S.stHide(valObj, i)
    valObj.Visible = false
    stUI.lbl[i].Visible = false
    stUI.dot[i].Visible = false
end

-- ===== POLL INPUT =====
local function pollInput()
    if not ScriptActive then return end
    local nowA = tick_()
    if (nowA - (S.pollT or 0)) < (CFG.slow and 0.05 or 0.02) then return end
    S.pollT = nowA
    local focused = _windowFocused()
    if focused then
        for i = 1, 5 do
            local vk = 48 + i
            if iskeypressed(vk) then
                if not S.keyDown[vk] then
                    S.keyDown[vk] = true
                    toggleFeature(i)
                end
            else
                S.keyDown[vk] = false
            end
        end
        
        local mx, my = S.pmx, S.pmy
        if mouse then pcall_(function() mx = mouse.X; my = mouse.Y end) end
        local m1 = false
        pcall_(function() m1 = ismouse1pressed() end)
        
        local moved = mabs(mx - S.pmx) + mabs(my - S.pmy)
        if moved > 3 or m1 then S.lastUser = nowA end
        S.pmx, S.pmy = mx, my
        if iskeypressed(0x57) or iskeypressed(0x41) or iskeypressed(0x53) or iskeypressed(0x44) or iskeypressed(0x20) then
            S.lastUser = nowA
        end
    end
    
    -- Status update
    if (nowA - (S.statusT or 0)) < (CFG.slow and 0.3 or 0.12) then return end
    S.statusT = nowA
    
    local vx = 1920
    pcall_(function() vx = camera.ViewportSize.X end)
    local vy0 = 58
    S.stX = vx - 314
    S.stY = vy0 + 16
    
    if lemonFarmActive then
        local txt
        if autoBuyActive and _autobuyHasWork then
            txt = "lemon farm  |  paused: buy"
        elseif autoStandActive and (nowA - (LSM.standBusyT or 0)) < 4 then
            txt = "lemon farm  |  paused: stand"
        elseif (nowA - (RB.busyT or 0)) < 4 then
            txt = "lemon farm  |  paused: rebirth"
        else
            local idleT = nowA - (S.lastUser or 0)
            if idleT < CFG.afkDelay then
                txt = sformat("lemon farm  |  starts in %ds", mfloor(CFG.afkDelay - idleT) + 1)
            else
                txt = "lemon farm  |  FARMING (WASD stops)"
            end
        end
        S.stLine(statusTx, 1, txt)
    else
        S.stHide(statusTx, 1)
    end
    
    if autoStandActive then
        local txt2
        if (nowA - (LSM.standBusyT or 0)) < 4 then
            txt2 = "auto stand  |  upgrading..."
        elseif LSM.standNextT and LSM.standNextT > nowA then
            txt2 = sformat("auto stand  |  pass in %ds", mfloor(LSM.standNextT - nowA) + 1)
        else
            txt2 = "auto stand  |  ON"
        end
        S.stLine(statusTx2, 2, txt2)
    else
        S.stHide(statusTx2, 2)
    end
    
    -- Simple status for other features
    if autoRebirthActive then
        S.stLine(statusTx5, 5, "rebirth  |  " .. (RB.status or "idle"))
    else
        S.stHide(statusTx5, 5)
    end
    
    if S.stY > vy0 + 16 then
        local bt = tick_()
        stUI.title.Position = Vec2(S.stX + 150, vy0 - 1)
        stUI.title.Transparency = 0.5 + 0.16 * msin(bt * 1.3)
        stUI.title.Visible = true
        stUI.panel.Position = Vec2(S.stX, vy0 - 8)
        stUI.panel.Size = Vec2(300, S.stY - vy0 + 12)
        stUI.panel.Visible = true
        stUI.ln.Position = Vec2(S.stX, vy0 - 8)
        stUI.ln.Size = Vec2(300, S.stY - vy0 + 12)
        stUI.ln.Transparency = 0.12 + 0.07 * msin(bt * 1.7)
        stUI.ln.Visible = true
    else
        stUI.title.Visible = false
        stUI.panel.Visible = false
        stUI.ln.Visible = false
    end
end

-- ===== RB (Rebirth) =====
local RB = { 
    mult = 2, 
    lastPeek = 0, 
    lastReb = 0, 
    goSince = 0, 
    peekEvery = 60, 
    go = false, 
    status = "off",
    busyT = 0,
    checkStartT = 0,
    curLog = nil,
    gainPct = 25,
}

function RB.thStr()
    return "+" .. (RB.gainPct or 25) .. "%"
end

function RB.cashLog()
    return nil -- Simplified for now
end

-- ===== MAIN RENDER LOOP =====
RunService.RenderStepped:Connect(function()
    if not ScriptActive then return end
    pcall_(ESP.update)
    local ok, err = pcall_(pollInput)
    if not ok then reportErr("ui-input", err) end
end)

-- ===== SIMPLE WRAPPERS =====
local function _tpHrpTo(pos)
    if autoStandActive then LSM.standBusyT = tick_() end
    local character = player.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local ok = pcall_(function()
        hrp.CFrame = CF(pos.X, pos.Y + 3, pos.Z)
    end)
    return ok
end

local function _autobuyHasWork()
    return false -- Simplified
end

-- ===== CLEANUP =====
_G.MatchaCleanup = function()
    pcall_(LSM.returnHome)
    ScriptActive = false
    for _, obj in ipairs_(drawObjs) do
        pcall_(function() obj:Remove() end)
    end
    print("[Hub] Cleanup done")
end

-- ===== STARTUP =====
print("sell lemons v22 loaded  |  by Inspecttor")
print("Keys: 1=AutoBuy, 2=LemonFarm, 3=AutoStand, 4=CashFarm, 5=StopAll")
