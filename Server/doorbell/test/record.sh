#!/bin/bash
arecord --device=plughw:1,0 --format S16_LE --rate 44100 -c1 /tmp/test.wav

