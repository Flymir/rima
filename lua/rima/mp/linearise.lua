-- Copyright (c) 2009-2011 Incremental IP Limited
-- see LICENSE for license information

local error, getmetatable, ipairs, pcall, require, type =
      error, getmetatable, ipairs, pcall, require, type

local object = require("rima.lib.object")
local proxy = require("rima.lib.proxy")
local lib = require("rima.lib")
local core = require("rima.core")
local index = require("rima.index")
local element = require("rima.sets.element")

module(...)

local scope = require("rima.scope")
local operators = require("rima.operators")

-- Getting a linear form -------------------------------------------------------

local function add_variable(terms, ref, coeff)
  local name = lib.repr(ref)
  if terms[name] then
    error(("the reference '%s' appears more than once"):format(name), 0)
  end
  terms[name] = { name=name, ref=ref, coeff=coeff }
end


function _linearise(l, S)

  local constant, terms = 0, {}
  local fail = false

  if type(l) == "number" then
    constant = l
  elseif object.typename(l) == "index" then
    add_variable(terms, l, 1)
  elseif element:isa(l) then
    local exp = element.expression(l)
    add_variable(terms, exp, 1)
  elseif getmetatable(l) == operators.add then
    for i, a in ipairs(proxy.O(l)) do
      a = proxy.O(a)
      local c, x = a[1], a[2]
      if type(x) == "number" then
        if i ~= 1 then
          error(("term %d is constant (%s).  Only the first term should be constant"):
            format(i, lib.repr(x)), 0)
        end
        if constant ~= 0 then
          error(("term %d is constant (%s), and so is an earlier term.  There can only be one constant in the expression"):
            format(i, lib.repr(x)), 0)
        end
        constant = c * x
      elseif object.typename(x) == "index" then
        add_variable(terms, x, c)
      elseif element:isa(x) then
        local exp = element.expression(x)
        add_variable(terms, exp, c)
      else
        error(("term %d is not linear (got '%s', %s)"):format(i, lib.repr(x), object.typename(x)), 0)
      end
    end
  else
    error("the expression does not evaluate to a sum of terms", 0)
  end
  
  return constant, terms
end


function linearise(e, S)
  local l = core.eval(e, S)
  local status, constant, terms = pcall(_linearise, l, S)
  if not status then
    error(("Error linearising '%s' (linear form: '%s'):\n  %s"):format(lib.repr(e), lib.repr(l), constant:gsub("\n", "\n    ")), 0)
  end
  return constant, terms
end


-- EOF -------------------------------------------------------------------------

