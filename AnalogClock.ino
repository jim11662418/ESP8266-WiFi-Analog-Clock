//--------------------------------------------------------------------------
// Analog Clock
//
// This sketch uses an ESP8266 on a WEMOS D1 Mini board to retrieve the time 
// from an NTP server and pulse the Lavet motor on an inexpensive analog quartz
// clock to keep the clock in sync with local time. The ESP8266 stores the position 
// of the clock's hour, minute and second hands in I2C Serial EERAM.
//
// Version 2 both fixes bugs and adds support for displaying status messages on a 
// Telnet client and uploading sketches wirelessly 'Over-The-Air'.
//--------------------------------------------------------------------------

#include <TimeLib.h>
#include <ESP8266WiFi.h>
#include <NtpClientLib.h>        // https://github.com/gmag11/NtpClient
#include <Ticker.h>
#include <ESP8266WebServer.h>
#include <ArduinoOTA.h>
#include "ESPTelnet.h"           // https://github.com/LennartHennigs/ESPTelnet
#include <EERAM.h>               // https://github.com/MajenkoLibraries/EERAM/

// WEMOS D1 Mini pins
#define D0 16                    // can't use D0 to generate interrupts
#define D1  5
#define D2  4
#define D3  0                    // 10K pull-up, boot fails if pulled LOW
#define D4  2                    // 10K pull-up, boot fails if pulled LOW, BUILTIN_LED,
#define D5 14
#define D6 12
#define D7 13
#define D8 15                    // 10K pull-down, boot fails if pulled HIGH

#define SDA D1                   // output to SDA on the EERam
#define SCL D2                   // output to SCL on the EERam
#define COIL1 D3                 // output to clock's lavet motor coil
#define COIL2 D7                 // output to clock's lavet motor coil
#define REDLED D5                // output to red part of the RGB LED
#define GREENLED D4              // output to green part of the RGB LED
#define BLUELED D8               // output to blue part of the RGB LED
#define SWITCHPIN D6             // input from push button switch

#define DEBOUNCE 50              // 50 milliseconds to debounce the pushbutton switch
#define PULSETIME 30             // 30 millisecond pulse for the clock's lavet motor

#define WIFISSID "********"
#define PASSWORD "********"    

#define HOUR     0x0000          // address in EERAM for analogClkHour
#define MINUTE   HOUR+1          // address in EERAM for analogClkMinute
#define SECOND   HOUR+2          // address in EERAM for analogClkSecond
#define TIMEZONE HOUR+3          // address in EERAM for analogClktimeZone
#define CHECK1   HOUR+4          // address in EERAM for 1st check byte 0xAA
#define CHECK2   HOUR+5          // address in EERAM for 2nd check byte 0x55

//#define NTPSERVERNAME "0.us.pool.ntp.org"
  #define NTPSERVERNAME "time.nist.gov"
//#define NTPSERVERNAME "time.windows.com"
//#define NTPSERVERNAME "time.google.com"
//#define NTPSERVERNAME "time-a-g.nist.gov"   // NIST, Gaithersburg, Maryland

EERAM eeRAM;
ESPTelnet telnet;
IPAddress ip;
ESP8266WebServer analogClkServer(80);
Ticker pulseTimer,clockTimer,ledTimer;
NTPSyncEvent_t ntpEvent;                      // last NTP triggered event time
String lastSyncTime = "";
String lastSyncDate = "";
boolean syncEventTriggered = false;           // true if an NTP time sync event has been triggered
boolean printTime = false;                    // true to print NTP and clock's time
byte analogClktimeZone=0;                     // default to UTC
byte analogClkHour=0;
byte analogClkMinute=0;
byte analogClkSecond=0;
byte analogClkWeekday=0;
byte analogClkDay=0;
byte analogClkMonth=0;
byte analogClkYear=0;

void ICACHE_RAM_ATTR pinInterruptISR();     // ISR functions should be defined with ICACHE_RAM_ATTR attribute

//--------------------------------------------------------------------------
// Setup
//--------------------------------------------------------------------------
void setup() {

   //--------------------------------------------------------------------------
   // configure hardware...
   //--------------------------------------------------------------------------
   eeRAM.begin(SDA,SCL);
   pinMode(SWITCHPIN,INPUT_PULLUP);
   attachInterrupt(digitalPinToInterrupt(SWITCHPIN),pinInterruptISR,FALLING); // interrupt when pushbutton is pressed   
   pinMode(COIL1,OUTPUT);
   pinMode(COIL2,OUTPUT);
   pinMode(REDLED,OUTPUT);
   pinMode(GREENLED,OUTPUT);
   pinMode(BLUELED,OUTPUT);
   digitalWrite(COIL1,LOW);
   digitalWrite(COIL2,LOW);
   digitalWrite(REDLED,LOW);
   digitalWrite(GREENLED,LOW);
   digitalWrite(BLUELED,LOW);

   //--------------------------------------------------------------------------      
   // print the banner... 
   //--------------------------------------------------------------------------
   Serial.begin(115200);  
   unsigned long waitTime = millis()+500;
   while(millis() < waitTime)yield();                          // wait one half second for the serial port
   Serial.println("\n\nESP8266 Analog Clock");
   Serial.printf("Sketch size: %u\n",ESP.getSketchSize());
   Serial.printf("Free size: %u\n",ESP.getFreeSketchSpace());
   Serial.print(ESP.getResetReason());
   Serial.println(" Reset");

   //--------------------------------------------------------------------------
   // connect to WIFI...
   //--------------------------------------------------------------------------
   Serial.printf("Connecting to %s",WIFISSID);
   WiFi.begin(WIFISSID,PASSWORD);
   byte waitCount = 120;
   while (WiFi.status() != WL_CONNECTED) {
   waitTime = millis()+500;
   while(millis() < waitTime)yield();                          // wait one half second       
      Serial.print(".");                                       // print a '.' every half second
      if (--waitCount==0) ESP.restart();                       // if WIFI not connected after 60 seconds, restart the ESP826      
   }
   Serial.println("\nConnected");
   
   //--------------------------------------------------------------------------
   // now that we're connected to WIFI, start the web server
   //--------------------------------------------------------------------------
   analogClkServer.begin();

   //--------------------------------------------------------------------------
   // if values have previously been saved in EERAM, read hour, minute, second
   // and timezone values stored in EERAM  
   //--------------------------------------------------------------------------
   if((eeRAM.read(CHECK1)==0xAA)&&(eeRAM.read(CHECK2)==0x55)){
      Serial.println("\nReading values from EERAM.");
      analogClkHour = eeRAM.read(HOUR);
      analogClkMinute = eeRAM.read(MINUTE);
      analogClkSecond = eeRAM.read(SECOND);
      analogClktimeZone = eeRAM.read(TIMEZONE); 
      analogClkServer.on("/",clkStatus);                      // server to show clock status     
   }
   
   //--------------------------------------------------------------------------   
   // else, get hour, minute, second and timezone values from the setup web page   
   //--------------------------------------------------------------------------
   else {
      for (byte i=0;i<10;i++) {
         eeRAM.write(HOUR+i,0);                                // clear eeram     
      }
      
      Serial.printf("\nBrowse to %s to set up the analog clock.\n\r",WiFi.localIP().toString().c_str());
      analogClkServer.on("/",setupSvr);                        // server to show set-up page
      byte lastSeconds = second();
      while(true) {                                            // loop here until initial values are entered into the web page
         analogClkServer.handleClient();
         byte seconds = second();  
         if (lastSeconds != seconds) {
            lastSeconds = seconds;
            digitalWrite(BLUELED,HIGH);                        // flash the blue LED once each second while waiting for input to the web page
            ledTimer.once_ms(100,blueLEDoff);
         }
      }
   }

   //--------------------------------------------------------------------------
   // connect to the NTP server...
   //--------------------------------------------------------------------------
   NTP.begin(NTPSERVERNAME,-analogClktimeZone,true);           // start the NTP client
   NTP.setDSTZone(DST_ZONE_USA);                               // use US rules for switching between standard and daylight saving time
   NTP.setDayLight(true);                                      // yes to daylight saving time   
   NTP.onNTPSyncEvent([](NTPSyncEvent_t event){ntpEvent=event;syncEventTriggered=true;});
   NTP.setInterval(10,60*10);                                  // update every 10 minutes 

   waitCount = 120;
   Serial.print("Waiting for sync with NTP server");   
   while (timeStatus() != timeSet) {                           // wait until the the time is set and synced
      waitTime = millis()+500;
      while(millis() < waitTime)yield();                       // wait one half second       
      Serial.print(".");                                       // print a '.' every half second
      if (--waitCount==0) ESP.restart();                       // if time is not set and synced after 60 seconds, restart the ESP8266
   }    

   Serial.println("\nTime is set.");
      
   analogClkWeekday=weekday();                                 // initialize values
   analogClkDay=day();
   analogClkMonth=month();
   analogClkYear=year()-1970;   
     
   //--------------------------------------------------------------------------   
   // start up the Telnet server...   
   //--------------------------------------------------------------------------
   telnet.onConnect(onTelnetConnect);
   telnet.onDisconnect(onTelnetDisconnect);
   if (telnet.begin(23,false))
      Serial.println("Telnet is running.");
   else
      Serial.println("Telnet error");

   //--------------------------------------------------------------------------   
   // start up Arduino OTA... 
   //--------------------------------------------------------------------------
   ArduinoOTA.onStart([]() {
     Serial.println(F("Start"));
   });
   ArduinoOTA.onEnd([]() {
     Serial.println(F(" \r\nEnd"));
   });
   ArduinoOTA.onProgress([](unsigned int progress, unsigned int total) {
     Serial.printf("Progress: %u%%\r", (progress/(total/100)));
   });
   ArduinoOTA.onError([](ota_error_t error) {
     Serial.printf("Error[%u]: ", error);
     if (error == OTA_AUTH_ERROR) Serial.println(F("Auth Failed"));
     else if (error == OTA_BEGIN_ERROR) Serial.println(F("Begin Failed"));
     else if (error == OTA_CONNECT_ERROR) Serial.println(F("Connect Failed"));
     else if (error == OTA_RECEIVE_ERROR) Serial.println(F("Receive Failed"));
     else if (error == OTA_END_ERROR) Serial.println(F("End Failed"));
   });
   ArduinoOTA.begin();

   //--------------------------------------------------------------------------   
   // lastly, start up 100 millisecond timer used to advance the analog clock's second hand
   //--------------------------------------------------------------------------
   clockTimer.attach_ms(100,checkClock);                       
}

//--------------------------------------------------------------------------
// Main Loop
//--------------------------------------------------------------------------
void loop() {
    static byte lastSeconds=0; 

    telnet.loop();                                             // telnet server
    
    ArduinoOTA.handle();                                       // over-the-air updates

    // flash the green LED once per second
    byte secs = second();  
    if (lastSeconds != secs) {
       lastSeconds = secs;                
       digitalWrite(GREENLED,HIGH);                            // turn on the green LED       
       ledTimer.once_ms(100,greenLEDoff);                      // turn off the green LED after 100 milliseconds
    }

    // if the clock's second hand has moved...
    if (printTime) {                                           // when the analog clock is updated...
       printTime = false;       
       // print NTP time and analog clock time
       char timeStr[24];
       sprintf(timeStr,"%02d:%02d:%02d    %02d:%02d:%02d",hour(),minute(),second(),analogClkHour,analogClkMinute,analogClkSecond);
       Serial.println(timeStr);              
       telnet.println(timeStr);        
    }

    // handle requests from the web server  
    analogClkServer.handleClient();                            // handle requests from status web page

    // process any NTPs events
    if (syncEventTriggered) {                                  // if an NTP time sync event has occured...
       processSyncEvent(ntpEvent);
       syncEventTriggered = false;
    }
}

//------------------------------------------------------------------------
// Ticker callbacks that turns off the LEDs after 100 milliseconds.
//-------------------------------------------------------------------------
void blueLEDoff(){
   digitalWrite(BLUELED,LOW);                          
}

void greenLEDoff(){
   digitalWrite(GREENLED,LOW);                          
}

//--------------------------------------------------------------------------
// pulse the clock's Lavet motor to advance the clock's second hand.
// The Lavet motor requires polarized control pulses. If the control pulses are inverted,
// the clock appears to run one second behind. To remedy the problem, invert the polarity
// of the control pulses. This is easily done by exchanging the wires connecting the Lavet motor.
//--------------------------------------------------------------------------
void pulseCoil() {
   if ((analogClkSecond%2)==0){                 // positive motor pulse on even seconds
      digitalWrite(COIL1,HIGH);
      digitalWrite(COIL2,LOW);
   }
   else {                                       // negative motor pulse on odd seconds
      digitalWrite(COIL1,LOW);
      digitalWrite(COIL2,HIGH);
   }
   pulseTimer.once_ms(PULSETIME,pulseOff);      // turn off pulse after 30 milliseconds...
}

//------------------------------------------------------------------------
// Ticker callback that turns off the pulse to the analog clock Lavet motor
// after 30 milliseconds.
//-------------------------------------------------------------------------
void pulseOff() {
   digitalWrite(COIL1,LOW);
   digitalWrite(COIL2,LOW);
}

//--------------------------------------------------------------------------
// Ticker callback runs every 100 milliseconds to check if the analog clock's 
// second hand needs to be advanced.
//--------------------------------------------------------------------------
void checkClock() {
   static byte lastSeconds = 0;  
   
   time_t analogClkTime = makeTime({analogClkSecond,analogClkMinute,analogClkHour,analogClkWeekday,analogClkDay,analogClkMonth,analogClkYear});
   if (analogClkTime < now()) {                    // if the analog clock is behind the actual time and needs to be advanced...
      pulseCoil();                                 // pulse the motor to advance the analog clock's second hand
      if (++analogClkSecond==60){                  // since the clock motor has been pulsed, increase the seconds count
         analogClkSecond=0;                        // at 60 seconds, reset analog clock's seconds count back to zero
         if (++analogClkMinute==60) {
             analogClkMinute=0;                    // at 60 minutes, reset analog clock's minutes count back to zero
             if (++analogClkHour==24) {
                 analogClkHour=0;                  // at 24 hours, reset analog clock's hours count back to zero
                 analogClkWeekday=weekday();       // update values
                 analogClkDay=day();
                 analogClkMonth=month();
                 analogClkYear=year()-1970;   
             }
         }
      }
      eeRAM.write(HOUR,analogClkHour);             // save the new values in eeRAM
      eeRAM.write(MINUTE,analogClkMinute);
      eeRAM.write(SECOND,analogClkSecond); 
      printTime = true;                            // set flag to update display
  } // if (analogClkTime<now())   
  
  // this part was added so that the times are printed when the analog clock's hands are stopped waiting for the NTP time to catch up
  byte secs = second();  
  if (lastSeconds != secs) {                       // when the second changes...
      lastSeconds = secs;                          // save for next time 
      printTime = true;                            // set flag to print new time if NTP seconds has changed
  }  
}

//--------------------------------------------------------------------------
// Handles requests to display analog clock status.
//--------------------------------------------------------------------------
void clkStatus() {
   char timeStr[10];
   sprintf(timeStr,"%02d:%02d:%02d", analogClkHour,analogClkMinute,analogClkSecond);
   analogClkServer.send(200, "text/html",
   "<!DOCTYPE HTML>"
   "<html>"
     "<head>"
       "<META HTTP-EQUIV=\"refresh\" CONTENT=\"1\">"
       "<meta content=\"text/html; charset=utf-8\">"
       "<title> ESP8266 Analog Clock </title>"
     "</head>"
     "<body style=\"background-color:lightgrey;\">"
       "<h1>Analog Clock&nbsp;&nbsp;"+String(timeStr)+"</h1>"
       "<p>Uptime: "+NTP.getUptimeString()+"</p>"
       "<p>Last NTP sync at "+lastSyncTime+" on "+lastSyncDate+"</p>"
     "</body>"
   "</html>");
}

//--------------------------------------------------------------------------
// Handles requests to initialize analog clock 
// hour, minute, second and timezone values.
//--------------------------------------------------------------------------
 void setupSvr() {
   analogClkServer.send(200, "text/html",
   "<!DOCTYPE HTML>"
   "<html>"
     "<head>"
       "<meta content=\"text/html; charset=utf-8\">"
       "<title>Analog Clock Setup</title>"
     "</head>"
     "<body>"
       "<form action=\"/\" method=\"POST\">"
       "<h1> Analog Clock Setup</h1>"
       "<p>Since the analog clock hands do not provide feedback of their position, you must specify<br>the starting position of the clock hour, minute and second hands. Do not leave any fields blank!</p>"
       "<ol>"
         "<li>Enter the current position of the hour, minute and second hands.</li>"
         "<li>Select your time zone.</li>"
         "<li>Click the \"Submit\" button.</li>"
       "</ol>"
       "<table>"
         "<tr><td><label>Hour   (0-23):</label></td><td><input type=\"number\" min=\"0\" max=\"23\" size=\"3\" name=\"hour\"   value=\"\"></td></tr>"
         "<tr><td><label>Minute (0-59):</label></td><td><input type=\"number\" min=\"0\" max=\"59\" size=\"3\" name=\"minute\" value=\"\"></td></tr>"
         "<tr><td><label>Second (0-59):</label></td><td><input type=\"number\" min=\"0\" max=\"59\" size=\"3\" name=\"second\" value=\"\"></td></tr>"
       "</table><br>"
       "Timezone:<br>"
       "&nbsp;<input type=\"radio\" name=\"timezone\" value=\"E\" checked>&nbsp;Eastern<br>"
       "&nbsp;<input type=\"radio\" name=\"timezone\" value=\"C\">&nbsp;Central<br>"
       "&nbsp;<input type=\"radio\" name=\"timezone\" value=\"M\">&nbsp;Mountain<br>"
       "&nbsp;<input type=\"radio\" name=\"timezone\" value=\"P\">&nbsp;Pacific<br><br>"
       "<input type=\"submit\" value=\"Submit\">"
       "</form>"
     "</body>"
   "</html>");  
    
   if (analogClkServer.hasArg("hour")&&analogClkServer.hasArg("minute")&&analogClkServer.hasArg("second")&&analogClkServer.hasArg("timezone")) {
      String hourValue = analogClkServer.arg("hour");
      analogClkHour = hourValue.toInt();
      String minuteValue = analogClkServer.arg("minute");
      analogClkMinute = minuteValue.toInt();  
      String secondValue = analogClkServer.arg("second");
      analogClkSecond = secondValue.toInt();
      String zoneValue = analogClkServer.arg("timezone");
      switch(zoneValue[0]) {
         case 'E': analogClktimeZone = 5;  // Eastern Standard Time 5 hours after UTC
                   break;
         case 'C': analogClktimeZone = 6;  // Central Standard Time 6 hours after UTC
                   break;        
         case 'M': analogClktimeZone = 7;  // Mountain Standard Time 7 hours after UTC
                   break;        
         case 'P': analogClktimeZone = 8;  // Pacific Standard Time 8 hours after UTC
                   break;        
         default:  analogClktimeZone = 5;  // EST
      }

      // save the updated values in EERAM...     
      eeRAM.write(HOUR,analogClkHour); 
      eeRAM.write(MINUTE,analogClkMinute);
      eeRAM.write(SECOND,analogClkSecond);      
      eeRAM.write(TIMEZONE,analogClktimeZone);     
      eeRAM.write(CHECK1,0xAA);
      eeRAM.write(CHECK2,0x55);
      ESP.restart();                                           // restart the ESP8266         
   }
}

//--------------------------------------------------------------------------
// NTP event handler
//--------------------------------------------------------------------------
void processSyncEvent(NTPSyncEvent_t ntpEvent) {

  if (ntpEvent) {
     if (ntpEvent == noResponse) {
        Serial.println("Time Sync error: NTP server not reachable");
        telnet.println("Time Sync error: NTP server not reachable");
     }
     else if (ntpEvent == invalidAddress) {
        Serial.println("Time Sync error: Invalid NTP server address");
        telnet.println("Time Sync error: Invalid NTP server address");
     }
  }
  else {
     lastSyncTime = NTP.getTimeStr(NTP.getLastNTPSync());
     lastSyncDate = NTP.getDateStr(NTP.getLastNTPSync());
     Serial.println("Got NTP time: "+lastSyncTime+"  "+lastSyncDate);
     
     if (NTP.isSummerTime()) 
        Serial.println("Daylight Saving Time in effect.");
     else  
        Serial.println("Standard Time in effect.");
    
     telnet.print("Got NTP time: "+lastSyncTime+"  "+lastSyncDate);
     if (NTP.isSummerTime()) 
        telnet.println("Daylight Saving Time in effect.");
     else  
        telnet.println("Standard Time in effect.");
  }
}

//--------------------------------------------------------------------------
// (optional) callback functions for Telnet events
//--------------------------------------------------------------------------
void onTelnetConnect(String ip) {
  Serial.println("Telnet: "+ip+" connected");
  telnet.println("\nWelcome " +ip);
}

void onTelnetDisconnect(String ip) {
  Serial.println("Telnet: "+ip+" disconnected");
}  

//--------------------------------------------------------------------------
// interrupt when the push button switch is pressed. clear EERAM and restart
// the ESP8266. this forces the user to re-enter the values for clock's
// hour, minute, second and timezone.
//--------------------------------------------------------------------------
void ICACHE_RAM_ATTR pinInterruptISR() {                    // ISR functions should be defined with ICACHE_RAM_ATTR...
   unsigned long debounce_time = millis()+DEBOUNCE;
   while(millis() < debounce_time);                         // wait 50 milliseconds for the switch contacts to stop bouncing
   for (byte i=0;i<10;i++) {
      eeRAM.write(HOUR+i,0);                                // clear eeram     
   }   
   ESP.restart();                                           // restart the ESP8266
}
