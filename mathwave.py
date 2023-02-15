import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import sys, time, math
import serial



# configure the serial port
ser = serial.Serial(
 port='COM5',
 baudrate=115200,
 parity=serial.PARITY_NONE,
 stopbits=serial.STOPBITS_TWO,
 bytesize=serial.EIGHTBITS
)
ser.isOpen()

#the ideas for the additional features were given by a past student Anshul

#Opening up a list to store all the temperature recorded by the 335 sensor
temp_list = []

xsize=100

def data_gen():
    t = data_gen.t
    while True:
       t+=1
       num = float(ser.readline())
       val= num
       yield t, val
       temp_list.append(num)
       if(num<26.000 and num>= 25.000):
           print("You're at room temperature")

def run(data):
##    # update the data
    t,y = data
    if t>-1:
        xdata.append(t)
        ydata.append(y)
        if t>xsize: # Scroll to the left.
            ax.set_xlim(t-xsize, t)
        line.set_data(xdata, ydata)

    return line,
#Created another function which calculates the average of the temperatures recorded by our circuit
def calculate_avg(temp_list):
    print("The following temperatures were recorded during your session:")
    print(temp_list)
    temp_count = len(temp_list)
    temp_sum = sum(temp_list)
    avg_temp = temp_sum/temp_count
    print("\n")
    print("The average temperature:")
    print(avg_temp)


def on_close_figure(event):
    #Calculates the average of the temperature values
    calculate_avg(temp_list)
    sys.exit(0)

data_gen.t = -1
fig = plt.figure()
fig.canvas.mpl_connect('close_event', on_close_figure)
ax = fig.add_subplot(111)
line, = ax.plot([], [], lw=2)
ax.set_ylim(-10, 50)
ax.set_xlim(0, xsize)
ax.grid()
xdata, ydata = [], []

# Important: Although blit=True makes graphing faster, we need blit=False to prevent
# spurious lines to appear when resizing the stripchart.
ani = animation.FuncAnimation(fig, run, data_gen, blit=False, interval=500, repeat=False)
plt.show()
