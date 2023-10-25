#!/bin/sh
#info: Start a Windows application on Desktop, Windows user must be logged in

APP_USER="$1"
APP_PASS="$2"
APP_PATH="$3"
APP_ARGS="$4"
APP_FORCE="$5"

if [ "$APP_FORCE" = "true" ] || [ "$APP_FORCE" = "True" ]; then
    APP_FORCE="true"
fi

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
TASK_NAME="Ansible-winrun $TIMESTAMP UUID-$UUID"
INFO_TAG="UUID-$UUID $APP_PATH_WIN"

# target does not exist
if [ ! -f "$APP_PATH_WIN" ]; then
    echo "ERROR: $APP_PATH_WIN does not exist" >&2
    exit 1
fi

# verify schtasks command
check() {
    STDOUT=""
    STDOUT="$(echo "$2" | sed '/^ *$/d' | awk '{$1=$1;print}')"
    if ! echo "$STDOUT" | grep -q "^SUCCESS"; then
        echo "$1 task ERROR: $INFO_TAG" >&2
        echo "reason: $STDOUT" >&2
        # remove task if failed
        sleep 1
        schtasks /Delete /TN "$TASK_NAME" /F 1>/dev/null 2>&1
        exit 1
    fi
}

check_removed() {
    STDOUT=""
    STDOUT="$(echo "$1" | sed '/^ *$/d' | awk '{$1=$1;print}')"
    if echo "$STDOUT" | grep -q "^SUCCESS"; then
        :
    elif echo "$STDOUT" | grep -qF "does not exist"; then
        :
    else
        echo "delete task ERROR: $INFO_TAG" >&2
        echo "reason: $STDOUT" >&2
        exit 1
    fi
}

### MAIN ######################################################################

# ignore if there is no desktop session
if [ "$APP_FORCE" != "true" ]; then
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
RESULT_RUN=$(schtasks /Run /TN "$TASK_NAME")
check run "$RESULT_RUN"

# must wait a second or it will fail
sleep 1

# remove task immediately
RESULT_DEL=$(schtasks /Delete /TN "$TASK_NAME" /F 2>&1)
check_removed "$RESULT_DEL"

echo "Ansible-winrun OK $UUID"
