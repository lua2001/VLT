-- Aimbot v5 (Fire-Only + Chest + Smooth + Crosshair Priority + Cover Check)
local CFG = {
    EN=true, LOG=true, TICK=0.016, FOV=45, MAXD=6000, NORECOIL=true,
    MAX_DEG=6.0, JITTER=0.3, CHEST_Z=25, MY_EYE_Z=55,
    AIM_SMOOTH=0.15,        -- Smoothing factor per tick (0.0=no move, 1.0=instant snap)
    AIM_SMOOTH_FIRST=0.6,   -- Higher smoothing for the very first frame of firing (fast initial lock)
    LOGP="/storage/emulated/0/Android/data/com.tencent.tmgp.codev/files/UE4Game/CodeV/CodeV/Saved/Paks/puffer_temp/aimbot_log_v8.txt",
}
local ok_tt,TT=pcall(require,"Common.Framework.TimeTicker")
local AP=nil
pcall(function() AP=require("Game.Mod.BaseMod.GamePlay.Core.GAS.Util.AbilityPreDefine") end)
local SGPS,SGCC,SGCH,KML,GP=nil,nil,nil,nil,nil
local UKSL=nil  -- UKismetSystemLibrary for line traces
local CVFunc=nil -- CVFunctionLibrary for trace type conversion
local ETTQ_Vis=nil -- Cached visibility trace type
local function LI()
    pcall(function() SGPS=import("SGBasePlayerState") end)
    pcall(function() SGCH=import("SGBaseCharacter") end)
    pcall(function() KML=import_func_lib("KismetMathLibrary") end)
    pcall(function() GP=import_func_lib("GameplayStatics") end)
    pcall(function() UKSL=import_func_lib("KismetSystemLibrary") end)
    pcall(function() CVFunc=import_func_lib("CVFunctionLibrary") end)
    -- Cache the visibility trace channel
    if CVFunc and not ETTQ_Vis then
        pcall(function()
            local ECC=import("ECollisionChannel")
            if ECC and ECC.ECC_Visibility then
                ETTQ_Vis=CVFunc.ConvertToTraceType(ECC.ECC_Visibility)
            end
        end)
    end
    if not AP then pcall(function() AP=require("Game.Mod.BaseMod.GamePlay.Core.GAS.Util.AbilityPreDefine") end) end
    pcall(function() if AP and AP.ASGBaseCharacterClass then SGCC=AP.ASGBaseCharacterClass end end)
    if not SGCC and SGCH then SGCC=SGCH end
end
local function L(m) if not CFG.LOG then return end pcall(function() local f=io.open(CFG.LOGP,"a") if f then f:write("["..os.date("%H:%M:%S").."] "..tostring(m).."\n") f:close() end end) end
local S={inM=false,mca=0,tc=0,ltk=nil,il=false,dd=false,fireFrames=0}
local function GetPC()
    if GameAPI and GameAPI.GetPlayerController then local p=GameAPI.GetPlayerController() if p and slua_isValid(p) then return p end end
    if GP and slua_getWorld then local o,p=pcall(function() return GP.GetPlayerController(slua_getWorld(),0) end) if o and p and slua_isValid(p) then return p end end
end
local function GetPS() if GameAPI and GameAPI.GetPlayerState then local o,p=pcall(function() return GameAPI.GetPlayerState() end) if o and p and slua_isValid(p) then return p end end end
local function GetCh(pc) if not pc then return end local o,c=pcall(function() return pc:GetSGBaseCharacter() end) if o and c and slua_isValid(c) then return c end end
local function InMatch()
    local pc=GetPC() if not pc then return false end
    local ps=GetPS() if not ps then return false end
    if not GetCh(pc) then return false end
    local o,a=pcall(function() return ps:IsAlive() end) if o and a then return true end
    if GameAPI and GameAPI.GetGameState then local o2,g=pcall(function() return GameAPI.GetGameState() end) if o2 and g and slua_isValid(g) then return true end end
    return false
end
-- Check if player is currently firing
local function IsFiring(myChar)
    local o,f=pcall(function() return myChar:HasPawnState(EPawnState_AFire) end)
    if o then return f end
    return false
end
-- Check if target is visible (not behind cover) using line trace
local function IsVisible(myChar, eyePos, targetPos)
    if not UKSL or not ETTQ_Vis then return true end -- if trace not available, assume visible
    local ok,bHit=pcall(function()
        local startV=FVector(eyePos.X, eyePos.Y, eyePos.Z)
        local endV=FVector(targetPos.X, targetPos.Y, targetPos.Z)
        local zeroColor=FLinearColor(0,0,0,0)
        -- LineTraceSingle: world, start, end, traceType, bComplex, ignoreActors, drawDebugType, hitResult, bIgnoreSelf, traceColor, traceHitColor, drawTime
        local hit=UKSL.LineTraceSingle(slua_getWorld(), startV, endV, ETTQ_Vis, true, {myChar}, 0, nil, false, zeroColor, zeroColor, 0.0)
        return hit
    end)
    if ok then
        return not bHit -- if nothing was hit, the target is visible
    end
    return true -- fallback: assume visible
end
local function Diag()
    L("=== DIAG ===")
    L("AP="..tostring(AP~=nil).." SGPS="..tostring(SGPS~=nil).." SGCC="..tostring(SGCC~=nil))
    L("EPawnState_AFire="..tostring(EPawnState_AFire~=nil))
    L("UKSL="..tostring(UKSL~=nil).." ETTQ_Vis="..tostring(ETTQ_Vis~=nil))
    if GameAPI and GameAPI.GetAllActorsOfClass and SGPS then
        local o,r=pcall(function() return GameAPI.GetAllActorsOfClass(SGPS) end)
        if o and r then local n=0 for _ in pairs(r) do n=n+1 end L("PS="..n)
            local i=0 for _,ps in pairs(r) do i=i+1 if i<=6 then
                local s="#"..i local oa,av=pcall(function() return ps:IsAlive() end) s=s.." a="..tostring(av)
                if AP then local oc,cv=pcall(function() return AP.IsSameCampWithLocalPlayer(ps) end) s=s.." sc="..tostring(cv) end
                L(s) end end end
    end
    local cc=SGCC or (AP and AP.ASGBaseCharacterClass)
    if cc and GameAPI then
        local o,r=pcall(function() return GameAPI.GetAllActorsOfClass(cc) end)
        if o and r then local n=0 for _ in pairs(r) do n=n+1 end L("CH="..n) end
    end
    L("=== END ===")
end
local function GetEnemies()
    local e={}
    if GameAPI and GameAPI.GetAllActorsOfClass and SGPS then
        local o,ap=pcall(function() return GameAPI.GetAllActorsOfClass(SGPS) end)
        if o and ap then for _,ps in pairs(ap) do pcall(function()
            if slua_isValid(ps) and ps:IsAlive() then
                local skip=false
                if AP and AP.IsSameCampWithLocalPlayer then local oc,s=pcall(function() return AP.IsSameCampWithLocalPlayer(ps) end) if oc and s then skip=true end end
                if not skip then local c=ps:GetSGBaseCharacter() if c and slua_isValid(c) then e[#e+1]={p=ps,c=c} end end
            end end) end end
    end
    if #e==0 then
        local cc=SGCC or (AP and AP.ASGBaseCharacterClass)
        if cc and GameAPI and GameAPI.GetAllActorsOfClass then
            local my=nil pcall(function() local pc=GetPC() if pc then my=GetCh(pc) end end)
            local o,ac=pcall(function() return GameAPI.GetAllActorsOfClass(cc) end)
            if o and ac then for _,ch in pairs(ac) do pcall(function()
                if slua_isValid(ch) and ch~=my then
                    local al=true local oa,a=pcall(function() return ch:IsAlive() end) if oa then al=a end
                    local od,d=pcall(function() return ch:IsDying() end) if od and d then al=false end
                    if al then local ie=true
                        if AP and AP.IsSameCampWithLocalPlayer then local oc,s=pcall(function() return AP.IsSameCampWithLocalPlayer(ch) end) if oc then ie=not s end end
                        if ie then e[#e+1]={p=nil,c=ch} end
                    end
                end end) end end
        end
    end
    return e
end
local function VDist(a,b) return math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2) end
local function NA(a) while a>180 do a=a-360 end while a<-180 do a=a+360 end return a end
local function LerpAngle(cur, tgt, t)
    local diff = NA(tgt - cur)
    return cur + diff * t
end
local function LookAt(f,t)
    if KML and KML.FindLookAtRotation then local o,r=pcall(function() return KML.FindLookAtRotation(f,t) end) if o and r then return r end end
    local dx,dy,dz=t.X-f.X,t.Y-f.Y,t.Z-f.Z local d2=math.sqrt(dx*dx+dy*dy)
    return FRotator(math.deg(math.atan(dz,d2)),math.deg(math.atan(dy,dx)),0)
end
local function OnTick(dt)
    if not CFG.EN then return end S.tc=S.tc+1
    if not S.il then LI() if SGPS and KML then S.il=true L("[INIT] OK") end end
    S.mca=S.mca+dt
    if S.mca>=1.0 then S.mca=0 local w=S.inM S.inM=InMatch()
        if S.inM and not w then L("=== IN ===") if not S.dd then S.dd=true Diag() end
        elseif not S.inM and w then L("=== OUT ===") S.ltk=nil end
    end
    if not S.inM then return end
    local pc=GetPC() if not pc then return end
    local ps=GetPS() if not ps then return end
    local al=false pcall(function() al=ps:IsAlive() end) if not al then return end
    local my=GetCh(pc) if not my then return end
    -- ONLY aim when firing
    if not IsFiring(my) then S.lockedRot=nil S.fireFrames=0 return end
    -- Track how many frames we've been firing
    S.fireFrames=S.fireFrames+1
    -- My position (eye level)
    local mp=nil pcall(function() mp=my:K2_GetActorLocation() end) if not mp then return end
    local myEye={X=mp.X,Y=mp.Y,Z=mp.Z+CFG.MY_EYE_Z}
    -- Current rotation
    local cr=nil pcall(function() cr=pc:GetControlRotation() end) if not cr then return end
    -- Get enemies
    local en=GetEnemies()
    if #en==0 then
        S.lockedRot=nil
        if S.tc%300==0 then L("[ST] t="..S.tc.." e=0 firing") end
        return
    end
    -- FIX 1: Find closest enemy to CROSSHAIR CENTER (angular distance), not world distance
    -- FIX 3: Skip enemies behind cover using line trace
    local be,bp,bestAng=nil,nil,999
    for _,v in ipairs(en) do
        local ok2,ep=pcall(function() return v.c:K2_GetActorLocation() end)
        if ok2 and ep then
            ep.Z=ep.Z+CFG.CHEST_Z -- chest
            local d=VDist(myEye,ep)
            if d<=CFG.MAXD then
                local tr=LookAt(myEye,ep)
                local dY=NA(tr.Yaw-cr.Yaw) local dP=NA(tr.Pitch-cr.Pitch)
                local ang=math.sqrt(dY*dY+dP*dP)
                -- Only consider enemies within FOV
                if ang<=(CFG.FOV/2) then
                    -- FIX 3: Check if enemy is visible (not behind cover)
                    if IsVisible(my, myEye, ep) then
                        -- FIX 1: Priority by angular distance to crosshair center (smallest angle wins)
                        if ang<bestAng then bestAng=ang be=v bp=ep end
                    end
                end
            end
        end
    end
    if not be or not bp then S.lockedRot=nil return end
    -- Log target change
    local ek=nil pcall(function() ek=be.p and be.p:GetPlayerKey() or "bot" end)
    if ek~=S.ltk then S.ltk=ek L("[AIM] → "..tostring(ek).." ang="..string.format("%.1f",bestAng)) end
    -- Calculate exact rotation to chest
    local exactRot=LookAt(myEye,bp)
    -- Add tiny jitter for human-like imperfection
    local jX=(math.random()-0.5)*CFG.JITTER
    local jY=(math.random()-0.5)*CFG.JITTER
    local targetPitch=exactRot.Pitch+jY
    local targetYaw=exactRot.Yaw+jX
    -- FIX 2: Smooth aiming - lerp from current rotation to target
    local smooth=CFG.AIM_SMOOTH
    if S.fireFrames==1 then smooth=CFG.AIM_SMOOTH_FIRST end -- faster on first frame
    local newPitch=LerpAngle(cr.Pitch, targetPitch, smooth)
    local newYaw=LerpAngle(cr.Yaw, targetYaw, smooth)
    local finalRot=FRotator(newPitch,newYaw,0)
    pcall(function() pc:ClientSetRotation(finalRot,false) end)
    S.lockedRot=finalRot
    if S.tc%300==0 then L("[ST] t="..S.tc.." e="..#en.." tg="..tostring(S.ltk or"-").." sm="..smooth) end
end
pcall(function() local f=io.open(CFG.LOGP,"w") if f then f:write("") f:close() end end)
L("Aimbot v5 smooth+crosshair+cover") L("FOV="..CFG.FOV.." Smooth="..CFG.AIM_SMOOTH.." SmoothFirst="..CFG.AIM_SMOOTH_FIRST.." Chest="..CFG.CHEST_Z.." Eye="..CFG.MY_EYE_Z)
if ok_tt then LI() TT.AddTimerLoop(CFG.TICK,OnTick) L("Tick OK") else L("FATAL") end
