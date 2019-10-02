#!/bin/bash

# strict mode
set -euo pipefail

# script specific vars
PROGNAME=$(basename "$0")
VERSION=1.0

# defaults
: ${DEBUG:=}
: ${LOCK_FILE:=}
: ${LOCK_FD:=200}
: ${LOG_FILE:=}
: ${COMMAND:=}

: ${LOG_ENABLED:=}
: ${TS_ENABLED:=}
: ${SILENT_ENABLED:=}
: ${PID_ENABLED:=}
: ${ERR_HL_ENABLED:=}

# tools
: ${TS:=/usr/bin/ts}

# functions
msg() {
    echo "$@"
}

err() {
    >&2 echo "$@"
}

errcat() {
    >&2 cat
}

lock () {
    local lockfile="$1" lockfd="$2"
    eval "exec $lockfd>$lockfile"
    flock --nonblock $lockfd
}

print_help() {
    cat <<EOF
$PROGNAME [options] [--] <command>

Version: $VERSION
Description: run <command> acquiring the lock over some file, so other command won't be able
             to run simultaneously

Options:
-l|--lock <lockfile>               <lockfile> will be the file to acquire lock
-j|--journal|--log <logfile>       <logfile> will be the file to print log
-t|--ts|--timestamp                enable timestamping (in logfile)
-s|--silent                        supress normal stdout/stderr, just print to log if specified
-p|--pid                           add pid before every line (in logfile)
-e|--err|--highlight-errors        add [ERR] before every line from stderr (in logfile)
-h|--help                          print this help and exit

Examples:
$PROGNAME -l lockfile -j log -tpes -- ./test-script.sh 1 10
$PROGNAME -l lockfile -j log -tpes -- sleep 100000

EOF
}

parse_opts() {
    local TEMP PARSE_OPTS_STATUS
    TEMP=$(getopt -o l:j:tspeh --long lock:,journal:,log:,ts:,timestamp:,silent,pid,err,highlight-errors,help,debug,dbg -- "$@")
    PARSE_OPTS_STATUS="$?"
    if [ "$PARSE_OPTS_STATUS" != 0 ]; then
	err "Error in parsing options";
	exit 1
    fi

    # modify cmdline
    eval set -- "$TEMP"
    unset TEMP

    # parse cmdline options
    while true; do
	case "$1" in
	    -h|--help) print_help; exit 0;;
	    --debug|--dbg) DEBUG=y; shift;;
	    -l|--lock) LOCK_FILE="$2"; shift 2;;
	    -j|--journal|--log) LOG_ENABLED=y; LOG_FILE="$2"; shift 2;;
	    -t|--ts|--timestamp) TS_ENABLED=y; shift;;
	    -s|--silent) SILENT_ENABLED=y; shift;;
	    -p|--pid) PID_ENABLED=y; shift;;
	    -e|--err|--highlight-errors) ERR_HL_ENABLED=y; shift;;
	    --) shift; break;;
	    *) err "Unknown option $1"; exit 1;;
	esac
    done

    # all the rest is the command
    COMMAND="$@"
}

print_conf() {
    errcat <<EOF
---------- Configuration ----------
PROGNAME=$PROGNAME
VERSION=$VERSION
LOCK_FILE=$LOCK_FILE
LOG_FILE=$LOG_FILE
LOG_ENABLED=$LOG_ENABLED
TS_ENABLED=$TS_ENABLED
SILENT_ENABLED=$SILENT_ENABLED
PID_ENABLED=$PID_ENABLED
ERR_HL_ENABLED=$ERR_HL_ENABLED
-----------------------------------
EOF
}

check_conf() {
    local found_conf_errors=

    if [ -z "$LOCK_FILE" ]; then
	found_conf_errors=y
	errcat <<EOF
Lock file not set. Check -l|--lock option.
EOF
    fi

    if [ -n "$LOG_ENABLED" ]; then
	if ! touch "$LOG_FILE"; then
	    found_conf_errors=y
	    errcat <<EOF
Cannot access log file: $LOG_FILE
EOF
	fi
    fi

    if [ -z "$COMMAND" ]; then
	found_conf_errors=y
	errcat <<EOF
Command is not specified. Check -h|--help option.
EOF
    fi

    # --- stop if errors found ---
    if [ -n "$found_conf_errors" ]; then
	exit 3
    fi
}

# PROGRAM

# init
parse_opts "$@"
if [ -n "$DEBUG" ]; then
    print_conf
fi
check_conf

# modify output
if [ -n "$LOG_ENABLED" ]; then
    if [ -n "$TS_ENABLED" ] && [ -x "$TS" ]; then
	exec 3> >($TS '[%Y-%m-%d %H:%M:%S]' >>$LOG_FILE)
    else
	exec 3>>$LOG_FILE
    fi

    if [ -n "$SILENT_ENABLED" ]; then
	# silent (supress stderr/stdout)
	if [ -n "$PID_ENABLED" ]; then
	    # with pid
	    exec > >(sed -u "s/^/[$$] /" >&3)
	    if [ -n "$ERR_HL_ENABLED" ]; then
		# with err
		exec 2> >(sed -u "s/^/[$$] [ERR] /">&3)
	    else
		# w/o err
		exec 2> >(sed -u "s/^/[$$] /" >&3)
	    fi
	else
	    # w/o pid
	    exec >&3
	    if [ -n "$ERR_HL_ENABLED" ]; then
		# with err
		exec 2> >(sed -u "s/^/[ERR] /" >&3)
	    else
		# w/o err
		exec 2>&3
	    fi
	fi
    else
	# not silent
	if [ -n "$PID_ENABLED" ]; then
	    # with pid
	    exec > >(tee >(sed -u "s/^/[$$] /" >&3) >&1)
	    if [ -n "$ERR_HL_ENABLED" ]; then
		# with err
		exec 2> >(tee >(sed -u "s/^/[$$] [ERR] /" >&3) >&2)
	    else
		# w/o err
		exec 2> >(tee >(sed -u "s/^/[$$] /" >&3) >&2)
	    fi
	else
	    # w/o pid
	    exec > >(tee >(cat >&3) >&1)
	    if [ -n "$ERR_HL_ENABLED" ]; then
		# with err
		exec 2> >(tee >(sed -u "s/^/[ERR] /" >&3) >&2)
	    else
		# w/o err
		exec 2> >(tee >(cat >&3) >&2)
	    fi
	fi
    fi
fi

# run script
if lock "$LOCK_FILE" "$LOCK_FD"; then
    msg "RUN: $COMMAND"
    $COMMAND &
    cmd_pid=$!
    trap "kill $cmd_pid" SIGTERM SIGINT
    wait $cmd_pid
    msg "DONE: $COMMAND"
else
    err "Another instance of this script is already running, exit"
fi

exit 0
