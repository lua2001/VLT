-- SKIN CHANGER v4.0 — Retry Until Weapons Ready
----------------------------------------------------------------------
local CFG = {
    LOG  = true,
    LOGP = "/storage/emulated/0/Android/data/com.tencent.tmgp.codev/files/UE4Game/CodeV/CodeV/Saved/Paks/puffer_temp/skin_log.txt",
    
    DESIRED_SKINS = {
        [10101] = 101005011,   -- Classic -> 万铀引力辐爆者
        [10104] = 104003011,   -- Ghost -> 天界神兵
        [10103] = 103003111,   -- Frenzy -> 全息波普
    },
}

local function L(m)
    if not CFG.LOG then return end
    pcall(function()
        local f = io.open(CFG.LOGP, "a")
        if f then f:write("[" .. os.date("%H:%M:%S") .. "] " .. tostring(m) .. "\n") f:close() end
    end)
end
pcall(function() local f=io.open(CFG.LOGP,"w") if f then f:write("") f:close() end end)
L("╔══════════════════════════════════════╗")
L("║  SKIN CHANGER v4.0 — Auto Retry     ║")
L("╚══════════════════════════════════════╝")

local function SR(n) local o,v = pcall(require, n) return o and v or nil end
local function SIL(n) local o,v = pcall(function() return import_func_lib(n) end) return o and v or nil end

local GP = SIL("GameplayStatics")
local RPCSender = SR("Game.Core.RPC.RPCSender")
local GameSystemUtil = SR("Game.Core.Util.GameSystemUtil")
local ok_tt, TT = pcall(require, "Common.Framework.TimeTicker")

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
    local pc = GetPC()
    if pc then
        local o,p = pcall(function() return pc:GetSGPlayerState() end)
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

----------------------------------------------------------------------
-- CHECK IF WEAPONS ARE READY
----------------------------------------------------------------------
local function GetWeapons()
    local pc = GetPC()
    if not pc then return nil, 0 end
    local ch = GetCh(pc)
    if not ch then return nil, 0 end
    local wl = nil
    pcall(function() wl = ch:GetWeaponList() end)
    if not wl then return nil, 0 end
    return wl, wl:Num()
end

----------------------------------------------------------------------
-- TRY ALL SKIN CHANGE METHODS ON ONE WEAPON
----------------------------------------------------------------------
local function TryChangeWeaponSkin(weaponObj, ps, weaponID, targetSkinID)
    local curAvatar = 0
    pcall(function() curAvatar = weaponObj:GetWeaponAvatarID() end)
    L("  Current AvatarID: " .. tostring(curAvatar))
    
    if curAvatar == targetSkinID then
        L("  Already has target skin!")
        return true
    end
    
    -- A: Create override table + apply
    pcall(function()
        if not ps.WeaponAvatarOverrideInfo then
            ps.WeaponAvatarOverrideInfo = {}
        end
        ps.WeaponAvatarOverrideInfo[weaponID] = {targetSkinID}
        L("  [A] Override table set")
    end)
    pcall(function()
        ps:SetWeaponAvatarOverride(weaponID, {targetSkinID})
        L("  [A2] SetWeaponAvatarOverride OK")
    end)
    pcall(function()
        ps:ApplyWeaponAvatarImmediately(weaponID)
        L("  [A3] ApplyWeaponAvatarImmediately OK")
    end)
    
    -- B: AvatarComp direct manipulation
    pcall(function()
        local ac = weaponObj.AvatarComp
        if ac and slua_isValid(ac) then
            -- List all functions
            local funcs = {}
            pcall(function()
                for k,v in pairs(ac) do
                    if type(v) == "function" then funcs[#funcs+1] = k end
                end
            end)
            if #funcs > 0 then L("  [B] AvatarComp funcs: " .. table.concat(funcs, ",")) end
            
            pcall(function() ac:SetAvatarID(targetSkinID) L("  [B] SetAvatarID OK") end)
            pcall(function() ac:InitAvatar(targetSkinID) L("  [B] InitAvatar OK") end)
            pcall(function() ac:ReloadAvatar() L("  [B] ReloadAvatar OK") end)
            pcall(function() ac:ChangeAvatar(targetSkinID) L("  [B] ChangeAvatar OK") end)
            pcall(function() ac:OnRep_AvatarID() L("  [B] OnRep_AvatarID OK") end)
            pcall(function() ac:RefreshAvatar() L("  [B] RefreshAvatar OK") end)
        else
            L("  [B] No AvatarComp")
        end
    end)
    
    -- C: SGEquipment remove + re-add
    pcall(function()
        local eq = ps.SGEquipment
        if eq and slua_isValid(eq) then
            local itemID = eq:GetItemID(weaponID)
            if itemID then
                local acq = eq:GetItemAcquireType(itemID)
                eq:RemoveItemsByResID(weaponID)
                eq:AddItemByResID(weaponID, 1, acq or 0)
                L("  [C] Re-equipped, AcqType=" .. tostring(acq))
            else
                L("  [C] No itemID")
            end
        else
            L("  [C] No SGEquipment")
        end
    end)
    
    -- D: RPCs
    pcall(function()
        if RPCSender then
            RPCSender:Server("ServerRPC_ChangeWeaponAvatar", 1, weaponID, targetSkinID, true)
            L("  [D] ServerRPC_ChangeWeaponAvatar sent")
        end
    end)
    pcall(function()
        if RPCSender then
            RPCSender:Server("ServerRPC_ActivateWeaponSkinList", 1)
            L("  [D2] ActivateWeaponSkinList sent")
        end
    end)
    
    -- Verify
    local newAvatar = 0
    pcall(function() newAvatar = weaponObj:GetWeaponAvatarID() end)
    local changed = (newAvatar ~= curAvatar)
    L("  [RESULT] AvatarID: " .. tostring(curAvatar) .. " -> " .. tostring(newAvatar) .. (changed and " ✓ CHANGED!" or " ✗ same"))
    return changed
end

----------------------------------------------------------------------
-- MAIN TICK
----------------------------------------------------------------------
local applied = false
local checkAcc = 0
local checkCount = 0
local maxChecks = 30  -- Try for 30 seconds

local function OnTick(dt)
    if applied then return end
    
    checkAcc = checkAcc + dt
    if checkAcc < 1.0 then return end  -- Check every 1 second
    checkAcc = 0
    checkCount = checkCount + 1
    
    if checkCount > maxChecks then
        L("[TIMEOUT] Gave up after " .. maxChecks .. " seconds")
        applied = true
        return
    end
    
    -- Check if player alive
    local ps = GetPS()
    if not ps then return end
    local alive = false
    pcall(function() alive = ps:IsAlive() end)
    if not alive then return end
    
    -- Check if weapons ready
    local wl, wCount = GetWeapons()
    
    -- Also check SGEquipment
    local hasEq = false
    pcall(function() hasEq = (ps.SGEquipment ~= nil and slua_isValid(ps.SGEquipment)) end)
    
    if checkCount <= 5 or checkCount % 5 == 0 then
        L("[WAIT] t=" .. checkCount .. "s weapons=" .. wCount .. " SGEquip=" .. tostring(hasEq))
    end
    
    -- Need at least 1 weapon to proceed
    if wCount == 0 then return end
    
    L("")
    L("========================================")
    L("  WEAPONS READY! Count=" .. wCount .. " at t=" .. checkCount .. "s")
    L("========================================")
    
    -- Log all current weapons
    for i = 0, wl:Num() - 1 do
        local w = wl:Get(i)
        if w and slua_isValid(w) then
            local wid, avid = 0, 0
            pcall(function() wid = w:GetWeaponID() end)
            pcall(function() avid = w:GetWeaponAvatarID() end)
            L("  Weapon[" .. i .. "] ID=" .. wid .. " AvatarID=" .. avid)
        end
    end
    
    -- Log SGEquipment and PlayerInfo state
    pcall(function()
        L("  SGEquipment: " .. tostring(hasEq))
        local pi = ps.PlayerInfo
        if pi then
            L("  BackpackID: " .. tostring(pi.DefaultWeaponBackpackId))
            if pi.AllWeaponBackpack then
                for bpId, bp in pairs(pi.AllWeaponBackpack) do
                    L("  Backpack[" .. bpId .. "] has " .. tostring(bp.WeaponSkinList and #bp.WeaponSkinList or 0) .. " skins")
                end
            end
        end
        L("  OverrideInfo: " .. tostring(ps.WeaponAvatarOverrideInfo ~= nil))
    end)
    
    -- Try to change each desired skin
    local anyChanged = false
    for weaponID, targetSkin in pairs(CFG.DESIRED_SKINS) do
        L("")
        L("=== WeaponID=" .. weaponID .. " -> Skin=" .. targetSkin .. " ===")
        
        -- Find weapon in list
        local weaponObj = nil
        for i = 0, wl:Num() - 1 do
            local w = wl:Get(i)
            if w and slua_isValid(w) then
                local wid = 0
                pcall(function() wid = w:GetWeaponID() end)
                if wid == weaponID then weaponObj = w break end
            end
        end
        
        if not weaponObj then
            L("  Weapon " .. weaponID .. " not in inventory")
        else
            local ok = TryChangeWeaponSkin(weaponObj, ps, weaponID, targetSkin)
            if ok then anyChanged = true end
        end
    end
    
    -- If nothing in desired list matched, try with whatever weapon is available
    if not anyChanged then
        L("")
        L("=== No desired weapons found, trying ANY weapon ===")
        local w = wl:Get(0)
        if w and slua_isValid(w) then
            local wid, avid = 0, 0
            pcall(function() wid = w:GetWeaponID() end)
            pcall(function() avid = w:GetWeaponAvatarID() end)
            L("  Testing with WeaponID=" .. wid .. " CurAvatar=" .. avid)
            
            -- Try common skin for this weapon
            -- Pattern: weaponID prefix * 10000000 + skin variant
            local prefix = math.floor(wid / 100)
            local testSkins = {
                prefix * 1000000,          -- default
                prefix * 1000000 + 10400,  -- 琉璃幻梦
                prefix * 1000000 + 1000,   -- 涂鸦
                avid + 1,                   -- next avatar
                avid - 1,                   -- prev avatar
            }
            for _, ts in ipairs(testSkins) do
                if ts > 0 and ts ~= avid then
                    L("  Trying skin " .. ts .. "...")
                    TryChangeWeaponSkin(w, ps, wid, ts)
                end
            end
        end
    end
    
    applied = true
    L("")
    L("=== COMPLETE ===")
end

if ok_tt then
    TT.AddTimerLoop(0.02, OnTick)
    L("[BOOT] Waiting for weapons to load...")
else
    L("[FATAL] TimeTicker not found!")
end
