local a_name, a_env = ...
local devel_db = _G['SR13-+DEVEL']

a_env.a_name = a_name

local function GetLoadDevel(addon_name)
   local val = devel_db
   if val then val = val[addon_name] end
   if val then val = val.load_devel end
   return not not val
end

local is_devel, _, a_basename = a_name:find('^(.+)-devel$')
is_devel = not not is_devel
a_env.a_basename = a_basename or a_name
local load_devel = GetLoadDevel(a_env.a_basename)
a_env.is_devel = is_devel
a_env.load_devel = load_devel

local load_another_addon
if is_devel == load_devel then
   a_env.load_this = true
else
   load_another_addon = is_devel and (a_basename) or (a_name .. '-devel')
end

a_env.load_another_addon = load_another_addon

if devel_db and devel_db.print_debug then devel_db.print_debug(a_env) end

if load_another_addon then LoadAddOn(load_another_addon) end
