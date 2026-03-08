-- MEGA HACK v2.0 — Deep Diagnostic + All Features
-- Fixed: Uses multiple methods to find enemies + detailed logging
----------------------------------------------------------------------
local CFG = {
    ESP_OUTLINE     = true,
    ESP_DRAW3D      = true,
    SMOKE_REMOVER   = true,
    AUTO_CALLOUT    = true,
    AIMBOT          = true,
    SPIKE_TRACKER   = true,

    FOV             = 45,
    MAXD            = 6000,
    CHEST_Z         = 25,
    MY_EYE_Z        = 55,
    AIM_SMOOTH      = 0.15,
    AIM_SMOOTH_FIRST= 0.6,
    JITTER          = 0.3,

    TICK            = 0.020,
    ESP_INTERVAL    = 0.5,
    CALLOUT_CD      = 3.0,
    LOG             = true,
    LOGP            = "/storage/emulated/0/Android/data/com.tencent.tmgp.codev/files/UE4Game/CodeV/CodeV/Saved/Paks/puffer_temp/mega_log2.txt",
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
local function SI(name) local o,v = pcall(function() return import(name) end) return o and v or nil end
local function SIL(name) local o,v = pcall(function() return import_func_lib(name) end) return o and v or nil end
local function SR(name) local o,v = pcall(require, name) return o and v or nil end

----------------------------------------------------------------------
-- CACHED REFERENCES
----------------------------------------------------------------------
local GP       = SIL("GameplayStatics")
local KML      = SIL("KismetMathLibrary")
local UKSL     = SIL("KismetSystemLibrary")
local CVFunc   = SIL("CVFunctionLibrary")
local SGPS_CLS = SI("SGBasePlayerState")
local SGCH_CLS = SI("SGBaseCharacter")
local AP       = SR("Game.Mod.BaseMod.GamePlay.Core.GAS.Util.AbilityPreDefine")
local RPCSender = SR("Game.Core.RPC.RPCSender")

-- Visibility trace
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
    -- Method 1: GameAPI
    if GameAPI and GameAPI.GetPlayerController then
        local o,p = pcall(function() return GameAPI.GetPlayerController() end)
        if o and p and slua_isValid(p) then return p end
    end
    -- Method 2: UGameplayStatics direct
    if GP then
        local o,p = pcall(function() return GP.GetPlayerController(slua_getWorld(), 0) end)
        if o and p and slua_isValid(p) then return p end
    end
end

local function GetPS()
    -- Method 1: GameAPI
    if GameAPI and GameAPI.GetPlayerState then
        local o,p = pcall(function() return GameAPI.GetPlayerState() end)
        if o and p and slua_isValid(p) then return p end
    end
    -- Method 2: From PC
    local pc = GetPC()
    if pc then
        local o,p = pcall(function() return pc:GetSGPlayerState() end)
        if o and p and slua_isValid(p) then return p end
        local o2,p2 = pcall(function() return pc.PlayerState end)
        if o2 and p2 and slua_isValid(p2) then return p2 end
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
-- GET ENEMIES — Multiple methods with detailed logging
----------------------------------------------------------------------
local diagCount = 0
local function GetEnemies()
    local e = {}
    local method = "none"
    diagCount = diagCount + 1
    local doDiag = (diagCount <= 5) or (diagCount % 200 == 0)

    -- METHOD 1: GameAPI.GetEnemies() — the game's own function
    if #e == 0 and GameAPI and GameAPI.GetEnemies then
        pcall(function()
            local enemies, count = GameAPI.GetEnemies()
            if enemies then
                for _, ps in pairs(enemies) do
                    if slua_isValid(ps) and ps:IsAlive() then
                        local c = ps:GetSGBaseCharacter()
                        if c and slua_isValid(c) then
                            e[#e+1] = {p=ps, c=c}
                        end
                    end
                end
                if #e > 0 then method = "GameAPI.GetEnemies" end
            end
        end)
        if doDiag then L("[DIAG] M1 GameAPI.GetEnemies => " .. #e) end
    end

    -- METHOD 2: GameAPI.GetAllPlayers() then filter
    if #e == 0 and GameAPI and GameAPI.GetAllPlayers then
        pcall(function()
            local all = GameAPI.GetAllPlayers()
            if all then
                local total = 0
                for _, ps in pairs(all) do
                    total = total + 1
                    if slua_isValid(ps) then
                        local skip = false
                        if AP and AP.IsSameCampWithLocalPlayer then
                            local oc,s = pcall(function() return AP.IsSameCampWithLocalPlayer(ps) end)
                            if oc and s then skip = true end
                        end
                        if not skip then
                            local alive = false
                            pcall(function() alive = ps:IsAlive() end)
                            if alive then
                                local c = nil
                                pcall(function() c = ps:GetSGBaseCharacter() end)
                                if c and slua_isValid(c) then
                                    e[#e+1] = {p=ps, c=c}
                                end
                            end
                        end
                    end
                end
                if doDiag then L("[DIAG] M2 GetAllPlayers total=" .. total .. " enemies=" .. #e) end
                if #e > 0 then method = "GetAllPlayers" end
            end
        end)
    end

    -- METHOD 3: GetAllActorsOfClass(SGBasePlayerState)
    if #e == 0 and GameAPI and GameAPI.GetAllActorsOfClass and SGPS_CLS then
        pcall(function()
            local ap = GameAPI.GetAllActorsOfClass(SGPS_CLS)
            if ap then
                local total = 0
                for _, ps in pairs(ap) do
                    total = total + 1
                    if slua_isValid(ps) and ps:IsAlive() then
                        local skip = false
                        if AP and AP.IsSameCampWithLocalPlayer then
                            local oc,s = pcall(function() return AP.IsSameCampWithLocalPlayer(ps) end)
                            if oc and s then skip = true end
                        end
                        if not skip then
                            local c = nil
                            pcall(function() c = ps:GetSGBaseCharacter() end)
                            if c and slua_isValid(c) then
                                e[#e+1] = {p=ps, c=c}
                            end
                        end
                    end
                end
                if doDiag then L("[DIAG] M3 ActorsOfClass(SGPS) total=" .. total .. " enemies=" .. #e) end
                if #e > 0 then method = "ActorsOfClass-PS" end
            end
        end)
    end

    -- METHOD 4: GetAllActorsOfClass(SGBaseCharacter)
    if #e == 0 then
        local chClass = SGCH_CLS
        if AP and AP.ASGBaseCharacterClass then chClass = AP.ASGBaseCharacterClass end
        if chClass and GameAPI and GameAPI.GetAllActorsOfClass then
            local myChar = nil
            pcall(function() local pc = GetPC() if pc then myChar = GetCh(pc) end end)
            pcall(function()
                local ac = GameAPI.GetAllActorsOfClass(chClass)
                if ac then
                    local total = 0
                    for _, ch in pairs(ac) do
                        total = total + 1
                        if slua_isValid(ch) and ch ~= myChar then
                            local alive = true
                            pcall(function() local a = ch:IsAlive() alive = a end)
                            pcall(function() if ch:IsDying() then alive = false end end)
                            if alive then
                                local isEnemy = true
                                if AP and AP.IsSameCampWithLocalPlayer then
                                    local o,s = pcall(function() return AP.IsSameCampWithLocalPlayer(ch) end)
                                    if o then isEnemy = not s end
                                end
                                if isEnemy then e[#e+1] = {p=nil, c=ch} end
                            end
                        end
                    end
                    if doDiag then L("[DIAG] M4 ActorsOfClass(CH) total=" .. total .. " enemies=" .. #e) end
                    if #e > 0 then method = "ActorsOfClass-CH" end
                end
            end)
        end
    end

    if doDiag and #e == 0 then
        -- Deep diagnostic: what globals exist?
        L("[DIAG] === DEEP DIAG ===")
        L("[DIAG] GameAPI=" .. tostring(GameAPI ~= nil))
        if GameAPI then
            L("[DIAG] GameAPI.GetEnemies=" .. tostring(GameAPI.GetEnemies ~= nil))
            L("[DIAG] GameAPI.GetAllPlayers=" .. tostring(GameAPI.GetAllPlayers ~= nil))
            L("[DIAG] GameAPI.GetAllActorsOfClass=" .. tostring(GameAPI.GetAllActorsOfClass ~= nil))
            L("[DIAG] GameAPI.GetGameState=" .. tostring(GameAPI.GetGameState ~= nil))
            L("[DIAG] GameAPI.GetPlayerController=" .. tostring(GameAPI.GetPlayerController ~= nil))
            L("[DIAG] GameAPI.GetPlayerState=" .. tostring(GameAPI.GetPlayerState ~= nil))
            -- Test GetGameState
            pcall(function()
                local gs = GameAPI.GetGameState()
                L("[DIAG] GameState=" .. tostring(gs) .. " valid=" .. tostring(slua_isValid(gs)))
                if gs then
                    -- Try to get player array
                    local pa = gs:GetNonObPlayerArray()
                    local cnt = 0
                    if pa then for _ in pairs(pa) do cnt = cnt + 1 end end
                    L("[DIAG] PlayerArray count=" .. cnt)
                end
            end)
            -- Test PC/PS
            pcall(function()
                local pc = GetPC()
                L("[DIAG] PC=" .. tostring(pc) .. " valid=" .. tostring(pc and slua_isValid(pc)))
                if pc then
                    local ch = GetCh(pc)
                    L("[DIAG] MyChar=" .. tostring(ch) .. " valid=" .. tostring(ch and slua_isValid(ch)))
                    if ch then
                        local loc = ch:K2_GetActorLocation()
                        L("[DIAG] MyPos=" .. tostring(loc.X) .. "," .. tostring(loc.Y) .. "," .. tostring(loc.Z))
                    end
                end
            end)
        end
        -- Check if slua_getWorld works
        pcall(function()
            local w = slua_getWorld()
            L("[DIAG] World=" .. tostring(w) .. " valid=" .. tostring(slua_isValid(w)))
        end)
        -- Try direct UGameplayStatics
        if GP then
            pcall(function()
                local pc = GP.GetPlayerController(slua_getWorld(), 0)
                L("[DIAG] GP.GetPlayerController=" .. tostring(pc) .. " valid=" .. tostring(pc and slua_isValid(pc)))
            end)
        end
        -- Try raw GetAllActorsOfClass on world
        pcall(function()
            if SGPS_CLS then
                local actors = GP.GetAllActorsOfClass(slua_getWorld(), SGPS_CLS)
                local cnt = 0
                if actors then
                    local num = actors:Num()
                    L("[DIAG] GP.GetAllActorsOfClass(SGPS) Num=" .. tostring(num))
                    for i = 0, num - 1 do
                        local a = actors:Get(i)
                        if a then
                            cnt = cnt + 1
                            local n = "?"
                            pcall(function() n = a:GetPlayerName() end)
                            L("[DIAG]   Actor#" .. i .. " name=" .. tostring(n))
                        end
                    end
                else
                    L("[DIAG] GP.GetAllActorsOfClass returned nil")
                end
            end
        end)
        L("[DIAG] === END DEEP DIAG ===")
    end

    if #e > 0 and doDiag then
        L("[ENEMIES] Found " .. #e .. " via " .. method)
    end
    return e
end

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------
local S = {
    inM=false, mca=0, tc=0, ltk=nil, fireFrames=0, lockedRot=nil,
    espAcc=0, outlinedEnemies={}, calloutTimers={}, DecoSys=nil,
}

----------------------------------------------------------------------
-- ESP OUTLINE
----------------------------------------------------------------------
local function DoESPOutline(enemies)
    if not CFG.ESP_OUTLINE or not S.DecoSys then return end
    local cur = {}
    for _, v in ipairs(enemies) do
        pcall(function()
            local k = tostring(v.c)
            cur[k] = true
            if not S.outlinedEnemies[k] then
                pcall(function() S.DecoSys:SetCharacterRevealed(v.c, FLinearColor(1,0,0,1)) end)
                S.outlinedEnemies[k] = v.c
                L("[ESP] Outlined: " .. k)
            end
        end)
    end
    for k, ch in pairs(S.outlinedEnemies) do
        if not cur[k] then
            pcall(function() S.DecoSys:RemoveCharacterDecoration(ch) end)
            S.outlinedEnemies[k] = nil
        end
    end
end

----------------------------------------------------------------------
-- ESP DRAW 3D
----------------------------------------------------------------------
local function DoESPDraw3D(enemies, myEye)
    if not CFG.ESP_DRAW3D or not UKSL then return end
    for _, v in ipairs(enemies) do
        pcall(function()
            local pos = v.c:K2_GetActorLocation()
            if not pos then return end
            local dist = VDist(myEye, pos)
            -- Box
            pcall(function()
                UKSL.DrawDebugBox(v.c, pos, FVector(30,30,90),
                    FLinearColor(1,0,0,0.8), FRotator(0,0,0), CFG.ESP_INTERVAL+0.1, 2)
            end)
            -- Text
            local info = ""
            pcall(function()
                local nm = v.p and v.p:GetPlayerName() or "?"
                local hp, sh = "?", "?"
                pcall(function() hp = math.floor(v.p:GetAttributeCurValue("Health")) end)
                pcall(function() sh = math.floor(v.p:GetAttributeCurValue("Shield")) end)
                local spike = ""
                pcall(function() if v.p:GetSuperData().bHasSpike then spike = " [SPIKE]" end end)
                info = string.format("%s [HP:%s SH:%s] %dm%s", nm, hp, sh, math.floor(dist/100), spike)
            end)
            if info ~= "" then
                pcall(function()
                    UKSL.DrawDebugString(v.c, pos+FVector(0,0,130), info, nil, FLinearColor(1,0.2,0.2,1), CFG.ESP_INTERVAL+0.1)
                end)
            end
        end)
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
            local key = nil
            pcall(function() key = v.p:GetPlayerKey() end)
            if not key then return end
            if S.calloutTimers[key] and (now-S.calloutTimers[key]) < CFG.CALLOUT_CD then return end
            local pos = v.c:K2_GetActorLocation()
            local mp = myChar:K2_GetActorLocation()
            if IsVisible(myChar, {X=mp.X,Y=mp.Y,Z=mp.Z+CFG.MY_EYE_Z}, pos) then
                pcall(function() RPCSender:Server("ServerRPC_OnReceivePostEnemySpotted", key, true, {}) end)
                S.calloutTimers[key] = now
                L("[CALLOUT] key=" .. tostring(key))
            end
        end)
    end
end

----------------------------------------------------------------------
-- AIMBOT
----------------------------------------------------------------------
local function DoAimbot(enemies, myChar, myEye, cr, pc)
    if not CFG.AIMBOT then return end
    if not IsFiring(myChar) then S.lockedRot=nil S.fireFrames=0 return end
    S.fireFrames = S.fireFrames + 1
    if #enemies == 0 then S.lockedRot=nil return end

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
    if not be or not bp then S.lockedRot=nil return end
    local ek = nil pcall(function() ek = be.p and be.p:GetPlayerKey() or "bot" end)
    if ek ~= S.ltk then S.ltk=ek L("[AIM] tgt="..tostring(ek).." ang="..string.format("%.1f",bestAng)) end
    local rot = LookAt(myEye, bp)
    local sm = S.fireFrames==1 and CFG.AIM_SMOOTH_FIRST or CFG.AIM_SMOOTH
    local np = LerpAng(cr.Pitch, rot.Pitch + (math.random()-0.5)*CFG.JITTER, sm)
    local ny = LerpAng(cr.Yaw, rot.Yaw + (math.random()-0.5)*CFG.JITTER, sm)
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
        local ps = GetPS()
        local ch = pc and GetCh(pc)
        local alive = false
        if ps then pcall(function() alive = ps:IsAlive() end) end
        S.inM = (pc ~= nil) and (ch ~= nil) and alive
        if S.inM and not was then
            L("=== MATCH START ===")
            S.outlinedEnemies = {}
            S.calloutTimers = {}
            -- Try to get DecorationSystem
            pcall(function()
                local GSU = require("Game.Core.Util.GameSystemUtil")
                if GSU and GSU.GetOrCreateGameSystem then
                    S.DecoSys = GSU.GetOrCreateGameSystem("DecorationSystem")
                    L("[DECO] DecoSys=" .. tostring(S.DecoSys ~= nil))
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

    local enemies = GetEnemies()

    -- AIMBOT (every tick)
    DoAimbot(enemies, myChar, myEye, cr, pc)

    -- ESP (at intervals)
    S.espAcc = S.espAcc + dt
    if S.espAcc >= CFG.ESP_INTERVAL then
        S.espAcc = 0
        if #enemies > 0 then
            DoESPOutline(enemies)
            DoESPDraw3D(enemies, myEye)
            DoAutoCallout(enemies, myChar)
        end
    end

    if S.tc % 500 == 0 then
        L("[STATUS] t=" .. S.tc .. " e=" .. #enemies .. " fire=" .. tostring(IsFiring(myChar)))
    end
end

----------------------------------------------------------------------
-- STARTUP
----------------------------------------------------------------------
pcall(function() local f=io.open(CFG.LOGP,"w") if f then f:write("") f:close() end end)
L("╔══════════════════════════════════════╗")
L("║    MEGA HACK v2.0 — Deep Diag       ║")
L("╚══════════════════════════════════════╝")
L("ESP=" .. tostring(CFG.ESP_OUTLINE) .. " Draw3D=" .. tostring(CFG.ESP_DRAW3D)
  .. " Smoke=" .. tostring(CFG.SMOKE_REMOVER) .. " Callout=" .. tostring(CFG.AUTO_CALLOUT)
  .. " Aimbot=" .. tostring(CFG.AIMBOT))
L("[INIT] AP=" .. tostring(AP~=nil) .. " SGPS=" .. tostring(SGPS_CLS~=nil)
  .. " SGCH=" .. tostring(SGCH_CLS~=nil) .. " KML=" .. tostring(KML~=nil)
  .. " UKSL=" .. tostring(UKSL~=nil) .. " ETTQ=" .. tostring(ETTQ_Vis~=nil)
  .. " RPC=" .. tostring(RPCSender~=nil) .. " GP=" .. tostring(GP~=nil))
L("[INIT] GameAPI=" .. tostring(GameAPI~=nil))
if GameAPI then
    L("[INIT] GameAPI.GetEnemies=" .. tostring(GameAPI.GetEnemies~=nil)
      .. " GetAllPlayers=" .. tostring(GameAPI.GetAllPlayers~=nil)
      .. " GetAllActorsOfClass=" .. tostring(GameAPI.GetAllActorsOfClass~=nil)
      .. " GetGameState=" .. tostring(GameAPI.GetGameState~=nil))
end
L("[INIT] slua_getWorld=" .. tostring(slua_getWorld~=nil)
  .. " slua_isValid=" .. tostring(slua_isValid~=nil)
  .. " EPawnState_AFire=" .. tostring(EPawnState_AFire~=nil))
L("[INIT] GIsClient=" .. tostring(GIsClient) .. " GIsDS=" .. tostring(GIsDS))

if ok_tt then
    TT.AddTimerLoop(CFG.TICK, OnTick)
    L("[BOOT] Timer started!")
else
    L("[FATAL] TimeTicker not found!")
end
