#!/usr/bin/env python3

import pyaudio
import numpy as np

CHUNK = 2*4096 # number of data points to read at a time
RATE = 48000 # time resolution of the recording device (Hz)
DEVICE = 1 # Webcam

p = pyaudio.PyAudio()

stream=p.open(format=pyaudio.paInt16,channels=1,rate=RATE,input=True, input_device_index=DEVICE,
              frames_per_buffer=CHUNK)

while True:
    indata = np.fromstring(stream.read(CHUNK),dtype=np.int16)

    # Take the fft and square each value
    fftData=abs(np.fft.rfft(indata))**2
    # find the maximum
    which = fftData[1:].argmax() + 1
    # use quadratic interpolation around the max
    if which != len(fftData)-1:
        y0,y1,y2 = np.log(fftData[which-1:which+2:])
        x1 = (y2 - y0) * .5 / (2 * y1 - y2 - y0)
        # find the frequency and output it
        thefreq = (which+x1)*RATE/CHUNK
        print("The freq is %f Hz." % (thefreq))
    else:
        thefreq = which*RATE/CHUNK
        print("The freq is %f Hz." % (thefreq))

stream.close()
p.terminate()
