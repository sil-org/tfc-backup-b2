#!/usr/bin/env sh

STATUS=0
myname="tfc-backup-b2"

echo "${myname}: init: Started"

start=$(date +%s)
/usr/local/bin/restic init || STATUS=$?
end=$(date +%s)

if [ $STATUS -ne 0 ]; then
	echo "${myname}: FATAL: Repository initialization returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
	exit $STATUS
else
	echo "${myname}: Repository initialization completed in $(expr ${end} - ${start}) seconds."
fi

echo "${myname}: init: Completed"
exit $STATUS
