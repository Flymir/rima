-- Copyright (c) 2009 Incremental IP Limited
-- see license.txt for license information

local ipairs, pairs = ipairs, pairs
local table = require("table")

local series = require("test.series")
local scope = require("rima.scope")
local expression = require("rima.expression")
require("rima.public")
local rima = rima

module(...)

-- Tests -----------------------------------------------------------------------

function test(show_passes)
  local T = series:new(_M, show_passes)


  local a, b, c, d = rima.R"a, b, c, d"
  local S = rima.scope.create{ ["a,b"] = rima.free(), c=rima.types.undefined_t:new() }
  S.d = { rima.free(), rima.free() }
  
  local L = function(e, _S) return rima.linearise(e, _S or S) end
  local LF = function(e, _S) return function() rima.linearise(e, _S or S) end end

  T:expect_ok(LF(a))
  T:expect_ok(LF(1 + a))
  T:expect_error(LF(1 + (3 + a^2)),
    "error while linearising '1 %+ 3 %+ a^2'.-linear form: 4 %+ a^2.-term 2 is not linear %(got 'a^2', pow%)")
  T:expect_error(LF(1 + c),
    "error while linearising '1 %+ c'.-linear form: 1 %+ c.-expecting a number type for 'c', got 'c undefined'")
  T:expect_error(LF(a * b),
    "error while linearising 'a%*b'.-linear form: a%*b.-the expression does not evaluate to a sum of terms")
  T:expect_error(LF(1 + a[2]*5), "'a' is not indexable")
  T:expect_error(LF(1 + c[2]*5), "No type information available for 'c%[2%]'")
  T:expect_ok(LF(1 + d[2]*5), "d[2] is a number")

  local function check_nonlinear(e, S)
    T:expect_error(function() rima.linearise(e, S) end, "error while linearising")
  end

  local function check_linear(e, expected_constant, expected_terms, S)
    local got_constant, got_terms = rima.linearise(e, S)
    for v, c in pairs(got_terms) do got_terms[v] = c.coeff end
    
    local pass = true
    if expected_constant ~= got_constant then
      pass = false
    else
      for k, v in pairs(expected_terms) do
        if got_terms[k] ~= v then
          pass = false
        end
      end
      for k, v in pairs(got_terms) do
        if expected_terms[k] ~= v then
          pass = false
        end
      end      
    end

    if not pass then
      local s = ""
      s = s..("error linearising %s:\n"):format(rima.repr(e))
      s = s..("  Evaluated to %s\n"): format(rima.repr(expression.eval(e, S)))
      s = s..("  Constant: %.4g %s %.4g\n"):format(expected_constant,
        (expected_constant==got_constant and "==") or "~=", got_constant)
      local all = {}
      for k, v in pairs(expected_terms) do all[k] = true end
      for k, v in pairs(got_terms) do all[k] = true end
      local ordered = {}
      for k in pairs(all) do ordered[#ordered+1] = k end
      table.sort(ordered)
      for _, k in ipairs(ordered) do
        local a, b = expected_terms[k], got_terms[k]
        s = s..("  %s: %s %s %s\n"):format(k, rima.repr(a), (a==b and "==") or "~=", rima.repr(b))
      end
      T:test(false, s)
    else
      T:test(true)
    end
  end

  check_linear(1, 1, {}, S)
  check_linear(1 + a*5, 1, {a=5}, S)
  check_nonlinear(1 + a*b, S)
  check_linear(1 + a*b, 1, {a=5}, scope.spawn(S, {b=5}))
  check_linear(1 + d[2]*5, 1, {["d[2]"]=5}, S)
  check_linear(1 + rima.sum({c=d}, c.value*5*c.index), 1, {["d[1]"]=5, ["d[2]"]=10}, S)
  check_linear(1 + rima.sum({c=d}, d[c]*5), 1, {["d[1]"]=5, ["d[2]"]=5}, S)

  return T:close()
end


-- EOF -------------------------------------------------------------------------

