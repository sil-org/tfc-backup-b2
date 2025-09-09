#!/usr/bin/env sh

STATUS=0
myname="tfc-backup-b2"

# Function to log errors to Sentry
error_to_sentry() {
    if [ -n "$SENTRY_DSN" ]; then
        sentry-cli send-event "$1" 2>/dev/null
    fi
}

echo "${myname}: Backing up ${SOURCE_PATH}"

start=$(date +%s)
/usr/local/bin/restic backup --host ${RESTIC_HOST} --tag ${RESTIC_TAG} ${RESTIC_BACKUP_ARGS} ${SOURCE_PATH} || STATUS=$?
end=$(date +%s)

if [ $STATUS -ne 0 ]; then
	echo "${myname}: FATAL: Backup returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
	error_to_sentry "${myname}: Backup failed with status $STATUS in $(expr ${end} - ${start}) seconds"
	exit $STATUS
else
	echo "${myname}: Backup completed in $(expr ${end} - ${start}) seconds."
fi

start=$(date +%s)
/usr/local/bin/restic forget --host ${RESTIC_HOST} ${RESTIC_FORGET_ARGS} --prune || STATUS=$?
end=$(date +%s)

if [ $STATUS -ne 0 ]; then
	echo "${myname}: FATAL: Backup pruning returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
	error_to_sentry "${myname}: Backup pruning failed with status $STATUS in $(expr ${end} - ${start}) seconds"
	exit $STATUS
else
	echo "${myname}: Backup pruning completed in $(expr ${end} - ${start}) seconds."
fi

start=$(date +%s)
/usr/local/bin/restic check || STATUS=$?
end=$(date +%s)

if [ $STATUS -ne 0 ]; then
	echo "${myname}: FATAL: Repository check returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
	error_to_sentry "${myname}: Repository check failed with status $STATUS in $(expr ${end} - ${start}) seconds"
	exit $STATUS
else
	echo "${myname}: Repository check completed in $(expr ${end} - ${start}) seconds."
fi

start=$(date +%s)
/usr/local/bin/restic unlock || STATUS=$?
end=$(date +%s)

if [ $STATUS -ne 0 ]; then
	echo "${myname}: FATAL: Repository unlock returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
	error_to_sentry "${myname}: Repository unlock failed with status $STATUS in $(expr ${end} - ${start}) seconds"
	exit $STATUS
else
	echo "${myname}: Repository unlock completed in $(expr ${end} - ${start}) seconds."
fi

exit $STATUS
