

local rTokensT={} -- key=tokenId, val=datetime
local elevenHours = (11*60*60) * 1000 -- In milliseconds
local getZoneName = require"ZoneDB".getZoneName
local db = require"ZoneDB"

local function sendToken(cmd,rToken,expDatetime)
   cmd:setheader("X-RefreshToken",ba.b64urlencode(rToken))
   cmd:setheader("X-Expires",expDatetime:tostring())
   cmd:abort()
end

local function createTimer(rToken)
   -- Remove (invalidate token) after 'elevenHours'
   ba.timer(function() rTokensT[rToken]=nil end):set(elevenHours,true)
end

local function cmdGetToken(cmd)
   if not getZoneName(cmd:header"X-Key") then
      cmd:senderror(404)
      cmd:abort()
   end
   local dkey=cmd:header"X-Dev"
   if dkey then db.updateTime4Device(dkey) end
   -- Set 'now' 15 minutes ahead
   local now = ba.datetime"NOW" + {mins=15}
   for rToken,exp in pairs(rTokensT) do
      if now < exp then
         sendToken(cmd,rToken,exp) -- Aborts (returns)
      end
   end
   -- Above: too old or no refresh token. Let's create a new token
   rToken = ba.rndbs(32)
   rTokensT[rToken] = now + {hours=10}
   createTimer(rToken)
   sendToken(cmd,rToken,rTokensT[rToken])
end


local function tokenValid(rtoken)
   return rTokensT[rtoken] and true or false
end

return {
   cmdGetToken=cmdGetToken,
   tokenValid=tokenValid,
}
