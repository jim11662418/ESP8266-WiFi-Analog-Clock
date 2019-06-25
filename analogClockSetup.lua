-- thi script sets up a web page to allow the user to specify the starting position of the
-- analog clock's hands. this is necessary since there is no feedback of the hand's position.
-- this web page also allows the user ti specify the time zone (necessary for convertinr the UTC
-- time to local time).

ON=0    -- zero turns the LED on
OFF=1   -- one turns the LED off
GPIO0=3 -- heartbeat LED connected to GPIO0

HOUR=0           -- address in EERAM for hours
MINUTE=1         -- address in EERAM for minutes
SECOND=2         -- address in EERAM for seconds
TIMEZONE=3       -- address in EERAM for timeZone
CHECK1=4         -- address in EERAM of first check byte
CHECK2=5         -- address in EERAM of second check byte
CHECKSUM=4095    -- address in EERAM of checksum

CHUNKSIZE=1460   -- maximum bytes for "send"

-- write EERAM SRAM
function writeEERAM(address,data)
   i2c.start(id)
   i2c.address(id,0x50,i2c.TRANSMITTER)         -- 0x50 is SRAM register
   i2c.write(id,address/256,address%256,data)   -- address high byte, address low byte, data
   i2c.stop(id)
end

-- read SRAM
function readEERAM(address)
   i2c.start(id)
   i2c.address(id,0x50,i2c.TRANSMITTER)         -- 0x50 is SRAM register
   i2c.write(id,address/256,address%256)        -- address high byte, address low byte
   i2c.stop(id)
   i2c.start(id)
   i2c.address(id,0x50,i2c.RECEIVER)            -- 0x50 is control register
   data=i2c.read(0x00,1)                        -- 0x00 is address of status register
   i2c.stop(id)
   return data
end

function finishedConfig()
   print("\nRestarting...")
   node.restart()
end -- function finishedConfig

--return the value from the "key=value" string
function getvalue(str)
   local s=string.gsub (str,"+"," ")
   s=string.gsub (s,"\r\n", "\n")
   return s
end

--return the size of a file in bytes
function fileSize(filename)
   local list=file.list()
   local size=0
   for k,v in pairs(list) do
      if string.find(k,filename) ~= nil then size=v end
   end     
   return size
end

function receiver(sck,payload)
  
   local response={}
   
   -- sends and removes the first element from the 'response' table
   local function send(localSocket)
      if #response > 0 then  -- if there's anything in the tale to send
         local html=table.remove(response,1)
         localSocket:send(html)
         print("sent "..#html.." bytes")
      else
         localSocket:close()
         print("connection closed")
         response = nil
      end
   end -- local function send(localSocket)

   -- triggers the send() function again once the current chunk of data was sent
   sck:on("sent",send)
  
   if (string.find(payload,"GET /favicon.ico HTTP/1.1")) then
      print("GET favicon request")
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
      print("GET received")
      local page=[[
      HTTP/1.1 200 OK]].."\r\n"..[[
      Content-type: text/html]].."\r\n"..[[
      Server: ESP8266]].."\r\n\r\n"..[[
      <!DOCTYPE HTML>
      <html>
        <head>
          <meta content="text/html; charset=utf-8">
          <title>Analog Clock Setup</title>
        </head>
        <body>
          <form action="/" method="POST">
            <h1> Analog Clock Setup</h1>
            <p>Since the analog clock hands do not provide feedback of their position,<br>the starting position of the clock hour, minute and second hands must be specified below.<br>Do not leave any fields blank!</p>
            <ol>
              <li>Enter the current position of the hour, minute and second hands.</li>
              <li>Select the time zone.</li>
              <li>Click the "Submit" button.</li>
            </ol>
            <table>
            <tr><td><label>Hour (1-12):</label></td><td><input type="number" min="1" max="12" size="3" id="hour" name="hour" value="" required></td></tr>
            <tr><td><label>Minute (0-59):</label></td><td><input type="number" min="0" max="59" size="3" id="minute" name="minute" value="" required></td></tr>
            <tr><td><label>Second (0-59):</label></td><td><input type="number" min="0" max="59" size="3" id="second" name="second" value="" required></td></tr>
            </table><br/>
            Timezone:<br/> 
            &nbsp;<input type="radio" name="tz" value="E" checked>&nbsp;Eastern<br>
            &nbsp;<input type="radio" name="tz" value="C">&nbsp;Central<br>
            &nbsp;<input type="radio" name="tz" value="M">&nbsp;Mountain<br>
            &nbsp;<input type="radio" name="tz" value="P">&nbsp;Pacific<br>
            &nbsp;<input type="radio" name="tz" value="A">&nbsp;Alaskan<br>
            &nbsp;<input type="radio" name="tz" value="H">&nbsp;Hawaiian<br><br>
            <input type="submit" value="Submit">
          </form>
        </body>
      </html>]]        
      
      -- populate the table 'response' with CHUNKSIZE byte chunks from the string 'page' which contains the html code
      if (#page>CHUNKSIZE) then  -- if there's more than CHUNKSIZE bytes to send...
         for i=1,math.max(1,#page/CHUNKSIZE) do -- populate the elements of the table with CHUNKSIZE byte 'chunks'
            response[#response+1]=string.sub(page,((i-1)*CHUNKSIZE)+1,CHUNKSIZE+((i-1)*CHUNKSIZE))
         end      
         response[#response+1]=string.sub(page,(#page-(#page%CHUNKSIZE))+1,-1) -- add the remainder of 'page' to the last element of the table
      else
         response[1]=page -- if less than CHUNKSIZE bytes, get the whole string 'page' into the first (and only) element
      end
      
      send(sck)
      
   elseif (string.find(payload,"POST / HTTP/1.1")) then
      --print("POST received")
      --print(payload) 
      -- look for the form data in the payload from the client
      local p=string.find(payload,"hour=") -- start of the form data
      if (p~=nil) then
         payload=string.sub(payload,p)
         --print(payload)
      
         -- fill in the 'args' table from the web page form data
         args={}
         for k,v in string.gmatch(payload,"([^=&]*)=([^&]*)") do 
            args[k]=getvalue(v) 
            print(args[k]) 
         end
      
         -- write the "args" to EERAM
         writeEERAM(HOUR,tonumber(args.hour)) 
         writeEERAM(MINUTE,tonumber(args.minute)) 
         writeEERAM(SECOND,tonumber(args.second)) 
         writeEERAM(TIMEZONE,string.byte(args.tz))
         writeEERAM(CHECK1,0xAA)
         writeEERAM(CHECK2,0x55)
         writeEERAM(CHECKSUM,(tonumber(args.hour)+tonumber(args.minute)+tonumber(args.second))%256)      

         tmr.alarm(1,1000,0,function() finishedConfig() end) --restart after 1 second...
      end -- if (p~=nil) then
   end -- if (string.find(payload,"GET /favicon.ico HTTP/1.1")) then
end

-- flash the LED connected to GPIO0 (500ms on, 500ms off) to indicate waiting for configuration...
function flashLED()
   if gpio.read(GPIO0)==ON then
      gpio.write(GPIO0,OFF)
   else
      gpio.write(GPIO0,ON)
   end
end

-- set up the server
function startConfigServer()
tmr.alarm(1,500,1,function() flashLED() end)
    srv=net.createServer(net.TCP)
    srv:listen(80,function(conn)
       conn:on("connection",function(sock) end)
       conn:on("reconnection",function(sock) end)   
       conn:on("receive",function(sock,payload) receiver(sock,payload) end)
       conn:on("sent", function(sock) sock:close() end)
       conn:on("disconnection", function(sock) end)
    end)
end -- function startConfigserver()    

-- once every half second, check the wifi connection status
--wifi.sta.status:
--  0 = Idle
--  1 = Connecting
--  2 = Wrong password
--  3 = No AP found
--  4 = Connect fail
--  5 = Got IP
--255 = Not in STATION mode

timeout=30 -- 15 seconds to wait for a connection before giving up
checkStatusCount=0
function checkWiFiStatus()
   checkStatusCount=checkStatusCount+1
   print("Waiting for WiFi connection...")      
   local s=wifi.sta.status()
   if(s==5) then -- successfully connected to wifi
      tmr.stop(0)
      a,b,c=wifi.sta.getip()
      print("\nBrowse to "..a.." to setup the analog clock.")
      startConfigServer()
      return
   elseif (s==2) then 
      print("Unable to connect to WiFi. Incorrect WiFi password. restarting...")
      node.restart()
   elseif (s==3) then
      print("Unable to connect to WiFi. No AP found. restarting...")
      node.restart()
   elseif (s==4) then
      print("Unable to connect to WiFi. Connection failure. restarting...")
      node.restart()
   end
 
   if(checkStatusCount >= timeout) then -- 15 seconds has elapsed, no connection
      print("No WiFi connection after 15 seconds. restarting...")
      node.restart()
   end
end -- function checkStatus()
  
-- execution starts here...
gpio.mode(GPIO0,gpio.OUTPUT)
gpio.write(GPIO0,OFF)  

-- initialize i2c for the EERAM
sda=6 -- pin 5 on 47C04 connected to GPIO12
scl=5 -- pin 6 on 47C04 connected to GPIO14
id =0  --always zero
i2c.setup(id,sda,scl,i2c.SLOW) 

print("\n     ")
-- once each half second, check to see if we're connected to wifi...
tmr.alarm(0,500,1,function() checkWiFiStatus() end)





