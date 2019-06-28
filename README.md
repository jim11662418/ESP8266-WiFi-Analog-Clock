# ESP8266 WiFi Analog Clock
## Introduction
This project uses an ESP8266 module and a [NodeMCU Lua](https://nodemcu.readthedocs.io/en/master/) script to connect to a NTP (Network Time Protocol) server to automatically retrieve and display the local time on a inexpensive analog quartz clock. The ESP8266 reconnects to the NTP server every 15 minutes which keeps the clock accurate. The clock also automatically adjusts for daylight savings time.
<p align="center"><img src="/images/Analog%20Clock.jpeg"/>
<p align="center">Analog Clock</p>

## Hardware
I found an analog clock with a quartz movement found at my local Walmart for $3.88. Whatever analog clock you decide to use, its quartz movement will need to be modified so that it can be controlled by the ESP8266 module. Open up the movement (most of them snap together without any fasteners), disconnect the internal coil of the Lavet stepping motor from its quartz oscillator and then solder a wire to each of the coil's leads to make connections for the ESP8266. If you search around on the web you'll find articles showing how others have done it. Be careful when working with the coil. The coil's wires are typically thinner than a human hair and extremely fragile.
<p align="center"><img src="/images/Clock%20Movement.jpeg"/>
<p align="center">Modified Clock Movement</p>

## Software
Once the modifications to your analog clock's mechanism are done, you should run tictock.lua and quickpulse.lua, which advance the analog clock's second hand once and ten times per second respectively to check your work. Your particular clock may require you to experiment with the value of the  PULSETIME constant to make the second hand advance reliably.

The biggest problem with using these cheap analog clocks for a project like this is that the clocks don't provide any type of feedback to indicate the position of the clock's hands.  To get around this problem, the positions of the hour, minute and second hands are stored in a [Microchip 47L04 EERAM](https://www.microchip.com/wwwproducts/en/47C04) (4Kbit SRAM with EEPROM backup) and updated each second as the clock's hands positions change. The first time that the script is run, the user will be directed to a simple web page served by the ESP8266 which is used to tell it where the analog clock's hands are initially positioned. From that point on, the ESP8266 will use the data stored in the EERAM to "remember" the positions of the clock's hands.
<p align="center"><img src="/images/analogClockSetup.jpg"/>
<p align="center">Analog Clock Setup</p>
