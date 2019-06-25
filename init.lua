NTPSERVER="0.us.pool.ntp.org"

   GPIO0  = 3
-- GPIO1  = 10
-- GPIO2  = 4
-- GPIO3  = 9
-- GPIO4  = 2	
-- GPIO5  = 1	
-- GPIO9  = 11
-- GPIO10 = 12
-- GPIO12 = 6		
-- GPIO13 = 7	
-- GPIO14 = 5		
-- GPIO15 = 8
-- GPIO16 = 0	

-- read SRAM
function readSRAM(address)
   local id =0 --always zero
   i2c.start(id)
   i2c.address(id,0x50,i2c.TRANSMITTER)         -- 0x50 is SRAM register
   i2c.write(id,address/256,address%256)        -- address high byte, address low byte
   i2c.stop(id)
   i2c.start(id)
   i2c.address(id,0x50,i2c.RECEIVER)            -- 0x50 is control register
   data=i2c.read(0x00,1)                        -- 0x00 is address of status register, read 1 byte
   i2c.stop(id)
   return data
end

function ntpSync()
   local errors={"DNS lookup failed.","Memory allocation failure.","UDP send failed.","Timeout, no NTP response received."}
   sntp.sync(NTPSERVER, 
      function(sec,usec,server)     -- success callback
         print("Successful sync with NTP server.")
         errors=nil
         collectgarbage()
         dofile("analogClock.lua")
         return
      end, --function(sec,usec,server)
      function(errorcode)           -- failure callback
         print(errors[errorcode])
         uart.write(0,"Retrying NTP sync... ")
         ntpSync()
      end --function(errorcode)
   ) -- sntp.sync   
end -- function ntpSync()

-----------------------------------------------------------------------------
-- script execution starts here...
-----------------------------------------------------------------------------
gpio.mode(GPIO0,gpio.INPUT)     -- switch connected to GPIO0 used to abort initialization
startTimer=tmr.create()
tmr.alarm(startTimer,100,tmr.ALARM_SINGLE, --allow 100 milliseconds for the cursor to return to left margin
   function()
      -- count down startupDelay seconds to allow time to abort 
      local startupDelay=10
      local bs=0
      print("\n\rPress the \"Flash\" button to abort initialization.\n\r")
      initTimer=tmr.create()
      tmr.alarm(initTimer,1000,tmr.ALARM_AUTO,
         function()
            if (gpio.read(GPIO0)==0) then -- pressing the button attached to GPIO0 aborts the initialization
               print("\n\rAbort button pressed.\n\r") 
               tmr.unregister(initTimer) 
               return
            end
         
            for i=1,bs do uart.write(0,"\b") end
            local str="Seconds until startup: "..startupDelay
            bs=string.len(str)
            uart.write(0,str)            
            startupDelay=startupDelay-1
            if startupDelay==0 then
               for i=1,string.len(str) do uart.write(0,"\b") end
               tmr.unregister(initTimer) 
               
               local sda=6 -- pin 5 on 47C04 connected to GPIO14
               local scl=5 -- pin 6 on 47C04 connected to GPIO12
               i2c.setup(0,sda,scl,i2c.SLOW)
               local checkEERAMaddress1=4
               local checkEERAMaddress2=5 
               if (string.byte(readSRAM(checkEERAMaddress1))==0xAA) and (string.byte(readSRAM(checkEERAMaddress2))==0x55) then
                  checkCount=0 
                  wifi.setmode(wifi.STATION,true)
                  station_cfg={}
                  station_cfg.ssid="traXu74P"
                  station_cfg.pwd="Zjx9rUVYyT"
                  station_cfg.save=true
                  wifi.sta.config(station_cfg)                  
                  ssid=wifi.sta.getconfig()
                  uart.write(0,"\n\rWaiting for IP address")
                  if ssid~=nil then uart.write(0," from "..ssid) end
                  uart.write(0,"...")
                  ssid=nil
                  -- start a timer to check for IP address from AP every 1000 milliseconds               
                  wifiTimer=tmr.create()  
                  tmr.alarm(wifiTimer,1000,tmr.ALARM_AUTO,
                     function()
                        checkCount=checkCount+1
                        uart.write(0,".")         
                        local ip,_=wifi.sta.getip()   
                        if (ip) then -- IP address received from AP
                           print(" "..ip)
                           tmr.unregister(wifiTimer)
                           uart.write(0,"Waiting for NTP sync... ")
                           ntpSync()
                        end -- if (ip~=nil)

                        if (checkCount==10) then -- no ip address after 10 seconds
                           tmr.unregister(wifiTimer)
                           print("\n\rNo IP address after 10 seconds. Starting AP...")
                           dofile("analogClockAP.lua")
                        end -- if (checkCount==10)
                     end -- function
                  ) -- tmr.alarm(wifiTimer,1000,tmr.ALARM_AUTO,
               else
                  print("Starting Analog Clock Setup.\n\r")
                  collectgarbage()
                  dofile("analogClockSetup.lua")
               end -- if (string.byte(readSRAM(checkEERAMaddress1))==0xAA) and (string.byte(readSRAM(checkEERAMaddress2))==0x55) then
            end --if startupDelay==0
         end -- function
      ) -- tmr.alarm(initTimer,1000,tmr.ALARM_AUTO,
   end -- function
) -- tmr.alarm(startTimer,100,tmr.ALARM_SINGLE,


