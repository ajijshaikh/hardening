#!/bin/bash

mkdir -p /run/keytemp
LOCK_FILE="/run/keytemp/lock_key"

function finish {
	rm -f $LOCK_FILE
}
trap finish EXIT

echo "generation of auto unlock key."

. /usr/local/etc/auto_unlock.conf

if [ "$KEYSLOT" = "0" ]; then
	echo "Cannot use key slot 0"
	exit 10
fi

echo "Type in YES to set-up LUKS key based on information above"
read ANSWER

if [ "$ANSWER" != "YES" ]; then
	echo "Exiting without setup"
	exit 5
fi

echo "this is my autounlock key" > $LOCK_FILE
echo "Checksum of lockfile $(md5sum $LOCK_FILE)"
echo "Stored lock file in $LOCK_FILE, please delete it manually if you cancel script execution"

echo "Parsing /etc/crypttab"

for TEXT in $(awk '/^..*$/ {print $1 ":" $2}' /etc/crypttab); do
	
	NAME=`echo "$TEXT" | cut -d: -f1`
	DEVICE=`echo "$TEXT" | cut -d: -f2`

	case $DEVICE in
		/dev/*) ;;
		UUID=*) UUID=${DEVICE##UUID=} 
			DEVICE=$(blkid -U "$UUID")
		;;
	esac

	if [ -z "$DEVICE" ]; then #its true if $DEVICE is null
		continue
	fi

	echo "found partition $DEVICE for $NAME"

	if [ ! -b $DEVICE ]; then #check if it is block device
		echo "Cannot work on $DEVICE, not a block device"
		continue
	fi

	SLOTS=`cryptsetup luksDump $DEVICE | grep '^Key Slot'`
	SLOT_USAGE=`echo "$SLOTS" | grep "Key Slot $KEYSLOT"`

	echo -e "slots usage for $DEVICE\n------\n${SLOTS}\n---------\n"

	SLOT_OK=
	case "$SLOT_USAGE" in 
		*DISABLED) SLOT_OK=1 ;;
		*ENABLED)
			echo "Slot $KEYSLOT is used for device $NAME $DEVICE"
			echo "Do you want to override it? Type YES to override"
			read ANSWER
			if [ "$ANSWER" != "YES" ]; then
				echo "Not overriding ..."
				continue
			fi
			cryptsetup luksKillSlot $DEVICE $KEYSLOT
			SLOT_OK=1
	esac

	if [ "$SLOT_OK" = "1" ]; then
		cryptsetup luksAddKey --key-slot $KEYSLOT $DEVICE $LOCK_FILE
	fi

done


