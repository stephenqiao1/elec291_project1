$NOLIST
$MODLP51RC2
$LIST


;-------------------------------------------------------------------------------------------------------------------------------
;These EQU must match the wiring between the microcontroller and ADC
CLK  EQU 22118400
TIMER1_RATE    EQU 25000 ;22050     ; 22050Hz is the sampling rate of the wav file we are playing
TIMER1_RELOAD  EQU 0x10000-(CLK/TIMER1_RATE)
BAUD equ 115200
BRG_VAL equ (0x100-(CLK/(16*BAUD)))

TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU (65536-(CLK/TIMER2_RATE))

;shjfjdfs
;-------------------------------------------------------------------------------------------------------------------------------
;Button Pin Mapping
NEXT_STATE_BUTTON  equ P0.5
STIME_BUTTON    equ P0.2
STEMP_BUTTON    equ P0.3
RTIME_BUTTON    equ P0.4
RTEMP_BUTTON    equ P0.6

POWER_BUTTON    equ P4.5
SHIFT_BUTTON    equ p0.4

;Output Pins
OVEN_POWER      equ P0.7
SPEAKER         equ P2.6

PWM_OUTPUT    equ P1.0 ; Attach an LED (with 1k resistor in series) to P1.0


;FLASH pins
MY_MOSI_SOUND EQU P2.4
MY_MISO_SOUND EQU P2.1
MY_SCLK_SOUND EQU P2.0
FLASH_CE        equ P2.5

;Thermowire Pins
CE_ADC    EQU  P1.7
MY_MOSI   EQU  P1.6
MY_MISO   EQU  P1.5
MY_SCLK   EQU  P1.4 

; Commands supported by the SPI flash memory according to the datasheet
WRITE_ENABLE     EQU 0x06  ; Address:0 Dummy:0 Num:0
WRITE_DISABLE    EQU 0x04  ; Address:0 Dummy:0 Num:0
READ_STATUS      EQU 0x05  ; Address:0 Dummy:0 Num:1 to infinite
READ_BYTES       EQU 0x03  ; Address:3 Dummy:0 Num:1 to infinite
READ_SILICON_ID  EQU 0xab  ; Address:0 Dummy:3 Num:1 to infinite
FAST_READ        EQU 0x0b  ; Address:3 Dummy:1 Num:1 to infinite
WRITE_STATUS     EQU 0x01  ; Address:0 Dummy:0 Num:1
WRITE_BYTES      EQU 0x02  ; Address:3 Dummy:0 Num:1 to 256
ERASE_ALL        EQU 0xc7  ; Address:0 Dummy:0 Num:0
ERASE_BLOCK      EQU 0xd8  ; Address:3 Dummy:0 Num:0
READ_DEVICE_ID   EQU 0x9f  ; Address:0 Dummy:2 Num:1 to infinite

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
Count5sec:        ds 1
States:           ds 1
Temp_soak:        ds 1
Time_soak:        ds 1
Temp_refl:        ds 1
Time_refl:        ds 1
Run_time_seconds: ds 1
Run_time_minutes: ds 1
State_time:       ds 1
Temp_oven:        ds 1
KTemp_oven:       ds 1
x:                ds 4
y:                ds 4
bcd:              ds 5
Result:           ds 2
w:                ds 3
pwm_ratio:        ds 2
average_count:    ds 1
K_or_C:           ds 1

$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

$NOLIST
$include(math32.inc)
$LIST

$NOLIST
$INCLUDE(sound_for_project1_index.asm)
$LIST

bseg
one_seconds_flag:  dbit 1
five_seconds_flag: dbit 1
enable_clk:        dbit 1
mf:                dbit 1

cseg

;-------------------------------------------------------------------------------------------------------------------------------
;***Messages To Display*** 

;shortened labels
STemp:  db 'STmp:', 0
STime:  db 'STm:', 0
RTemp:  db 'RTmp:', 0
RTime:  db 'RTm:', 0

;lables for runnning oven
state:     db 'State>' , 0
time:      db 'Tme>' , 0
colon:     db ':', 0
temp:      db 'Tmp>', 0

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
	setb MY_MISO          ; Make MISO an input pin
	clr MY_SCLK           ; Mode 0,0 default
	ret
DO_SPI_G:
	push acc
	mov R1, #0            ; Received byte stored in R1
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
		mov MY_MOSI_SOUND, c
		setb MY_SCLK_SOUND
		mov c, MY_MISO_SOUND
		clr MY_SCLK_SOUND
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

    Change_8bit_Variable(STIME_BUTTON, Time_soak, CHECK_STIME_END)
	
CHECK_STIME_END:
ret

CHECK_STEMP:
    Change_8bit_Variable(STEMP_BUTTON, Temp_soak, CHECK_STEMP_END)
    ;lcall Save_Configuration
	
CHECK_STEMP_END:
ret

CHECK_RTIME:
	Change_8bit_Variable(RTIME_BUTTON, Time_refl, CHECK_RTIME_END)
CHECK_RTIME_END:
ret

CHECK_RTEMP:
    Change_8bit_Variable(RTEMP_BUTTON, Temp_refl, CHECK_RTEMP_END)
CHECK_RTEMP_END:
ret

CHECK_POWER:

    jb POWER_BUTTON, CHECK_POWER_END ; if button not pressed, stop checking
	Wait_Milli_Seconds(#50) ; debounce time
	jb POWER_BUTTON, CHECK_POWER_END ; if button not pressed, stop checking
	jnb POWER_BUTTON, $ ; loop while the button is pressed
    mov pwm_ratio+0, #low(0)
	mov pwm_ratio+1, #high(0)
    lcall OFF_STATE

CHECK_POWER_END:
ret

CHECK_K_OR_C:

    jb RTEMP_BUTTON, CHECK_K_OR_C_END ; if button not pressed, stop checking
	Wait_Milli_Seconds(#50) ; debounce time
	jb RTEMP_BUTTON, CHECK_K_OR_C_END ; if button not pressed, stop checking
	jnb RTEMP_BUTTON, $ ; loop while the button is pressed
    
    ;mov a, K_or_C
    ;anl a,
    ;anl a, #00000001B  ; We need only the two least significant bits




CHECK_K_OR_C_END:
ret

; Playback MACRO for sound --------------------------------------------------

PLAYBACK_TEMP MAC
    ; ***play audio***
    clr TR1 ; Stop Timer 1 ISR from playing previous request
    setb FLASH_CE
    clr SPEAKER ; Turn off speaker
    
    clr FLASH_CE ; Enable SPI Flash
    mov a, #READ_BYTES
    lcall Send_SPI
    ; Set the initial position in memory where to start playing
    
    mov a, %0 ; change initial position
    lcall Send_SPI
    mov a, %1 ; next memory position
    lcall Send_SPI
    mov a, %2 ; next memory position
    lcall Send_SPI
    mov a, %0 ; request first byte to send to DAC
    lcall Send_SPI
    
    ; How many bytes to play?
    mov w+2, #0x00 ; Load the high byte of the number of bytes to play
    mov w+1, %3 ; Load the middle byte of the number of bytes to play
    mov w+0, %4 ; Load the low byte of the number of bytes to play
    
    
    setb SPEAKER ;Turn on speaker
    setb TR1 ;Start playback by enabling Timer1
ENDMAC



;**SOUND STUFF---------------------------------------------------------------

SOUND_FSM:
state_0_sound:
;check if 5 seconds has passed, if yes go to state 1, if no exit function 
    jnb five_seconds_flag, Sound_ret
    clr five_seconds_flag
    ljmp state_1_sound
Sound_ret:
    ret

state_1_sound:
; check if temp is greater than 100, if yes go to state 2
; check if temp is less than 100, if yes go to state 4
    mov a, Temp_oven
    subb a, #100
    jnc state_2_sound_hop
    jc state_4_sound_hop

    state_2_sound_hop:
        ljmp state_2_sound

    state_4_sound_hop:
        ljmp state_4_sound

state_2_sound:
;divide temp by 100, if it is 1 play sound: "100", if it is 2 play sound: "200"
; go to state_3_sound
    mov b, #100
    mov a, Temp_oven
    div ab
    subb a, #1
    jz play_sound_1

    mov b, #100
    mov a, Temp_oven
    div ab
    subb a, #2
    jz play_sound_2
   
    play_sound_1: 
        PLAYBACK_TEMP(#0x01,#0x93, #0x84, #0x36, #0xb0) ;one
        PLAYBACK_TEMP(#0x05,#0x09,#0x10, #0x27,#0x10) ;hundred
        ljmp state_3_sound

    play_sound_2:
        PLAYBACK_TEMP(#0x01, #0xc7, #0x14, #0x13, #0x88) ;two
        PLAYBACK_TEMP(#0x05,#0x09,#0x10, #0x27,#0x10) ;hundred
        ljmp state_3_sound



    


state_3_sound:
; check remainder of temp, if it is 0, go back to state_0_sound
; if not 0, go to state_4_sound

    mov b, #100
    mov a, Temp_oven
    div ab
    mov a, b
    jz state_0_sound_hop
    jnz state_4_sound

    state_0_sound_hop:
        ljmp state_0_sound

state_4_sound:
; if T % 100 greater or equal to 20, go to state_5_sound,
    mov b, #100
    mov a, Temp_oven
    div ab
    mov a, b 
    subb a, #20
    jnc state_5_sound
    clr a
; if T % 100 is less than 10, go to state_6_sound
    mov b, #100
    mov a, Temp_oven
    div ab
    mov a, b
    subb a, #10
    jc state_6_sound_hop0
    clr a
; if T % 100 is greater than 10 and less than 20, go to state_7_sound
    ljmp state_7_sound

    state_6_sound_hop0:
        ljmp state_6_sound
    

state_5_sound:
; play number from 20 to 90 in decades (20, 30, 40, 50, 60, 70, 80, 90), based off remainder from temp divided by 100
; if (T % 100) % 10 is not equal to 0, go to state_6_sound
; if (T % 100) % 10 is equal to 0, go to state_8_sound

    mov a, Temp_oven
    mov b, #100 
    div ab
    mov a, b
    mov b, #10
    div ab
    mov a, b
    jz play_sound
    jnz state_6_sound_hop1

    state_6_sound_hop1:
        ljmp state_6_sound
    

    play_sound:
        ;ljmp PLAYBACK_TEMP
        cjne a, #0x14, play_30   

        PLAYBACK_TEMP(#0x03,#0xef,#0xd0, #0x27,#0x10)
        ljmp state_8_hop0

        play_30:
            cjne a, #0x1e, play_40
            PLAYBACK_TEMP(#0x04,#0x16,#0xe0, #0x23,#0x28)
            ljmp state_8_hop0

        play_40:
            cjne a, #0x28, play_50
            PLAYBACK_TEMP(#0x04,#0x3d,#0xf0, #0x1f,#0x40)
            ljmp state_8_hop0

        play_50:
            cjne a, #0x32, play_60
            PLAYBACK_TEMP(#0x04,#0x51,#0x78, #0x23,#0x28)
            ljmp state_8_hop0

        play_60:
            cjne a, #0x3c, play_70
            PLAYBACK_TEMP(#0x04,#0x74,#0xa0, #0x27,#0x10)
            ljmp state_8_hop0

        play_70:
            cjne a, #0x46, play_80
            PLAYBACK_TEMP(#0x04,#0x9b,#0xb0, #0x32,#0xc8)
            ljmp state_8_hop0

        play_80:
            cjne a, #0x50, play_90
            PLAYBACK_TEMP(#0x04,#0xc6,#0xa8, #0x23,#0x28)
            ljmp state_8_hop0

        play_90:
            PLAYBACK_TEMP(#0x04,#0xed,#0xb8, #0x1f,#0x40)

        state_8_hop0:
            ljmp state_8_sound


state_6_sound:
; play 1 - 9
    ;ljmp PLAYBACK_TEMP
    cjne a, #0x01, play_2

    PLAYBACK_TEMP(#0x01,#0x93,#0x84, #0x36,#0xb0)
    ljmp state_8_hop1

    play_2:
        cjne a, #0x02, play_3
        PLAYBACK_TEMP(#0x01,#0xc7,#0x14, #0x13,#0x88)
        ljmp state_8_hop1

    play_3:
        cjne a, #0x03, play_4
        PLAYBACK_TEMP(#0x01,#0xd6,#0x68, #0x23,#0x28)
        ljmp state_8_hop1

    play_4:
        cjne a, #0x04, play_5
        PLAYBACK_TEMP(#0x01,#0xf4,#0x00, #0x1b,#0x58)
        ljmp state_8_hop1

    play_5:
        cjne a, #0x05, play_6
        PLAYBACK_TEMP(#0x02,#0x07,#0x88, #0x1b,#0x58)
        ljmp state_8_hop1

    play_6:
        cjne a, #0x06, play_7
        PLAYBACK_TEMP(#0x02,#0x26,#0xc8, #0x1f,#0x40)
        ljmp state_8_hop1

    play_7:
        cjne a, #0x07, play_8
        PLAYBACK_TEMP(#0x02,#0x36,#0x68, #0x23,#0x28)
        ljmp state_8_hop1

    play_8:
        cjne a, #0x08, play_9
        PLAYBACK_TEMP(#0x02,#0x57,#0x9c, #0x1b,#0x58)
        ljmp state_8_hop1

    play_9:
        PLAYBACK_TEMP(#0x02,#0x69,#0x30, #0x1f,#0x40)

state_8_hop1:
; go to state_8_sound
    ljmp state_8_sound


state_7_sound:
; play 10 - 19
    ;ljmp PLAYBACK_TEMP
    cjne a, #0x0a, play_11
    PLAYBACK_TEMP(#0x02,#0x84,#0x88, #0x17,#0x70)
    ljmp state_8_hop2

    play_11:
        cjne a, #0x0b, play_12
        PLAYBACK_TEMP(#0x02,#0x9b,#0xf8, #0x1f,#0x40)
        ljmp state_8_hop2

    play_12:
        cjne a, #0x0c, play_13
        PLAYBACK_TEMP(#0x02,#0xb7,#0x50, #0x1f,#0x40)
        ljmp state_8_hop2

    play_13:
        cjne a, #0x0d, play_14
        PLAYBACK_TEMP(#0x02,#0xce,#0xc0, #0x2e,#0xe0)
        ljmp state_8_hop2

    play_14:
        cjne a, #0x0e, play_15
        PLAYBACK_TEMP(#0x02,#0xf5,#0xd0, #0x36,#0xb0)
        ljmp state_8_hop2

    play_15:
        cjne a, #0x0f, play_16
        PLAYBACK_TEMP(#0x03,#0x28,#0x98, #0x23,#0x28)
        ljmp state_8_hop2

    play_16:
        cjne a, #0x10, play_17
        PLAYBACK_TEMP(#0x03,#0x47,#0xd8, #0x32,#0xc8)
        ljmp state_8_hop2

    play_17:
        cjne a, #0x11, play_18
        PLAYBACK_TEMP(#0x03,#0x76,#0xb8, #0x2e,#0x20)
        ljmp state_8_hop2

    play_18:
        cjne a, #0x12, play_19
        PLAYBACK_TEMP(#0x03,#0xa1,#0xb0, #0x27,#0x10)
        ljmp state_8_hop2

    play_19:
        PLAYBACK_TEMP(#0x03,#0xc8,#0xc0, #0x27,#0x10)

    state_8_hop2:
    ; go to state_8_sound
        ljmp state_8_sound

state_8_sound:
; go to state_0_sound
    ljmp state_0_sound


INI_PLAYBACK_TEMP:
    ; ****INITIALIZATION****
    ; Configure SPI pins and turn off speaker
	;anl P2M0, #0b_1100_1110
    orl P2M0, #0b_1001_0000
    ;orl P2M0, #0b_0011_0001
	;orl P2M1, #0b_0011_0001
    orl P2M1, #0b_1001_0000
	setb MY_MISO_SOUND  ; Configured as input
	setb FLASH_CE ; CS=1 for SPI flash memory
	clr MY_SCLK_SOUND   ; Rest state of SCLK=0
	clr SPEAKER   ; Turn off speaker.
	
	; Configure timer 1
	anl	TMOD, #0x0F ; Clear the bits of timer 1 in TMOD
	orl	TMOD, #0x10 ; Set timer 1 in 16-bit timer mode.  Don't change the bits of timer 0
	mov TH1, #high(TIMER1_RELOAD)
	mov TL1, #low(TIMER1_RELOAD)
	; Set autoreload value
	mov RH1, #high(TIMER1_RELOAD)
	mov RL1, #low(TIMER1_RELOAD)

	;Enable the timer and interrupts
    setb ET1  ; Enable timer 1 interrupt
	setb TR1 ; Timer 1 is only enabled to play stored sound

	; Configure the DAC.  The DAC output we are using is P2.3, but P2.2 is also reserved.
	mov DADI, #0b_1010_0000 ; ACON=1
	mov DADC, #0b_0011_1010 ; Enabled, DAC mode, Left adjusted, CLK/4
	mov DADH, #0x80 ; Middle of scale
	mov DADL, #0
	orl DADC, #0b_0100_0000 ; Start DAC by GO/BSY=1
    check_DAC_init:
	mov a, DADC
	jb acc.6, check_DAC_init ; Wait for DAC to finish
	
ret

    
;-------------------------------------------------------------------------------------------------------------------------------
;***LCD FXNS

Display_lower_BCD mac
    push ar0
    mov r0, %0
    lcall ?Display_lower_BCD
    pop ar0
endmac

?Display_lower_BCD:
    push acc
    ; write least significant digit
    mov a, r0
    anl a, #0fh
    orl a, #30h
    lcall ?WriteData
    pop acc
ret


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

Initialize_State_Display:

    ;***clear the screen and set new display***
    WriteCommand(#0x01)
    Wait_Milli_Seconds(#2)
    
    Set_Cursor(1, 1)
    Send_Constant_String(#time)
	
    Set_Cursor(1,6)
    Send_Constant_String(#colon)
   
    Set_Cursor(1,10)
    Send_Constant_String(#temp)
    
    Set_Cursor(2,1)
    Send_Constant_String(#state)
ret

Update_Display:
    Set_Cursor(1, 5)
    Display_lower_BCD(Run_time_minutes)
    Set_Cursor(1, 7)
    Display_BCD(Run_time_seconds)
    ;Set_Cursor(1,14)
    ;mov a, Temp_oven
    ;SendToLCD(Temp_oven)
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

Display_3_digit_BCD:
	Set_Cursor(1, 14)
	Display_lower_BCD(bcd+1)
	Display_BCD(bcd+0)
ret

Animation:
    WriteCommand(#0x0f) ;display cursor

    ;name ; Move cursor to line 1 column 1
    WriteCommand(#0x80)
    WriteData(#'W')
    Wait_Milli_Seconds(#250)
    WriteData(#'e')
    Wait_Milli_Seconds(#250)
    WriteData(#'l')
    Wait_Milli_Seconds(#250)
    WriteData(#'c')
    Wait_Milli_Seconds(#250)
    WriteData(#'o')
    Wait_Milli_Seconds(#250)
    WriteData(#'m')
    Wait_Milli_Seconds(#250)
    WriteData(#'e')
    Wait_Milli_Seconds(#250)
    WriteData(#'!')
    Wait_Milli_Seconds(#250)
    WriteData(#' ')
    Wait_Milli_Seconds(#250)
    WriteData(#96)
    Wait_Milli_Seconds(#250)
    WriteData(#239)
    Wait_Milli_Seconds(#250)
    WriteData(#47)
    lcall Wait_One_Second
    lcall Wait_One_Second
    WriteCommand(#0x0c) ;clear cursor
ret

;The following functions store and restore the values--------------------------------------------------------------------------
loadbyte mac
    mov a, %0
    movx @dptr, a
    inc dptr
endmac

Save_Configuration:
    push IE ; Save the current state of bit EA in the stack
    clr EA ; Disable interrupts
    mov FCON, #0x08 ; Page Buffer Mapping Enabled (FPS = 1)
    mov dptr, #0x7f80 ; Last page of flash memory
    ; Save variables
    loadbyte(temp_soak) ; @0x7f80
    loadbyte(time_soak) ; @0x7f81
    loadbyte(temp_refl) ; @0x7f82
    loadbyte(time_refl) ; @0x7f83
    loadbyte(#0x55) ; First key value @0x7f84
    loadbyte(#0xAA) ; Second key value @0x7f85
    mov FCON, #0x00 ; Page Buffer Mapping Disabled (FPS = 0) 
    orl EECON, #0b01000000 ; Enable auto-erase on next write sequence  
    mov FCON, #0x50 ; Write trigger first byte
    mov FCON, #0xA0 ; Write trigger second byte
    ; CPU idles until writing of flash completes.
    mov FCON, #0x00 ; Page Buffer Mapping Disabled (FPS = 0)
    anl EECON, #0b10111111 ; Disable auto-erase
    pop IE ; Restore the state of bit EA from the stack
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
    mov Temp_refl, #220 ; Range 220-240
    mov Time_refl, #0x1E ; Range 30-45 seconds
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
    ljmp main
ret
;-------------------------------------------------------------------------------------------------------------------------------

;***CHECK TEMPERATURE BY READING VOLTAGE AND CONVERTING
Check_Temp:
    
    ;jnb one_seconds_flag, Check_Temp_done
    ;clr one_seconds_flag
    
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
	mov Result+0, R1     ; R1 contains bits 0 to 7.  Save result low.
	setb CE_ADC

	Wait_Milli_Seconds(#10)
    ; Copy the 10-bits of the ADC conversion into the 32-bits of 'x'
	mov R6, Result+0
	mov R7, Result+1
ret

    
    
;***CALCULATES THE TEMPERATURE
Average_Temp:
    Load_x(0)
    mov R5, #100
Ave_loop:
    lcall Check_Temp
    mov y+3, #0
    mov y+2, #0
    mov y+1, R7
    mov y+0, R6
    lcall add32
    lcall Wait10us
    djnz R5, Ave_loop
    load_y(100)
    lcall div32

    ;**INSERT MATH FUNCTIONS

    load_Y(2894) ;6078; 2026
	lcall mul32
	load_Y(10000) ;14000; 7000
	lcall div32
    Load_Y(22)
    lcall add32
    mov Temp_oven, x+0
    ;add KTemp_oven, Temp_oven, #273

Display_Temp_BCD_Or_Kelvin:
	lcall hex2bcd ; converts binary in x to BCD in BCD
    ;mov a, K_or_C
    ;cjne a, #1, Display_3_digit_BCD
    ;mov a, KTemp_oven
    ;SendToLCD
    ;sjmp Send_Temp_Port

Display_Temp_BCD:    
    lcall Display_3_digit_BCD

Send_Temp_Port:
    ;Send_BCD(bcd+4)
    ;Send_BCD(bcd+3)
    ;Send_BCD(bcd+2)
	Send_BCD(bcd+1)
    Send_BCD(bcd+0)
	mov a, #'\r'
	lcall putchar
	mov a, #'\n'
	lcall putchar
Check_Temp_done:
ret    

;-------------------------------------------------------------------------------------------------------------------------------

;Time wait

Wait_One_Second:
    Wait_Milli_Seconds(#250)
    Wait_Milli_Seconds(#250)
    Wait_Milli_Seconds(#250)
    Wait_Milli_Seconds(#250)
ret

Wait_Half_Second:
    Wait_Milli_Seconds(#250)
    Wait_Milli_Seconds(#250)
ret



Wait10us:
    mov R0, #74
    djnz R0, $
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
	;mov P0, a ; WARNING: Remove this if not using an external DAC to use the pins of P0 as GPIO
	add a, #0x80
	mov DADH, a ; Output to DAC. DAC output is pin P2.3
	orl DADC, #0b_0100_0000 ; Start DAC by setting GO/BSY=1
	sjmp Timer1_ISR_Done

stop_playing:
	clr TR1 ; Stop timer 1
	setb FLASH_CE  ; Disable SPI Flash
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
    mov Count5sec , a
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

;**Oven Power Output-------------------
    ; Do the PWM thing
	; Check if Count1ms > pwm_ratio (this is a 16-bit compare)
	clr c
	mov a, pwm_ratio+0
	subb a, Count1ms+0
	mov a, pwm_ratio+1
	subb a, Count1ms+1
	; if Count1ms > pwm_ratio  the carry is set.  Just copy the carry to the pwm output pin:
	mov PWM_OUTPUT, c
;**----------------------------------
	; Check if one second has passed
	mov a, Count1ms+0
	cjne a, #low(1000), Timer2_ISR_done ; Warning: this instruction changes the carry flag!
	mov a, Count1ms+1
	cjne a, #high(1000), Timer2_ISR_done
	
	; 1000 milliseconds have passed.  Set a flag so the main program knows
	setb one_seconds_flag ; Let the main program know one second had passed
    
    inc Count5sec
    mov a, Count5sec
    cjne a, #5, Set_5sec_flag_done
    setb five_seconds_flag
    clr a
    mov Count5sec, a
    
Set_5sec_flag_done:
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
    cjne a, #0x60, Check_sec_overflow_done
    mov Run_time_seconds, #0x00
    mov a, Run_time_minutes ;inc min
    add a, #1
    da a
    mov Run_time_minutes, a
Check_sec_overflow_done:
    inc State_time
Timer2_ISR_done:
	pop psw
	pop acc
	reti


; ==================================================================================================

main:
    mov SP, #0x7F
    lcall Timer2_Init
    ;lcall INI_SPI
    lcall LCD_4BIT
    lcall InitSerialPort
    lcall INI_PLAYBACK_TEMP
    ; In case you decide to use the pins of P0, configure the port in bidirectional mode. Can be ignored
    mov P0M0, #0
    mov P0M1, #0
    setb EA   ;Enable global enterupt

    lcall Load_Configuration

    ;Set the default pwm output ratio to 0%.  That is 0ms of every second:
	mov pwm_ratio+0, #low(0)
	mov pwm_ratio+1, #high(0)
    mov States, #0
    lcall Animation
    
state0: ; idle
    ;Set the default pwm output ratio to 0%.  That is 0ms of every second:
	;mov pwm_ratio+0, #low(0)
	;mov pwm_ratio+1, #high(0)
    ;mov States, #0

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
    
    ;lcall Check_Temp
    ;lcall PLAYBACK_TEMP

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
    mov Run_time_seconds, #0 ; time starts at 0:00
    mov Run_time_minutes, #0
    mov State_time, #0

    ;***clear the screen and set new display***
    lcall Initialize_State_Display
    Set_Cursor(2,7)
    Send_Constant_String(#Ramp2Soak); displays current state

    ;Set the default pwm output ratio to 100%.  That is 1000ms of every second:
	mov pwm_ratio+0, #low(1000)
	mov pwm_ratio+1, #high(1000)
    PLAYBACK_TEMP(#0x00,#0x00,#0x2d, #0x4e,#0x20)
    sjmp state1
    
main_1:
	ljmp main

state1: ; ramp to soak
    
    ;PLAYBACK_TEMP(#0x00,#0x00,#0x2d, #0x4e,#0x20)
    ;check power on
    lcall CHECK_POWER
    ;Update Time and Temp
    lcall Update_Display
    lcall Average_Temp
    lcall SOUND_FSM

Check_Temp_done1:

    ;check if temp is below 150 
    
    mov a, Temp_oven           
    subb a, Temp_soak
    jnc state1_done      ; if greater, jump to state 2
    jz state1_done       ; if equal to, jump to state 2
    jc Check_state1_time ; if less than, check state time
Check_state1_time:       ;safety
    mov a, State_time      
    subb a, #60
    jnc main_1             ; if greater, restart
    jz main_1              ; if equal to, restart
    jc state1            ; if less than, go back to state1
;*Checking moving to states with buttons---- 
;*Will remove after proper temperature reading----

    ;jb NEXT_STATE_BUTTON, state1
    ;Wait_Milli_Seconds(#50) ; debounce time
	;jb NEXT_STATE_BUTTON, state1 ; if button not pressed, loop
	;jnb NEXT_STATE_BUTTON, $ 

state1_done:
    mov States, #2

; preheat/soak
state2_beginning: 
    mov State_time, #0;x00 ;clear the state time
    ;***clear the screen and set new display***
    lcall Initialize_State_Display
    Set_Cursor(2,7)
    Send_Constant_String(#Soak) ;displays current state

    ;Set the default pwm output ratio to 20%.  That is 200ms of every second:
	mov pwm_ratio+0, #low(200)
	mov pwm_ratio+1, #high(000)
    ; Produces SOAK on speaker
    PLAYBACK_TEMP(#0x00,#0x44,#0xdd, #0x4e,#0x20)

state2:
    ;check power on
    lcall CHECK_POWER 
    ;Update Time and Temp
    lcall Update_Display
    lcall Average_Temp
    
    ; loop back to state2 if run time is less than soak time. If greater than jump to state3 cuz of overflow of time
     
    mov a, State_time
    subb a, Time_soak
    jnc state2_done
    jc state2


;*Checking moving to states with buttons---- 
;*Will remove after proper temperature reading----

    ;jb NEXT_STATE_BUTTON, state2
    ;Wait_Milli_Seconds(#50) ; debounce time
	;jb NEXT_STATE_BUTTON, state2 ; if button not pressed, loop
	;jnb NEXT_STATE_BUTTON, $ 
    
state2_done:
    mov State_time, #3

; ramp to peak
state3_beginning:
    ;setb OVEN_POWER ;turn power on 100%

    ;***clear the screen and set new display***
    lcall Initialize_State_Display
    Set_Cursor(2,7)
    Send_Constant_String(#Ramp2Peak)

    ;Set the default pwm output ratio to 100%.  That is 1000ms of every second:
	mov pwm_ratio+0, #low(1000)
	mov pwm_ratio+1, #high(1000)

    ; Produces RAMP TO PEAK on speaker
    PLAYBACK_TEMP(#0x00,#0x8b,#0xca, #0x75,#0x30)

state3: 
    ;check power on
    lcall CHECK_POWER
    lcall Average_Temp
    
    
    ;Update Time and Temp
    lcall Update_Display
    
    mov a, Temp_oven           
    subb a, Temp_refl
    jnc state3_done    ; if greater, jump to state 4
    jz state3_done ; if equal to, jump to state 4
    jc state3 ; if less than, go back to state3
    
    ;jb NEXT_STATE_BUTTON, state3
    ;Wait_Milli_Seconds(#50) ; debounce time
	;jb NEXT_STATE_BUTTON, state3 ; if button not pressed, loop
	;jnb NEXT_STATE_BUTTON, $

state3_done:
    mov State_time, #4

; reflow 
state4_beginning:
    
    mov State_time, #0;x00 clear the state time
    ;***clear the screen and set new display***
    lcall Initialize_State_Display
    Set_Cursor(2,7)
    Send_Constant_String(#Reflow)

    ;Set the default pwm output ratio to 20%.  That is 200ms of every second:
	mov pwm_ratio+0, #low(200)
	mov pwm_ratio+1, #high(000)

    ; Produces REFLOW on speaker
    PLAYBACK_TEMP(#0x00,#0xf0,#0x63, #0x59,#0xd8)


state4:
    ;check power on
    lcall CHECK_POWER
    ;Update Time and Temp
    lcall Update_Display
    lcall Average_Temp
    
    ; loop back to state2 if run time is less than soak time
    mov a, State_time
    subb a, Time_refl
    jnc state4_done
    jc state4

    ;*Checking moving to states with buttons---- 
;*Will remove after proper temperature reading----

    ;jb NEXT_STATE_BUTTON, state4
    ;Wait_Milli_Seconds(#50) ; debounce time
	;jb NEXT_STATE_BUTTON, state4 ; if button not pressed, loop
	;jnb NEXT_STATE_BUTTON, $ 

state4_done: 
    mov State_time, #0
    ljmp state5_beginning 


; cooling
state5_beginning: ; turn oven off
    clr OVEN_POWER

;***clear the screen and set new display***
    lcall Initialize_State_Display
    Send_Constant_String(#Cooling)

    ;Set the default pwm output ratio to 0%.  That is 0ms of every second:
	mov pwm_ratio+0, #low(0)
	mov pwm_ratio+1, #high(0)

    ; Produces COOLING on speaker
    PLAYBACK_TEMP(#0x01,#0x48,#0x9a, #0x6b,#0x6c)

state5:
    ;check power on
    lcall CHECK_POWER
    
    ; update display
    lcall Update_Display
    lcall Average_Temp

    mov a, Temp_oven
    subb a, #60
    JNC state5    ; if greater, jump back to state 5
    JZ state5 ; if equal to, go back to state5
    JC state5_done ; if less than, go back to state 0

    ;*Checking moving to states with buttons---- 
;*Will remove after proper temperature reading----

    ;jb NEXT_STATE_BUTTON, state5
    ;Wait_Milli_Seconds(#50) ; debounce time
	;jb NEXT_STATE_BUTTON, state5 ; if button not pressed, loop
	;jnb NEXT_STATE_BUTTON, $ 

state5_done:
    mov State_time, #0
    mov States, #0
    ljmp main

END