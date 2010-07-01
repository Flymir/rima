-- Copyright (c) 2009-2010 Incremental IP Limited
-- see LICENSE for license information

local error = error
local ipairs, pairs = ipairs, pairs
local require, rawtype, tostring, unpack = require, type, tostring, unpack
local getmetatable, setmetatable = getmetatable, setmetatable
local rawget, rawset = rawget, rawset

local object = require("rima.lib.object")
local proxy = require("rima.lib.proxy")
local lib = require("rima.lib")
local core = require("rima.core")
local rima = rima

module(...)

local operators = require("rima.operators")

-- Constructor -----------------------------------------------------------------

local expression = object:new(_M, "expression")
expression.proxy_mt = setmetatable({}, expression)


function expression:new(x, ...)
  local e = {...}
  if x and rawget(x, "construct") then e = x.construct(e) end
  for k, v in pairs(self.proxy_mt) do if not(rawget(x, k)) then rawset(x, k, v) end end
--  e:check()
  return proxy:new(object.new(self, e), x)
end

function expression:new_table(x, t)
  local e
  if x and rawget(x, "construct") then
    e = x.construct(t)
  else
    e = {}
    for i, a in ipairs(t) do e[i] = a end
  end

  for k, v in pairs(self.proxy_mt) do if not(rawget(x, k)) then rawset(x, k, v) end end
--  e:check()
  return proxy:new(object.new(self, e), x)
end


-- Argument Checking -----------------------------------------------------------

--[[
function expression:check()
  local m = rawtype(self.op) == "table" and self.op.check
  if m then
    return m(self.op, self.args)
  else
    return true
  end
end
--]]

-- Result Types ----------------------------------------------------------------

--[[
function expression.result_type_match(a, t)
  local r = result_type(a)
  return r:includes(t) or t:includes(r)
end

function expression.result_type(a)
  if rawtype(a) == "table" then
    local op, args = a.op, a.args
    if op and rawtype(args) == "table" then    -- this is an expression
      local m = rawtype(op) == "table" and op.result_type
      if m then                                 -- the operator can handle itself
        return m(op, args)
      elseif #args == 0 then                    -- looks like a literal
        return type(op) == "number" and rima.free() or types.undefined_t
      else                                      -- some kind of call
        error(("unable to determine the result type of '%s': the operator doesn't take arguments"):format(rima.tostring(a)), 0)
      end
    else                                        -- this is some other object.  Can it handle itself?
      local m = a.result_type
      if m then return m(a) end
    end
  end
  return type(op) == "number" and rima.free() or types.undefined_t
end
--]]


-- String representation -------------------------------------------------------

function expression.proxy_mt.__repr(e, format)
  return object.type(e).."("..lib.concat_repr(proxy.O(e), format)..")"
end
expression.proxy_mt.__tostring = lib.__tostring

function expression.parenthise(e, format, parent_precedence)
  parent_precedence = parent_precedence or 1
  local s = lib.repr(e, format)
  local mt = getmetatable(e)
  local precedence = (mt and rawget(mt, "precedence")) or 0
  if precedence > parent_precedence then
    s = "("..s..")"
  end
  return s
end


-- Evaluation ------------------------------------------------------------------

function expression.bind(e, S)
  if core.trace then core.tracein("bind", e) end

  local mt = getmetatable(e)
  if mt then
    local r
    local E = proxy.O(e)
    local f = rawget(mt, "__bind")
    if f then
      r = { f(E, S) }
    else
      f = rawget(mt, "__eval")
      if f then
        r = { f(E, S, bind) }
      end
    end
    
    if r then
      if core.trace then core.traceout("bind", e, r[1]) end
      return unpack(r)
    end
    
  end
  if core.trace then core.traceout("bind", e, e) end
  return e
end


function expression.set(e, t, v)
  local mt = getmetatable(e)
  local f = mt and rawget(mt, "__set")
  if not f then
    error(("error setting result field '%s' to '%s': the object used as a field index doesn't support setting"):
      format(rima.repr(e), rima.repr(v)))
  end
  f(proxy.O(e), t, v)
end


function expression.type(e, S)
  local mt = getmetatable(e)
  local f = mt and rawget(mt, "__type")
  if not f then
    error(("error getting type information for '%s': the object doesn't support type queries"):
      format(rima.repr(e)))
  end
  return f(proxy.O(e), S)
end


-- Overloaded operators --------------------------------------------------------

function expression.proxy_mt.__add(a, b)
  return expression:new(operators.add, {1, a}, {1, b})
end

function expression.proxy_mt.__sub(a, b)
  return expression:new(operators.add, {1, a}, {-1, b})
end

function expression.proxy_mt.__unm(a)
  return expression:new(operators.add, {-1, a})
end

function expression.proxy_mt.__mul(a, b, c)
  return expression:new(operators.mul, {1, a}, {1, b})
end

function expression.proxy_mt.__div(a, b)
  return expression:new(operators.mul, {1, a}, {-1, b})
end

function expression.proxy_mt.__pow(a, b)
  return expression:new(operators.pow, a, b)
end

function expression.proxy_mt.__call(...)
  return expression:new(operators.call, ...)
end

function expression.proxy_mt.__index(r, i)
  local e = expression:new(operators.index, r, i)
  local f = core.eval(e)
  if not f or (object.type(f) == "table" and not getmetatable(f)) then
    return e
  else
    return f
  end
end


function expression.proxy_mt.__newindex(e, i, v)
  local err
  r = bind(e)
  local R = proxy.O(r)
  if object.type(r) == "ref" then
    if R.scope then
      proxy.O(R.scope).newindex(R.scope, R.name, nil, i, v)
    else
      err = "is not bound to a scope"
    end
  elseif object.type(r) == "index" then
    local r2, address = R[1], R[2]
    if object.type(r2) == "ref" then
      local R2 = proxy.O(r2)
      if R2.scope then
        proxy.O(R2.scope).newindex(R2.scope, R2.name, address, i, v)
      else
        err = "is not bound to a scope"
      end
    else
      err = "isn't an expression that can be set"
    end
  else
    err = "isn't an expression that can be set"
  end
  if err then
    error(("expression new index: error setting '%s' as '%s' to %s: '%s' %s"):
      format(rima.repr(e[i]), rima.repr(r[i]), rima.repr(v), rima.repr(r), err), 0)
  end
end


-- EOF -------------------------------------------------------------------------

