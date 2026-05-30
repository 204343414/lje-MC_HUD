-- ================================================================
-- MC_SpawnMenu v1.0 - Minecraft creative-inventory style Q menu
-- A companion module for MCHUD (Garry's Mod / LJE)
--
-- Author : written for "ba" by Arena.ai Agent Mode
-- Target : LJE + ljeutil environment (Eyoko1.ljeutil)
-- License: do whatever, share with friends, don't sell
--
-- WHAT THIS DOES
--   Pressing Q (the +menu bind) no longer opens GMod's stock spawn
--   menu. Instead we draw a Minecraft "creative inventory" style
--   window: a 9-column grid of slots showing every spawnable SWEP
--   registered on the server. Click a slot and we run gm_giveswep,
--   which hands you that weapon -- exactly like grabbing an item out
--   of the MC creative menu.
--
-- HONESTY NOTE (read this)
--   Unlike the MCHUD itself, THIS menu is NOT invisible to the server.
--   gm_giveswep is a real console command that asks the server to
--   give you a weapon. That's a normal sandbox action (every GMod
--   player does it), but it is server-visible. So this is a "reskin
--   of a real feature", not a stealth hack.
--
-- DESIGN
--   We deliberately mirror MCHUD's proven techniques so this behaves
--   identically in the LJE sandbox:
--     * native hook table bypass (don't touch DLib)
--     * hook.pre("PlayerBindPress") to grab Q before DLib eats it
--     * gui.EnableScreenClicker for the cursor
--     * surface.* + widgets.png/icons.png sprites for true MC look
--     * dual-path render (ljeutil/render primary, HUDPaint backup)
-- ================================================================

-- ---------------- 0. CONFIG ----------------
local DEBUG = true             -- v1.1: ON so the panel shows counts while we debug

-- Which bind opens the menu. GMod's Q is "+menu". If you'd rather use
-- a different key, change this and rebind in-game. "+menu" = Q default.
local OPEN_BIND     = "+menu"

-- Visual scale of one inventory slot, in screen pixels. MC slots are
-- 18x18 in the source texture; 3x feels right at 1080p (matches MCHUD).
local SLOT_SRC      = 18
local SLOT_SCALE    = 2
local COLS          = 9        -- MC creative inventory is 9 columns wide
local ROWS          = 6        -- visible rows per page (9x6 = 54 slots/page)

local function dbg(...)
    if not DEBUG then return end
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    lje.con_print("[MCSPAWN] " .. table.concat(parts, " "))
end

dbg("v1.0 main.lua starting")

-- ---------------- 1. NATIVE HOOK BYPASS ----------------
-- Same trick MCHUD uses: capture the real hook table at load time so
-- DLib's wrapper never sees our registrations.
local native_hook = lje.get_global("hook")
if not native_hook or not native_hook.Add then
    lje.con_print("[MCSPAWN] FATAL: native hook table missing")
    return
end

local _hook_Add    = native_hook.Add
local _hook_Remove = native_hook.Remove

local function hAdd(event, id, fn)
    pcall(_hook_Remove, event, id)
    _hook_Add(event, id, fn)
end
local function hRemove(event, id)
    pcall(_hook_Remove, event, id)
end

dbg("native hook table captured")

-- ---------------- 2. PULL ENGINE GLOBALS ----------------
local function bring(name)
    local v = lje.get_global(name)
    if v ~= nil then rawset(_G, name, v) end
    return v
end

bring("surface") bring("render") bring("draw")
bring("Material") bring("Color")
bring("ScrW") bring("ScrH")
bring("LocalPlayer") bring("IsValid") bring("IsColor")
bring("CurTime") bring("RealTime") bring("FrameTime") bring("FrameNumber")
bring("input") bring("RunConsoleCommand") bring("gui")
bring("list") bring("weapons") bring("killicon") bring("language")
bring("scripted_ents") bring("player_manager")
bring("pairs") bring("ipairs") bring("pcall") bring("tostring") bring("tonumber")
bring("isnumber") bring("isstring") bring("istable") bring("isfunction")
bring("math") bring("string") bring("table")
bring("MOUSE_LEFT") bring("MOUSE_RIGHT") bring("MOUSE_MIDDLE")
bring("KEY_ESCAPE")

if not math.pow then math.pow = function(b, e) return b ^ e end end
if not math.Clamp then
    math.Clamp = function(v, lo, hi)
        if v < lo then return lo elseif v > hi then return hi end
        return v
    end
end

dbg("engine globals bridged")

-- ---------------- 3. TEXTURES ----------------
-- Reuse MCHUD's already-installed texture pack (mc_hud/widgets.png).
-- widgets.png holds the MC slot / button sprites. If MCHUD is
-- installed, these files already exist -- we don't download anything.
local MAT_WIDGETS = Material("mc_hud/widgets.png", "noclamp")
local MAT_ICONS   = Material("mc_hud/icons.png",   "noclamp")

local function mat_ok(m)
    if not m then return false end
    local ok, err = pcall(function() return m:IsError() end)
    if not ok then return false end
    return not err
end
if not mat_ok(MAT_WIDGETS) then
    lje.con_print("[MCSPAWN] WARN: mc_hud/widgets.png not found - "
        .. "install MCHUD's texture pack. Falling back to flat slots.")
end

-- ---------------- 4. SPRITE HELPER ----------------
-- Identical UV math to MCHUD's Spr() so sampling lines up perfectly.
local function Spr(mat, sx, sy, sw, sh, dx, dy, dw, dh, sz)
    if not mat then return end
    sz = sz or 256
    local du = 0.5 / sz
    local dv = 0.5 / sz
    local u0 = (sx / sz - du) / (1 - 2 * du)
    local v0 = (sy / sz - dv) / (1 - 2 * dv)
    local u1 = ((sx + sw) / sz - du) / (1 - 2 * du)
    local v1 = ((sy + sh) / sz - dv) / (1 - 2 * dv)
    surface.SetMaterial(mat)
    surface.SetDrawColor(255, 255, 255, 255)
    surface.DrawTexturedRectUV(
        math.floor(dx), math.floor(dy),
        math.floor(dw), math.floor(dh),
        u0, v0, u1, v1)
end

-- ---------------- 5. TEXT HELPERS (gilbhax-style, LJE-safe) ----------------
local function DrawText(txt, font, x, y, color, ax, ay)
    if not txt or txt == "" then return end
    surface.SetFont(font)
    local tw, th = surface.GetTextSize(txt)
    local px, py = x, y
    if ax == 1 then px = x - tw / 2 elseif ax == 2 then px = x - tw end
    if ay == 1 then py = y - th / 2 elseif ay == 2 then py = y - th end
    surface.SetTextPos(math.floor(px), math.floor(py))
    if color then
        surface.SetTextColor(color.r or 255, color.g or 255, color.b or 255, color.a or 255)
    else
        surface.SetTextColor(255, 255, 255, 255)
    end
    surface.DrawText(txt)
end

local function DrawTextShadow(txt, font, x, y, col, ax, ay)
    DrawText(txt, font, x + 2, y + 2, Color(0, 0, 0, (col and col.a) or 200), ax, ay)
    DrawText(txt, font, x, y, col, ax, ay)
end

-- ---------------- 6. WEAPON ICON RESOLUTION ----------------
-- Lifted from MCHUD: try several material paths to find a nice icon
-- for each weapon class, with a text fallback.
local iconCache = {}
local defaultTexID = nil

local function ResolveIcon(cls)
    if iconCache[cls] ~= nil then return iconCache[cls] end

    if defaultTexID == nil and surface.GetTextureID then
        defaultTexID = surface.GetTextureID("weapons/swep")
    end

    local stored = weapons and weapons.GetStored and weapons.GetStored(cls) or nil

    -- 1) explicit icon material paths
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
                return iconCache[cls]
            end
        end
    end

    -- 2) killicon
    if killicon and killicon.Exists and killicon.Exists(cls) then
        iconCache[cls] = { t = "kill", v = cls }
        return iconCache[cls]
    end

    -- 3) nothing found -> text
    iconCache[cls] = false
    return false
end

local function DrawWeaponIcon(cls, x, y, w, h)
    local c = ResolveIcon(cls)
    if not c then
        -- short text fallback (class name minus weapon_ prefix)
        local short = string.gsub(cls, "^weapon_", "")
        short = string.sub(short, 1, 4)
        DrawText(short, "DermaDefault", x + w / 2, y + h / 2,
            Color(230, 230, 230, 180), 1, 1)
        return
    end
    if c.t == "mat" then
        surface.SetMaterial(c.v)
        surface.SetDrawColor(255, 255, 255, 255)
        surface.DrawTexturedRect(x, y, w, h)
    elseif c.t == "kill" then
        local iw, ih = killicon.GetSize(c.v)
        if iw and ih and iw > 0 then
            local scale = math.min(w / iw, h / ih) * 0.85
            local rw, rh = iw * scale, ih * scale
            killicon.Render(
                math.floor(x + (w - rw) / 2),
                math.floor(y + (h - rh) / 2), c.v, 230)
        end
    end
end

-- ---------------- 7. BUILD THE ITEM LIST ----------------
-- v1.1: this is the part that was broken before. The old code only read
-- list.Get("Weapon") and filtered hard on Spawnable. In the LJE sandbox
-- list.Get often returns nil, so the menu was empty.
--
-- Now we:
--   * try several ways to read each registry (Get / GetForEdit)
--   * read FOUR categories: Weapon / Entity (SENT) / NPC / Vehicle
--   * fall back to weapons.GetList() for weapons if the list table fails
--   * relax filtering (keep entries unless explicitly AdminOnly)
--
-- Each category is its own array so we can show MC-style tabs.

-- categories: id used for spawn cmd routing + tab label
local CATS = {
    { id = "weapon",  label = "Weapons", cmd = "gm_giveswep"   },
    { id = "entity",  label = "Entities", cmd = "gm_spawnsent" },
    { id = "npc",     label = "NPCs",     cmd = "gmod_spawnnpc"},
    { id = "vehicle", label = "Vehicles", cmd = "gm_spawnvehicle"},
}
local catItems = { weapon = {}, entity = {}, npc = {}, vehicle = {} }
local activeCat = "weapon"
local itemsBuilt = false

-- Read a list.* registry table by name, trying every API LJE might expose.
local function readList(name)
    if not list then return nil end
    -- list.Get returns a copy in newer GMod; GetForEdit the live table
    if list.Get then
        local ok, t = pcall(list.Get, name)
        if ok and istable(t) and next(t) ~= nil then return t end
    end
    if list.GetForEdit then
        local ok, t = pcall(list.GetForEdit, name)
        if ok and istable(t) and next(t) ~= nil then return t end
    end
    return nil
end

local function phrase(pname, class)
    if not pname or pname == "" then return class end
    if string.sub(pname, 1, 1) == "#" and language and language.GetPhrase then
        return language.GetPhrase(pname)
    end
    return pname
end

-- Generic harvester: walk a registry, push {class,name} into dest.
-- keyIsClass = true means the table KEY is the class name (Weapon/NPC list),
-- otherwise we look at t.ClassName / t.Class fields.
local function harvest(reg, dest, keyIsClass)
    if not istable(reg) then return 0 end
    local n = 0
    for k, t in pairs(reg) do
        if istable(t) then
            -- skip explicit admin-only stuff (we can't spawn it anyway on most servers)
            if not t.AdminOnly then
                local class = keyIsClass and k or (t.ClassName or t.Class or k)
                local name  = phrase(t.PrintName or t.Name or t.Title, tostring(class))
                if class and class ~= "" then
                    table.insert(dest, { class = tostring(class), name = name })
                    n = n + 1
                end
            end
        elseif isstring(t) then
            -- some lists map class -> printname string
            table.insert(dest, { class = tostring(k), name = tostring(t) })
            n = n + 1
        end
    end
    return n
end

local function sortCat(arr)
    table.sort(arr, function(a, b)
        return string.lower(a.name) < string.lower(b.name)
    end)
end

local function BuildItems()
    catItems = { weapon = {}, entity = {}, npc = {}, vehicle = {} }

    -- WEAPONS ----------------------------------------------------------
    local wreg = readList("Weapon")
    local wn = harvest(wreg, catItems.weapon, true)
    -- fallback: weapons.GetList() returns an array of swep tables
    if wn == 0 and weapons and weapons.GetList then
        local ok, all = pcall(weapons.GetList)
        if ok and istable(all) then
            for _, sw in pairs(all) do
                if istable(sw) and not sw.AdminOnly then
                    local class = sw.ClassName or sw.Classname
                    if class then
                        table.insert(catItems.weapon,
                            { class = class, name = phrase(sw.PrintName, class) })
                        wn = wn + 1
                    end
                end
            end
        end
    end

    -- ENTITIES (SENTs) -------------------------------------------------
    local en = harvest(readList("SpawnableEntities"), catItems.entity, true)

    -- NPCs -------------------------------------------------------------
    local nn = harvest(readList("NPC"), catItems.npc, true)

    -- VEHICLES ---------------------------------------------------------
    local vn = harvest(readList("Vehicles"), catItems.vehicle, true)

    sortCat(catItems.weapon)
    sortCat(catItems.entity)
    sortCat(catItems.npc)
    sortCat(catItems.vehicle)

    itemsBuilt = (wn + en + nn + vn) > 0
    dbg("built lists -> weapons:", wn, "entities:", en, "npcs:", nn, "vehicles:", vn)
    if not itemsBuilt then
        dbg("ALL LISTS EMPTY - list.* table likely not bridged in LJE")
    end
end

-- helper used by the rest of the file
local function curItems() return catItems[activeCat] or {} end
local function curCmd()
    for _, c in ipairs(CATS) do if c.id == activeCat then return c.cmd end end
    return "gm_giveswep"
end

-- ---------------- 8. MENU STATE ----------------
local menuOpen      = false
local cursorShown   = false
local page          = 0
local clickLock     = 0       -- debounce so one click = one give
local hoverIndex    = -1

local function PerPage() return COLS * ROWS end
local function TotalPages()
    return math.max(1, math.ceil(#curItems() / PerPage()))
end

local function SetCursor(state)
    if state == cursorShown then return end
    if gui and gui.EnableScreenClicker then
        pcall(gui.EnableScreenClicker, state)
        cursorShown = state
    end
end

local function OpenMenu()
    if not itemsBuilt then BuildItems() end
    menuOpen = true
    page = 0
    SetCursor(true)
    dbg("menu opened")
end

local function CloseMenu()
    menuOpen = false
    SetCursor(false)
    clickLock = 0
    dbg("menu closed")
end

local function ToggleMenu()
    if menuOpen then CloseMenu() else OpenMenu() end
end

-- ---------------- 9. INPUT: GRAB Q ----------------
-- hook.pre fires before DLib, same as MCHUD. We grab the open-bind key
-- and toggle our menu instead of letting +menu open the stock one.
local function BindHandler(ply, bind, pressed)
    if not pressed then return end
    local lp = LocalPlayer()
    if not IsValid(lp) then return end

    if bind == OPEN_BIND then
        ToggleMenu()
        return true   -- suppress stock spawn menu
    end

    -- While our menu is open, swallow movement-ish binds so the player
    -- doesn't run around behind the menu. (Optional; comment out if you
    -- want to keep moving.)
    if menuOpen and (string.find(bind, "+forward") or string.find(bind, "+back")
        or string.find(bind, "+attack")) then
        return true
    end
end

if hook and hook.pre then
    hook.pre("PlayerBindPress", "MCSPAWN_Bind", BindHandler)
    dbg("bind hook attached via hook.pre")
else
    hAdd("PlayerBindPress", "MCSPAWN_Bind", BindHandler)
    dbg("bind hook attached via native hook.Add")
end

-- ---------------- 10. THINK (esc to close, list refresh) ----------------
hAdd("Think", "MCSPAWN_Think", function()
    -- Rebuild item list once shortly after load (weapons register late)
    if not itemsBuilt then BuildItems() end

    if menuOpen then
        -- Close on ESC
        if input and input.IsKeyDown and KEY_ESCAPE
            and input.IsKeyDown(KEY_ESCAPE) then
            CloseMenu()
        end
    end
end)

-- ---------------- 11. DRAW THE MENU ----------------
local function DoDraw()
    if not menuOpen then return end
    local lp = LocalPlayer()
    if not IsValid(lp) then return end

    local sw, sh = ScrW(), ScrH()
    local slot   = SLOT_SRC * SLOT_SCALE          -- pixel size of a slot
    local pad    = math.floor(SLOT_SCALE * 2)     -- gap inside the panel
    local gridW  = COLS * slot
    local gridH  = ROWS * slot
    local panelPadX = math.floor(SLOT_SCALE * 8)
    local panelPadTop = math.floor(SLOT_SCALE * 18)   -- room for title
    local panelPadBot = math.floor(SLOT_SCALE * 10)
    local panelW = gridW + panelPadX * 2
    local panelH = gridH + panelPadTop + panelPadBot
    local px = math.floor((sw - panelW) / 2)
    local py = math.floor((sh - panelH) / 2)

    -- darken the world behind (MC pause/inv style ~ alpha 130)
    surface.SetDrawColor(0, 0, 0, 150)
    surface.DrawRect(0, 0, sw, sh)

    -- panel background: MC inventory parchment grey (#C6C6C6) with
    -- a darker bevel border, drawn with primitives (no texture needed)
    surface.SetDrawColor(40, 40, 40, 245)               -- outer border
    surface.DrawRect(px - 3, py - 3, panelW + 6, panelH + 6)
    surface.SetDrawColor(198, 198, 198, 255)            -- panel face
    surface.DrawRect(px, py, panelW, panelH)
    -- top + left highlight bevel
    surface.SetDrawColor(255, 255, 255, 255)
    surface.DrawRect(px, py, panelW, 2)
    surface.DrawRect(px, py, 2, panelH)
    -- bottom + right shadow bevel
    surface.SetDrawColor(85, 85, 85, 255)
    surface.DrawRect(px, py + panelH - 2, panelW, 2)
    surface.DrawRect(px + panelW - 2, py, 2, panelH)

    -- title
    DrawTextShadow("Creative Inventory", "DermaLarge",
        px + panelPadX, py + math.floor(SLOT_SCALE * 5),
        Color(64, 64, 64, 255), 0, 0)

    -- page indicator (top-right of panel)
    local totalPages = TotalPages()
    DrawText("[" .. (page + 1) .. "/" .. totalPages .. "]  scroll to flip",
        "DermaDefaultBold",
        px + panelW - panelPadX, py + math.floor(SLOT_SCALE * 8),
        Color(64, 64, 64, 230), 2, 0)

    -- mouse position
    local mx = (gui and gui.MouseX and gui.MouseX()) or 0
    local my = (gui and gui.MouseY and gui.MouseY()) or 0
    hoverIndex = -1

    -- ---- category tabs (MC creative-inventory style, across the top) ----
    -- Drawn as little buttons just under the title; click to switch.
    local tabY = py - math.floor(SLOT_SCALE * 12)
    local tabH = math.floor(SLOT_SCALE * 12)
    local tabW = math.floor(panelW / #CATS)
    local clickedTab = nil
    for i, c in ipairs(CATS) do
        local tx = px + (i - 1) * tabW
        local isActive = (c.id == activeCat)
        local hov = (mx >= tx and mx <= tx + tabW and my >= tabY and my <= tabY + tabH)
        -- tab face
        surface.SetDrawColor(isActive and 198 or 150, isActive and 198 or 150,
            isActive and 198 or 150, 255)
        surface.DrawRect(tx, tabY, tabW - 2, tabH)
        surface.SetDrawColor(255, 255, 255, isActive and 255 or 120)
        surface.DrawRect(tx, tabY, tabW - 2, 2)            -- top highlight
        local n = #(catItems[c.id] or {})
        DrawText(c.label .. " (" .. n .. ")", "DermaDefaultBold",
            tx + (tabW - 2) / 2, tabY + tabH / 2,
            Color(40, 40, 40, isActive and 255 or 200), 1, 1)
        if hov then clickedTab = c.id end
    end

    local gridX = px + panelPadX
    local gridY = py + panelPadTop

    local list_now = curItems()
    local startIdx = page * PerPage()
    for r = 0, ROWS - 1 do
        for c = 0, COLS - 1 do
            local cellX = gridX + c * slot
            local cellY = gridY + r * slot
            local idx = startIdx + r * COLS + c + 1   -- 1-based
            local data = list_now[idx]

            -- slot background (sunken MC cell): dark border + grey fill
            surface.SetDrawColor(139, 139, 139, 255)
            surface.DrawRect(cellX, cellY, slot, slot)
            surface.SetDrawColor(55, 55, 55, 255)            -- top/left shadow
            surface.DrawRect(cellX, cellY, slot, 2)
            surface.DrawRect(cellX, cellY, 2, slot)
            surface.SetDrawColor(255, 255, 255, 90)          -- bottom/right light
            surface.DrawRect(cellX, cellY + slot - 2, slot, 2)
            surface.DrawRect(cellX + slot - 2, cellY, 2, slot)

            if data then
                -- icon, inset a couple px
                local inset = math.floor(SLOT_SCALE * 1.5)
                DrawWeaponIcon(data.class,
                    cellX + inset, cellY + inset,
                    slot - inset * 2, slot - inset * 2)

                -- hover highlight (MC white 0x80FFFFFF overlay)
                if mx >= cellX and mx <= cellX + slot
                    and my >= cellY and my <= cellY + slot then
                    hoverIndex = idx
                    surface.SetDrawColor(255, 255, 255, 110)
                    surface.DrawRect(cellX + 2, cellY + 2, slot - 4, slot - 4)
                end
            end
        end
    end

    -- empty-state message so a blank grid is never a mystery
    if #list_now == 0 then
        DrawText("(this category is empty - see LJE console for [MCSPAWN] counts)",
            "DermaDefaultBold",
            px + panelW / 2, gridY + gridH / 2,
            Color(90, 30, 30, 230), 1, 1)
    end

    -- tooltip for hovered item (MC style: name in a small dark box)
    if hoverIndex > 0 and list_now[hoverIndex] then
        local label = list_now[hoverIndex].name
        surface.SetFont("DermaDefaultBold")
        local tw, th = surface.GetTextSize(label)
        local boxX, boxY = mx + 14, my + 14
        surface.SetDrawColor(16, 0, 16, 240)
        surface.DrawRect(boxX - 4, boxY - 4, tw + 8, th + 8)
        surface.SetDrawColor(80, 0, 120, 255)
        surface.DrawRect(boxX - 4, boxY - 4, tw + 8, 1)
        surface.DrawRect(boxX - 4, boxY + th + 3, tw + 8, 1)
        DrawText(label, "DermaDefaultBold", boxX, boxY,
            Color(255, 255, 255, 255), 0, 0)
    end

    -- hint line at bottom
    DrawText("Click a slot to get the weapon  -  Q or ESC to close",
        "DermaDefaultBold",
        px + panelW / 2, py + panelH - math.floor(SLOT_SCALE * 5),
        Color(70, 70, 70, 230), 1, 1)

    -- ---- click handling (debounced, like MCHUD death screen) ----
    local mouseDown = input and input.IsMouseDown
        and input.IsMouseDown(MOUSE_LEFT) or false

    if mouseDown and clickLock == 0 then
        clickLock = 1
        if clickedTab then
            -- switch category, reset to first page
            activeCat = clickedTab
            page = 0
            dbg("switched category ->", activeCat)
        elseif hoverIndex > 0 and list_now[hoverIndex] then
            local cls = list_now[hoverIndex].class
            local cmd = curCmd()
            if RunConsoleCommand then
                pcall(RunConsoleCommand, cmd, cls)
            end
            dbg("spawn:", cmd, cls)
        end
    elseif not mouseDown and clickLock == 1 then
        clickLock = 0
    end
end

-- ---------------- 12. MOUSE WHEEL: FLIP PAGES ----------------
local lastWheel = 0
local function ScrollHandler(cmd)
    if not menuOpen then return end
    local wheel = cmd:GetMouseWheel()
    if wheel == 0 then return end
    if CurTime() - lastWheel < 0.05 then return end
    lastWheel = CurTime()
    local tp = TotalPages()
    if wheel > 0 then
        page = (page - 1 + tp) % tp
    else
        page = (page + 1) % tp
    end
end

if hook and hook.pre then
    hook.pre("InputMouseApply", "MCSPAWN_Scroll", function(cmd, x, y, ang)
        ScrollHandler(cmd)
    end)
else
    hAdd("InputMouseApply", "MCSPAWN_Scroll", function(cmd, x, y, ang)
        ScrollHandler(cmd)
    end)
end

-- ---------------- 13. ATTACH RENDER (dual-path, MCHUD-style) ----------------
local last_drawn_frame = -1
local function frame_id()
    if FrameNumber then return FrameNumber() end
    return math.floor(CurTime() * 1000)
end
local function GuardedDraw(path)
    local f = frame_id()
    if f == last_drawn_frame then return end
    last_drawn_frame = f
    local ok, err = pcall(DoDraw)
    if not ok then
        lje.con_print("[MCSPAWN] draw error in " .. path .. ": " .. tostring(err))
    end
end

if hook and hook.pre then
    hook.pre("ljeutil/render", "MCSPAWN_Render", function()
        GuardedDraw("ljeutil/render")
    end)
end
hAdd("HUDPaint", "MCSPAWN_RenderBackup", function()
    GuardedDraw("HUDPaint")
end)

-- ---------------- 14. DONE ----------------
lje.con_print("[MCSPAWN] v1.0 loaded - press Q for the Minecraft creative menu")
if DEBUG then
    lje.con_print("[MCSPAWN] DEBUG is ON - set DEBUG=false before sharing")
end
