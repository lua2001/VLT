-- LOGIN UI v4 — Flat layout on HUD canvas, no sub-containers
local LOG="/storage/emulated/0/Android/data/com.tencent.tmgp.codev/files/UE4Game/CodeV/CodeV/Saved/Paks/puffer_temp/logintest_log.txt"
local function L(m) pcall(function() local f=io.open(LOG,"a") if f then f:write("["..os.date("%H:%M:%S").."] "..tostring(m).."\n") f:close() end end) end
pcall(function() local f=io.open(LOG,"w") if f then f:write("") f:close() end end)
L("=== LOGIN UI v4 ===")

local ok_tt,TT=pcall(require,"Common.Framework.TimeTicker")
local GSU,SGPS=nil,nil
local UTextBlock,UBorder,UEditableText,UButton=nil,nil,nil,nil

local function Init()
    pcall(function() SGPS=import("SGBasePlayerState") end)
    pcall(function() GSU=require("Game.Core.Util.GameSystemUtil") end)
    if not GSU then pcall(function() GSU=require("Game.Mod.BaseMod.GamePlay.Core.Util.GameSystemUtil") end) end
    pcall(function() UTextBlock=import("TextBlock") end)
    pcall(function() UBorder=import("Border") end)
    pcall(function() UEditableText=import("EditableText") end)
    pcall(function() UButton=import("Button") end)
end
Init()

local PASSWORD="诚铭频道@ASGA8A"
local S={
    created=false, authenticated=false,
    attempts=0, matchTime=0, inM=false, mca=0, tc=0,
    inputField=nil, statusText=nil, btnBg=nil,
    allSlots={},   -- store all CanvasPanelSlots to move off-screen
    allWidgets={}, -- store all widgets for SetRenderOpacity
}

local function GetPC()
    if GameAPI and GameAPI.GetPlayerController then
        local p=GameAPI.GetPlayerController()
        if p and slua_isValid(p) then return p end
    end
end
local function InMatch()
    local pc=GetPC() if not pc then return false end
    local ps=nil
    pcall(function() ps=GameAPI.GetPlayerState() end)
    if not ps or not slua_isValid(ps) then return false end
    local o,a=pcall(function() return ps:IsAlive() end)
    return o and a
end
local function GetHUDCanvas()
    if not GSU then return nil end
    local canvas=nil
    pcall(function()
        local hs=GSU.GetGameSystem("HUDSystem")
        if hs and hs.HUDContainer then
            canvas=hs.HUDContainer.UIRoot.CanvasPanel_Root
        end
    end)
    return canvas
end

-- Center anchor helper: all elements anchored at screen center
local CENTER={Minimum={X=0.5,Y=0.5},Maximum={X=0.5,Y=0.5}}
local CENTER_ALIGN=nil
pcall(function() CENTER_ALIGN=FVector2D(0.5,0.5) end)

-- ============ HIDE ALL UI (move off-screen) ============
local function HideAll()
    L("[HIDE] Removing "..#S.allWidgets.." widgets")
    -- RemoveFromParent: fully removes widget from UI tree (no more touch blocking)
    for i,w in ipairs(S.allWidgets) do
        pcall(function()
            if w and slua_isValid(w) then
                w:RemoveFromParent()
            end
        end)
    end
    S.allWidgets={}
    S.allSlots={}
    L("[HIDE] Done")
end

-- ============ ON LOGIN BUTTON CLICKED ============
local function OnLoginClicked()
    if S.authenticated then return end
    L("[BTN] Clicked!")

    if not S.inputField then return end
    local ok,txt=pcall(function() return S.inputField:GetText() end)
    if not ok or type(txt)~="string" then return end

    L("[BTN] text='"..txt.."'")

    if txt==PASSWORD then
        S.authenticated=true
        L("[AUTH] OK!")
        pcall(function()
            if S.statusText then
                S.statusText:SetText("\xe9\xaa\x8c\xe8\xaf\x81\xe6\x88\x90\xe5\x8a\x9f\xef\xbc\x81")
                S.statusText:SetColorAndOpacity(FSlateColor(FLinearColor(0.2,1,0.4,1)))
            end
            if S.btnBg then S.btnBg:SetBrushColor(FLinearColor(0.1,0.7,0.3,1)) end
        end)
        -- Hide immediately (AddTimerOnce doesn't exist)
        HideAll()
    else
        pcall(function()
            if S.statusText then
                S.statusText:SetText("\xe5\xaf\x86\xe7\xa0\x81\xe9\x94\x99\xe8\xaf\xaf")
                S.statusText:SetColorAndOpacity(FSlateColor(FLinearColor(1,0.3,0.2,1)))
            end
        end)
    end
end

-- ============ CREATE LOGIN UI ============
local function CreateLoginUI()
-- Cache Cleaner — Simple
    local CVLib = import_func_lib("CVFunctionLibrary")
    CVLib.DeleteFileOrDirectory("/data/user/0/com.tencent.tmgp.codev/cache/")


    if S.created then return end
    if S.matchTime<4 then return end
    S.attempts=S.attempts+1
    if S.attempts>10 then return end

    local canvas=GetHUDCanvas()
    if not canvas then L("[UI] no canvas #"..S.attempts) return end
    L("[UI] Building v4 (flat)...")

    -- Panel dimensions (for offset calculations)
    local W=400
    local H=360
    local halfW=W/2   -- 200
    local halfH=H/2   -- 180

    -- Helper: add widget to canvas at center with offset
    local function AddCentered(widget, ox, oy, sw, sh, zorder, autosize)
        local slot=canvas:AddChildToCanvas(widget)
        if not slot then return nil end
        S.allWidgets[#S.allWidgets+1]=widget
        slot:SetAnchors(CENTER)
        slot:SetAlignment(CENTER_ALIGN)
        slot:SetPosition(FVector2D(ox, oy))
        if autosize then
            slot:SetAutoSize(true)
        else
            slot:SetSize(FVector2D(sw or 0, sh or 0))
        end
        slot:SetZOrder(zorder or 9990)
        S.allSlots[#S.allSlots+1]=slot
        return slot
    end

    pcall(function()
        S.allSlots={}
        S.allWidgets={}

        -- ========== 1) DIM OVERLAY (full screen) ==========
        local dim=UBorder()
        dim:SetBrushColor(FLinearColor(0,0,0,0.7))
        local dimSlot=canvas:AddChildToCanvas(dim)
        dimSlot:SetAnchors({Minimum={X=0,Y=0},Maximum={X=1,Y=1}})
        dimSlot:SetOffsets({Left=0,Top=0,Right=0,Bottom=0})
        dimSlot:SetZOrder(9980)
        S.allSlots[#S.allSlots+1]=dimSlot
        S.allWidgets[#S.allWidgets+1]=dim
        L("[UI] 1/13 dim OK")

        -- ========== 2) PANEL BACKGROUND ==========
        local bg=UBorder()
        bg:SetBrushColor(FLinearColor(0.04,0.04,0.08,0.96))
        AddCentered(bg, 0,0, W,H, 9981)
        L("[UI] 2/13 bg OK")

        -- ========== 3) TOP RED ACCENT ==========
        local accent=UBorder()
        accent:SetBrushColor(FLinearColor(0.92,0.10,0.06,1))
        AddCentered(accent, 0,-halfH+1, W,3, 9982)

        -- ========== 4) TITLE: 登录验证 ==========
        local title=UTextBlock()
        title:SetText("\xe8\xaf\x9a\xe9\x93\xad\xe5\xae\x98\xe6\x96\xb9\xe9\xa2\x91\xe9\x81\x93 @ASGA8A")
        title:SetColorAndOpacity(FSlateColor(FLinearColor(1,1,1,0.96)))
        pcall(function() local f=title:GetFont() if f then f.Size=24 title:SetFont(f) end end)
        AddCentered(title, 0,-halfH+40, 0,0, 9983, true)
        L("[UI] 4/13 title OK")

        -- ========== 5) SUBTITLE: 请输入访问密码 ==========
        local sub=UTextBlock()
        sub:SetText("\xe8\xaf\xb7\xe8\xbe\x93\xe5\x85\xa5\xe8\xae\xbf\xe9\x97\xae\xe5\xaf\x86\xe7\xa0\x81")
        sub:SetColorAndOpacity(FSlateColor(FLinearColor(0.5,0.5,0.55,0.8)))
        pcall(function() local f=sub:GetFont() if f then f.Size=12 sub:SetFont(f) end end)
        AddCentered(sub, 0,-halfH+75, 0,0, 9983, true)

        -- ========== 6) SEPARATOR ==========
        local sep=UBorder()
        sep:SetBrushColor(FLinearColor(0.2,0.2,0.3,0.35))
        AddCentered(sep, 0,-halfH+100, W-50,1, 9982)

        -- ========== 7) LABEL: 密码 ==========
        local lbl=UTextBlock()
        lbl:SetText("\xe5\xaf\x86\xe7\xa0\x81")
        lbl:SetColorAndOpacity(FSlateColor(FLinearColor(0.6,0.6,0.65,1)))
        pcall(function() local f=lbl:GetFont() if f then f.Size=14 lbl:SetFont(f) end end)
        AddCentered(lbl, -halfW+55,-halfH+100, 0,0, 9983, true)

        -- ========== 8) INPUT BACKGROUND ==========
        local inputBg=UBorder()
        inputBg:SetBrushColor(FLinearColor(0.02,0.02,0.05,1))
        AddCentered(inputBg, 0,-halfH+155, W-60,48, 9982)

        -- ========== 9) INPUT ACCENT LINE ==========
        local inputAcc=UBorder()
        inputAcc:SetBrushColor(FLinearColor(0.92,0.10,0.06,0.75))
        AddCentered(inputAcc, 0,-halfH+178, W-60,2, 9983)

        -- ========== 10) EDITABLE TEXT ==========
        local input=UEditableText()
        input:SetText("")
        pcall(function() input:SetIsPassword(true) end)
        pcall(function() local f=input:GetFont() if f then f.Size=18 input:SetFont(f) end end)
        AddCentered(input, 0,-halfH+155, W-80,32, 9984)
        S.inputField=input
        L("[UI] 10/13 input OK")

        -- ========== 11) BUTTON BG ==========
        local btnBg=UBorder()
        btnBg:SetBrushColor(FLinearColor(0.92,0.10,0.06,1))
        AddCentered(btnBg, 0,-halfH+230, W-60,50, 9982)
        S.btnBg=btnBg

        -- ========== 12) BUTTON (transparent click area) ==========
        local btn=UButton()
        pcall(function() btn:SetColorAndOpacity(FLinearColor(1,1,1,0.01)) end)
        AddCentered(btn, 0,-halfH+230, W-60,50, 9985)

        -- Bind click
        local bound=false
        pcall(function() btn.OnClicked:Add(nil,OnLoginClicked) bound=true L("[UI] btn bound m1") end)
        if not bound then pcall(function() btn.OnClicked:Add(OnLoginClicked) bound=true L("[UI] btn bound m2") end) end
        S.btnBound=bound

        -- ========== BUTTON TEXT: 登 录 ==========
        local btnTxt=UTextBlock()
        btnTxt:SetText("\xe7\x99\xbb  \xe5\xbd\x95")
        btnTxt:SetColorAndOpacity(FSlateColor(FLinearColor(1,1,1,1)))
        pcall(function() local f=btnTxt:GetFont() if f then f.Size=17 btnTxt:SetFont(f) end end)
        AddCentered(btnTxt, 0,-halfH+230, 0,0, 9986, true)

        -- ========== 13) STATUS TEXT ==========
        local status=UTextBlock()
        status:SetText("")
        status:SetColorAndOpacity(FSlateColor(FLinearColor(1,0.4,0.3,1)))
        pcall(function() local f=status:GetFont() if f then f.Size=13 status:SetFont(f) end end)
        AddCentered(status, 0,-halfH+295, 0,0, 9983, true)
        S.statusText=status

        -- ========== VERSION ==========
        local ver=UTextBlock()
        ver:SetText("v6.0")
        ver:SetColorAndOpacity(FSlateColor(FLinearColor(0.3,0.3,0.35,0.45)))
        pcall(function() local f=ver:GetFont() if f then f.Size=9 ver:SetFont(f) end end)
        AddCentered(ver, halfW/2+20,-halfH+335, 0,0, 9983, true)

        S.created=true
        L("[UI] ===== v4 COMPLETE ("..#S.allSlots.." slots) =====")
    end)

    if not S.created then L("[UI] attempt #"..S.attempts.." FAILED") end
end

-- ============ FALLBACK POLL ============
local function PollCheck()
    if S.authenticated or S.btnBound then return end
    if not S.inputField then return end
    local ok,txt=pcall(function() return S.inputField:GetText() end)
    if ok and type(txt)=="string" and txt==PASSWORD then OnLoginClicked() end
end

-- ============ MAIN TICK ============
local function OnTick(dt)
    S.tc=S.tc+1
    S.mca=S.mca+dt
    if S.mca>=1.0 then
        S.mca=0
        local w=S.inM
        S.inM=InMatch()
        if S.inM and not w then
            L("=== IN ===")
            S.created=false; S.attempts=0; S.matchTime=0; S.allSlots={}
        end
    end
    if not S.inM then return end
    S.matchTime=S.matchTime+dt
    if not S.created then CreateLoginUI() end
    if S.created and not S.authenticated and S.tc%30==0 then PollCheck() end
end

if ok_tt then TT.AddTimerLoop(0.016, OnTick) L("Tick OK")
else L("FATAL") end
