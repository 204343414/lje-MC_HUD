-- ================================================================
--   MCHUD v1.2  -  Minecraft style HUD for Garry's Mod (LJE)
--
--   Author : ba   (with assist from Arena.ai Agent Mode)
--   Target : LJE + ljeutil environment (Eyoko1.ljeutil)
--   License: do whatever, share with friends, don't sell
--
--   v1.2 changes vs v1.1:
--     · Dual-path rendering: ljeutil/render PRIMARY + HUDPaint BACKUP
--       (v1.1 used hook.post which Clear()s our draws -- ZERO output)
--     · Frame-id dedup so we never draw twice per frame
--
--   v1.1 changes vs v1.0:
--     · render hook: ljeutil/render -> ljeutil/postrender
--       (v1.0 drew BEFORE 3D scene finished; bots showed THROUGH HUD)
--     · text rendering: draw.SimpleText -> surface.DrawText
--       (gilbhax-style; SimpleText doesn't survive LJE font sandbox)
--     · DLib bind hijack defeated: PlayerBindPress now uses hook.pre
--       (v1.0 lost to DLib's higher-priority handler that ate slot1-9)
--     · DLib HUD scrub: remove ONLY DLib's own HUDPaint hooks at boot
--       (the yellow HL2 HUD you saw was DLib's, blocking our hearts)
-- ================================================================

-- ---------------- 0. CONFIG ----------------
local DEBUG = true   -- set to false for "quiet" public release
local function dbg(...)
    if not DEBUG then return end
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end
    lje.con_print("[MCHUD] " .. table.concat(parts, " "))
end

dbg("v1.2 main.lua starting")

-- ---------------- 1. NATIVE HOOK BYPASS ----------------
local native_hook = lje.get_global("hook")
if not native_hook or not native_hook.Add then
    lje.con_print("[MCHUD] FATAL: native hook table missing")
    return
end

local _hook_Add      = native_hook.Add
local _hook_Remove   = native_hook.Remove
local _hook_GetTable = native_hook.GetTable

local function hAdd(event, id, fn)
    pcall(_hook_Remove, event, id)
    _hook_Add(event, id, fn)
end
local function hRemove(event, id)
    pcall(_hook_Remove, event, id)
end

dbg("native hook table captured, DLib bypass active")

-- ---------------- 2. PULL ENGINE GLOBALS ----------------
local function bring(name)
    local v = lje.get_global(name)
    if v ~= nil then rawset(_G, name, v) end
    return v
end

bring("surface")    bring("render")    bring("draw")     bring("cam")
bring("Material")   bring("Color")
bring("ScrW")       bring("ScrH")

bring("LocalPlayer")  bring("IsValid")   bring("IsColor")
bring("ents")         bring("player")
bring("CurTime")      bring("RealTime")  bring("FrameTime")
bring("SysTime")

bring("input")        bring("RunConsoleCommand")

bring("weapons")      bring("killicon")  bring("language")

bring("isnumber")  bring("isstring")  bring("istable")  bring("isfunction")
bring("MsgC")      bring("Msg")
bring("math")      bring("string")    bring("table")

bring("TEXT_ALIGN_LEFT")    bring("TEXT_ALIGN_RIGHT")  bring("TEXT_ALIGN_CENTER")
bring("TEXT_ALIGN_TOP")     bring("TEXT_ALIGN_BOTTOM")
bring("MOUSE_LEFT")         bring("MOUSE_RIGHT")       bring("MOUSE_MIDDLE")

if not math.pow then
    math.pow = function(b, e) return b ^ e end
end

dbg("engine globals bridged")

-- ---------------- 3. TEXTURES ----------------
local MAT_ICONS   = Material("mc_hud/icons.png",   "noclamp")
local MAT_WIDGETS = Material("mc_hud/widgets.png", "noclamp")

local function mat_ok(m)
    if not m then return false end
    local ok, err = pcall(function() return m:IsError() end)
    if not ok then return false end
    return not err
end
if not mat_ok(MAT_ICONS) then
    lje.con_print("[MCHUD] WARN: mc_hud/icons.png not found - install the assets! See README.")
end
if not mat_ok(MAT_WIDGETS) then
    lje.con_print("[MCHUD] WARN: mc_hud/widgets.png not found - install the assets! See README.")
end

-- ---------------- 4. STATE ----------------
local lastHP         = nil
local flashUntil     = 0
local FLASH_DURATION = 0.5

local currentPage     = 0
local activeSlot      = 0
local allWeapons      = {}
local lastWepCount    = -1
local pageLockedUntil = 0

local oxygenTimer = 0
local OXYGEN_MAX  = 15
local isDrowning  = false

local xpKills = 0
local xpLevel = 0
local xpAnim  = 0
local xpFlash = 0
local function XPToNextLevel(lv) return math.pow(2, lv) end
local function XPProgress()
    local base = 0
    for i = 0, xpLevel - 1 do base = base + XPToNextLevel(i) end
    local need = XPToNextLevel(xpLevel)
    if need <= 0 then return 0 end
    return math.max(0, math.min(1, (xpKills - base) / need))
end

local wasDead = false

-- ---------------- 5. SPRITE HELPERS ----------------
local function Spr(mat, sx, sy, sw, sh, dx, dy, dw, dh, sz)
    if not mat then return end
    sz = sz or 256
    local du = 0.5 / sz
    local dv = 0.5 / sz
    local u0 = (sx       / sz - du) / (1 - 2 * du)
    local v0 = (sy       / sz - dv) / (1 - 2 * dv)
    local u1 = ((sx+sw)  / sz - du) / (1 - 2 * du)
    local v1 = ((sy+sh)  / sz - dv) / (1 - 2 * dv)
    surface.SetMaterial(mat)
    surface.SetDrawColor(255, 255, 255, 255)
    surface.DrawTexturedRectUV(
        math.floor(dx), math.floor(dy),
        math.floor(dw), math.floor(dh),
        u0, v0, u1, v1)
end

local function SprA(mat, sx, sy, sw, sh, dx, dy, dw, dh, alpha, sz)
    if not mat then return end
    sz = sz or 256
    local du = 0.5 / sz
    local dv = 0.5 / sz
    local u0 = (sx       / sz - du) / (1 - 2 * du)
    local v0 = (sy       / sz - dv) / (1 - 2 * dv)
    local u1 = ((sx+sw)  / sz - du) / (1 - 2 * du)
    local v1 = ((sy+sh)  / sz - dv) / (1 - 2 * dv)
    surface.SetMaterial(mat)
    surface.SetDrawColor(255, 255, 255, alpha or 255)
    surface.DrawTexturedRectUV(
        math.floor(dx), math.floor(dy),
        math.floor(dw), math.floor(dh),
        u0, v0, u1, v1)
end

local function SprPart(mat, sx, sy, sw, sh, dx, dy, dw, dh, partRatio, sz)
    if not mat then return end
    if partRatio <= 0 then return end
    if partRatio > 1 then partRatio = 1 end
    sz = sz or 256
    local du = 0.5 / sz
    local dv = 0.5 / sz
    local clippedSw = sw * partRatio
    local clippedDw = dw * partRatio
    local u0 = (sx                 / sz - du) / (1 - 2 * du)
    local v0 = (sy                 / sz - dv) / (1 - 2 * dv)
    local u1 = ((sx + clippedSw)   / sz - du) / (1 - 2 * du)
    local v1 = ((sy + sh)          / sz - dv) / (1 - 2 * dv)
    surface.SetMaterial(mat)
    surface.SetDrawColor(255, 255, 255, 255)
    surface.DrawTexturedRectUV(
        math.floor(dx), math.floor(dy),
        math.floor(clippedDw), math.floor(dh),
        u0, v0, u1, v1)
end

-- ---------------- 5b. TEXT HELPERS (v1.1: gilbhax-style) ----------------
-- draw.SimpleText doesn't render reliably in the LJE postrender context,
-- because it manages font state via internals that LJE may not have
-- bridged. We use the lower-level surface.* primitives, which gilbhax
-- proves work fine in this exact context.
--
-- Returns the (w, h) of the rendered text, useful for centering.
local function TextSize(font, txt)
    surface.SetFont(font)
    return surface.GetTextSize(txt)
end

-- Draw text. align_x/align_y mimic TEXT_ALIGN_*: 0=left/top, 1=center, 2=right/bottom
local function DrawText(txt, font, x, y, color, align_x, align_y)
    if not txt or txt == "" then return end
    surface.SetFont(font)
    local tw, th = surface.GetTextSize(txt)
    local px = x
    local py = y
    if align_x == 1 then px = x - tw / 2
    elseif align_x == 2 then px = x - tw end
    if align_y == 1 then py = y - th / 2
    elseif align_y == 2 then py = y - th end
    surface.SetTextPos(math.floor(px), math.floor(py))
    if color then
        surface.SetTextColor(color.r or 255, color.g or 255, color.b or 255, color.a or 255)
    else
        surface.SetTextColor(255, 255, 255, 255)
    end
    surface.DrawText(txt)
end

-- Draw text with a 1-shadow + 1-main pass (MC style).
local function DrawTextShadow(txt, font, x, y, mainColor, align_x, align_y)
    DrawText(txt, font, x + 2, y + 2, Color(0, 0, 0, mainColor.a or 200),
        align_x, align_y)
    DrawText(txt, font, x, y, mainColor, align_x, align_y)
end

-- ---------------- 6. HIDE STOCK HUD + DLIB HUD ----------------
local HIDE = {
    CHudHealth      = true,  CHudBattery        = true,
    CHudAmmo        = true,  CHudSecondaryAmmo  = true,
    CHudCrosshair   = true,  CHudDamageIndicator= true,
    CHudSuitPower   = true,  CHudSquadStatus    = true,
    CHudWeaponSelection = true,  CHudGeiger     = true,
    CHudTrain       = true,  CHudZoom           = true,
    CHudFlashlight  = true,
}
hAdd("HUDShouldDraw", "MCHUD_Hide", function(name)
    if HIDE[name] then return false end
end)

-- v1.1: surgical DLib HUD removal.
-- We DO NOT iterate all hooks (that's the v8 §11 anti-cheat trip).
-- We only remove the small set of well-known DLib HUDPaint hook IDs.
-- If they're not present (no DLib installed), the Remove calls are no-ops.
--
-- This is "scalpel" not "shotgun": at most ~10 specific name removals,
-- only on HUDPaint, only at startup. No iteration, no scanning, no
-- pattern matching.
local DLIB_HUD_HOOK_IDS = {
    -- DLib's own HUDPaint registrations and known Wilk/DBot HUD ports
    "DLib.HUDPaint",
    "DLib.HUDCommons",
    "DLib.HUDCommons.HUDPaint",
    "DLib.HUDCommons.PostDrawHUD",
    "DLib.HUDCommons.PreDrawHUD",
    "DBotHUD",
    "WilkHUD",
    "wilk_hud",
    "Wilk_Hud",
    "TacIntHUD",
    "TacticalInterventionHUD",
}
local function nuke_dlib_hud()
    local removed = 0
    for _, id in ipairs(DLIB_HUD_HOOK_IDS) do
        for _, ev in ipairs({"HUDPaint", "PostDrawHUD", "DrawOverlay", "HUDPaintBackground"}) do
            -- Only remove if it actually exists (silent if not)
            if _hook_GetTable then
                local tbl = _hook_GetTable()
                if tbl and tbl[ev] and tbl[ev][id] then
                    pcall(_hook_Remove, ev, id)
                    removed = removed + 1
                    dbg("removed DLib hook:", ev, "->", id)
                end
            else
                -- No GetTable available; just try blindly
                pcall(_hook_Remove, ev, id)
            end
        end
    end
    if removed > 0 then
        dbg("removed", removed, "DLib HUD hooks")
    else
        dbg("no DLib HUD hooks found (clean environment or already removed)")
    end
end

-- Run nuke now and once more 1 second later in case DLib loads after us
nuke_dlib_hud()
hAdd("Think", "MCHUD_DLibLateNuke", function()
    nuke_dlib_hud()
    hRemove("Think", "MCHUD_DLibLateNuke")  -- one-shot
end)

-- ---------------- 7. CROSSHAIR ----------------
local function DrawCrosshair(sw, sh)
    local cx, cy = math.floor(sw/2), math.floor(sh/2)
    local L, T = 8, 2
    surface.SetDrawColor(0, 0, 0, 140)
    surface.DrawRect(cx-L-1,   cy-T/2+1, L*2, T)
    surface.DrawRect(cx-T/2+1, cy-L-1,   T,   L*2)
    surface.SetDrawColor(255, 255, 255, 230)
    surface.DrawRect(cx-L,   cy-T/2, L*2, T)
    surface.DrawRect(cx-T/2, cy-L,   T,   L*2)
end

-- ---------------- 8. WEAPONS / ICONS ----------------
local iconCache    = {}
local defaultTexID = nil

local function UpdateWeapons(lp)
    local weps = lp:GetWeapons()
    local validCount = 0
    for _, w in ipairs(weps) do
        if IsValid(w) then validCount = validCount + 1 end
    end
    if validCount == lastWepCount then return end
    lastWepCount = validCount

    iconCache  = {}
    allWeapons = {}
    for _, w in ipairs(weps) do
        if IsValid(w) then table.insert(allWeapons, w) end
    end
    table.sort(allWeapons, function(a, b)
        if a:GetSlot() ~= b:GetSlot() then
            return a:GetSlot() < b:GetSlot()
        end
        return a:GetClass() < b:GetClass()
    end)
end

local function DrawWeaponIcon(wep, x, y, w, h)
    if not IsValid(wep) then return end
    local cls = wep:GetClass()

    if defaultTexID == nil and surface.GetTextureID then
        defaultTexID = surface.GetTextureID("weapons/swep")
    end

    if iconCache[cls] == nil then
        local found = false
        local stored = weapons and weapons.GetStored and weapons.GetStored(cls) or nil

        if stored and isnumber and isnumber(stored.WepSelectIcon)
           and stored.WepSelectIcon ~= defaultTexID
           and stored.WepSelectIcon ~= 0 then
            iconCache[cls] = { t = "tex", v = stored.WepSelectIcon }
            found = true
        end

        if not found then
            local override = stored and stored.IconOverride
            local tryMats = {
                override,
                "entities/" .. cls .. ".png",
                "vgui/entities/" .. cls .. ".png",
            }
            for _, p in ipairs(tryMats) do
                if p and p ~= "" then
                    local mat = Material(p, "noclamp smooth")
                    if mat_ok(mat) then
                        iconCache[cls] = { t = "mat", v = mat }
                        found = true
                        break
                    end
                end
            end
        end

        if not found then
            local mdl = wep.GetWeaponWorldModel and wep:GetWeaponWorldModel()
            if mdl and mdl ~= "" then
                local baseName = string.lower(string.gsub(mdl, "%.mdl$", ""))
                local matched  = string.match(mdl, "([^/]+)$") or mdl
                local tryPaths = {
                    "spawnicons/" .. baseName .. ".png",
                    "spawnicons/models/weapons/"
                        .. string.lower(string.gsub(matched, "%.mdl$", ""))
                        .. ".png",
                }
                for _, p in ipairs(tryPaths) do
                    local mat = Material(p, "noclamp smooth")
                    if mat_ok(mat) then
                        iconCache[cls] = { t = "mat", v = mat }
                        found = true
                        break
                    end
                end
            end
        end

        if not found then
            if stored and isfunction and isfunction(stored.DrawWeaponSelection) then
                iconCache[cls] = { t = "dws", v = stored }
                found = true
            end
        end

        if not found and killicon and killicon.Exists and killicon.Exists(cls) then
            iconCache[cls] = { t = "kill", v = cls }
            found = true
        end

        if not found then
            iconCache[cls] = false
        end
    end

    local c = iconCache[cls]
    if not c then
        local raw  = wep.GetPrintName and wep:GetPrintName() or cls
        local name = (language and language.GetPhrase and language.GetPhrase(raw)) or raw
        if string.sub(name, 1, 1) == "#" then name = cls end
        DrawText(string.sub(name, 1, 4), "DermaDefault",
            x + w/2, y + h/2, Color(255, 255, 255, 150), 1, 1)
        return
    end

    if c.t == "kill" then
        local iw, ih = killicon.GetSize(c.v)
        if iw and ih and iw > 0 then
            local scale = math.min(w/iw, h/ih) * 0.8
            local rw, rh = iw * scale, ih * scale
            killicon.Render(
                math.floor(x + (w - rw) / 2),
                math.floor(y + (h - rh) / 2),
                c.v, 220)
        end
    elseif c.t == "tex" then
        surface.SetDrawColor(255, 255, 255, 255)
        surface.SetTexture(c.v)
        surface.DrawTexturedRect(x, y + h/4, w, h/2)
    elseif c.t == "mat" then
        surface.SetMaterial(c.v)
        surface.SetDrawColor(255, 255, 255, 255)
        surface.DrawTexturedRect(x, y, w, h)
    elseif c.t == "dws" then
        pcall(function()
            c.v.DrawWeaponSelection(nil, x, y, w, h, 255)
        end)
    end
end

local function DrawDurBar(x, y, w, h, ratio)
    surface.SetDrawColor(0, 0, 0, 180)
    surface.DrawRect(x, y, w, h)
    local r = math.floor(255 * (1 - ratio))
    local g = math.floor(255 * ratio)
    surface.SetDrawColor(r, g, 0, 255)
    surface.DrawRect(x, y, math.max(1, math.floor(w * ratio)), h)
end

local function DrawHotbar(lp, sw, sh, sc)
    local slotW = 20 * sc
    local barW  = slotW * 9 + 2 * sc
    local barH  = 22 * sc
    local barX  = math.floor((sw - barW) / 2)
    local barY  = sh - barH - 5

    Spr(MAT_WIDGETS, 0,  0, 182, 22, barX, barY, barW, barH)
    Spr(MAT_WIDGETS, 0, 22,  24, 24,
        barX + activeSlot * slotW - sc,
        barY - sc,
        24 * sc, 24 * sc)

    local totalPages = math.max(1, math.ceil(#allWeapons / 9))
    if totalPages > 1 then
        DrawText(
            "[" .. (currentPage + 1) .. "/" .. totalPages .. "]",
            "DermaDefaultBold",
            barX + barW + 8, barY + (22 * sc) / 2,
            Color(255, 255, 100, 220),
            0, 1)
    end

    for i = 0, 8 do
        local idx = currentPage * 9 + i + 1
        local wep = allWeapons[idx]
        local sx  = barX + i * slotW + 2
        local sy  = barY + 2
        local ssz = slotW - 4
        if IsValid(wep) then
            DrawWeaponIcon(wep, sx, sy, ssz, ssz)
            local clip    = wep:Clip1()
            local maxclip = wep:GetMaxClip1()
            if clip >= 0 and maxclip > 0 then
                DrawDurBar(sx, barY + barH - 4, ssz, 3,
                    math.Clamp(clip / maxclip, 0, 1))
            end
        end
    end
    return barX, barY
end

-- ---------------- 9. HEALTH / ARMOR ----------------
local function DrawHealth(hp, maxhp, x, y, sc)
    local hs  = 9 * sc
    local fOn = (CurTime() < flashUntil) and (math.floor(CurTime() * 10) % 2 == 0)

    if maxhp > 100 then
        DrawText("x" .. math.ceil(math.max(hp, 1) / 100),
            "DermaLarge",
            x - 22, y + hs / 2,
            Color(255, 85, 85, 255),
            1, 1)
    end

    local curHP = (hp <= 0) and 0 or ((hp - 1) % 100 + 1)
    local hVal  = (curHP / 100) * 20
    for i = 0, 9 do
        local px = x + i * (8 * sc + 2)
        Spr(MAT_ICONS, fOn and 25 or 16, 0, 9, 9, px, y, hs, hs)
        local v = hVal - i * 2
        if v >= 2 then
            Spr(MAT_ICONS, fOn and 70 or 52, 0, 9, 9, px, y, hs, hs)
        elseif v >= 1 then
            Spr(MAT_ICONS, fOn and 79 or 61, 0, 9, 9, px, y, hs, hs)
        end
    end
end

local function DrawArmor(armor, x, y, sc)
    if armor <= 0 then return false end
    local as   = 9 * sc
    local aVal = math.Clamp(armor / 100 * 20, 0, 20)
    for i = 0, 9 do
        local px = x + i * (8 * sc + 2)
        Spr(MAT_ICONS, 16, 9, 9, 9, px, y, as, as)
        local v = aVal - i * 2
        if v >= 2 then
            Spr(MAT_ICONS, 34, 9, 9, 9, px, y, as, as)
        elseif v >= 1 then
            Spr(MAT_ICONS, 25, 9, 9, 9, px, y, as, as)
        end
    end
    return true
end

-- ---------------- 10. INPUT (1-9 keys + scroll wheel) ----------------
-- v1.1 KEY CHANGE: use hook.pre instead of native hook.Add for
-- PlayerBindPress. ljeutil's pre-hook fires BEFORE GMod runs the
-- registered hook chain, which means before DLib's PlayerBindPress
-- handler. So even if DLib intercepts and returns false later, our
-- input.SelectWeapon() has already executed.
local lastWheel = 0

if hook and hook.pre then
    -- pre-hook style: fires before DLib gets to chew on it
    hook.pre("InputMouseApply", "MCHUD_Scroll", function(cmd, x, y, ang)
        local lp = LocalPlayer()
        if not IsValid(lp) or not lp:Alive() then return end
        if input.IsMouseDown(MOUSE_LEFT)
           or input.IsMouseDown(MOUSE_RIGHT)
           or input.IsMouseDown(MOUSE_MIDDLE) then return end

        local wheel = cmd:GetMouseWheel()
        if wheel == 0 then return end
        if CurTime() - lastWheel < 0.01 then return end
        lastWheel = CurTime()

        local totalPages = math.max(1, math.ceil(#allWeapons / 9))
        if wheel > 0 then
            currentPage = (currentPage - 1 + totalPages) % totalPages
        else
            currentPage = (currentPage + 1) % totalPages
        end
        pageLockedUntil = CurTime() + 0.15

        for i = 0, 8 do
            local wep = allWeapons[currentPage * 9 + i + 1]
            if IsValid(wep) then
                activeSlot = i
                input.SelectWeapon(wep)
                break
            end
        end
    end)

    hook.pre("PlayerBindPress", "MCHUD_Binds", function(ply, bind, pressed)
        if not pressed then return end
        local lp = LocalPlayer()
        if not IsValid(lp) or not lp:Alive() then return end

        if string.find(bind, "slot") then
            local sNum = tonumber(string.match(bind, "slot(%d)"))
            if sNum then
                local slot = sNum - 1
                local idx  = currentPage * 9 + slot + 1
                local wep  = allWeapons[idx]
                if IsValid(wep) then
                    activeSlot = slot
                    input.SelectWeapon(wep)
                end
                -- Returning true here works in pre-hook to suppress
                -- the rest of the chain (including DLib's handler).
                return true
            end
        end
    end)
    dbg("input hooks attached via hook.pre (defeats DLib intercept)")
else
    -- Fallback: ljeutil missing
    hAdd("InputMouseApply", "MCHUD_Scroll", function(cmd, x, y, ang)
        local lp = LocalPlayer()
        if not IsValid(lp) or not lp:Alive() then return end
        if input.IsMouseDown(MOUSE_LEFT)
           or input.IsMouseDown(MOUSE_RIGHT)
           or input.IsMouseDown(MOUSE_MIDDLE) then return end
        local wheel = cmd:GetMouseWheel()
        if wheel == 0 then return end
        if CurTime() - lastWheel < 0.01 then return end
        lastWheel = CurTime()
        local totalPages = math.max(1, math.ceil(#allWeapons / 9))
        if wheel > 0 then
            currentPage = (currentPage - 1 + totalPages) % totalPages
        else
            currentPage = (currentPage + 1) % totalPages
        end
        pageLockedUntil = CurTime() + 0.15
        for i = 0, 8 do
            local wep = allWeapons[currentPage * 9 + i + 1]
            if IsValid(wep) then
                activeSlot = i
                input.SelectWeapon(wep)
                break
            end
        end
    end)
    hAdd("PlayerBindPress", "MCHUD_Binds", function(ply, bind, pressed)
        if not pressed then return end
        local lp = LocalPlayer()
        if not IsValid(lp) or not lp:Alive() then return end
        if string.find(bind, "slot") then
            local sNum = tonumber(string.match(bind, "slot(%d)"))
            if sNum then
                local slot = sNum - 1
                local idx  = currentPage * 9 + slot + 1
                local wep  = allWeapons[idx]
                if IsValid(wep) then
                    activeSlot = slot
                    input.SelectWeapon(wep)
                end
                return true
            end
        end
    end)
    dbg("input hooks attached via native hook.Add (no ljeutil pre-hook)")
end

-- ---------------- 11. THINK ----------------
hAdd("Think", "MCHUD_Think", function()
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    local alive = lp:Alive()

    if not alive and not wasDead then
        wasDead = true
    elseif alive and wasDead then
        wasDead = false
    end
    if not alive then return end

    local kills = lp:Frags()
    if kills ~= xpKills then
        xpKills = kills
        local needed = 0
        local lv     = 0
        while xpKills >= needed + XPToNextLevel(lv) do
            needed = needed + XPToNextLevel(lv)
            lv     = lv + 1
        end
        if lv > xpLevel then
            xpLevel = lv
            xpFlash = CurTime() + 1.0
        end
    end

    local target = XPProgress()
    xpAnim = xpAnim + (target - xpAnim) * math.min(FrameTime() * 8, 1)

    if CurTime() > pageLockedUntil then
        local activeWep = lp:GetActiveWeapon()
        if IsValid(activeWep) then
            for i, w in ipairs(allWeapons) do
                if w == activeWep then
                    currentPage = math.floor((i - 1) / 9)
                    activeSlot  = (i - 1) % 9
                    break
                end
            end
        end
    end
end)

-- ---------------- 12. THE MAIN DRAW ----------------
local function DoDraw()
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    if not lp:Alive() then
        if wasDead then
            local sw, sh = ScrW(), ScrH()
            surface.SetDrawColor(80, 0, 0, 160)
            surface.DrawRect(0, 0, sw, sh)
            DrawTextShadow("You Died!", "HudHintTextLarge",
                sw/2, sh/2, Color(255, 50, 50, 255), 1, 1)
        end
        return
    end

    local sw, sh = ScrW(), ScrH()
    local sc     = 3
    local rowH   = 9 * sc + 6

    local barW = 20 * sc * 9 + 2 * sc
    local barX = math.floor((sw - barW) / 2)
    local barY = sh - (22 * sc) - 5

    local hp    = math.max(lp:Health(), 0)
    local maxhp = math.max(lp:GetMaxHealth(), 1)
    local armor = lp:Armor()

    local xpBarH = 4 * sc
    local xpBarY = barY - xpBarH - 4

    local heartY   = xpBarY - rowH - 2
    local hungerY  = heartY
    local armorY   = heartY - rowH
    local bubDrawY = armorY

    DrawHealth(hp, maxhp, barX, heartY, sc)
    DrawArmor(armor, barX, armorY, sc)

    local hs = 9 * sc
    for i = 0, 9 do
        local px = barX + barW - (i + 1) * (8 * sc + 2)
        Spr(MAT_ICONS, 16, 27, 9, 9, px, hungerY, hs, hs)
        Spr(MAT_ICONS, 52, 27, 9, 9, px, hungerY, hs, hs)
    end

    UpdateWeapons(lp)
    DrawHotbar(lp, sw, sh, sc)
    DrawCrosshair(sw, sh)

    -- XP bar
    local isFlashing = CurTime() < xpFlash
    Spr(MAT_ICONS, 0, 64, 182, 5, barX, xpBarY, barW, xpBarH, 256)
    if xpAnim > 0 then
        SprPart(MAT_ICONS, 0, 69, 182, 5, barX, xpBarY, barW, xpBarH, xpAnim, 256)
    end

    -- Level number using surface.DrawText (gilbhax-style; works in postrender)
    local lvText = isFlashing and "LEVEL UP!" or tostring(xpLevel)
    DrawTextShadow(lvText, "HudHintTextLarge",
        barX + barW / 2, xpBarY - 1,
        isFlashing and Color(255, 255, 0, 255) or Color(128, 255, 32, 255),
        1, 2)

    -- Bubbles
    local waterLv = lp:WaterLevel()
    if waterLv >= 3 then
        if not isDrowning then
            isDrowning  = true
            oxygenTimer = CurTime()
        end
        local elapsed   = CurTime() - oxygenTimer
        local ratio     = math.Clamp(1 - elapsed / OXYGEN_MAX, 0, 1)
        local totalHalf = math.floor(ratio * 20)
        local bs        = 9 * sc
        for i = 0, 9 do
            local px   = barX + barW - (i + 1) * (8 * sc + 2)
            local slot = 9 - i
            local v    = totalHalf - slot * 2
            local frac = (ratio * 20) - math.floor(ratio * 20)
            if v >= 2 then
                Spr(MAT_ICONS, 16, 18, 9, 9, px, bubDrawY, bs, bs)
            elseif v == 1 then
                local alpha = math.floor(frac * 255)
                SprA(MAT_ICONS, 25, 18, 9, 9, px, bubDrawY, bs, bs, alpha)
            end
        end
    else
        isDrowning  = false
        oxygenTimer = 0
    end

    if lastHP == nil then lastHP = hp end
    if hp ~= lastHP then
        flashUntil = CurTime() + FLASH_DURATION
    end
    lastHP = hp
end

-- ---------------- 13. ATTACH TO RENDER (v1.2: dual-path) ----------------
-- After reading ljeutil's modules/render.lua source we now know the
-- truth about the safert pipeline:
--
--   hook.post("PostRender", "__safert", function()
--       cam.Start2D()
--       render.PushRenderTarget(safert)         -- enter safe RT
--       hook.callpre("ljeutil/render")          -- ← we draw here
--       hook.callpre("ljeutil/postrender")
--       render.PushRenderTarget(nil)            -- back to screen
--       render.SetMaterial(safertmaterial)
--       render.DrawScreenQuad()                 -- blit safe RT to screen
--       render.PopRenderTarget()
--       hook.callpost("ljeutil/render")         -- ← these run AFTER
--       hook.callpost("ljeutil/postrender")     -- ← Clear()s the RT,
--       render.Clear(0, 0, 0, 0, true, true)    -- so post hooks are gone
--       render.PopRenderTarget()
--   end)
--
-- Conclusions:
--   · ONLY hook.pre("ljeutil/render") draws to the safe RT and shows up
--   · hook.post(...) draws get Clear()ed before screen blit -- DEAD
--   · The "bot showing through HUD" v1.0 issue is alpha-blending
--     between safe RT and screen, fixed by drawing a fully opaque
--     primitive first to reset alpha, OR by also registering HUDPaint
--     as a backup which draws straight to screen.
--
-- v1.2 strategy: register BOTH paths.
--   · Primary: hook.pre("ljeutil/render") -- preferred, draws to safe RT
--     which is screengrab-protected by ljeutil
--   · Backup: HUDPaint -- always works in vanilla GMod, only used when
--     ljeutil's safert hook didn't fire this frame (e.g. ljeutil missing,
--     DLib suppressed it, or screenshot in progress)
--
-- A frame-counter ensures we draw exactly ONCE per frame regardless of
-- which path fires first.

local last_drawn_frame = -1

local function frame_id()
    -- FrameNumber() exists in GMod; use CurTime as fallback
    local fn = lje.get_global("FrameNumber")
    if fn then return fn() end
    return math.floor(CurTime() * 1000)
end

local function GuardedDraw(path_name)
    local f = frame_id()
    if f == last_drawn_frame then return end
    last_drawn_frame = f
    local ok, err = pcall(DoDraw)
    if not ok then
        lje.con_print("[MCHUD] draw error in " .. path_name .. ": " .. tostring(err))
    end
end

-- Path 1: ljeutil safe-RT path (preferred)
if hook and hook.pre then
    dbg("attaching primary render path: hook.pre(ljeutil/render)")
    hook.pre("ljeutil/render", "MCHUD_Render", function()
        GuardedDraw("ljeutil/render")
    end)
else
    dbg("ljeutil hook.pre unavailable -- primary render path disabled")
end

-- Path 2: HUDPaint fallback (always registered)
-- This draws straight to screen, so:
--   · works even if ljeutil isn't loaded
--   · works even if DLib breaks ljeutil's hook chain
--   · works even during screengrabs (which is technically a leak,
--     but the alternative is no HUD at all)
dbg("attaching backup render path: HUDPaint")
hAdd("HUDPaint", "MCHUD_RenderBackup", function()
    GuardedDraw("HUDPaint")
end)

-- ---------------- 14. DONE ----------------
lje.con_print("[MCHUD] v1.2 loaded successfully")
if DEBUG then
    lje.con_print("[MCHUD] DEBUG mode is ON - set DEBUG=false in main.lua before sharing")
end
