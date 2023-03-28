#!/bin/sh
#info: Start a Windows application on Desktop, Windows user must be logged in

APP_USER="$1"
APP_PASS="$2"
APP_PATH="$3"
APP_ARGS="$4"

# verify args
if [ -z "$APP_PATH" ]; then
    echo "ERROR: variable APP_PATH is empty" >&2
    exit 1
fi
if [ -z "$APP_USER" ]; then
    echo "ERROR: variable APP_USER is empty" >&2
    exit 1
fi
if [ -z "$APP_PASS" ]; then
    echo "ERROR: variable APP_PASS is empty" >&2
    exit 1
fi

# verify requirements
if [ -z "$(command -v schtasks)" ]; then
    echo "ERROR: schtasks is missing" >&2
    exit 1
fi

APP_PATH_WIN=$(echo "$APP_PATH" | sed 's|\\|/|g')
UUID=$(uuidgen | tr -d '-')
TIMESTAMP=$(date +"%Y.%m.%d %H.%M %z")
TASK_NAME="Ansible-SSH-runner $TIMESTAMP UUID-$UUID"
INFO_TAG="UUID-$UUID $APP_PATH_WIN"

# verify schtasks command
check() {
    if ! echo "$2" | grep -q "^SUCCESS"; then
        echo "ERROR: Failed to $1 task $INFO_TAG" >&2
        echo "$2" | sed '/^ *$/d' >&2
        # remove task if failed
        sleep 1
        schtasks /Delete /TN "$TASK_NAME" /F 1>/dev/null
        exit 1
    fi
}

### MAIN ######################################################################

# check if there are any desktop session
DESKTOP_LOGGED_IN=$(tasklist /NH /V | grep "explorer.exe")
if [ -z "$DESKTOP_LOGGED_IN" ]; then
    echo "ERROR: There are no Desktop sessions $INFO_TAG" >&2
    exit 1
fi

# check if there is a desktop session for the target user
if ! echo "$DESKTOP_LOGGED_IN" | grep -q "\\$APP_USER "; then
    echo "ERROR: '$APP_USER' is not logged in to a Desktop $INFO_TAG" >&2
    exit 1
fi

# add task
RESULT_ADD=$(schtasks /Create \
    /SC ONCE \
    /TN "$TASK_NAME" \
    /TR "$APP_PATH_WIN $APP_ARGS" \
    /SD "01/01/1970" /ST "00:00:00" \
    /RU "$APP_USER" /RP "$APP_PASS")
check add "$RESULT_ADD"

# run task
RESULT_RUN=$(schtasks /Run \
    /TN "$TASK_NAME")
check run "$RESULT_RUN"

# must wait a second or it will fail
sleep 1

# remove task immediately
RESULT_DEL=$(schtasks /Delete \
    /TN "$TASK_NAME" /F)
check delete "$RESULT_DEL"

echo "Ansible-SSH-runner OK $UUID"
