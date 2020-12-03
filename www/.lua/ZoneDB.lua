

-----------------------------------------------------------------------
--                   File database management                        --
-----------------------------------------------------------------------
--  Functions for working with JSON database structures  --

local sbyte=string.byte
local rw=require"rwfile"
local fmt=string.format
local hio=ba.openio"home"

if not hio:stat"data" and not hio:mkdir"data" then
   error("Cannot create "..hio:realpath"data")
end

local dio = ba.mkio(hio,"data") -- Data directory for all JSON files

local function wZonesT(tab)
   cachedZT=tab return rw.json(dio,"zones.json",tab)
end

local function rZonesT()
   return rw.json(dio,"zones.json")
end

local cachedZT=rZonesT()
local function rcZonesT()
   return cachedZT
end

-- Read or write a zone (domain) table
local function fmtZone(zkey)
   return fmt("z.%s.json",zkey)
end

local function validateZoneKey(zkey)
   return zkey and dio:stat(fmtZone(zkey))
end

-- zkey=64b-account-key
local function rwZoneT(zkey,tab)
   return rw.json(dio,fmtZone(zkey),tab)
end

 -- Read or update zone wan table
local function fmtWan(zkey)
   return fmt("w.%s.json",zkey)
end

local function rwWanT(zkey, tab)
   return rw.json(dio,fmtWan(zkey), tab)
end

local function updateWanT(zkey,dname,ip,newwan,oldwan)
   local wanT=rwWanT(zkey) or {}
   if oldwan and newwan ~= oldwan then
      local t = wanT[oldwan]
      if t then
         t[dname]=nil
         if not next(t) then wanT[oldwan]=nil end
      end
   end
   local t = wanT[newwan] or {}
   t[dname]=ip
   wanT[newwan]=t
   return rwWanT(zkey,wanT)
end

-- Read or write a device table.
local function fmtDevice(dkey)
   return fmt("d.%s.json",dkey)
end

-- dkey=20b-device-key
local function rwDeviceT(dkey,tab)
   local fn = fmtDevice(dkey)
   return rw.json(dio,fn,tab),fn
end

-- Removes all files associated with one device: device-tab,cert-key,cert
local function rmDevice(dkey)
   dio:remove(fmtDevice(dkey))
end


-- Deletes all files related to zone
local function deleteZone(zkey)
   local zoneT=rwZoneT(zkey)
   if zoneT then
      log(false, "Terminating zone %s : %s", zname, zoneT.uname)
      for _,dkey in pairs(zoneT.devices) do rmDevice(dkey) end
   else
      log(true, "Terminating zone warn: missing %s for %s",fmtZone(zkey),zname)
   end
   dio:remove(fmtZone(zkey)) -- Delete zone table
   dio:remove(fmtWan(zkey)) -- Delete zone wan table
end

local function createDeviceKey() 
   local dkey
   while true do
      dkey=ba.rndbs(10):gsub(".",function(x) return fmt("%02X",sbyte(x)) end)
      if not dio:stat(fmtDevice(dkey)) then break end
   end
   return dkey
end

if not rZonesT() then trace("Creating zones.json") wZonesT{} end

return {
   validateZoneKey=validateZoneKey,
   wZonesT=wZonesT,
   rwZoneT=rwZoneT,
   rcZonesT=rcZonesT,
   rwWanT=rwWanT,
   updateWanT=updateWanT,
   rwDeviceT=rwDeviceT,
   rmDevice=rmDevice,
   deleteZone=deleteZone,
   createDeviceKey=createDeviceKey
}
