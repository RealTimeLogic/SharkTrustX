

local cacheT={} -- key=zkey, val = DK (result from PBKDF2)
local PBKDF2=ba.crypto.PBKDF2

local function getDK(zkey, secret)
   local dk = cacheT[zkey]
   if not dk then
      local schar=string.char
      local zkT={}
      for x in zkey:gmatch("%x%x") do table.insert(zkT, schar(tonumber(x,16))) end
      local zkbin=table.concat(zkT)
      dk = PBKDF2("sha256",secret,zkbin,1000,32)
      cacheT[zkey]=dk
   end
   return dk
end

return {
   getDK=getDK
}
