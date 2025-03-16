local a_name, a_env  = ...
if not a_env.load_this then return end

local child_frame_cache = {}
a_env.child_frame_cache = child_frame_cache

function a_env.BuildChildFrameCache(getter)
   local meta = {
      __index = function (tbl, key)
         local val = getter(key)
         tbl[key] = val
         return val
      end
   }
   local cache = {}
   return setmetatable(cache, meta)
end
