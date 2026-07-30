--- Used to filter Entities with specific Components
--- A Filter has an associated Pool that can contain any amount of Entities.

local PATH = (...):gsub('%.[^%.]+$', '')

local List       = require(PATH..".list")
local Type       = require(PATH..".type")
local Utils      = require(PATH..".utils")
local Components = require(PATH..".components")


---@class Filter
---@field pool List<Entity>
---@field private __filter table
---@field private __name string?
---@field private __isFilter boolean
local Filter = {}
Filter.__mt = {
   __index = Filter,
}

--- Validates a Filter Definition to make sure every component is valid.
---@param errorLevel number Error level offset for the error message
---@param name? string Name for the Filter.
---@param def table Table containing the Filter Definition
---@param onComponent? function Optional function, called when a component is valid.
function Filter.validate(errorLevel, name, def, onComponent)
   local filter = "World:query filter"
   if name then
      filter = ("filter '%s'"):format(name)
   end

   if type(def) ~= 'table' then
      Utils.error(3 + errorLevel, "invalid component list for %s (table expected, got %s)", filter, type(def))
   end

   if not onComponent and def.constructor and not Type.isCallable(def.constructor) then
      Utils.error(3 + errorLevel, "invalid pool constructor for %s (callable expected, got %s)", filter, type(def.constructor))
   end

   for n, component in ipairs(def) do
      local ok, err, reject = Components.try(component, true)

      if not ok then
         Utils.error(3 + errorLevel, "invalid component for %s at position #%d (%s)", filter, n, err)
      end

      if onComponent then
         onComponent(component, reject)
      end
   end
end

--- Parses the Filter Definition into an array.
--- required: An array of all the required component names.
--- rejected: An array of all the components that will be rejected.
---@param name? string Name for the Filter.
---@param def table Table containing the Filter Definition
---@return table filter Parsed filter logic array
function Filter.parse(name, def)
   local filter = {}

   Filter.validate(1, name, def, function (component, reject)
      if reject then
         table.insert(filter, reject)
         table.insert(filter, false)
      else
         table.insert(filter, component)
         table.insert(filter, true)
      end
   end)

   return filter
end

--- Matches an entity against a parsed filter.
---@param e Entity The entity to check
---@param filter table The parsed filter table
---@return boolean matched
function Filter.match(e, filter)
   for i=#filter, 2, -2 do
      local match = filter[i - 0]
      local name  = filter[i - 1]

      if (not e[name]) == match then return false end
   end

   return true
end

local REQUIRED_METHODS = {"add", "remove", "has", "clear"}
local VALID_POOL_TYPES = {table=true, userdata=true, lightuserdata=true, cdata=true}

--- Checks if a custom pool is valid.
---@param name? string Name of the pool/filter
---@param pool table|userdata The pool to check
function Filter.isValidPool(name, pool)
   local poolType = type(pool)
   --Check that pool is not nil
   if not VALID_POOL_TYPES[poolType] then
      Utils.error(3, "invalid value returned by pool '%s' constructor (table expected, got %s).", name, type(pool))
   end

   --Check if methods are callables
   for _, method in ipairs(REQUIRED_METHODS) do
      if not Type.isCallable(pool[method]) then
         Utils.error(3, "invalid :%s method on pool '%s' (callable expected, got %s).", method, name, type(pool[method]))
      end
   end
end

--- Creates a new Filter
---@param name? string Name for the Filter.
---@param def table Table containing the Filter Definition
---@return Filter filter The new Filter
---@return table|List pool The associated Pool
function Filter.new(name, def)
   local pool

   if def.constructor then
      pool = def.constructor(def)
      Filter.isValidPool(name, pool)
   else
      pool = List()
   end

   local parsedFilter = Filter.parse(name, def)

   ---@type Filter
   local filter = setmetatable({
      pool = pool,

      __filter = parsedFilter,
      __name   = name,

      __isFilter = true,
   }, Filter.__mt)

   return filter, pool
end

--- Checks if an Entity fulfills the Filter requirements.
---@param e Entity Entity to check
---@return boolean eligible
function Filter:eligible(e)
   return Filter.match(e, self.__filter)
end

--- Evaluates an entity against the filter and updates the pool.
---@param e Entity
---@return Filter self
function Filter:evaluate(e)
   local has  = self.pool:has(e)
   local eligible = self:eligible(e)

   if not has and eligible then
      self.pool:add(e)
   elseif has and not eligible then
      self.pool:remove(e)
   end

   return self
end

--- Adds an Entity to the Pool, if it passes the Filter.
---@param e Entity Entity to add
---@param bypass? boolean Whether to bypass the Filter or not.
---@return Filter self
---@return boolean added Whether the entity was added or not.
function Filter:add(e, bypass)
   if not bypass and not self:eligible(e) then
      return self, false
   end

   self.pool:add(e)

   return self, true
end

--- Remove an Entity from the Pool associated to this Filter.
---@param e Entity Entity to remove
---@return Filter self
function Filter:remove(e)
   self.pool:remove(e)
   return self
end

--- Clear the Pool associated to this Filter.
---@return Filter self
function Filter:clear()
   self.pool:clear()
   return self
end

--- Check if the Pool bound to this System contains the passed Entity
---@param e Entity Entity to check
---@return boolean has Whether the Entity exists.
function Filter:has(e)
   return self.pool:has(e)
end

--- Gets the name of the Filter
---@return string? name
function Filter:getName()
   return self.__name
end

return setmetatable(Filter, {
  __call  = function(_, ...)
     return Filter.new(...)
  end,
})
