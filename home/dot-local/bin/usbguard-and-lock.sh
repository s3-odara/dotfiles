#!/bin/sh

POLICY_UNLOCKED=apply-policy
POLICY_LOCKED=reject

revert() {
  usbguard set-parameter InsertedDevicePolicy $POLICY_UNLOCKED
}

trap revert SIGHUP SIGINT SIGTERM

usbguard set-parameter InsertedDevicePolicy $POLICY_LOCKED

waylock -ignore-empty-password -fork-on-lock
revert
