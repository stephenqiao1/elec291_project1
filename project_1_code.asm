$NOLIST
$MODLP51RC2
$LIST

;-------------------------------------------------------------------------------------------------------------------------------
;These EQU must match the wiring between the microcontroller and ADC
CLK  EQU 22118400
TIMER1_RATE    EQU 22050     ; 22050Hz is the sampling rate of the wav file we are playing
TIMER1_RELOAD  EQU 0x10000-(SYSCLK/TIMER1_RATE)
BAUD equ 115200
BRG_VAL equ (0x100-(CLK/(16*BAUD)))

TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU (65536-(CLK/TIMER2_RATE))


;-------------------------------------------------------------------------------------------------------------------------------
;Button Pin Mapping
NEXT_STATE_BUTTON  equ P0.5
STIME_BUTTON    equ P0.2
STEMP_BUTTON    equ P0.3
RTIME_BUTTON    equ P0.4
RTEMP_BUTTON    equ P0.6
POWER_BUTTON    equ P4.5
SHIFT_BUTTON    equ p0.0

;Output Pins
OVEN_POWER      equ P0.7
SPEAKER         equ P2.6
;FLASH_CE        equ P0.

;Thermowire Pins
CE_ADC    EQU  P1.7
MY_MOSI   EQU  P1.6
MY_MISO   EQU  P1.5
MY_SCLK   EQU  P1.4 

; These 'equ' must match the hardware wiring
LCD_RS equ P3.2
;LCD_RW equ PX.X ; Not used in this code, connect the pin to GND
LCD_E  equ P3.3
LCD_D4 equ P3.4
LCD_D5 equ P3.5
LCD_D6 equ P3.6
LCD_D7 equ P3.7

;-------------------------------------------------------------------------------------------------------------------------------

org 0x0000
    ljmp main

; External interrupt 0 vector (not used in this code)
org 0x0003
	reti

; Timer/Counter 0 overflow interrupt vector
org 0x000B
	reti

; External interrupt 1 vector (not used in this code)
org 0x0013
	reti

; Timer/Counter 1 overflow interrupt vector
org 0x001B
	ljmp Timer1_ISR

; Serial port receive/transmit interrupt vector (not used in this code)
org 0x0023 
	reti
	
; Timer/Counter 2 overflow interrupt vector
org 0x002B
    ljmp Timer2_ISR
;-------------------------------------------------------------------------------------------------------------------------------
; Place our variables here
DSEG at 0x30 ; Before the state machine!
Count1ms:         ds 2 ; Used to determine when one second has passed
States:           ds 1
Temp_soak:        ds 1
Time_soak:        ds 1
Temp_refl:        ds 1
Time_refl:        ds 1
Run_time_seconds: ds 1
Run_time_minutes: ds 1
State_time:       ds 1
Temp_oven:        ds 1
x:                ds 4
y:                ds 4
bcd:              ds 5
Result:           ds 2
w:                ds 3

$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

$NOLIST
$include(math32.inc)
$LIST



bseg
one_seconds_flag: dbit 1
enable_clk:       dbit 1
mf:               dbit 1

cseg

;-------------------------------------------------------------------------------------------------------------------------------
;***Messages To Display*** 

;shortened labels
STemp:  db 'STmp:', 0
STime:  db 'STm:', 0
RTemp:  db 'RTmp:', 0
RTime:  db 'RTm:', 0

;lables for runnning oven
state:     db 'State:' , 0
time:      db 'Tme:' , 0
colon:     db ':', 0
temp:      db 'Tmp:', 0

;labels for changin parameters
ReflowTemp:  db 'Reflow Temperature:', 0
ReflowTime:  db 'Reflow Time:', 0
SoakTime:    db 'Soak Time:', 0
SoakTemp:    db 'Soak Temperature:', 0


;Current State in Oven
Ramp2Soak: db 'Ramp-Soak' , 0
Soak:      db 'Soak' , 0
Ramp2Peak: db 'Ramp-Peak' , 0
Reflow:    db 'Reflow' , 0
Cooling:   db 'Cooling' , 0

;-------------------------------------------------------------------------------------------------------------------------------
;FXNS FOR THERMOWIRE

;initialize SPI 
INI_SPI:
	setb MY_MISO ; Make MISO an input pin
	clr MY_SCLK           ; Mode 0,0 default
	ret
DO_SPI_G:
	push acc
	mov R1, #0 ; Received byte stored in R1
	mov R2, #8            ; Loop counter (8-bits)
DO_SPI_G_LOOP:
	mov a, R0             ; Byte to write is in R0
	rlc a                 ; Carry flag has bit to write
	mov R0, a
	mov MY_MOSI, c
	setb MY_SCLK          ; Transmit
	mov c, MY_MISO        ; Read received bit
	mov a, R1             ; Save received bit in R1
	rlc a
	mov R1, a
	clr MY_SCLK
	djnz R2, DO_SPI_G_LOOP
	pop acc
	ret

Send_SPI:
	SPIBIT MAC
	    ; Send/Receive bit %0
		rlc a
		mov MY_MOSI, c
		setb MY_SCLK
		mov c, MY_MISO
		clr MY_SCLK
		mov acc.0, c
	ENDMAC
	
	SPIBIT(7)
	SPIBIT(6)
	SPIBIT(5)
	SPIBIT(4)
	SPIBIT(3)
	SPIBIT(2)
	SPIBIT(1)
	SPIBIT(0)

ret

Change_8bit_Variable MAC
    jb %0, %2
    Wait_Milli_Seconds(#50) ; de-bounce
    jb %0, %2
    jnb %0, $
    jb SHIFT_BUTTON, skip%Mb
    dec %1
    sjmp skip%Ma
    skip%Mb:
    inc %1
    skip%Ma:
ENDMAC

;Change_8bit_Variable(MY_VARIABLE_BUTTON, my_variable, loop_c)
;    Set_Cursor(2, 14)
;    mov a, my_variable
;    lcall SendToLCD
;lcall Save_Configuration

;-------------------------------------------------------------------------------------------------------------------------------
;***FXNS For Serial Port

; Configure the serial port and baud rate
InitSerialPort:
    ; Since the reset button bounces, we need to wait a bit before
    ; sending messages, otherwise we risk displaying gibberish!
    mov R1, #222
    mov R0, #166
    djnz R0, $   ; 3 cycles->3*45.21123ns*166=22.51519us
    djnz R1, $-4 ; 22.51519us*222=4.998ms
    ; Now we can proceed with the configuration
	orl	PCON,#0x80
	mov	SCON,#0x52
	mov	BDRCON,#0x00
	mov	BRL,#BRG_VAL
	mov	BDRCON,#0x1E ; BDRCON=BRR|TBCK|RBCK|SPD;
ret


putchar:
    jnb TI, putchar
    clr TI
    mov SBUF, a
ret

;-------------------------------------------------------------------------------------------------------------------------------
;***FXNS to CHECK BUTTONS

CHECK_STIME:

    ;jb STIME_BUTTON, CHECK_STIME_END ; if button not pressed, stop checking
	;Wait_Milli_Seconds(#50) ; debounce time
	;jb STIME_BUTTON, CHECK_STIME_END ; if button not pressed, stop checking
	;jnb STIME_BUTTON, $ ; loop while the button is pressed
    
    ;inc Time_soak

    ;mov a, Time_soak ;increment STime by 1
    ;add a, #0x01
    ;da a
    ;mov Time_soak, a
    ;cjne a, #0x5B, CHECK_STIME_END
    ;mov Time_soak, #0x3C
    ;lcall Save_Configuration

    Change_8bit_Variable(STIME_BUTTON, Time_soak, CHECK_STIME_END)
    ;mov a, Time_soak
    ;lcall SendToLCD
    ;lcall Save_Configuration
	
CHECK_STIME_END:
ret

CHECK_STEMP:

    ;jb STEMP_BUTTON, CHECK_STEMP_END ; if button not pressed, stop checking
	;Wait_Milli_Seconds(#50) ; debounce time
	;jb STEMP_BUTTON, CHECK_STEMP_END ; if button not pressed, stop checking
	;jnb STEMP_BUTTON, $ ; loop while the button is pressed
    
    ;mov a, Temp_soak ;increment STEMP by 5
    ;add a, #5
    ;da a
    ;mov Temp_soak, a
    ;cjne a, #175, CHECK_STEMP_END
    ;mov Temp_soak, #130

    Change_8bit_Variable(STEMP_BUTTON, Temp_soak, CHECK_STEMP_END)
    ;lcall Save_Configuration
	
CHECK_STEMP_END:
ret

CHECK_RTIME:

    ;jb RTIME_BUTTON, CHECK_RTIME_END ; if button not pressed, stop checking
	;Wait_Milli_Seconds(#50) ; debounce time
	;jb RTIME_BUTTON, CHECK_RTIME_END ; if button not pressed, stop checking
	;jnb RTIME_BUTTON, $ ; loop while the button is pressed
    
    ;mov a, Time_refl ;increment RTime by 1
    ;add a, #0x01
    ;da a
    ;mov Time_refl, a
    ;cjne a, #0x3D, CHECK_RTIME_END
    ;mov Time_refl, #0x1E
    ;lcall Save_Configuration
	Change_8bit_Variable(RTIME_BUTTON, Time_refl, CHECK_RTIME_END)

CHECK_RTIME_END:
ret

CHECK_RTEMP:

    ;jb RTEMP_BUTTON, CHECK_RTEMP_END ; if button not pressed, stop checking
	;Wait_Milli_Seconds(#50) ; debounce time
	;jb RTEMP_BUTTON, CHECK_RTEMP_END ; if button not pressed, stop checking
	;jnb RTEMP_BUTTON, $ ; loop while the button is pressed
    
    ;mov a, Temp_refl ;increment RTemp by 5
    ;add a, #5
    ;da a
    ;mov Temp_refl, a
    ;cjne a, #255, CHECK_RTEMP_END
    ;mov Temp_refl, #220
    ;lcall Save_Configuration

    Change_8bit_Variable(RTEMP_BUTTON, Temp_refl, CHECK_RTEMP_END)
	
CHECK_RTEMP_END:
ret

CHECK_POWER:

    jb POWER_BUTTON, CHECK_POWER_END ; if button not pressed, stop checking
	Wait_Milli_Seconds(#50) ; debounce time
	jb POWER_BUTTON, CHECK_POWER_END ; if button not pressed, stop checking
	jnb POWER_BUTTON, $ ; loop while the button is pressed
    lcall OFF_STATE

CHECK_POWER_END:
ret

;-------------------------------------------------------------------------------------------------------------------------------
;***LCD FXNS

SendToLCD:
    mov b, #100
    div ab
    orl a, #0x30h ; Convert hundreds to ASCII
    lcall ?WriteData ; Send to LCD
    mov a, b    ; Remainder is in register b
    mov b, #10
    div ab
    orl a, #0x30h ; Convert tens to ASCII
    lcall ?WriteData; Send to LCD
    mov a, b
    orl a, #0x30h ; Convert units to ASCII
    lcall ?WriteData; Send to LCD
ret

;The following functions store and restore the values--------------------------------------------------------------------------
loadbyte mac
    mov a, %0
    movx @dptr, a
    inc dptr
endmac

Save_Configuration:
    mov FCON, #0x08 ; Page Buffer Mapping Enabled (FPS = 1)
    mov dptr, #0x7f80 ; Last page of flash memory
; Save variables
    loadbyte(Temp_soak) ; @0x7f80
    loadbyte(Time_soak) ; @0x7f81
    loadbyte(Temp_refl) ; @0x7f82
    loadbyte(Time_refl) ; @0x7f83
    loadbyte(#0x55) ; First key value @0x7f84
    loadbyte(#0xAA) ; Second key value @0x7f85
    mov FCON, #0x00 ; Page Buffer Mapping Disabled (FPS = 0)
    orl EECON, #0b01000000 ; Enable auto-erase on next write sequence
    mov FCON, #0x50 ; Write trigger first byte
    mov FCON, #0xA0 ; Write trigger second byte
; CPU idles until writing of flash completes.
    mov FCON, #0x00 ; Page Buffer Mapping Disabled (FPS = 0)
    anl EECON, #0b10111111 ; Disable auto-erase
ret

getbyte mac
    clr a
    movc a, @a+dptr
    mov %0, a
    inc dptr
endmac

Load_Configuration:
    mov dptr, #0x7f84 ; First key value location.
    getbyte(R0) ; 0x7f84 should contain 0x55
    cjne R0, #0x55, Load_Defaults
    getbyte(R0) ; 0x7f85 should contain 0xAA
    cjne R0, #0xAA, Load_Defaults
; Keys are good.  Get stored values.
    mov dptr, #0x7f80
    getbyte(Temp_soak) ; 0x7f80
    getbyte(Time_soak) ; 0x7f81
    getbyte(Temp_refl) ; 0x7f82
    getbyte(Time_refl) ; 0x7f83
ret

Load_Defaults:
    mov Temp_soak, #130 ; Soak Tmp Range is 130-170
    mov Time_soak, #0x3C ; Range 60-90 seconds
    mov Temp_refl, #220 ; Range 220-245
    mov Time_refl, #0x1E ; Range 30-60 seconds
    ret 
;-------------------------------------------------------------------------------------------------------------------------------
;off state

OFF_STATE:
    ;**CLEAR SCREEN**
    WriteCommand(#0x01)

    ;OFF_STATE1:
    
    jb POWER_BUTTON, $ ; loop while the button is not pressed
	Wait_Milli_Seconds(#50) ; debounce time
	jb POWER_BUTTON, OFF_STATE ; it was a bounce, try again
	jnb POWER_BUTTON, $ ; loop while the button is pressed
    ;Wait_Milli_Seconds(#250)
    ;Wait_Milli_Seconds(#250)
    ;Wait_Milli_Seconds(#250)
    ;Wait_Milli_Seconds(#250)
    ;Wait_Milli_Seconds(#250)
    ;Wait_Milli_Seconds(#250)
    ;Wait_Milli_Seconds(#250)
    ;Wait_Milli_Seconds(#250)
    ;Wait_Milli_Seconds(#250)
    ;Wait_Milli_Seconds(#250)
    ;Wait_Milli_Seconds(#250)
    ;Wait_Milli_Seconds(#250)

    ljmp main
    ret
;-------------------------------------------------------------------------------------------------------------------------------

;***CHECK TEMPERATURE BY READING VOLTAGE AND CONVERTING
Check_Temp:
    clr CE_ADC
	mov R0, #00000001B ; Start bit:1
	lcall DO_SPI_G
	mov R0, #10000000B ; Single ended, read channel 0
	lcall DO_SPI_G
	mov a, R1          ; R1 contains bits 8 and 9
	anl a, #00000011B  ; We need only the two least significant bits
	mov Result+1, a    ; Save result high.
	mov R0, #55H ; It doesn't matter what we transmit...
	lcall DO_SPI_G
	mov Result, R1     ; R1 contains bits 0 to 7.  Save result low.
	setb CE_ADC
	
    ; Copy the 10-bits of the ADC conversion into the 32-bits of 'x'
	mov x+0, result+0
	mov x+1, result+1
	mov x+2, #0
	mov x+3, #0
	
    ;conversion from voltage to temperature unit
    load_Y(1000)
    lcall mul32
    load_Y(41)
    lcall div32
    
	; The 4-bytes of x have the temperature in binary
	lcall hex2bcd ; converts binary in x to BCD in BCD

	Send_BCD(bcd)
	mov a, #'\r'
	lcall putchar
	mov a, #'\n'
	lcall putchar
	pop acc
    ret
    

State0_display:
    Set_Cursor(1, 1)
    Send_Constant_String(#STemp)
    Set_Cursor(1, 6)
    mov a, Temp_soak
    lcall SendToLCD
    
    Set_Cursor(1,10)
    Send_Constant_String(#STime)
    Set_Cursor(1, 14)
    mov a, Time_soak
	lcall SendToLCD
    ;Display_BCD(Time_soak)

    ;Displays Reflow Temp and Time
    Set_Cursor(2,1)
    Send_Constant_String(#RTemp)
    Set_Cursor(2,6)
    mov a, Temp_refl
    lcall SendToLCD
    
    Set_Cursor(2,10)
    Send_Constant_String(#RTime)
    Set_Cursor(2, 14)
    mov a, Time_refl
	lcall SendToLCD
ret
;-------------------------------------------------------------------------------------------------------------------------------

;Time wait

Wait_One_Second:
    Wait_Milli_Seconds(#250)
    Wait_Milli_Seconds(#250)
    Wait_Milli_Seconds(#250)
    Wait_Milli_Seconds(#250)
ret

; ==================================================================================================

;-------------------------------------;
; ISR for Timer 1.  Used to playback  ;
; the WAV file stored in the SPI      ;
; flash memory.                       ;
;-------------------------------------;
Timer1_ISR:
	; The registers used in the ISR must be saved in the stack
	push acc
	push psw
	
	; Check if the play counter is zero.  If so, stop playing sound.
	mov a, w+0
	orl a, w+1
	orl a, w+2
	jz stop_playing
	
	; Decrement play counter 'w'.  In this implementation 'w' is a 24-bit counter.
	mov a, #0xff
	dec w+0
	cjne a, w+0, keep_playing
	dec w+1
	cjne a, w+1, keep_playing
	dec w+2
	
keep_playing:
	setb SPEAKER
	lcall Send_SPI ; Read the next byte from the SPI Flash...
	mov P0, a ; WARNING: Remove this if not using an external DAC to use the pins of P0 as GPIO
	add a, #0x80
	mov DADH, a ; Output to DAC. DAC output is pin P2.3
	orl DADC, #0b_0100_0000 ; Start DAC by setting GO/BSY=1
	sjmp Timer1_ISR_Done

stop_playing:
	clr TR1 ; Stop timer 1
	;setb FLASH_CE  ; Disable SPI Flash
	clr SPEAKER ; Turn off speaker.  Removes hissing noise when not playing sound.
	mov DADH, #0x80 ; middle of range
	orl DADC, #0b_0100_0000 ; Start DAC by setting GO/BSY=1

Timer1_ISR_Done:	
	pop psw
	pop acc
	reti
; ==================================================================================================

;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 2                     ;
;---------------------------------;
Timer2_init:
mov T2CON, #0
mov TH2, #high(TIMER2_RELOAD)
mov TL2, #low(TIMER2_RELOAD)

mov RCAP2H, #high(TIMER2_RELOAD)
mov RCAP2L, #low(TIMER2_RELOAD)

    clr a
    mov Count1ms+0, a
    mov Count1ms+1, a
    setb ET2
    setb TR2
    clr enable_clk
    ret

;---------------------------------;
; ISR for timer 2                 ;
;---------------------------------;
Timer2_ISR:
    clr TF2  ; Timer 2 doesn't clear TF2 automatically. Do it in ISR
    cpl P1.0 ; To check the interrupt rate with oscilloscope. It must be precisely a 1 ms pulse.
	
	; The two registers used in the ISR must be saved in the stack
    push acc
    push psw
	
	; Increment the 16-bit one mili second counter
	inc Count1ms+0    ; Increment the low 8-bits first
	mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
	jnz Inc_Done
	inc Count1ms+1

Inc_Done:
	; Check if one second has passed
	mov a, Count1ms+0
	cjne a, #low(1000), Timer2_ISR_done ; Warning: this instruction changes the carry flag!
	mov a, Count1ms+1
	cjne a, #high(1000), Timer2_ISR_done
	
	; 1000 milliseconds have passed.  Set a flag so the main program knows
	setb one_seconds_flag ; Let the main program know one second had passed
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a

    jnb enable_clk, Timer2_ISR_done ;if the clk is enabled, increment the second. Otherwise skip
; Increment the run time counter and state time counter
	mov a, Run_time_seconds
	add a, #0x01
	da a
    mov Run_time_seconds, a
    ;check sec overflow
    cjne a, #0x60, Check_time_done
    mov Run_time_seconds, #0x00
    mov a, Run_time_minutes
    add a, #1
    da a
    mov Run_time_minutes, a
Check_time_done:
	mov a, State_time
	add a, #0x01
	da a
	mov State_time, a
Timer2_ISR_done:
	pop psw
	pop acc
	reti


; ==================================================================================================

main:

    
    mov SP, #0x7F
    lcall Timer2_Init
    lcall INI_SPI
    lcall LCD_4BIT
    lcall InitSerialPort
    ; In case you decide to use the pins of P0, configure the port in bidirectional mode. Can be ignored
    mov P0M0, #0
    mov P0M1, #0
    setb EA   ;Enable global enterupt
    lcall LCD_4BIT

    lcall Load_Configuration
    

state0: ; idle

;***initial parameters displayed***
    
    ;Displays Soak Temp and Time
    lcall State0_display
    ;check power on
    lcall CHECK_POWER
    ; check the parameters being pressed
    lcall CHECK_STIME
    lcall CHECK_STEMP
    lcall CHECK_RTIME
    lcall CHECK_RTEMP
    lcall Save_Configuration

    jb NEXT_STATE_BUTTON, state0
    Wait_Milli_Seconds(#50) ; debounce time
	jb NEXT_STATE_BUTTON, state0 ; if button not pressed, loop
	jnb NEXT_STATE_BUTTON, $ 
state0_done:
    mov States, #1
    mov State_time, #0
    setb enable_clk

state1_beginning:
    
    ;Start Run Time
    mov Run_time_seconds, #0x00 ; time starts at 0:00
    mov Run_time_minutes, #0x00

    ;***clear the screen and set new display***
    WriteCommand(#0x01)
    
    Set_Cursor(1, 1)
    Send_Constant_String(#time)
	Display_BCD(Run_time_minutes)
    Send_Constant_String(#colon)
    Display_BCD(Run_time_seconds)
    
    Set_Cursor(1,10)
    Send_Constant_String(#temp)
    Set_Cursor(1,14)
    mov a, Temp_oven
    lcall SendToLCD
    
    Set_Cursor(2,1)
    Send_Constant_String(#state)
    Set_Cursor(2,7)
    Send_Constant_String(#Ramp2Soak); displays current state
    

state1: ; ramp to soak
    Set_Cursor(1, 5)
	Display_BCD(Run_time_minutes)
    Set_Cursor(1, 7)
    Display_BCD(Run_time_seconds)

    ;check power on
    lcall CHECK_POWER
    
    ; check if temp is below 150 
    MOV A, Temp_soak           
    SUBB A, Temp_soak       
    JNC state1_done    ; if greater, jump to state 2
    JZ state1_done ; if equal to, jump to state 2
    JC state1 ; if less than, go back to state1
state1_done:
    mov States, #2
    ;set State_time = 0
    sjmp state2_beginning

;OFF_STATE2:
    ;ljmp OFF_STATE

; preheat/soak
state2_beginning: 
    mov State_time, #0x00 ;clear the state time
    ;***clear the screen and set new display***
    WriteCommand(#0x01)
    
    Set_Cursor(1, 1)
    Send_Constant_String(#time)
	Display_BCD(Run_time_minutes)
    Send_Constant_String(#colon)
    Display_BCD(Run_time_seconds)
    
    Set_Cursor(1,10)
    Send_Constant_String(#temp)
    Set_Cursor(1,14)
    mov a, Temp_oven
    lcall SendToLCD
    
    Send_Constant_String(#state)
    Set_Cursor(2,7)
    Send_Constant_String(#Soak); displays current state

state2:
    ;check power on
    lcall CHECK_POWER

    ;on
    setb OVEN_POWER
    lcall Wait_One_Second
    ;off
    clr OVEN_POWER
    mov r5, #0
four_sec_loop:
    ; loop back to state2 if run time is less than soak time
    mov a, Time_soak
    subb a, State_time
    cjne a, #0, state2
    Set_Cursor(1,5)
	Display_BCD(Run_time_minutes)
    Set_Cursor(1,7)
    Send_Constant_String(#colon)
    Set_Cursor(1,8)
    Display_BCD(Run_time_seconds)
    Wait_Milli_Seconds(#250)
    inc r5
    cjne r5, #16, four_sec_loop
        
    
    ; loop back to state2 if run time is less than soak time
    mov a, Time_soak
    subb a, State_time
    cjne a, #0, state2
    
state2_done:
    mov State_time, #0
    ljmp state3_beginning

; ramp to peak
state3_beginning:
    setb OVEN_POWER ;turn power on 100%

    ;***clear the screen and set new display***
    WriteCommand(#0x01)
    Set_Cursor(1, 1)
    Send_Constant_String(#time)
	Display_BCD(Run_time_minutes)
    Send_Constant_String(#colon)
    Display_BCD(Run_time_seconds)
    
    Set_Cursor(1,10)
    Send_Constant_String(#temp)
    Set_Cursor(1,14)
    mov a, Temp_oven
    lcall SendToLCD
    
    Set_Cursor(2,1)
    Send_Constant_String(#state)
    Set_Cursor(2,7)
    Send_Constant_String(#Ramp2Peak)

state3: 
    ;check power on
    lcall CHECK_POWER
    
    ; update display
    Set_Cursor(1,5)
	Display_BCD(Run_time_minutes)
    Send_Constant_String(#colon)
    Display_BCD(Run_time_seconds)

    mov a, Temp_oven
    subb a, Temp_refl 
    JNC state3_done    ; if greater, jump to state 4
    JZ state3_done ; if equal to, jump to state 4
    JC state3 ; if less than, go back to state3
    
;helllooooooooo
state3_done:
    mov State_time, #0
    ljmp state4_beginning


; reflow 
state4_beginning:
    ;***clear the screen and set new display***
    WriteCommand(#0x01)
    Set_Cursor(1, 1)
    Send_Constant_String(#time)
	Display_BCD(Run_time_minutes)

    Send_Constant_String(#colon)
    Set_Cursor(1,7)
    Display_BCD(Run_time_seconds)
    
    Set_Cursor(1,10)
    Send_Constant_String(#temp)
    Set_Cursor(1,14)
    mov a, Temp_oven
    lcall SendToLCD
    
    Set_Cursor(2,1)  
    Send_Constant_String(#state)
    Set_Cursor(2,7)
    Send_Constant_String(#Reflow)


state4:
    ;check power on
    lcall CHECK_POWER

    ;on
    setb OVEN_POWER
    lcall Wait_One_Second
    ;off
    clr OVEN_POWER
    mov r5, #0
    four_sec_loop2:
        ; loop back to state2 if run time is less than soak time
        mov a, Time_refl
        subb a, State_time
        cjne a, #0, state4
        Set_Cursor(1, 5)
	    Display_BCD(Run_time_minutes)
        Set_Cursor(1,7)
        Display_BCD(Run_time_seconds)
        Wait_Milli_Seconds(#250)

        inc r5
        cjne r5, #16, four_sec_loop2
        
    
    ; loop back to state2 if run time is less than soak time
    mov a, Time_refl
    subb a, State_time
    cjne a, #0, state4

state4_done: 
    mov State_time, #0
    ljmp state5_beginning 


; cooling
state5_beginning: ; turn oven off
    clr OVEN_POWER

;***clear the screen and set new display***
    WriteCommand(#0x01)
    Set_Cursor(1, 1)
    Send_Constant_String(#time)
    Set_Cursor(1, 5)
	Display_BCD(Run_time_minutes)
    Set_Cursor(1,6)
    Send_Constant_String(#colon)
    Set_Cursor(1,7)
    Display_BCD(Run_time_seconds)
    
    Set_Cursor(1,10)
    Send_Constant_String(#temp)
    Set_Cursor(1,14)
    mov a, Temp_oven
    lcall SendToLCD
    
    Set_Cursor(2,1)
    Send_Constant_String(#state)
    Set_Cursor(2,7)
    Send_Constant_String(#Cooling)
state5:
    ;check power on
    lcall CHECK_POWER
    
    ; update display
    Set_Cursor(1,5)
	Display_BCD(Run_time_minutes)
    Set_Cursor(1,7)
    Send_Constant_String(#colon)
    Set_Cursor(1,8)
    Display_BCD(Run_time_seconds)

    mov a, Temp_oven
    subb a, #60
    JNC state5    ; if greater, jump back to state 5
    JZ state5 ; if equal to, go back to state5
    JC state5_done ; if less than, go back to state 0

state5_done:
    mov State_time, #0
    ljmp main

END