-- Copyright (c) 2009-2012 Incremental IP Limited
-- see LICENSE for license information

local object = require("rima.lib.object")
local proxy = require("rima.lib.proxy")
local lib = require("rima.lib")
local core = require("rima.core")
local mul = require("rima.operators.mul")
local expression = require("rima.expression")
local opmath = require("rima.operators.math")
local ops = require("rima.operations")


------------------------------------------------------------------------------

local pow = expression:new_type({}, "pow")
pow.precedence = 0


------------------------------------------------------------------------------

function pow:__repr(format)
  local terms = proxy.O(self)
  local base, exponent = terms[1], terms[2]
  local repr = lib.repr
  local paren = core.parenthise
  local prec = pow.precedence

  local ff = format.format
  if ff == "dump" then
    return "^("..repr(base, format)..", "..repr(exponent, format)..")"
  elseif ff == "latex" then
    return "{"..paren(base, format, prec).."}^{"..repr(exponent, format).."}"
  else
    return paren(base, format, prec).."^"..paren(exponent, format, prec)
  end
end


------------------------------------------------------------------------------

function pow:simplify()
  local terms = proxy.O(self)
  local base, exponent = terms[1], terms[2]

  if base == 0 then
    return 0
  elseif base == 1 or exponent == 0 then
    return 1
  elseif exponent == 1 then
    return base
  elseif type(exponent) == "number" then
    return expression:new(mul, {exponent, base})
  else
    return self
  end
end


function pow:__eval(...)
  local terms = proxy.O(self)
  local t1, t2 = terms[1], terms[2]
  local base, exponent = core.eval(t1, ...), core.eval(t2, ...)
  if base == t1 and exponent == t2 then
    return self
  else
    return base ^ exponent
  end
end


------------------------------------------------------------------------------

function pow.__diff(args, v)
  args = proxy.O(args)
  local base, exponent = args[1], args[2]

  local base_is_number = type(base) == "number"

  if type(exponent) == "number" then
    if base_is_number then return 0 end
    return core.eval(ops.mul(exponent, core.diff(base, v), ops.pow(base, exponent - 1)))
  end

  if base_is_number then
    return core.eval(ops.mul(core.diff(exponent, v), math.log(base), ops.pow(base, exponent)))
  end
  
  return core.eval(ops.mul(core.diff(ops.mul(exponent, opmath.log(base)), v), ops.pow(base, exponent)))
end


------------------------------------------------------------------------------

return pow

------------------------------------------------------------------------------

