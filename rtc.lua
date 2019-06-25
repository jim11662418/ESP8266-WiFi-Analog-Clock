-- retrieve and the time and date from the ESP8266 RTC
-- convert UTC to local time and date according to the time zone (tzone)
-- adjust for Daylight Saving Time if:
--    1. the time zone (tzone) is one of the United States time zones (EST UTC-5 to AKST UTC-9)
--    2. the date is between of the 2nd Sunday in March when DST begins and 1st Sunday in November when DST ends
-- requires the sntp and rtctime firmware modules
-- the ESP8266 RTC is synced with the NTP server when the module is loaded into memory
-- note that this module doesn't work correctly with the floating point firmware.

local moduleName= ... 
local M={}
_G[moduleName]=M 

-- returns a number corresponding to the date for Nth day of the month.
-- for example: nthDate(2,0,3,2016) will return the number 13 (the 13th) for the 2nd Sunday(0) in March(3) 2016 when DST begins
--              nthDate(1,0,11,2016) will return the number 6 (the 6th) for the 1st Sunday(0) in November(11) 2016 when DST ends
local function nthDate(nth,dow,month,year)
   local targetDate=1
   local t={0,3,2,5,0,3,5,1,4,6,2,4}
   if month<3 then
      year=year-1
   end
   firstDOW=(year+year/4-year/100+year/400+ t[month]+1)%7
   while (firstDOW~=dow) do
      firstDOW=(firstDOW+1)%7
      targetDate=targetDate+1
   end
   targetDate = targetDate+(nth-1)*7
   return targetDate
end -- function nthDate

-- returns the hour, minute, second, day, month and year from the ESP8266 RTC seconds count
-- corrected to local time according to the time zone. (timeZone defaults to UTC if not specified.)
function M.getTime(timeZone)
    local tz=0  -- default to UTC if time zone is not valid
    if (timeZone) and (timeZone>-13) and (timeZone<13) then
       tz=timeZone
    end

    -- get the time from the ESP8266 firmware rtc
    local timestamp=rtctime.get()
    local loctime=rtctime.epoch2cal(math.max(0,timestamp+(tz*3600)))  --local time
    
    local SUNDAY=0
    local MARCH=3
    local NOVEMBER=11
    local FIRST=1
    local SECOND=2
    if ((tz<-4) and (tz>-10)) then                                                                                -- if US time zone (EST UTC-5 to AKST UTC-9)...
       local startDST=nthDate(SECOND,SUNDAY,MARCH,loctime["year"])                                                -- date when DST starts this year (2nd Sunday in March)
       local endDST=nthDate(FIRST,SUNDAY,NOVEMBER,loctime["year"])                                                -- date when DST ends this year (1st Sunday in November)
       if ((loctime["mon"] >MARCH)    and (loctime["mon"]<NOVEMBER)) or                                           -- is it April through October?
          ((loctime["mon"]==MARCH)    and (loctime["day"]>startDST)) or                                           -- is it March and after the 2nd Sunday in March (DST start date)?
          ((loctime["mon"]==MARCH)    and (loctime["day"]==startDST))and (loctime["hour"]>1) or                   -- is it the 2nd Sunday in March after EST 1:59:59?
          ((loctime["mon"]==NOVEMBER) and (loctime["day"]<endDST))   or                                           -- is it November and before the 1st Sunday in November (DST end date)?
          ((loctime["mon"]==NOVEMBER) and (loctime["day"]==endDST)   and (loctime["hour"]<1)) then                 -- is it the 1st Sunday in November before EST 0:59:59 (EDT 1:59:59)?
             timestamp=timestamp+3600                                                                             -- then daylight savings time is in effect, advance time one hour (3600 seconds)
             loctime=rtctime.epoch2cal(math.max(0,timestamp+(tz*3600)))                                           -- convert to local month, day, year, hour, minute second with DST offest added            
       end
    end -- if ((tz<-4) and (tz>-10)) then 

    return loctime["hour"],loctime["min"],loctime["sec"],loctime["mon"],loctime["day"],loctime["year"]
end -- function getime

-----------------------------------------------------------------------------
-- script execution starts here...
-----------------------------------------------------------------------------

return M