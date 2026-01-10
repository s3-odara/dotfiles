#!/bin/sh

#usbguard set-parameter InsertedDevicePolicy block
doas /usr/bin/systemctl start usbkill.service

