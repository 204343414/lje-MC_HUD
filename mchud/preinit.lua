-- ================================================================
--   mchud/preinit.lua
--
--   Runs BEFORE GMod's init.lua. GMod Lua API is NOT available here.
--   We can ONLY use:
--     · pure Lua (math, string, table)
--     · lje.* APIs
--
--   Job of this file:
--     1. Stash a reference to the ORIGINAL hook table (before DLib
--        or any other mod gets a chance to overwrite it). We use
--        this in main.lua to bypass DLib's wrapper hook.Add and
--        register our hooks straight on the engine table.
--     2. Print a banner so you know preinit ran.
--
--   We DO NOT do any actual hook registration here, because the
--   hook table itself doesn't exist yet at preinit time. We just
--   set up a tiny "todo list" that main.lua executes once it's
--   safe.
-- ================================================================

lje.con_print("[MCHUD preinit] starting")

-- A shared bag we'll attach things to. Read in main.lua.
-- We stash it in _G so main.lua can find it; this is fine because
-- preinit's _G is the safe environment shared with main.
_G.MCHUD_BOOT = _G.MCHUD_BOOT or {}

-- We can't grab the GMod 'hook' table here yet (engine isn't up).
-- Instead we leave a flag for main.lua to do the grab as the very
-- first thing, before anything inside main runs that could trigger
-- DLib re-wrapping.
_G.MCHUD_BOOT.want_native_hook = true

lje.con_print("[MCHUD preinit] done")
