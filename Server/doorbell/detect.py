#!/usr/bin/env python3

import os

dir=os.path.dirname(os.path.abspath(__file__)) + "/detect.d/"

for root, dirs, files in os.walk(dir):
   for fname in files:
       os.system(dir + fname + " &")

