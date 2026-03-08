-- MEGA HACK v4.0 — Production (Only Working Features)
-- ✅ ESP Wallhack (outline through walls via DecorationSystem)
-- ✅ Aimbot (smooth + crosshair priority + cover check)
-- ✅ Auto Callout (ping visible enemies to team)
----------------------------------------------------------------------
local CFG = {
    -- Feature toggles
    ESP_OUTLINE     = true,    -- Reveal enemies through walls (colored outline)
    AIMBOT          = true,    -- Auto aim when firing
    AUTO_CALLOUT    = false,   -- Auto ping enemies (disable to avoid spam/detection)
    ESP_TEAMMATE    = false,   -- Also outline teammates in green (for awareness)

    -- ESP Colors
    ESP_COLOR_CLOSE = {1, 0, 0, 1},       -- Red: Close enemies (< 15m)
    ESP_COLOR_MID   = {1, 0.5, 0, 1},     -- Orange: Medium range (15-30m)
    ESP_COLOR_FAR   = {1, 1, 0, 1},       -- Yellow: Far enemies (> 30m)
    ESP_COLOR_SPIKE = {1, 0, 1, 1},       -- Magenta: Spike carrier
    ESP_COLOR_TEAM  = {0, 1, 0, 1},       -- Green: Teammates
    ESP_DIST_CLOSE  = 1500,                -- Close range threshold (cm)
    ESP_DIST_MID    = 3000,                -- Mid range threshold (cm)

    -- Aimbot settings
    FOV             = 45,
    MAXD            = 6000,
    CHEST_Z         = 25,
    MY_EYE_Z        = 55,
    AIM_SMOOTH      = 0.15,
    AIM_SMOOTH_FIRST= 0.6,
    JITTER          = 0.3,

    -- Timing
    TICK            = 0.020,
    ESP_INTERVAL    = 0.3,     -- ESP refresh
    CALLOUT_CD      = 5.0,     -- Callout cooldown per enemy

    -- Logging
    LOG             = false,
    LOGP            = "/storage/emulated/0/Android/data/com.tencent.tmgp.codev/files/UE4Game/CodeV/CodeV/Saved/Paks/puffer_temp/mega_log.txt",
}

local ok_tt, TT = pcall(require, "Common.Framework.TimeTicker")

----------------------------------------------------------------------
-- LOGGING
----------------------------------------------------------------------
local function L(m)
    if not CFG.LOG then return end
    pcall(function()
        local f = io.open(CFG.LOGP, "a")
        if f then f:write("[" .. os.date("%H:%M:%S") .. "] " .. tostring(m) .. "\n") f:close() end
    end)
end

----------------------------------------------------------------------
-- SAFE IMPORTS
----------------------------------------------------------------------
local function SI(n) local o,v = pcall(function() return import(n) end) return o and v or nil end
local function SIL(n) local o,v = pcall(function() return import_func_lib(n) end) return o and v or nil end
local function SR(n) local o,v = pcall(require, n) return o and v or nil end

local KML      = SIL("KismetMathLibrary")
local GP       = SIL("GameplayStatics")
local UKSL     = SIL("KismetSystemLibrary")
local CVFunc   = SIL("CVFunctionLibrary")
local SGPS_CLS = SI("SGBasePlayerState")
local SGCH_CLS = SI("SGBaseCharacter")
local AP       = SR("Game.Mod.BaseMod.GamePlay.Core.GAS.Util.AbilityPreDefine")
local RPCSender = SR("Game.Core.RPC.RPCSender")

local ETTQ_Vis = nil
pcall(function()
    local ECC = import("ECollisionChannel")
    if ECC and ECC.ECC_Visibility and CVFunc then
        ETTQ_Vis = CVFunc.ConvertToTraceType(ECC.ECC_Visibility)
    end
end)

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------
local function GetPC()
    if GameAPI and GameAPI.GetPlayerController then
        local o,p = pcall(function() return GameAPI.GetPlayerController() end)
        if o and p and slua_isValid(p) then return p end
    end
    if GP then
        local o,p = pcall(function() return GP.GetPlayerController(slua_getWorld(), 0) end)
        if o and p and slua_isValid(p) then return p end
    end
end

local function GetPS()
    if GameAPI and GameAPI.GetPlayerState then
        local o,p = pcall(function() return GameAPI.GetPlayerState() end)
        if o and p and slua_isValid(p) then return p end
    end
end

local function GetCh(pc)
    if not pc then return end
    local o,c = pcall(function() return pc:GetSGBaseCharacter() end)
    if o and c and slua_isValid(c) then return c end
    local o2,c2 = pcall(function() return pc:K2_GetPawn() end)
    if o2 and c2 and slua_isValid(c2) then return c2 end
end

local function IsFiring(ch)
    local o,f = pcall(function() return ch:HasPawnState(EPawnState_AFire) end)
    return o and f or false
end

local function VDist(a,b) return math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2) end
local function NA(a) while a>180 do a=a-360 end while a<-180 do a=a+360 end return a end
local function LerpAng(c,t,s) return c + NA(t-c)*s end

local function LookAt(f,t)
    if KML and KML.FindLookAtRotation then
        local o,r = pcall(function() return KML.FindLookAtRotation(f,t) end)
        if o and r then return r end
    end
    local dx,dy,dz = t.X-f.X, t.Y-f.Y, t.Z-f.Z
    local d2 = math.sqrt(dx*dx+dy*dy)
    return FRotator(math.deg(math.atan(dz,d2)), math.deg(math.atan(dy,dx)), 0)
end

local function IsVisible(myChar, eyePos, targetPos)
    if not UKSL or not ETTQ_Vis then return true end
    local ok2, bHit = pcall(function()
        local zc = FLinearColor(0,0,0,0)
        return UKSL.LineTraceSingle(slua_getWorld(),
            FVector(eyePos.X,eyePos.Y,eyePos.Z),
            FVector(targetPos.X,targetPos.Y,targetPos.Z),
            ETTQ_Vis, true, {myChar}, 0, nil, false, zc, zc, 0.0)
    end)
    if ok2 then return not bHit end
    return true
end

----------------------------------------------------------------------
-- GET CHARACTERS (enemies + optionally teammates)
----------------------------------------------------------------------
local function GetCharacters()
    local enemies = {}
    local teammates = {}

    -- Try GameAPI.GetEnemies first (works with real players)
    if GameAPI and GameAPI.GetEnemies then
        pcall(function()
            local en = GameAPI.GetEnemies()
            if en then
                for _, ps in pairs(en) do
                    if slua_isValid(ps) and ps:IsAlive() then
                        local c = ps:GetSGBaseCharacter()
                        if c and slua_isValid(c) then
                            enemies[#enemies+1] = {p=ps, c=c}
                        end
                    end
                end
            end
        end)
    end

    -- Fallback: GetAllActorsOfClass(SGBaseCharacter) for bots
    if #enemies == 0 then
        local chClass = SGCH_CLS
        if AP and AP.ASGBaseCharacterClass then chClass = AP.ASGBaseCharacterClass end
        if chClass and GameAPI and GameAPI.GetAllActorsOfClass then
            local myChar = nil
            pcall(function() local pc = GetPC() if pc then myChar = GetCh(pc) end end)
            pcall(function()
                local ac = GameAPI.GetAllActorsOfClass(chClass)
                if ac then
                    for _, ch in pairs(ac) do
                        if slua_isValid(ch) and ch ~= myChar then
                            local alive = true
                            pcall(function() local a = ch:IsAlive() alive = a end)
                            pcall(function() if ch:IsDying() then alive = false end end)
                            if alive then
                                local isSame = false
                                if AP and AP.IsSameCampWithLocalPlayer then
                                    local o,s = pcall(function() return AP.IsSameCampWithLocalPlayer(ch) end)
                                    if o then isSame = s end
                                end
                                if isSame then
                                    teammates[#teammates+1] = {p=nil, c=ch}
                                else
                                    enemies[#enemies+1] = {p=nil, c=ch}
                                end
                            end
                        end
                    end
                end
            end)
        end
    end

    -- Get teammates via GameAPI
    if CFG.ESP_TEAMMATE and #teammates == 0 and GameAPI and GameAPI.GetTeammates then
        pcall(function()
            local tm = GameAPI.GetTeammates()
            if tm then
                for _, ps in pairs(tm) do
                    if slua_isValid(ps) and ps:IsAlive() then
                        local c = ps:GetSGBaseCharacter()
                        if c and slua_isValid(c) then
                            teammates[#teammates+1] = {p=ps, c=c}
                        end
                    end
                end
            end
        end)
    end

    return enemies, teammates
end

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------
local S = {
    inM=false, mca=0, tc=0, ltk=nil, fireFrames=0,
    espAcc=0, outlinedChars={}, calloutTimers={}, DecoSys=nil,
}

----------------------------------------------------------------------
-- ESP OUTLINE (distance-based colors!)
----------------------------------------------------------------------
local function ColorForDist(dist, hasSpikeFlag)
    if hasSpikeFlag then return CFG.ESP_COLOR_SPIKE end
    if dist < CFG.ESP_DIST_CLOSE then return CFG.ESP_COLOR_CLOSE end
    if dist < CFG.ESP_DIST_MID then return CFG.ESP_COLOR_MID end
    return CFG.ESP_COLOR_FAR
end

local function DoESP(enemies, teammates, myEye)
    if not CFG.ESP_OUTLINE or not S.DecoSys then return end

    local currentKeys = {}

    -- Outline enemies
    for _, v in ipairs(enemies) do
        pcall(function()
            local k = tostring(v.c)
            currentKeys[k] = true
            local pos = v.c:K2_GetActorLocation()
            if not pos then return end
            local dist = VDist(myEye, pos)

            -- Check spike
            local hasSpike = false
            pcall(function()
                if v.p then hasSpike = v.p:GetSuperData().bHasSpike end
            end)

            local col = ColorForDist(dist, hasSpike)
            local fCol = FLinearColor(col[1], col[2], col[3], col[4])

            -- Apply or update outline
            if not S.outlinedChars[k] or S.outlinedChars[k].colKey ~= tostring(col[1])..tostring(col[2]) then
                -- Remove old first if color changed
                if S.outlinedChars[k] then
                    pcall(function() S.DecoSys:RemoveCharacterDecoration(v.c) end)
                end
                pcall(function() S.DecoSys:SetCharacterRevealed(v.c, fCol) end)
                S.outlinedChars[k] = {char=v.c, colKey=tostring(col[1])..tostring(col[2]), isTeam=false}
            end
        end)
    end

    -- Outline teammates (green)
    if CFG.ESP_TEAMMATE then
        for _, v in ipairs(teammates) do
            pcall(function()
                local k = tostring(v.c)
                currentKeys[k] = true
                if not S.outlinedChars[k] then
                    local col = CFG.ESP_COLOR_TEAM
                    pcall(function()
                        S.DecoSys:SetCharacterRevealed(v.c, FLinearColor(col[1],col[2],col[3],col[4]))
                    end)
                    S.outlinedChars[k] = {char=v.c, colKey="team", isTeam=true}
                end
            end)
        end
    end

    -- Remove outlines for characters no longer tracked
    for k, data in pairs(S.outlinedChars) do
        if not currentKeys[k] then
            pcall(function() S.DecoSys:RemoveCharacterDecoration(data.char) end)
            S.outlinedChars[k] = nil
        end
    end
end

----------------------------------------------------------------------
-- AUTO CALLOUT
----------------------------------------------------------------------
local function DoAutoCallout(enemies, myChar)
    if not CFG.AUTO_CALLOUT or not RPCSender then return end
    local now = os.clock()
    for _, v in ipairs(enemies) do
        pcall(function()
            local pos = v.c:K2_GetActorLocation()
            if not pos then return end
            local ck = tostring(v.c)
            if S.calloutTimers[ck] and (now - S.calloutTimers[ck]) < CFG.CALLOUT_CD then return end
            local mp = myChar:K2_GetActorLocation()
            if not IsVisible(myChar, {X=mp.X,Y=mp.Y,Z=mp.Z+CFG.MY_EYE_Z}, pos) then return end
            if v.p then
                pcall(function()
                    local key = v.p:GetPlayerKey()
                    if key then
                        RPCSender:Server("ServerRPC_OnReceivePostEnemySpotted", key, true, {})
                        S.calloutTimers[ck] = now
                    end
                end)
            end
        end)
    end
end

----------------------------------------------------------------------
-- AIMBOT
----------------------------------------------------------------------
local function DoAimbot(enemies, myChar, myEye, cr, pc)
    if not CFG.AIMBOT then return end
    if not IsFiring(myChar) then S.fireFrames=0 return end
    S.fireFrames = S.fireFrames + 1
    if #enemies == 0 then return end

    local be,bp,bestAng = nil,nil,999
    for _,v in ipairs(enemies) do
        local ok2,ep = pcall(function() return v.c:K2_GetActorLocation() end)
        if ok2 and ep then
            ep.Z = ep.Z + CFG.CHEST_Z
            local d = VDist(myEye, ep)
            if d <= CFG.MAXD then
                local tr = LookAt(myEye, ep)
                local dY,dP = NA(tr.Yaw-cr.Yaw), NA(tr.Pitch-cr.Pitch)
                local ang = math.sqrt(dY*dY+dP*dP)
                if ang <= CFG.FOV/2 and IsVisible(myChar, myEye, ep) then
                    if ang < bestAng then bestAng=ang be=v bp=ep end
                end
            end
        end
    end
    if not be or not bp then return end
    local ek = nil pcall(function() ek = be.p and be.p:GetPlayerKey() or "bot" end)
    if ek ~= S.ltk then S.ltk=ek L("[AIM] tgt="..tostring(ek).." ang="..string.format("%.1f",bestAng)) end
    local rot = LookAt(myEye, bp)
    local sm = S.fireFrames==1 and CFG.AIM_SMOOTH_FIRST or CFG.AIM_SMOOTH
    local np = LerpAng(cr.Pitch, rot.Pitch + (math.random()-0.5)*CFG.JITTER, sm)
    local ny = LerpAng(cr.Yaw,   rot.Yaw   + (math.random()-0.5)*CFG.JITTER, sm)
    pcall(function() pc:ClientSetRotation(FRotator(np,ny,0), false) end)
end

----------------------------------------------------------------------
-- MAIN TICK
----------------------------------------------------------------------
local function OnTick(dt)
    S.tc = S.tc + 1

    -- Match check every 1s
    S.mca = S.mca + dt
    if S.mca >= 1.0 then
        S.mca = 0
        local was = S.inM
        local pc = GetPC()
        local ch = pc and GetCh(pc)
        local alive = false
        local ps = GetPS()
        if ps then pcall(function() alive = ps:IsAlive() end) end
        S.inM = (pc ~= nil) and (ch ~= nil) and alive
        if S.inM and not was then
            L("=== MATCH START ===")
            S.outlinedChars = {}
            S.calloutTimers = {}
            pcall(function()
                local GSU = require("Game.Core.Util.GameSystemUtil")
                if GSU and GSU.GetOrCreateGameSystem then
                    S.DecoSys = GSU.GetOrCreateGameSystem("DecorationSystem")
                    L("[DECO] Loaded=" .. tostring(S.DecoSys ~= nil))
                end
            end)
        elseif not S.inM and was then
            L("=== MATCH END ===")
            S.ltk = nil
        end
    end
    if not S.inM then return end

    local pc = GetPC() if not pc then return end
    local myChar = GetCh(pc) if not myChar then return end
    local mp = nil pcall(function() mp = myChar:K2_GetActorLocation() end)
    if not mp then return end
    local myEye = {X=mp.X, Y=mp.Y, Z=mp.Z+CFG.MY_EYE_Z}
    local cr = nil pcall(function() cr = pc:GetControlRotation() end)
    if not cr then return end

    local enemies, teammates = GetCharacters()

    -- AIMBOT every tick
    DoAimbot(enemies, myChar, myEye, cr, pc)

    -- ESP + Callout at interval
    S.espAcc = S.espAcc + dt
    if S.espAcc >= CFG.ESP_INTERVAL then
        S.espAcc = 0
        DoESP(enemies, teammates, myEye)
        if #enemies > 0 then
            DoAutoCallout(enemies, myChar)
        end
    end

    if S.tc % 1000 == 0 then
        L("[STATUS] t=" .. S.tc .. " enemies=" .. #enemies .. " fire=" .. tostring(IsFiring(myChar)))
    end
end

----------------------------------------------------------------------
-- STARTUP
----------------------------------------------------------------------
pcall(function() local f=io.open(CFG.LOGP,"w") if f then f:write("") f:close() end end)
L("╔══════════════════════════════════════╗")
L("║   MEGA HACK v4.0 — Production       ║")
L("║   ESP + Aimbot + Callout            ║")
L("╚══════════════════════════════════════╝")
L("ESP Outline: " .. tostring(CFG.ESP_OUTLINE))
L("Aimbot:      " .. tostring(CFG.AIMBOT))
L("Callout:     " .. tostring(CFG.AUTO_CALLOUT))
L("ESP Colors:  Close=RED Mid=ORANGE Far=YELLOW Spike=MAGENTA")
if ok_tt then
    TT.AddTimerLoop(CFG.TICK, OnTick)
    L("[BOOT] Started! Tick=" .. CFG.TICK)
else
    L("[FATAL] TimeTicker not found!")
end
