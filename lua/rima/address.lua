-- Copyright (c) 2009 Incremental IP Limited
-- see license.txt for license information

local debug = require("debug")
local ipairs, require = ipairs, require
local getmetatable, unpack = getmetatable, unpack
local error, xpcall = error, xpcall

local object = require("rima.object")
local proxy = require("rima.proxy")
local undefined_t = require("rima.types.undefined_t")
local number_t = require("rima.types.number_t")
require("rima.private")
local rima = rima

module(...)

local scope = require("rima.scope")
local expression = require("rima.expression")
local iteration = require("rima.iteration")

--------------------------------------------------------------------------------

local address = object:new(_M, "address")

function address:new(a)
  local a2 = {}
  for i, v in ipairs(a) do
    a2[i] = { exp=v, value=v }
  end
  return object.new(self, a2)
end


-- string representation -------------------------------------------------------

function address:__repr(format)
  if not self[1] then
    return ""
  else
    if format and format.dump then
      return ("address(%s)"):format(rima.concat(self, ", ",
        function(a)
          return rima.repr(a.value, format)
        end))
    else
      local mode = "s"
      local count = 0
      local s = ""
      for _, a in ipairs(self) do
        a = a.value
        if type(a) == "string" and a:match("^[_%a][_%w]*$") then
          if mode ~= "s" then
            mode = "s"
            s = s.."]"
          end
          s = s.."."..rima.repr(a, format)
        else
          if mode ~= "v" then
            mode = "v"
            s = s.."["
            count = 0
          end
          if count > 0 then
            s = s..", "
          end
          count = count + 1
          if type(a) == "string" then
            s = s.."'"..a.."'"
          else
            s = s..rima.repr(a, format)
          end
        end
      end
      if mode == "v" then s = s.."]" end
      return s
    end
  end
end
__tostring = __repr


-- lengthening and shortening --------------------------------------------------

function address.__add(a, b)
  local z = {}
  if object.isa(a, address) then
    for i, a in ipairs(a) do
      z[i] = { exp=a.exp, value=a.value }
    end
  else
    z[1] = { exp=a, value=a }
  end
  if object.isa(b, address) then
    for _, a in ipairs(b) do
      z[#z+1] = { exp=a.exp, value=a.value }
    end
  else
    z[#z+1] = { exp=b, value=b }
  end
  return object.new(address, z)
end


function address:sub(i, j)
  local l = #self
  i = i or 1
  j = j or l
  if i < 0 then i = l + i + 1 end
  if j < 0 then j = l + j + 1 end

  local z = {}
  for k = i, j do
    z[#z+1] = { exp=self[k].exp, value=self[k].value }
  end
  return object.new(address, z)
end


function address:value(i)
  return self[i].value
end


local function avnext(a, i)
  i = i + 1
  local v = a[i]
  if v then
    return i, v.value
  end
end


function address:values()
  return avnext, self, 0
end


-- evaluation ------------------------------------------------------------------

function address:__eval(S, eval)
  local a = {}
  for i, v in ipairs(self) do
    local b = expression.bind(v.exp, S)
    a[i] = { exp=b, value=eval(v.value, S) }
  end
  return object.new(address, a)
end


function address:defined()
  for _, a in ipairs(self) do
    if not expression.defined(a.value) then
      return false
    end
  end
  return true
end


-- resolving -------------------------------------------------------------------

-- resolve an address by working through its indexes recursively
function address:resolve(S, current, i, base, eval)
  local si = self[i]
  if not si then return true, current, base, self end
  local a = si.value
  local b = si.exp

  local function fail()
    error(("address: error resolving '%s%s': '%s%s' is not indexable (got '%s' %s)"):
      format(rima.repr(base), rima.repr(self:sub(1, i)), rima.repr(base), rima.repr(self:sub(1, i-1)), rima.repr(current), object.type(current)))
  end

  local function index(t, j, b)
    if object.isa(j, iteration.element) then
      if t[1] then
        self[i].value = j.index
        return t[j.index]
      else
        self[i].value = j.value
        return t[j.value]
      end
    else
      return t[j]
    end
  end

  -- What do we do when we come across an expression?
  local function handle_expression(c, j)
    local new_base = expression.bind(c, S)
    local new_address = self:sub(j)

    -- if the base is an index, use its base and glue the two addresses together
    if object.type(new_base) == "index" then
      local C = proxy.O(new_base)
      new_base = C[1]
      new_address = C[2] + new_address
    end

    local function try_current(c)
      local status, r = xpcall(function() return { new_address:resolve(S, c, 1, new_base, eval) } end, debug.traceback)
      if not status then
        error(("address: error evaluating '%s%s' as '%s%s':\n  %s"):
          format(rima.repr(base), rima.repr(self), rima.repr(new_base), rima.repr(new_address), r:gsub("\n", "\n  ")), 0)
      end
      return r
    end

    -- If the base is ref, we have to try to resolve the address in all the
    -- scopes that the ref occurs in.  We do it manually.  This is a real mess.
    if object.type(new_base) == "ref" then
      local R = proxy.O(new_base)

      -- Get the list of values for this reference
      local RS = scope.find_bound_scope(S, R.scope, R.name)
      local values = scope.find(RS, R.name, "read")

      -- Give up if there's none or it's hidden
      if not values or values[1][1] == hidden then
        return false, nil, new_base, new_address
      end

      -- Run through the values, seeing if we can find something
      local results = {}
      for k, v in ipairs(values) do

        -- By now we should have bare refs that don't reference other objects.
        -- This should never happen, but I could be wrong.
        if not expression.defined(v[1]) then
          error(("address: internal error evaluating '%s%s' as '%s%s':\n  Got an undefined expression (%s) when I shouldn't"):
            format(rima.repr(base), rima.repr(self), rima.repr(new_base), rima.repr(new_address), rima.repr(v[1])), 0)
        end

        -- try to resolve the address with this version of the ref as a base
        results[#results+1] = try_current(v[1])
        -- and if we find something good, return it
        if results[#results][1] then
          return unpack(results[#results])
        end
      end
      -- We found nothing good, return the first thing we found (I think we
      -- could return any of the results.
      return unpack(results[1])

    else
      -- Otherwise, the new base is not a ref.  I'm not sure this can actually happen --
      -- I'll have to write more tests...
      local new_current = expression.eval(new_base, S)
      if not expression.defined(new_current) then
        return false, nil, new_base, new_address
      end
      return unpack(try_current(new_current))
    end
  end

  -- This is where the function proper starts.
  -- We've got an object (current) and we're trying to index it with a.
  -- How should we treat it?
  local mt = getmetatable(current)

  -- if we've got something that wants to resolve itself, then handle it and continue.
  -- The object might use more than one element of the address.
  if mt and mt.__address then
    -- We only want to bind to the result...
    local status, v, j = xpcall(function() return mt.__address(current, S, self, i, expression.bind) end, debug.traceback)
    if not status then
      error(("address: error evaluating '%s%s' as '%s':\n  %s"):
        format(rima.repr(base), rima.repr(self), rima.repr(current), v:gsub("\n", "\n  ")), 0)
    end
    -- ... and then, if there are no more indexes left, we'll evaluate it.
    -- otherwise we leave it as a ref for the next call to index.
    if not j then v = eval(v, S) end
    return self:resolve(S, v, j, base, eval)

  -- if it's a ref or an expression, evaluate it (and recursively tidy up the remaining indices)
  elseif not expression.defined(current) then
    return handle_expression(current, i)

  -- if we're trying to index what has to be a scalar, give up
  elseif object.isa(current, number_t) then
    fail()

  -- if we're trying to index an undefined type, return it and say we didn't get to the end
  elseif object.isa(current, undefined_t) then
    return false, current, base, self

  -- if it's hidden then stop here
  elseif current == scope.hidden then
    return true, scope.hidden, base, self

  -- handle tables and things we can index just by indexing
  elseif (mt and mt.__index) or type(current) == "table" then
    local next = index(current, a, b)
    local r1
    if next then
      r1 = { self:resolve(S, next, i+1, base, eval) }
      if r1[1] then return unpack(r1) end
    end
    -- including any default values
    next = scope.default(current)
    if next then
      local r2 = { self:resolve(S, next, i+1, base, eval) }
      if r2[1] then return unpack(r2) end
    end
    if r1 then
      return unpack(r1)
    else
      return false, nil, base, self
    end

  -- we can't index something that's not a table
  else
    fail()
  end
end


-- EOF -------------------------------------------------------------------------
