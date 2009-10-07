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


-- string representation -------------------------------------------------------

function address:__repr(format)
  if not self[1] then
    return ""
  else
    if format and format.dump then
      return ("address(%s)"):format(expression.concat(self, format))
    else
      local mode = "s"
      local count = 0
      local s = ""
      for _, a in ipairs(self) do
        if type(a) == "string" then
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
          s = s..rima.repr(a, format)
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
      z[i] = a
    end
  else
    z[1] = a
  end
  if object.isa(b, address) then
    for _, a in ipairs(b) do
      z[#z+1] = a
    end
  else
    z[#z+1] = b
  end
  return address:new(z)
end


function address:sub(i, j)
  local l = #self
  i = i or 1
  j = j or l
  if i < 0 then i = l + i + 1 end
  if j < 0 then j = l + j + 1 end

  local z = {}
  for k = i, j do
    z[#z+1] = self[k]
  end
  return address:new(z)
end


-- evaluation ------------------------------------------------------------------

function address:__eval(S, eval)
  return address:new(rima.imap(function(a) return eval(a, S) end, self))
end


function address:defined()
  for _, a in ipairs(self) do
    if not expression.defined(a) then
      return false
    end
  end
  return true
end


-- resolving -------------------------------------------------------------------

-- resolve an address by working through its indexes recursively
function address:resolve(S, current, i, base, eval)
  local a = self[i]
  if not a then return true, current, base, self end

  local function fail()
    error(("address: error resolving '%s%s': '%s%s' is not indexable (got '%s' %s)"):
      format(rima.repr(base), rima.repr(self:sub(1, i)), rima.repr(base), rima.repr(self:sub(1, i-1)), rima.repr(current), object.type(current)))
  end

  local function index(v, j)
    if object.isa(j, iteration.element) then
      if v[1] then
        self[i] = j.index
        return v[j.index]
      else
        self[i] = j.key
        return v[j.key]
      end
    else
      return v[j]
    end
  end

  local function handle_undefined(c, j)
    local new_base = expression.bind(c, S)
    local new_address = self:sub(j)
    local new_current = expression.eval(new_base, S)
    if not expression.defined(new_current) then
      return false, nil, new_base, new_address
    end

    local k = 1
    -- if it's an index, glue the two addresses together - it looks prettier
    if object.type(new_base) == "index" then
      local C = proxy.O(new_base)
      new_base = C[1]
      new_address = C[2] + new_address
      k = #C[2] + 1
    end
    local status, r = xpcall(function() return { new_address:resolve(S, new_current, k, new_base) } end, debug.traceback)
    if not status then
      error(("address: error evaluating '%s%s' as '%s%s':\n  %s"):
        format(rima.repr(base), rima.repr(self), rima.repr(new_base), rima.repr(new_address), r:gsub("\n", "\n  ")), 0)
    end
    return unpack(r)
  end

  local mt = getmetatable(current)

  -- if we've got something that wants to resolve itself, then handle it and continue
  if mt and mt.__address then
    local status, v, j = xpcall(function() return mt.__address(current, S, self, i, expression.bind) end, debug.traceback)
    if not status then
      error(("address: error evaluating '%s%s' as '%s':\n  %s"):
        format(rima.repr(base), rima.repr(self), rima.repr(current), v:gsub("\n", "\n  ")), 0)
    end
    if not j then v = eval(v, S) end
    return self:resolve(S, v, j, base, eval)

  -- if it's a ref or an expression, evaluate it and continue
  elseif not expression.defined(current) then
    return handle_undefined(current, i)

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
    local next = index(current, a)
    local r1
    if next then
      r1 = { self:resolve(S, next, i+1, base, eval) }
      if r1[1] then return unpack(r1) end
    end
    -- including any default values
    next = current[rima.default]
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
