#!/bin/bash

sleep 1
echo mem > /sys/power/state

sleep 1
/usr/local/bin/cpu-scaling.sh

