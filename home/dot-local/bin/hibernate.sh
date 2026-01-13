#!/bin/bash

sleep 1
echo disk > /sys/power/state

sleep 3
/usr/local/bin/cpu-scaling.sh

