-- set up an access point to allow user to select SSID and enter password if unable to connect

currentAPs = {}   -- global table of Access Point SSIDs

-- stuff the AP data into the table to be used by the web page...
function listAPs_callback(t)
  if(t==nil) then
    return
  end
  currentAPs=t
end

--return the value from the "key=value" string
function getvalue(str)
   local s=string.gsub (str,"+"," ")
   s=string.gsub (s,"\r\n", "\n")
   return s
end

function incomingData(conn,payload)
   if (string.find(payload,"GET /favicon.ico HTTP/1.1")~=nil) then
      --print("GET favicon request")
   elseif (string.find(payload,"GET / HTTP/1.1")~=nil) then
      --print("GET received")
      local page=''
      page=page..'HTTP/1.1 200 OK\r\n'
      page=page..'Content-type: text/html\r\n'
      page=page..'Server: ESP8266 NodeMCU\r\n\r\n'                
      page=page..'<!DOCTYPE HTML>'
      page=page..'<html>'
      page=page..  '<head>'
      page=page..    '<meta http-equiv="content-type" content="text/html; charset=UTF-8">'
      page=page..    '<title>Analog Clock Configuration</title>'
      page=page..  '</head>'
      page=page..  '<body>'
      page=page..    '<form method="POST" id="formid">'
      page=page..      '<table>'
      page=page..        '<tr><th>Click on an access point to connect to:</th></tr>'
      for ap,v in pairs(currentAPs) do
         page=page..     '<tr><td><input type="button" onClick=\'document.getElementById("ssid").value = "'.. ap ..'"\' value="'.. ap ..'"/></td></tr>\n'
      end
      page=page..      '</table><br/>'
      page=page..      '<table>'
      page=page..        '<tr><td><label>SSID:</label></td><td><input type="text" id="ssid" name="ssid" value=""></td></tr>'
      page=page..        '<tr><td><label>Password:</label></td><td><input type="password" id="password" name="password" value=""></td></tr>'
      page=page..      '</table><br/>'
      page=page..      'Enter values into fields and then click:&nbsp;'
      page=page..      '<input type="submit" name="reboot" value="Reboot"/>'
      page=page..    '</form>'
      page=page..  '</body>'
      page=page..'</html>'
      conn:send(page)
      
   elseif (string.find(payload,"POST / HTTP/1.1")~=nil) then  
      --print("POST received")
      --print(payload)
   end -- if (string.find(payload,"GET /favicon.ico HTTP/1.1")~=nil) then
      
  -- look for the form variables sent from the client
  local p=string.find(payload,"ssid=") -- find the first variable sent from the client
  if(p~=nil) then
     payload=string.sub(payload,p)
     --print("payload: "..payload)
     
     -- populate the args table with the form data
     args={}
     for k,v in string.gmatch(payload,"([^=&]*)=([^&]*)") do 
        args[k]=getvalue(v)
     end
      
     --print("args.ssid: "..args.ssid)
     --print("args.password: "..args.password)
     
     wifi.sta.config(args.ssid,args.password)  
     print("\nRestarting...")
     finishedTimer=tmr.create()
     tmr.alarm(finishedTimer,1000,tmr.ALARM_SINGLE,function() node.restart() end) --restart after 1 second...     
   end -- if(p~=nil) then
end -- function incomingData

-----------------------------------------------------------------------------
-- script execution starts here...
-----------------------------------------------------------------------------

-- scan for nearby APs
wifi.sta.getap(listAPs_callback)

-- start a periodic scan (every SCANINTERVAL) for other nearby APs
scanTimer=tmr.create()
tmr.alarm(scanTimer,15*1000,tmr.ALARM_AUTO,function() wifi.sta.getap(listAPs_callback) end)

-- Set up our Access Point
apNetConfig = {ip      = "192.168.4.1", -- NodeMCU seems to be hard-coded to hand out IPs in the 192.168.4.x range, so let's make sure we're there, too
               netmask = "255.255.255.0",
               gateway = "192.168.4.1"}

apSsidConfig = {}
apSsidConfig.ssid = "Analog Clock AP"

wifi.setmode(wifi.STATIONAP)
wifi.ap.config(apSsidConfig)
wifi.ap.setip(apNetConfig)

print("Connect to Analog Clock Access Point. Browse to 192.168.4.1 to enter SSID and password.")
  
-- create the web server
srv=net.createServer(net.TCP)
srv:listen(80,function(conn)
   conn:on("connection",function(conn) end)
   conn:on("reconnection",function(conn) end)   
   conn:on("receive",function(conn,payload) incomingData(conn,payload) end)
   conn:on("sent", function(conn) conn:close() end)
   conn:on("disconnection", function(conn) end)
end)
