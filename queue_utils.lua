-- Queue is an array with extra methods and special organization.
-- Generally you .push data into queue and then take it from begining with .shift, making a FIFO structure that preserves order.
-- .unshift (insert as first element) and .pop (take last inserted element) are available too when necessary, but .push/.shift is considered "main" flow.
-- Table additionaly holds current pointer at "first" and "last" data so .shift'ing (and un-shifting) things can be performed fast by simply moving pointer instead of actually moving elements around.
-- It is expected that you routinely empty queue by taking all elements from it, so methods can collapse indices back to beginning of empty array.

local a_name, a_env = ...
if a_env and not a_env.load_this then return end

local export = a_env and a_env.internal_export.queue_utils

local FIRST, LAST = {}, {}

local function queue_init(queue)
   queue[FIRST] = 1
   queue[LAST] = 0

   return queue
end

local function queue_is_empty(queue)
   local last = queue[LAST]
   if last < queue[FIRST] then
      if last ~= 0 then queue_init(queue) end
      return true
   end
end

local function queue_push(queue, element)
   local last = queue[LAST]
   last = last + 1
   queue[last] = element
   queue[LAST] = last
end

local function queue_shift(queue)
   local first = queue[FIRST]
   if first > queue[LAST] then
      queue_init(queue)
      return
   end

   local val = queue[first]
   queue[first] = nil
   first = first + 1
   queue[FIRST] = first

   return val
end

local function queue_shift(queue)
   local first = queue[FIRST]
   if first > queue[LAST] then
      queue_init(queue)
      return
   end

   local val = queue[first]
   queue[first] = nil
   first = first + 1
   queue[FIRST] = first

   return val
end


local function queue_test(queue)
   queue_init(queue)

   queue_push(queue, 10)
   queue_push(queue, 20)
   print(queue_shift(queue), queue_is_empty(queue))
   queue_push(queue, 30)
   queue_push(queue, 40)
   print(queue_shift(queue), queue_is_empty(queue))
   print(queue_shift(queue), queue_is_empty(queue))
   print(queue_shift(queue), queue_is_empty(queue))
   if DevTools_Dump then DevTools_Dump(queue) end
end
-- queue_test({})

export.FIRST          = FIRST
export.LAST           = LAST
export.queue_init     = queue_init
export.queue_is_empty = queue_is_empty
export.queue_push     = queue_push
export.queue_shift    = queue_shift
-- export.queue_test  = queue_test
