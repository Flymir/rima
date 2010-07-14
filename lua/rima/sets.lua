-- Copyright (c) 2009-2010 Incremental IP Limited
-- see LICENSE for license information

local error, type = error, type

local object = require("rima.lib.object")
local proxy = require("rima.lib.proxy")
local lib = require("rima.lib")
local core = require("rima.core")
local iterator = require("rima.sets.iterator")
local set_ref = require("rima.sets.ref")
local expression = require("rima.expression")
local rima = rima

module(...)


-- Ord -------------------------------------------------------------------------

ord = object:new({}, "ord")


function ord.__eval(args, S, eval)
  args = proxy.O(args)
  local e = eval(args[1], S)
  if iterator:isa(e) then
    return iterator.key(e)
  else
    if core.defined(e) then
      error("ord can only be applied to iterators")
    else
      return expression:new(ord, e)
    end
  end
end


function rima.ord(e)
  return expression:new(ord, e)
end


-- Ranges ----------------------------------------------------------------------

local range_type = object:new({}, "range_type")
function range_type:new(l, h)
  return object.new(self, { low = l, high = h} )
end


function range_type:__repr(format)
  return ("range(%s, %s)"):format(lib.repr(self.low, format), lib.repr(self.high, format))
end
range_type.__tostring = lib.__tostring


local function range_type_iter(high, i)
  i = i + 1
  if i <= high then return i end
end

function range_type:__iterate()
  -- Cast self.high to a number by adding zero
  return range_type_iter, self.high+0, self.low-1
end


local range_op = object:new({}, "range")
function range_op.__eval(args, S, eval)
  args = proxy.O(args)
  local l, h = eval(args[1], S), eval(args[2], S)
  if core.defined(l) and core.defined(h) then
    return range_type:new(l, h)
  else
    return expression:new(range_op, l, h)
  end
end


function rima.range(l, h)
  return expression:new(range_op, l, h)
end


-- Top-level sequences ---------------------------------------------------------

function rima.pairs(exp)
  return set_ref:new(exp, "", "pairs")
end


function rima.ipairs(exp)
  return set_ref:new(exp, "i", "pairs")
end


-- EOF -------------------------------------------------------------------------

