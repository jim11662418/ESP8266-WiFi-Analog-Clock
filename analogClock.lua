-----------------------------------------------------------------------------------------------------------------------------------
-- Copyright © 2020 Jim Loos
-- 
-- Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files
-- (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge,
-- publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do
-- so, subject to the following conditions:
-- 
-- The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
-- 
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
-- OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
-- LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
-- IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-----------------------------------------------------------------------------------------------------------------------------------

-- this script connects to an NTP server to sync the ESP8266 RTC. re-syncs with the NTP server every 15 minutes.
-- pulses the analog clock's Lavet type stepping motor to keep the analog clock in sync with the ESP8266 RTC.
-- in addition to the usual file, gpio, net, node, sntp, tmr, and wifi modules, the interger firmware also 
-- requires the i2c, rtctime, sntp and uart modules.

-- GPIO     Index
   GPIO0  = 3	
-- GPIO1  = 10 --TX
   GPIO2  = 4	
-- GPIO3  = 9  --RX
   GPIO4  = 2	
   GPIO5  = 1	
-- GPIO9  = 11
-- GPIO10 = 12
   GPIO12 = 6		
   GPIO13 = 7	
   GPIO14 = 5		
-- GPIO15 = 8
-- GPIO16 = 0	

COIL1=GPIO2             -- use GPIO2 for COIL1 output to motor
COIL2=GPIO13            -- use GPIO13 for COIL2 output to motor
LED=GPIO0               -- use GPIO0 for LED output (heartbeat LED)
LEDTIME=50              -- heartbeat LED on for 50 milliseconds
PULSETIME=30            -- pulse analog clock Lavet motor for 30 milliseconds
RESYNCINTERVAL=15       -- re-sync RTC to NTP server every 15 minutes

ON=0                    -- turns LED on
OFF=1                   -- turns LED off
POS=0                   -- makes clock motor coil pulse positive
NEG=1                   -- makes clock motor coil pulse leg negative

HOUR=0                  -- address in EERAM where analogClKHour is saved
MINUTE=1                -- address in EERAM where analogClKMinute is saved
SECOND=2                -- address in EERAM where analogClKSecond is saved
TIMEZONE=3              -- address in EERAM where timeZone is saved
CHECK1=4                -- address in EERAM of first check byte (should be 0xAA)
CHECK2=5                -- address in EERAM of second check byte (should be 0x55)
CHECKSUM=4095           -- address in EERAM where checksum of EERAM bytes 0-3 is stored

hour=0                  -- global hour from ESP8266 RTC
minute=0                -- global minute from ESP8266 RTC
second=0                -- global second from ESP8266 RTC
analogClkHour=0         -- global analog clock hour hand setting (initialized by values from the EERAM read on startup)
analogClkMinute=0       -- global analog clock minute hand setting (initialized by values from the EERAM read on startup)
analogClkSecond=0       -- global analog clock second hand setting (initialized by values from the EERAM read on startup)
timeZone=0              -- global time zone, defaults to UTC

timePeriodStr=''        -- Ante Meridiem or Post Meridiem (AM or PM)

ntpSyncInProgress=false
ntpSyncStr=''

function ntpSync()
   local errors={"DNS lookup failed.","Memory allocation failure.","UDP send failed.","Timeout, no NTP response received."}
   ntpSyncInProgress=true
   sntp.sync("0.us.pool.ntp.org", 
      function(sec,usec,server)     -- success callback
         print("Synced with "..server) 
         ntpSyncInProgress=false
         ntpSyncStr=string.format("%2d",analogClkHour)..":"..string.format("%02d",analogClkMinute)..":"..string.format("%02d",analogClkSecond)..timePeriodStr         
      end, --function(sec,usec,server)
      function(errorcode)           -- failure callback
         print(errors[errorcode])
         print("Retrying NTP sync... ")
         ntpSync()                  -- recursive call
      end --function(errorcode)
   ) -- sntp.sync   
end -- function ntpSync()

-- returns the uptime as a formatted string: days, hours, minutes
local function getUpTime()
   -- tmr.time() rolls over after it exceeds 31 bits (2,147,483,647 seconds) which is more than 68 years! 
   local t=tmr.time()
   local d=t/86400
   local h=(t%86400)/3600
   local m=(t%3600)/60
   local s=t%60
   local upTimeStr=''
   if d>0 then if d==1 then upTimeStr=string.format("%3d",d).." day, " else upTimeStr=string.format("%3d",d).." days, " end end
   if h>0 then if h==1 then upTimeStr=upTimeStr..string.format("%2d",h).." hour, " else upTimeStr=upTimeStr..string.format("%2d",h).." hours, " end end
   if m>0 then if m==1 then upTimeStr=upTimeStr..string.format("%2d",m).." minute" else upTimeStr=upTimeStr..string.format("%2d",m).." minutes" end end
   return upTimeStr
end -- function

-- returns the hour, minute and second from the ESP8266 RTC seconds count
-- corrected to local time according to the time zone. automatically adjust for daylight saving if the
-- local time is from 2AM on the second Sunday in March until 2AM on the first Sunday in November.
function getLocalTime(timeZone)
    local DSTstartDate={11,10,8,14,13,12,10,9,8,14,12,11,10,9,14,13,12,11,9,8,14}   -- daylight saving time start date (2nd Sunday in March) for years 2018 thru 2038
    local DSTendDate={4,3,1,7,6,5,3,2,1,7,5,4,3,2,7,6,5,4,2,1,7}                    -- daylight saving time end date (1st Sunday in November) for years 2018 thru 2038
    
    -- get the time from the ESP8266 firmware rtc
    local loctime=rtctime.epoch2cal(math.max(0,rtctime.get()+(timeZone*3600)))                     -- add time zone to convert to local time
    local y=loctime["year"]-2017                                                                   -- convert year into table index
    if ((loctime["mon"] >3)  and (loctime["mon"]<11))              or                              -- is it April through October?
       ((loctime["mon"]==3)  and (loctime["day"]>DSTstartDate[y])) or                              -- is it March and after the 2nd Sunday in March (DST start date)?
       ((loctime["mon"]==11) and (loctime["day"]<DSTendDate[y]))   or                              -- is it November and before the 1st Sunday in November (DST end date)?
       ((loctime["mon"]==3)  and (loctime["day"]==DSTstartDate[y]) and (loctime["hour"]>1)) or     -- is it the 2nd Sunday in March after EST 1:59:59?
       ((loctime["mon"]==11) and (loctime["day"]==DSTendDate[y])   and (loctime["hour"]<1)) then   -- is it the 1st Sunday in November before EST 0:59:59 (EDT 1:59:59)?
          loctime=rtctime.epoch2cal(math.max(0,rtctime.get()+(timeZone*3600)+3600))                -- then add one hour for DST and convert to local month, day, year, hour, minute second with time zone offset added            
    end -- if
    return loctime["hour"],loctime["min"],loctime["sec"]
end -- function geLocalTime

-- function called by the timer once every 100 milliseonds...
function oneHundredMS()
   local printTime=false
   local lastSecond=second
   hour,minute,second=getLocalTime(timeZone) -- retrieve the current time and date from the ESP8266 RTC
   if hour<12 then timePeriodStr=' AM' else timePeriodStr=' PM' end
   hour=((hour+11)%12)+1 -- convert 13-23 hours to 1-11 hours

   if lastSecond~=second then   -- if the time has changed since last time
      printTime= true           -- the display needs to be updated
      gpio.write(LED,ON)        -- turn the LED on
      ledTimer=tmr.create()
      tmr.alarm(ledTimer,LEDTIME,tmr.ALARM_SINGLE,function() gpio.write(LED,OFF) end)     -- turn the LED off after 50 milliseconds     
      if (second==0) and (minute%RESYNCINTERVAL==0) and (not ntpSyncInProgress) then ntpSync() end
   end  -- if lastSecond~=second then
   
   local analogClkTotalSeconds=(analogClkHour*3600)+(analogClkMinute*60)+analogClkSecond -- total clock's seconds past midnight
   local totalSeconds=(hour*3600)+(minute*60)+second                                     -- total RTC number of seconds past midnight

   -- check to see if the analog clock is behind the RTC time and needs to be advanced...
   if ((analogClkTotalSeconds<totalSeconds) or ((analogClkTotalSeconds==46799) and (totalSeconds==3600))) then
      -- the expression "or ((analogClkTotalSeconds==46799) and (totalSeconds==3600))" is an ugly hack 
      -- to take care of the problem that occurs when the RTC rolls over from 12:59:59 to 01:00:00 
      -- (totalSeconds==3600) while the analog clock is still at 12:59:59 (analogClkTotalSeconds==46799).
      -- to do: invent a more elegant solution.

      -- the analog clock lags the RTC time so pulse the analog clock Lavet motor to advance the clock's second 
      -- hand one second so that the analog clock catches up with the RTC time
      if ((analogClkSecond%2)==0) then -- positive motor pulse on even seconds
         gpio.write(COIL1,POS)
         gpio.write(COIL2,NEG)
         pulseTimer=tmr.create()         
         tmr.alarm(pulseTimer,PULSETIME,tmr.ALARM_SINGLE,function() gpio.write(COIL1,NEG) end)       
      else                             -- negative motor pulse on odd seconds
         gpio.write(COIL2,POS)
         gpio.write(COIL1,NEG)
         pulseTimer=tmr.create()         
         tmr.alarm(pulseTimer,PULSETIME,tmr.ALARM_SINGLE,function() gpio.write(COIL2,NEG) end)              
      end -- if ((analogClkSecond%2)==0)
    
      -- we've pulsed the analog clock's second hand, so increment the analog clock's second count
      analogClkSecond=analogClkSecond+1             -- increment analog clock's seconds count
      if (analogClkSecond==60) then
         analogClkSecond=0                          -- reset analog clock's seconds count back to zero
         analogClkMinute=analogClkMinute+1          -- update analog clock's minutes count every 60 seconds
         if (analogClkMinute==60) then
            analogClkMinute=0                       -- reset analog clock's minutes count back to zero
            analogClkHour=analogClkHour+1           -- update analog clock's hours count every 60 minutes
            if (analogClkHour==13) then
               analogClkHour=1                      -- reset analog clock's hours count back to 1
            end
         end
      end -- if (analogClkSecond==60) then
      -- save the positions of the hour, minute and seconds hands to EERAM
      writeEERAM(HOUR,analogClkHour,analogClkMinute,analogClkSecond) 
      local checksum=(analogClkHour+analogClkMinute+analogClkSecond)%256
      writeEERAM(CHECKSUM,checksum)
      printTime=true                                -- the display needs to be updated
   end -- if ((analogClkTotalSeconds<totalSeconds) or ((analogClkTotalSeconds==46799) and (totalSeconds==3600))) then
   
   if (printTime) then  -- if the display needs to be updated...
      -- print the updated analog clock time and RTC time as "HH:MM:SS     HH:MM:SS"
      local analogClockStr=string.format("%2d",analogClkHour)..":"..string.format("%02d",analogClkMinute)..":"..string.format("%02d",analogClkSecond)
      local rtcStr=string.format("%2d",hour)..":"..string.format("%02d",minute)..":"..string.format("%02d",second)
      print(analogClockStr.."\t"..rtcStr)
   end -- if (printTime) then
end -- function oneHundredMS()

-- write 'data' to sequential SRAM locations starting at 'address'
function writeEERAM(address,data,...)
  local arg={n=select('#',...),...}
  i2c.start(0)
  i2c.address(0,0x50,i2c.TRANSMITTER)          -- 0x50 is SRAM register
  i2c.write(0,address/256,address%256,data)    -- write address high byte, address low byte, first data byte
  for i = 1,arg.n do i2c.write(0,arg[i]) end   -- write sequential data bytes
  i2c.stop(0)  
end

-- read a byte from SRAM location 'address'
function readEERAM(address)
   i2c.start(0)
   i2c.address(0,0x50,i2c.TRANSMITTER)         -- 0x50 is SRAM register
   i2c.write(0,address/256,address%256)        -- address high byte, address low byte
   i2c.stop(0)
   i2c.start(0)
   i2c.address(0,0x50,i2c.RECEIVER)            -- 0x50 is control register
   local data=i2c.read(0x00,1)                 -- 0x00 is address of status register
   i2c.stop(0)
   return data
end

--return the size of a file in bytes
function fileSize(filename)
   local list=file.list()
   local size=0
   for k,v in pairs(list) do
      if string.find(k,filename) then size=v end
   end     
   return size
end

-- TCP server "receive" callback function
function onReceive(sck, payload)
   if (string.find(payload,"HEAD / HTTP/1.1")) then
      --print("HEAD received")
      --print(payload)
      local page=''      
      page=page..'HTTP/1.1 200 OK\r\n'
      page=page..'Content-type: text/html\r\n'
      page=page..'Server: ESP8266\r\n\r\n'
      sck:send(page)

   elseif (string.find(payload,"GET /favicon.ico HTTP/1.1")) then
      --print("GET favicon request")
      --print(payload)      
      local page=''
      if file.open("favicon.ico","r") then
         local buffer=file.read(fileSize('favicon.ico')) -- favicon.ico must be less than 1372 bytes to keep the total "send" less than CHUNKSIZE
         page=page..'HTTP/1.1 200 OK\r\n'
         page=page..'Content-Length: '..#buffer..'\r\n'
         page=page..'Connection: close\r\n'
         page=page..'Content-Type: image/x-icon\r\n\r\n'
         page=page..buffer
      else
         page=page..'HTTP/1.0 404 Not Found\r\n\r\n'
      end -- if file.open("favicon.ico","r") then
      
      sck:send(page)
      --print("sent "..#page.." bytes")
      file.close();
      
   elseif (string.find(payload,"GET / HTTP/1.1")) then
      --print("GET received")
      --print(payload)
      local analogClockStr=string.format("%2d",analogClkHour)..":"..string.format("%02d",analogClkMinute)..":"..string.format("%02d",analogClkSecond)..timePeriodStr
      local page=''
      page=page..'HTTP/1.1 200 OK\r\n'
      page=page..'Content-type: text/html\r\n'
      page=page..'Server: ESP8266\r\n\r\n'                
      page=page..'<!DOCTYPE HTML>'
      page=page..'<html>'
      page=page..  '<head>'
      page=page..    '<META HTTP-EQUIV="refresh" CONTENT="1">'
      page=page..    '<meta content="text/html; charset=utf-8">'
      page=page..    '<title>ESP8266 Analog Clock</title>'
      page=page..  '</head>'
      page=page..  '<body style="background-color:lightgrey;">'
      page=page..    '<h1>Analog&nbsp;Clock&nbsp;&nbsp;'..analogClockStr..'</h1>'
      page=page..    '<br>'
      page=page..    '<p>Uptime: '..getUpTime()..'</p>'
      page=page..    '<br>'
      page=page..    '<p>Last NTP sync at: '..ntpSyncStr..'</p>'      
      page=page..  '</body>'
      page=page..'</html>'      
      sck:send(page)
      
   elseif (string.find(payload,"POST / HTTP/1.1")) then
      --print("POST received")
      --print(payload) 
      
   end -- if (string.find(payload,"HEAD / HTTP/1.1")) then
end -- function onReceive(conn, payload)

-- set up the web server to display the analog clock hours, minutes and seconds
function startServer()
   srv=net.createServer(net.TCP)
   srv:listen(80,function(conn)
      conn:on("connection",function(sock) end)
      conn:on("reconnection",function(sock) end)   
      conn:on("receive",function(sock,payload) onReceive(sock,payload) end)
      conn:on("sent", function(sock) sock:close() end)
      conn:on("disconnection", function(sock) end)
   end)
end -- function startServer()    

function printEERAM(addr)
   print("0x" .. string.format("%02X",string.byte(readEERAM(addr))))
end

-----------------------------------------------------------------------------
-- script execution starts here...
-- no need to wait for an ip address, that's done in init.lua
-- no need for the initial NTP sync, that's done in init.lua
-----------------------------------------------------------------------------
--set the IP of the DNS servers used to resolve hostnames

net.dns.setdnsserver("208.67.222.222",0)    -- OpenDNS.com
net.dns.setdnsserver("8.8.8.8",1)           -- Google.com

gpio.mode(COIL1,gpio.OUTPUT)   -- set up gpio outputs for clock motor coil
gpio.mode(COIL2,gpio.OUTPUT)
gpio.write(COIL1,NEG)          -- turn the clock motor coil off
gpio.write(COIL2,NEG)        

gpio.mode(LED,gpio.OUTPUT)    -- set up gpio output for heartbeat LED
gpio.write(LED,OFF)           -- turn the heartbeat LED off

-- initialize i2c for the EERAM
-- pin 5 on 47C04 (SDA) is connected to GPIO12
-- pin 6 on 47C04 (SDL) is connected to GPIO14
i2c.setup(0,GPIO12,GPIO14,i2c.SLOW) 

-- read stored values from EERAM, if the check bytes are correct...
analogClkHour=string.byte(readEERAM(HOUR))        -- read stored position of the analog clock's hour hand from EERAM
analogClkMinute=string.byte(readEERAM(MINUTE))    -- read stored position of the analog clock's minute hand from EERAM
analogClkSecond=string.byte(readEERAM(SECOND))    -- read stored position of the analog clock's second hand from EERAM

if (string.byte(readEERAM(CHECK1))==0xAA) and (string.byte(readEERAM(CHECK2))==0x55) and ((analogClkHour+analogClkMinute+analogClkSecond)%256==string.byte(readEERAM(CHECKSUM))) then
   local zones='XXXXECMPAH'
   timeZone=0-string.find(zones,readEERAM(TIMEZONE)) -- match the time zone value stored in EERAM to the table. In the US, they're always negative
   -- start the web server
   startServer()   
   -- all the work is done in the oneHundredMS function
   clkTimer=tmr.create()
   tmr.alarm(clkTimer,100,tmr.ALARM_AUTO,function() oneHundredMS() end)    -- call oneHundredMS() every 100 milliseconds    
   collectgarbage()
else -- the EERAM check bytes are not correct
   print("The values stored in EERAM are not valid. The analog clock setup script needs to be run!")
   dofile("analogClockSetup.lua")
end -- if (string.byte(readEERAM(CHECK1))==0xAA) and (string.byte(readEERAM(CHECK2))==0x55)



