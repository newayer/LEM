#!/usr/bin/env lua
-- ***************************************************************
--
-- Copyright 2014 by Sean Conner.  All Rights Reserved.
-- 
-- This library is free software; you can redistribute it and/or modify it
-- under the terms of the GNU Lesser General Public License as published by
-- the Free Software Foundation; either version 3 of the License, or (at your
-- option) any later version.
-- 
-- This library is distributed in the hope that it will be useful, but
-- WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
-- or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
-- License for more details.
-- 
-- You should have received a copy of the GNU Lesser General Public License
-- along with this library; if not, see <http://www.gnu.org/licenses/>.
--
-- Comments, questions and criticisms can be sent to: sean@conman.org
--
-- ------------------------------------------------------------------
--
-- Loads and tests a few modules from the sample.lem file.
--
-- ********************************************************************

local sys   = require "org.conman.sys"
local errno = require "org.conman.errno"
local zipr  = require "zipr"
local mz    = require "mz"
local dump  = require "org.conman.table".dump

-- *********************************************************************
-- Any module loaded past this point *WILL* come from the supplied LEM file. 
-- No ands, ifs or buts about it.
-- *********************************************************************

package.path  = ""
package.cpath = ""

-- ***********************************************************************

local function error(...)
  io.stderr:write(string.format(...),"\n")
  os.exit(1)
end

-- ***********************************************************************

local function read_data(entry,lem,sink)
  lem:seek('set',entry.offset)
  local file = zipr.file(lem)
  
  local rc,err = mz.inflate(function()  
    return lem:read(file.csize)
  end,sink)  
end

-- ***********************************************************************

local VER     = 5 * 256 + 1
local MODULES = {}
local APP     = {}
local FILES   = {}
local META
local lem

do
  local _LEM
  local function store(entry)
    local function add(list,name)
      if VER < entry.extra.lvmin 
      or VER > entry.extra.lvmax 
      then
        return
      end
      
      if list[name] then
        if entry.extra.version < list[name].extra.version then
          return
        end
      end
      
      list[name] = entry
    end
    
    if entry.extra and entry.extra.cpu == "_LEM" then
      _LEM = entry
      return
    end
    
    local list,name = entry.name:match("^_([^%/]+)%/(.*)")
    local dolist
    
    if list == 'MODULES' then
      dolist = MODULES
    elseif list == 'APP' then
      dolist = APP
    else
      dolist = FILES
      entry.name = name
    end
    
    if dolist == FILES then
      dolist[name] = entry
    elseif entry.extra.os == 'none' then
      add(dolist,name)
    else
      if  entry.extra.os  == sys.SYSNAME 
      and entry.extra.cpu == sys.CPU 
      then
        add(dolist,name)
      end      
    end
  end
  
  lem        = io.open("sample.lem","rb")
  local eocd = zipr.eocd(lem);

  lem:seek('set',eocd.offset)

  for i = 1 , eocd.entries do
    local dir,err = zipr.dir(lem)
    if not dir then error("ERROR %s: %s","sample.lem",errno[err]) end
    store(dir)
  end

  local data = {}
  read_data(_LEM,lem,function(s) data[#data + 1] = s end)
  local thelem,err = load(function() return table.remove(data,1) end,"_LEM")
  
  if not thelem then error("_LEM: %s",err) end
  
  META = {}
  setfenv(thelem,META)
  thelem()
end

-- ***********************************************************************

local function zip_loader(name)
  if not MODULES[name] then return string.format("\n\tno file %s",name) end

  if MODULES[name].extra.os == 'none' then
    local data = {}
    read_data(MODULES[name],lem,function(s) data[#data + 1] = s end)
    local func,err = load(function() return table.remove(data,1) end,name)
    if not func then error("%s: %s",name,err) end
    return func
  end
    
  local lib  = os.tmpname()
  local f    = io.open(lib,"wb")
  
  read_data(MODULES[name],lem,function(s) f:write(s) end)
  
  local func,err = package.loadlib(lib,"luaopen_" .. name:gsub("%.","_"))
  os.remove(lib)
  
  if not func then
    return err
  else
    return func
  end  
end

-- ***********************************************************************

table.insert(package.loaders,2,zip_loader)

print("PATH",package.path)
print("CPATH",package.cpath)

print()
print(META.NOTES)

date = require "org.conman.date"

print()
print(date.tojulianday())
print()

unix = require "org.conman.unix"

lpeg = require "lpeg"
print("LPeg",lpeg.version())

dump("USER",unix.users[os.getenv("USER")])

for name,entry in pairs(FILES) do
  dump(name,entry)
end
