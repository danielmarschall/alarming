#!/usr/bin/env python3

# This script listens to the microphone and detects a doorbell that plays 2 sounds ("ding" "dong")
# Please configure and adjust the script to your needings

import pyaudio
import wave
import numpy as np
import time
import os

CHUNK = 2*4096 # number of data points to read at a time
RATE = 48000 # time resolution of the recording device (Hz)
DEVICE = 1 # Webcam
TARGET_FREQ_DING = 3232 # Hz, in AudaCity, select "Analyze > Spectrum" to find out the frequency of your doorbell
TARGET_FREQ_DONG = 2781 # Hz
DING_TRES = 1.5
DONG_TRES = 2.4
DING_DONG_INTERVAL = 4 # max seconds between "ding" and "dong"

#SIMULATE_WAVEFILE = "test/doorbell_test.wav"
SIMULATE_WAVEFILE = ""
DEBUG = 2

# -------------------------------------------------------------

p = pyaudio.PyAudio()

if SIMULATE_WAVEFILE == "":
	RATE = 48000 # TODO: read from hw-params
	DTYPE = np.int16 # TODO: read from hw-params?
	stream=p.open(format=pyaudio.paInt16,channels=1,rate=RATE,input=True, input_device_index=DEVICE, frames_per_buffer=CHUNK)
else:
	wf = wave.open(SIMULATE_WAVEFILE, 'rb')
	DTYPE = np.int16 # TODO: read from wave file?
	RATE = wf.getframerate()

col_target_ding = []
col_target_dong = []
col_other = []

last_detected_ding = 0
last_detected_dong = 0
max_intensity_ding = 0
max_intensity_dong = 0

while True:
    if SIMULATE_WAVEFILE == "":
        indata = np.fromstring(stream.read(CHUNK),dtype=DTYPE)
    else:
        d = wf.readframes(CHUNK)
        if len(d) == 0:
            break;
        indata = np.fromstring(d,dtype=DTYPE)

    fftData = np.fft.fft(indata)
    freqs = np.fft.fftfreq(fftData.size)
    magnitudes = fftData[1:int(fftData.size/2)]

    # Find out volume of target "ding" frequency

    idx = (np.abs(freqs-TARGET_FREQ_DING/RATE)).argmin()
    volume_target_ding = np.sum(np.abs(magnitudes[int(idx-1):int(idx+1)])) / 3

    # Find out volume of target "dong" frequency

    idx = (np.abs(freqs-TARGET_FREQ_DONG/RATE)).argmin()
    volume_target_dong = np.sum(np.abs(magnitudes[int(idx-1):int(idx+1)])) / 3

    # Find out the general volume

    volume_other = np.mean(np.abs(magnitudes))
    #volume_other = np.median(np.abs(magnitudes))

    # Filter peaks

    col_other.append(volume_other)
    while len(col_other) > 5:
        col_other.pop(0)
    volume_other = (np.sum(col_other) + 10*volume_other) / 15

    col_target_ding.append(volume_target_ding)
    while len(col_target_ding) > 5:
        col_target_ding.pop(0)
    volume_target_ding = (np.sum(col_target_ding) + 10*volume_target_ding) / 15

    col_target_dong.append(volume_target_dong)
    while len(col_target_dong) > 5:
        col_target_dong.pop(0)
    volume_target_dong = (np.sum(col_target_dong) + 10*volume_target_dong) / 15

    # Debug
    if DEBUG > 1:
        print("Debug: DING", volume_target_ding/volume_other, "DONG", volume_target_dong/volume_other)

    # Check ratio
    if (volume_target_ding/volume_other > DING_TRES):
        if DEBUG > 0:
            print("Detected: DING with intensity {}>{}".format(volume_target_ding/volume_other,DING_TRES))
        last_detected_ding = time.time()
        max_intensity_ding = max(max_intensity_ding, volume_target_ding/volume_other)

    if (volume_target_dong/volume_other > DONG_TRES):
        if DEBUG > 0:
            print("Detected: DONG with intensity {}>{}".format(volume_target_dong/volume_other,DONG_TRES))
        last_detected_dong = time.time()
        max_intensity_dong = max(max_intensity_dong, volume_target_dong/volume_other)

    interval = last_detected_dong - last_detected_ding
    if (last_detected_ding > 0) and (last_detected_dong > 0) and (interval > 0) and (interval < DING_DONG_INTERVAL):
        if DEBUG > 0:
            print("Detected: DING DONG! with max intensity ding {} dong {}".format(max_intensity_ding, max_intensity_dong))
        else:
            print("DING DONG!")
            os.system(os.path.dirname(os.path.abspath(__file__)) + "/detect.py")
        last_detected_ding = 0
        last_detected_dong = 0
        max_intensity_ding = 0
        max_intensity_dong = 0

if SIMULATE_WAVEFILE == "":
	stream.close()
p.terminate()
