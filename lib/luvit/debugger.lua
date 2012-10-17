--[[

Copyright 2012 The Luvit Authors. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

  http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS-IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

This debugger was heavily inspired by Dave Nichols's debugger 
which itself was inspired by:
RemDebug 1.0 Beta  (under Lua License)
Copyright Kepler Project 2005 (http://www.keplerproject.org/remdebug)
--]]

local debug = require('debug')
local string = require('string')
local utils = require('utils')
local Object = require('core').Object

local io

local debugger = nil

local help = {
q = [[ 
(q)  quit 

]],
w = [[
(w)  where                            --shows call stack

]],
c = [[
(c)  continue 

]],
n = [[
(n)  next                             --step once

]],
o = [[
(o)  out [number of frames]           --step out of the existing function

]],
l = [[
(l)  list                             --Show the current file

]],
v = [[
(v)  variables                        --list all reachable variables and thier values

]],
lb = [[
(lb) list breakpoints

]],
sb = [[
(sb) set breakpoint [file:line]

]],
db = [[
(db) delete breakpoint [file:line]

]],
x = [[
(x)  eval                             -- evals the statment via loadstring in the current strack frame 
This function can't set local variables in the stack because loadstring returns a function.  Any input that 
doesn't match an op defaults to eval.
]]
}


local OPS = {['c']=0, ['q']=1, ['nop']=2}

local function getinfo(lvl)
  local info = debug.getinfo(lvl)
  if not info then 
    return {nil, nil}
  end
  return {info.short_src, info.currentline}
end


local function getvalue(level, name)
  -- this is an efficient lookup of a name
  local value, found, attrs

  attrs = name:split('%.')
  name = attrs[1]

  local function resolve_attrs()
    for i=2,#attrs do
      if not value or type(value) ~= "table" then
        p(value)
        break
      end
      value = value[attrs[i]]
    end

    return value
  end

  -- try local variables
  local i = 1
  while true do
    local n, v = debug.getlocal(level, i)
    if not n then break end
    if n == name then
      value = v
      found = true
    end
    i = i + 1
  end
  if found then
    return resolve_attrs() 
  end

  -- try upvalues
  local func = debug.getinfo(level).func
  i = 1
  while true do
    local n, v = debug.getupvalue(func, i)
    if not n then break end
    if n == name then return v end
    i = i + 1
  end

  -- not found; get global
  value = getfenv(func)[name]
  return resolve_attrs()
end


local function capture_vars(level)
  -- captures all variables in scope which is
  --useful for evaling user input in the given stack frame
  local ar = debug.getinfo(level, "f")
  if not ar then return {},'?',0 end
  
  local vars = {__UPVALUES__={}, __LOCALS__={}}
  local i
  
  local func = ar.func
  if func then
    i = 1
    while true do
      local name, value = debug.getupvalue(func, i)
      if not name then break end
      --ignoring internal control variables
      if string.sub(name,1,1) ~= '(' then  
        vars[name] = value
        vars.__UPVALUES__[i] = name
      end
      i = i + 1
    end
    vars.__ENVIRONMENT__ = getfenv(func)
  end
  
  vars.__GLOBALS__ = getfenv(0)
  
  i = 1
  while true do
    local name, value = debug.getlocal(level, i)
    if not name then break end
    if string.sub(name,1,1) ~= '(' then
      vars[name] = value
      vars.__LOCALS__[i] = name
    end
    i = i + 1
  end
  
  vars.__VARSLEVEL__ = level
  
  if func then
    --Do not do this until finished filling the vars table
    setmetatable(vars, { __index = getfenv(func), __newindex = getfenv(func) })
  end
  
  --Do not read or write the vars table anymore else the metatable functions will get invoked!

  return vars

end

local function restore_vars(level, vars)

  local i
  local written_vars = {}

  i = 1
  while true do
    local name, value = debug.getlocal(level, i)
    if not name then break end
    if vars[name] and string.sub(name,1,1) ~= '(' then
      debug.setlocal(level, i, vars[name])
      written_vars[name] = true
    end
    i = i + 1
  end

  local ar = debug.getinfo(level, "f")
  if not ar then return end

  local func = ar.func
  if func then

    i = 1
    while true do
      local name, value = debug.getupvalue(func, i)
      if not name then break end
      if vars[name] and string.sub(name,1,1) ~= '(' then
        if not written_vars[name] then
          debug.setupvalue(func, i, vars[name])
        end
        written_vars[name] = true
      end
      i = i + 1
    end

  end

end

local Debugger = Object:extend()

function Debugger:initialize()
  self.op = OPS.nop
  self.steps = 0
  self.stack = 0
  self.breaks = {}
  self.lvl = 5
  self.target_lvl = nil
  self.step_over = false
  self.step_out = false
  self.hooked = false
end

Debugger.switch = {
  ['h'] = function(Debugger, file, line, topic)
    local _,v
    
    if topic and help[topic]
      v = help[topic] or string.format('no help topic found for %s', topic)
      io.write(v)
      return OPS.nop
    end

    for _,v in pairs(help) do
      io.write(v)
    end

    return OPS.nop
  end,
  ['w'] = function(Debugger, file, line, args)
    io.write(debug.traceback("", Debugger.lvl + 2))
    return OPS.nop
  end,
  ["l"] = function(Debugger, file, line, args)
    Debugger:show(input, file, line)
    return OPS.nop
  end,
  ['q'] = function(Debugger, file, line, args)
    return OPS.q
  end,
  ["c"] = function(Debugger, file, line, args)
    return OPS.c
  end,
  ["n"] = function(Debugger, file, line, args)
    Debugger.step_over = true
    Debugger.steps = 1
    return OPS.c
  end,
  ["o"] = function(Debugger, file, line, args)
    Debugger.step_out = true
    Debugger.target_lvl = Debugger.stack - 1
    return OPS.c
  end,
  ["v"] = function(Debugger, file, line, args, level)
    io.write(utils.dump(capture_vars(level+1)))
    return OPS.nop
  end,
  ["lb"] = function(Debugger, file, line, args)
    for file, lines in pairs(Debugger.breaks) do
      for line, is_set in pairs(lines) do
        io.write(string.format("%s:%s (%s)", file, line, tostring(is_set)))
      end
    end
    return OPS.nop
  end,
  ["sb"] = function(Debugger, file, line, args)
    file,line = unpack(args:split(':'))
    line = tonumber(line)
    if file and line then
      Debugger:set_breakpoint(file, line)
    end
    return OPS.nop
  end,
  ["db"] = function(Debugger, file, line, args)
    file,line = unpack(args:split(':'))
    line = tonumber(line)
    if file and line then
      Debugger:remove_breakpoint(file, line)
    end
    return OPS.nop
  end,
  ['x'] = function(Debugger, file, line, eval, level)

    local function reply(msg)
      io.write(msg .. '\n')
      return OPS.nop
    end

    -- offset for ourselves
    level = level + 1

    local ok, func = pcall(loadstring, eval)
    if not ok and not func then
      return reply("Compile error: "..func)
    end
    if not func then
      eval = 'return ' .. eval
      ok, func = pcall(loadstring, eval)
      if not (ok and func) then 
        return reply("Loadstring returns a function, try using the return statement.")
      end
    end

    local vars = capture_vars(level)

    setfenv(func, vars)
    local isgood, res = pcall(func)

    if not isgood then
      return reply("Run error: "..res)
    end
    restore_vars(level, vars)

    local msg = utils.dump(res)
    return reply(msg)
  end
}

function Debugger:set_hook()
  debug.sethook(function(...) self:hook(...) end, "crl")
  self.hooked = true
end

function Debugger:set_breakpoint(file, line)
  if not self.hooked then
    self:set_hook()
  end

  self.breaks[file] = self.breaks[file] or {}
  self.breaks[file][line] = true
end

function Debugger:remove_breakpoint(file, line)
  if self.breaks[file] then
    self.breaks[file][line] = nil
  end
end

function Debugger:show(input, file, line)
  local before = 10
  local after = 10
  line = tonumber(line or 1)

  if not string.find(file,'%.') then file = file..'.lua' end

  local f = io.open(file,'r')
  if not f then
    -- looks for a file in the package path
    local path = package.path or LUA_PATH or ''
    for c in string.gmatch (path, "[^;]+") do
      local c = string.gsub (c, "%?%.lua", file)
      f = io.open (c,'r')
      if f then
        break
      end
    end
    
    if not f then
      io.write('Cannot find '..file..'\n')
      return
    end
  end

  local i = 0
  for l in f:lines() do
    i = i + 1
    if i >= (line-before) then
      if i > (line+after) then break end
      if i == line then
        io.write('*** ' ..i ..'\t'..l..'\n')
      else
        io.write('    '..i.. '\t'.. l..'\n')
      end
    end
  end

  f:close()

end
function Debugger:has_breakpoint(file, line)
  -- p(file, line)
  -- file = file or 'nil'
  -- line = line or 'nil'
  -- print('looking for '.. file .. line)
  -- p(breaks)
  return self.breaks[file] and self.breaks[file][line]
  -- if not breaks[file] then 
  --   return false 
  -- end

  -- local noext = string.gsub(file,"(%..-)$",'',1)

  -- if noext == file then noext = nil end
  -- while file do
  --   if breaks[file][line] then 
  --     return true end
  --   file = string.match(file,"[:/](.+)$")
  -- end
  -- while noext do
  --   if breaks[noext][line] then return true end
  --   noext = string.match(noext,"[:/](.+)$")
  -- end
  -- return false
end

function Debugger:should_break(file, line, event)
  
  if event == "call" then
    self.stack = self.stack + 1
    return false
  end
  
  if event == "return" then
    self.stack = self.stack - 1
    if self.step_out and self.target_lvl == self.stack then
      self.step_out = false
      return true
    end 
    return false
  end

  -- only line events at this point
  if self:has_breakpoint(file, line) then
    return true
  end

  -- should step over/
  if self.step_over then
    -- have we arrived?
    if self.steps > 0 then
      self.steps = self.steps - 1
      return false
    end
    self.step_over = false
    return true
  end
  
  return false

end

function Debugger:input(file, line, event)
  local ok, msg, op
  if file and line then
    io.write(string.format('\nbreak at %s:%s (%s)', file, line, event))
  end

  io.write("\n> ")
  input = io.stdin:read('*l')
  ok, op = pcall(self.process_input, self, file, line, input)

  if not ok then
    print('ERROR: call failed', op)
    return OPS.q
  end
    -- use last op if no input
  if not op then
    op = self.op
  end

  return op
end



function Debugger:process_input(file, line, input)
  local lvl = self.lvl + 3
  local args = input
  -- parses user input
  local op = input:sub(0,1)
  local f = self.switch[op]

  if not op then 
    io.write('Give me something.')
    return OPS.nop
  end

  -- valid op with args?
  if f and input:sub(2,2) == '' or input:sub(2,2) == ' ' then
    args = input:sub(3)
  else
    f = nil
  end
  -- if the op doesn't exist, eval the expression and hope for the best
  if not f then 
    f = self.switch['x']
  end

  return f(self, file, line, args, lvl)

end

function Debugger:hook(event, line)

  file, line = unpack(getinfo(self.lvl))

  if not self:should_break(file, line) then
    return
  end

  self.op = self:input(file, line, event)

  while true do 
    if self.op == OPS.q then 
      return debug.sethook()
    elseif self.op == OPS.c then
      return
    elseif self.op == OPS.nop then
      self.op = self:input(file, line, event)
    else
      process.stdout:write('Unrecognized command: ' .. self.op .. '\n')
      self.op = OPS.nop
    end
  end
end

return {
  ['install'] = function(io)
    read = io.read,
    write = io.write
    return function()
      file, line = unpack(getinfo(3))
      debugger = debugger or Debugger:new()
      debugger:set_breakpoint(file, line)
    end
  end
}