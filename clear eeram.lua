
-- write SRAM
function writeSRAM(address,data)
   i2c.start(id)
   i2c.address(id,0x50,i2c.TRANSMITTER)         -- 0x50 is SRAM register
   i2c.write(id,address/256,address%256,data)   -- address high byte, address low byte, data
   i2c.stop(id)
end

-- initialize i2c for the EERAM
sda=6 -- pin 5 on 47C04 connected to GPIO12
scl=5 -- pin 6 on 47C04 connected to GPIO14
id =0  --always zero
i2c.setup(id,sda,scl,i2c.SLOW) 

for high=0,15 do
   print("page 0x"..string.format("%02X",high))
   for low=0,15 do
      tmr.wdclr()
      for i=0,15 do
         writeSRAM((high*256)+((low*16)+i),0)
      end
   end
end

