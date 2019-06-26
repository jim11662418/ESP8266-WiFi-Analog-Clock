-- "Pulse" the clock motor coil once each second.
-- It may be necessary to experiment with different values of PULSETIME
-- to make the second advance reliably.

-- GPIO0  = 3	
-- GPIO1  = 10 (TX)
-- GPIO2  = 4	
-- GPIO3  = 9  (RX)
-- GPIO4  = 2	
-- GPIO5  = 1	
-- GPIO9  = 11
-- GPIO10 = 12
-- GPIO12 = 6		
-- GPIO13 = 7	
-- GPIO14 = 5		
-- GPIO15 = 8
-- GPIO16 = 0	

GPIO2 = 4           -- use GPIO2 output for one side of the coil
GPIO13= 7           -- use GPIO3 output for the other side of the coil
GPIO0 = 3           -- use GPIO0 output for heartbeat LED
ONESECOND = 1000    -- 1000 milliseconds/second
PULSETIME = 30     -- 30 millisecond length of clock pulse (minimum 33, maximum 47)
ON = 0
OFF = 1
POS = 0
NEG = 1

isPositive = false

function tick()
    if (isPositive==true) then  -- for positive pulses...
       gpio.write(GPIO2,POS)   -- make this side high
       gpio.write(GPIO13,NEG)   -- make this side low
       gpio.write(GPIO0,ON)     -- turn on the LED
       print("tick")       
       tmr.alarm(6,PULSETIME,0,function() 
          gpio.write(GPIO2,NEG) -- return the high side to low
          gpio.write(GPIO0,OFF)  -- turn off the LED          
       end) --function()
    else                        -- for negative pulses
       gpio.write(GPIO13,POS)   -- make this side low
       gpio.write(GPIO2,NEG)   -- make this side high
       gpio.write(GPIO0,ON)     -- turn on the LED              
       print("tock")
       tmr.alarm(6,PULSETIME,0,function() 
          gpio.write(GPIO13,NEG) -- return the high side to low
          gpio.write(GPIO0,OFF)  -- turn off the LED
       end) -- function()
    end -- if
    isPositive = not isPositive
end  -- function tick()

-- Execution starts here...
gpio.mode(GPIO2,gpio.OUTPUT)
gpio.mode(GPIO13,gpio.OUTPUT)
gpio.write(GPIO2,NEG)          -- start out with both sides of the coil low 
gpio.write(GPIO13,NEG)        

gpio.mode(GPIO0,gpio.OUTPUT)
gpio.write(GPIO0,OFF)    -- "1" turns the LED off

tmr.alarm(0,ONESECOND,1,function() tick() end) -- pulse the clock motor once every second         

