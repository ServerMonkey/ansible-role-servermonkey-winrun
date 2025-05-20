#!/bin/sh
#info: Start a Windows application on Desktop, Windows user must be logged in

set -e

APP_USER="$1"
APP_PASS="$2"
APP_PATH="$3"
APP_ARGS="$4"
APP_FORCE="$5"

error() {
    echo "ERROR: $1" >&2
    exit 1
}

search_path() {
    SEARCH="$1"
    APP="$2"

    if [ -d "$SEARCH" ]; then
        FOUND=$(find "$SEARCH" -maxdepth 4 -type f -name "$APP" 2>/dev/null)
        FIRST=$(echo "$FOUND" | head -n1)
        if [ -n "$FIRST" ]; then
            echo "$FIRST"
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

if [ "$APP_FORCE" = "true" ] || [ "$APP_FORCE" = "True" ]; then
    APP_FORCE="true"
fi

# verify args
[ -z "$APP_PATH" ] && error "variable APP_PATH is empty"
[ -z "$APP_USER" ] && error "variable APP_USER is empty"
[ -z "$APP_PASS" ] && error "variable APP_PASS is empty"

# verify requirements
if [ -z "$(command -v schtasks)" ]; then
    error "schtasks is not installed"
fi
if [ -z "$(command -v uuidgen)" ]; then
    error "uuidgen is not installed"
fi
if [ -z "$(command -v cygpath)" ]; then
    error "cygpath is not installed"
fi

PATH_WIN="$(cygpath -uW)" || error "get Windows path"
PATH_WIN_ROOT=$(dirname "$PATH_WIN") || error "dirname $PATH_WIN"
APP_PATH_NIX=$(cygpath -u "$APP_PATH") ||
    error "convert path to Unix: $APP_PATH"
[ -z "$APP_PATH_NIX" ] && error "variable APP_PATH_NIX is empty"
APP_BASE_NAME=$(basename "$APP_PATH_NIX")
UUID=$(uuidgen | tr -d '-') || error "generate UUID"
TIMESTAMP=$(date +"%Y.%m.%d %H.%M %z") || error "get timestamp"
TASK_NAME="Ansible-winrun $TIMESTAMP UUID-$UUID"
INFO_TAG="UUID-$UUID $APP_BASE_NAME"
PATH_SYS=$(cygpath -uS) || error "get System32 path"
PATH_DESK=$(cygpath -uD) || error "get Desktop path"
PATH_PROGRAMS=$(cygpath -u "$PROGRAMFILES") || error "get 'Program Files' path"
PATH_APPS="$PATH_PROGRAMS/WindowsApps"

# search paths
PATH_OPT="$PATH_WIN_ROOT/opt"
APP_PATH_NIX="$PATH_WIN_ROOT/$APP_PATH"
APP_PATH_NIX_OPT="$PATH_OPT/$APP_PATH"
APP_PATH_NIX_WIN="$PATH_WIN/$APP_PATH"
APP_PATH_NIX_S32="$PATH_SYS/$APP_PATH"
APP_PATH_NIX_PRO="$PATH_PROGRAMS/$APP_PATH"

# search for the application
# starts with /, absolute path
APP_PATH_FINAL=""
if [ -f "$APP_PATH_NIX" ]; then
    # /c/cygdrive/hello.exe --> SAME
    APP_PATH_FINAL="$APP_PATH_NIX"
elif [ -f "$APP_PATH_NIX" ]; then
    # /cygdrive/c + hello.exe
    APP_PATH_FINAL="$APP_PATH_NIX"
elif [ -f "$APP_PATH_NIX_OPT" ]; then
    # /cygdrive/c/opt + hello.exe
    APP_PATH_FINAL="$APP_PATH_NIX_OPT"
elif [ -f "$APP_PATH_NIX_WIN" ]; then
    # /cygdrive/c/Windows + hello.exe
    APP_PATH_FINAL="$APP_PATH_NIX_WIN"
elif [ -f "$APP_PATH_NIX_S32" ]; then
    # /cygdrive/c/Windows/System32 + hello.exe
    APP_PATH_FINAL="$APP_PATH_NIX_S32"
elif [ -f "$APP_PATH_NIX_PRO" ]; then
    # /cygdrive/c/Program Files + hello.exe
    APP_PATH_FINAL="$APP_PATH_NIX_PRO"
# if does not start with /, do a recursive search
elif echo "$APP_PATH" | grep -qv "^/"; then
    if APP_PATH_FINAL=$(search_path "$PATH_OPT" "$APP_PATH"); then
        # /cygdrive/c/opt + find hello.exe
        :
    elif APP_PATH_FINAL=$(search_path "$PATH_DESK" "$APP_PATH"); then
        # /cygdrive/c/Users/username/Desktop + find hello.exe
        :
    elif APP_PATH_FINAL=$(search_path "$PATH_APPS" "$APP_PATH"); then
        # /cygdrive/c/Program Files/WindowsApps + find hello.exe
        :
    else
        error "can not find $APP_PATH "
    fi
else
    error "file does not exist in any absolute path: $APP_PATH"
fi

[ -z "$APP_PATH_FINAL" ] && error "variable APP_PATH_FINAL is empty"

# verify schtasks command
check() {
    FAIL=true
    STDOUT=""
    STDOUT="$(echo "$2" | sed '/^ *$/d' | awk '{$1=$1;print}' |
        sed '/ST is earlier/d')"

    if echo "$STDOUT" | grep -qF "^ERROR"; then
        FAIL=true
    elif echo "$STDOUT" | grep -qF "^WARNING"; then
        FAIL=true
    elif echo "$STDOUT" | grep -vq "^SUCCESS"; then
        # if not successful
        FAIL=true
    else
        FAIL=false
    fi

    if [ "$FAIL" = "true" ]; then
        echo "CMD:"
        echo "$CMD_1"
        echo "$CMD_2 $CMD_3"
        echo "ERROR $1 TASK: $INFO_TAG" >&2
        echo "REASON: $STDOUT" >&2
        # remove task if failed
        sleep 1
        schtasks /Delete /TN "$TASK_NAME" /F 1>/dev/null 2>&1 || true
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
        echo "ERROR DELETE TASK: $INFO_TAG" >&2
        echo "REASON: $STDOUT" >&2
        exit 1
    fi
}

### MAIN ######################################################################

# detect different Windows versions
WIN_VER=$(regtool get "/HKLM/SOFTWARE/Microsoft/Windows NT/CurrentVersion/ProductName")

# to run desktop application, user must be logged in
if [ "$APP_FORCE" != "true" ]; then
    LIST_USERS=$(qwinsta "$USER" 2>/dev/null) || error "can not get user list"
    if echo "$LIST_USERS" | tail -n1 | awk '{print $4}' |
        grep -vxq 'Disc\|Active'; then
        error "User is not logged in $INFO_TAG"
    fi
fi

# add task
START_BIN=$(cygpath -w "$APP_PATH_FINAL") ||
    error "can not convert path to Windows: $APP_PATH_FINAL"
[ -z "$START_BIN" ] && error "variable START_BIN is empty"

TIME="00:00:00"
DATE="01/01/1970"

if echo "$WIN_VER" | grep -q "Windows XP"; then
    FLAGS="/SC ONCE"
else
    FLAGS="/SC ONCE /IT /V1"
fi

CMD_1="schtasks /Create /SC ONCE /TN \"$TASK_NAME\""
CMD_2="/TR \"$START_BIN $APP_ARGS\" /SD $DATE /ST $TIME"
CMD_3="/RU \"$APP_USER\" /RP \"$APP_PASS\" $FLAGS"

# shellcheck disable=SC2086
RESULT_ADD=$(schtasks /Create \
    /TN "$TASK_NAME" \
    /TR "\"$START_BIN\" $APP_ARGS" \
    /SD "$DATE" /ST "$TIME" \
    /RU "$APP_USER" /RP "$APP_PASS" \
    $FLAGS \
    2>&1 || true)

check ADD "$RESULT_ADD" || error "check add"

# run task
RESULT_RUN=$(schtasks /Run /TN "$TASK_NAME" 2>&1 || true)
check RUN "$RESULT_RUN" || error "check run"

# must wait a second or it will fail
sleep 1

# cleanup task that should have been run
RESULT_DEL=$(schtasks /Delete /TN "$TASK_NAME" /F 2>&1 || true)
check_removed "$RESULT_DEL" || error "check removed"

echo "Ansible-winrun OK $UUID"
