-- Keep only addresses in deferred loggers, never a request or credentials.
local M={}

local function ipv4(value)
   if type(value) ~= "string" then return end
   local a,b,c,d=value:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
   if not a then return end
   for _,n in ipairs{a,b,c,d} do
      if #n > 3 or tonumber(n) > 255 then return end
   end
   return value
end

function M.context(wan)
   if type(wan) ~= "string" or #wan == 0 or #wan > 64 or wan:find("[^%x:%.%%]") then wan="unknown" end
   wan=wan:gsub("^::[fF][fF][fF][fF]:","")
   return {deviceIP="unknown",wanIP=wan}
end

function M.device(context,device,reportedIP)
   context.deviceIP=ipv4(reportedIP) or ipv4(device and device.localAddr) or "unknown"
end

function M.suffix(context)
   return string.format(" [device IP=%s; WAN IP=%s]",context.deviceIP,context.wanIP)
end

function M.message(context,format,...)
   return string.format(format,...)..M.suffix(context)
end

function M.logger(log,context)
   return function(iserr,format,...)
      return log(iserr,"%s",M.message(context,format,...))
   end
end

return M
