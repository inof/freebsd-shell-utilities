#!/bin/sh -
#   The above line exists only to make syntax highlighter happy.
#   Note that it doesn't make sense to execute this file directly.
#
#   Copyright (c) 2010-2026, GitHub user "inof"
#   Standard 2-clause BSD license and disclaimer apply.
#   SPDX-License-Identifier: BSD-2-Clause
#   https://opensource.org/licenses/BSD-2-Clause
#
#   This file contains a lot of useful functions for shell scripts.
#   It is meant to be used with FreeBSD's /bin/sh that is lacking some
#   features present in zsh, ksh and bash.
#
#   HIGHLIGHTS:  Among other things, there are various string functions
#                (match, contains, isdigit, split, ...), diagnostics
#                and user interation (Err, Warn, Debug, Confirm, Query),
#                file handling (getsize, getowner, getmtime), a simple
#                way to handle command line options (std_getopts) and to
#                quote arbitrary arguments (quote_args), some functions
#                that are similar to Python constructs (range, enumerate),
#                colorized output (red, green, ...), progress report for
#                long-running jobs, handling of X11 resources and X11 cut
#                buffers (so a shell script can let the user mark some
#                text with the mouse), and more.
#
#   USAGE:  Include this line at the beginning of your scripts:
#
#               . utils.sh		# Search $PATH first, then in $PWD.
#           or:
#               . "${0%/*}"/utils.sh	# Same directory as main script.
#
#           The first will probably not work when your script is started
#           via cron(1) because utils.sh is probably no in the default
#           $PATH, unless you set it in your crontab(5) explicitly.
#           Therefore, the second variant is recommended for cron scripts.
#
#   This file can be used safely with "set -Cefu" (recommended).
#
#   NOTE:  Functions and variables beginning with an underscore
#          are for internal use only.
#
#   INDEX:
#   ======
#
#	ME		Err		Warn		Note		Debug
#	Warn_prefix	Confirm		Query
#
#	match		startswith	endswith	contains
#	not		eq		neq
#	have		no		empty		nonempty
#
#	isdigit		isalpha		isalnum		isupper		islower
#	isident
#
#	isnatural	isinteger	ispositive	in_range	zeropad
#
#	exists		isfile		isdir		islink		isatty
#	isreadable	newer		older		same_file
#	empty_file	nonempty_file	empty_dir	nonempty_dir	safe_dir
#	getsize		getowner	getgroup	getmtime
#	getctime	getatime	getmodes	getperm
#	isabsolute	isrelative
#
#	bool		cond		assert		let		length
#	range		assign		augment		default		split
#	str_split	strip		charcut
#
#	argv_init	argv_add	argv_count	argv_get	argv_words
#	argv_quote	argv_doublequote
#	record		array		Set		dict
#	quote_args	quote_regex	add_path	std_getopts
#	enumerate	repeat
#
#	ATTR_RED	ATTR_GREEN	ATTR_YELLOW	ATTR_BLUE	ATTR_PURPLE
#	ATTR_CYAN	ATTR_GREY	ATTR_ORANGE	ATTR_OFF
#	ATTR_BG_PURPLE
#	BOLD_ON		BOLD_OFF	ULINE_ON	ULINE_OFF
#	ITAL_ON		ITAL_OFF	REV_ON		REV_OFF
#	red		green		yellow		blue		purple
#	cyan		magenta		grey		orange
#	bg_purple
#	bold		italics		reverse		underline
#	color		double
#
#	progress_start	progress_value	HMS_to_S	S_to_HMS	th_sep
#
#	get_resource		set_resource
#	add_resource_string	remove_resource_string
#
#	get_selection	cp_stat
#
#	round_down	round_up	within_percent
#

#   Set "UTILS_DEBUG=true" before sourcing this file in order to
#   receive debug output from some of the functions.
if [ "_${UTILS_DEBUG-}" != "_true" ]; then
	UTILS_DEBUG=false
fi

#
#   Set $ME to the base name of the script, or just "sh" if running
#   interactively.
#   Also define some useful constants for control characters.
#

ME="${0##*/}"	# base name of the main script
NL=$'\n'	# newline (a.k.a. line feed), 0x0A
LF=$'\n'	# ditto
CR=$'\r'	# carriage return, 0x0D
ESC=$'\e'	# escape, 0x1B
TAB=$'\t'	# tabulator, 0x09
BEL=$'\a'	# ascii bell, 0x07

#
#   This function is used internally, but you can use it yourself, too.
#   Usage:  Diag <func> <prefix> <line ...>
#    - <func> is the name of a function that prints its arguments.
#             You can use "echo" or one of the functions for colorized
#             output ("red", "green", ...).
#    - <prefix> is prepended in front of the first line, separated by
#               a space (if non-empty).  Further lines are indented so
#               they line up nicely.
#    - <line ...> are one or more lines of text.
#   For example, you can define your own Hint() function like this:
#     Hint () { Diag blue "Hint:" "$@"; }
#

Diag ()
{
	local OUT_FUNC="$1" PREFIX="$2"
	shift 2
	local LINE FIRST=true

	for LINE in "$@"; do
		$OUT_FUNC "${PREFIX}${PREFIX:+ }$LINE" >&2
		if $FIRST; then
			PREFIX=$(printf '%*s' ${#PREFIX} "")
			FIRST=false
		fi
	done
}

#
#   Define useful diagnostic functions (you can override them in your
#   script if you need them to be more sophisticated).
#    - Err() prints a message in red, prefixed by the script's name,
#            and exits with code 1.  If the -n option is specified,
#            exit is supressed.
#    - Warn() prints a message in orange, by default prefixed by the
#             script's name and the word "WARNING".  The prefix can be
#             changed with the Warn_prefix() function.
#    - Note() prints a message in yellow.
#    - Debug() prints a message with purple background, prefixed by the
#              script's name and the tag "[DEBUG]", but only if $DEBUG
#              is true.  It is suggested that your script supports an
#              option -D that sets $DEBUG accordingly.  The std_getopts()
#              function implements this by default, see below.
#   All the output from the above function goes to stderr.  If stderr is
#   not a TTY, colors are suppressed.
#

Err ()
{
	local NO_EXIT=false

	if eq "${1-}" "--"; then
		shift
	elif eq "${1-}" "-n"; then
		NO_EXIT=true
		shift
	fi

	Diag red "${ME}:" "$@"

	if ! $NO_EXIT; then
		exit 1
	fi
}

Warn_prefix ()
{
	_WARN_PREFIX="$*"
}

Warn_prefix "${ME}: WARNING:"

Warn ()
{
	Diag orange "$_WARN_PREFIX" "$@"
}

Note ()
{
	Diag yellow "" "$@"
}

Debug ()
{
	if ${DEBUG:-false}; then
		Diag bg_purple "${ME} [DEBUG]" "$@"
	fi
}

#
#   Print a message ($*) and ask for confirmation ([y]es or [n]o).
#   The default message is:  "Are you sure?"
#   If the answer is [y]es, return success (0).
#   If the answer is [n]o, exit with an error message: "Cancelled by user."
#   If the answer is anything else, print a warning and keep asking.
#   Options:
#       -a    Exit on any answer that is not [y]es, i.e. don't insist on
#             having to type [n]o.
#       -e <msg>    Specify a different error message upon exit.
#       -n    If the user replies [n]o (or anything that is not [y]es if
#             the -a option is in effect), don't exit, but return silently
#             with return code 1, so the main script can decide if and how
#             to proceed.
#

Confirm ()
{
	local ERR_MSG="" NO_EXIT=false ANY_CANCEL=false
	local MSG REPLY

	while match "${1-}" "-a|-e|-n"; do
		if eq "$1" "-a"; then
			ANY_CANCEL=true
			shift
		elif eq "$1" "-e"; then
			ERR_MSG="${2-}"
			shift 2
		elif eq "$1" "-n"; then
			NO_EXIT=true
			shift
		fi
	done
	MSG="$*"
	if no "$MSG"; then
		MSG="Are you sure?"
	fi
	if no "$ERR_MSG"; then
		ERR_MSG="Cancelled by user."
	fi
	while :; do
		cyan -n "$MSG [y/n] " >&2
		read REPLY
		if match "$REPLY" '[Yy]|[Yy][Ee][Ss]'; then
			return 0
		elif $ANY_CANCEL || match "$REPLY" '[Nn]|[Nn][Oo]'; then
			if $NO_EXIT; then
				return 1
			else
				Err "$ERR_MSG"
			fi
		else
			Warn 'Please enter "y" or "n"!'
		fi
	done
}

#
#   Print a message ($1) and ask the user for a choice.
#
#   The arguments starting at $2 are patterns, each one represents a valid
#   reply.  If the user enters a reply matching one of the patterns, the
#   return code is the ordinal number of the pattern, starting at 1, i.e.
#   return code 1 for pattern $2, return code 2 for pattern $3, and so on.
#   If multiple patterns match, the first one is taken.
#   If the reply does not match any of the patterns, print a warning and
#   keep asking.  Note that the function never returns code 0.
#
#   Options:
#       -a    If the reply does not match any of the patterns, do not keep
#             asking.  In this case, the return code is one more than the
#             maximum number.  Example:  If there are 3 patterns, return
#             codes 1 to 3 are used for valid answers, and return code 4
#             is used if there is no match and the -a option has been used.
#
#   Examples:
#
#   if Query "Are you sure? [y/n] " '[Yy]' '[Nn]' || eq $? 1; then
#   # Note: similar to:  if Confirm -n; then
#           ... yes ...
#   else
#           ... no ...
#   fi
#
#   Query "Retry, Wait, Cancel? [r/w/c] " '[Rr]' '[Ww]' '[Cc]' \
#   || case $? in
#           1)      ... ;;
#           2)      ... ;;
#           3)      ... ;;
#   esac
#

Query ()
{
	local RETURN_NOMATCH=false
	local MSG REPLY NUM ARG

	if eq "${1-}" "-a"; then
		RETURN_NOMATCH=true
		shift
	fi

	MSG="${1-}"
	shift

	while :; do
		cyan -n "$MSG" >&2
		read REPLY
		enumerate NUM ARG 'if match "$REPLY" "$ARG"; then break; fi' "$@" '*'
		if $(( NUM <= $# )) || $RETURN_NOMATCH; then
			return $NUM
		fi
		Warn 'Invalid reply, please try again.'
	done
}

#
#   Generate a standard Usage() function with the given text.
#   There are two ways to specify the text:
#   1.  It can be specified as arguments to the command, where each
#       argument is one line of the usage text (arguments may also
#       contain $NL).
#   2.  If no arguments are specified, the usage text is read from
#       standard input.  This is meant to be used with the "<<" syntax
#       of the shell (so-called "here-document").
#
#   Examples (all do the same thing):
#       Usage_Text "Usage: $ME <file>" "Frobnicates the given file."
#       Usage_Text "Usage: $ME <file>${NL}Frobnicates the given file."
#       Usage_Text <<-EOU
#               Usage: $ME <file>
#               Frobnicates the given file.
#       EOU
#
#   Options:
#      -c   Use the color() function, so color tags are supported.
#

Usage_Text ()
{
	#global _USAGE_TEXT
	#global _COLOR_FUNC
	local LINE

	_COLOR_FUNC=yellow
	while startswith "${1-}" "-"; do
		case "$1" in
			-c)	_COLOR_FUNC=color ; shift ;;
			--)	shift ; break ;;
			#   Any unknown option is assumed to be part of the message.
			*)	break
		esac
	done

	if $(( $# != 0 )); then
		_USAGE_TEXT=""
		for LINE in "$@"; do
			_USAGE_TEXT="${_USAGE_TEXT}${_USAGE_TEXT:+$NL}$LINE"
		done
	else
		_USAGE_TEXT=$(cat)
	fi

	Usage () { $_COLOR_FUNC "$_USAGE_TEXT" >&2 ; exit 1 ; }
}

#
#   Usage:   match <string> <pattern>
#
#   Pattern match function (uses patterns like case/esac).
#   The <pattern> should be protected with single quotes.
#   Example:
#       if match "$SOME_VAR" '*foo*|*bar*'; then ...
#
#   Additionally, if there are characters that are to be
#   matched literally and that have a special meaning to
#   the shell, these need to be enclosed in another level
#   of quotes.  In particular, this applies to spaces,
#   and to wildcard characters that you want to match
#   literally.  Examples:
#       if match "$SOME_WORDS" '*two" "words*'; then ...    # quote space
#       if match "$SOME_WORDS" '*"two words"*'; then ...    # (same thing)
#       if match "$SOME_WORDS" '*"really?"*'; then ...    # quote question mark
#   Note that these particular examples can also be written
#   using the contains() function below, which is easier to
#   use if you only need substring matching without patterns:
#       if contains "$SOME_WORDS" "two words"; then ...
#       if contains "$SOME_WORDS" "really?"; then ...
#

match ()
{
	eval 'case "$1" in
		'"$2"') return 0 ;;
		*)      return 1 ;;
	esac'
}

#
#   Usage:  startswith <string> <prefix>
#           endswith   <string> <suffix>
#           contains   <string> <substring>
#
#   Check if a string starts (or ends) with a certain prefix or
#   suffix, respectively, or if it contains the given substring.
#   No pattern matching is performed, all characters are treated
#   normally.  Use the match() function above for pattern matching.
#
#   Examples (all evaluate to "true"):
#       if startswith "foobar" "foo"; then ...
#       if endswith "foobar" "bar"; then ...
#       if contains "foobar" "oob"; then ...
#

startswith () { test "x${1#"$2"}" != "x$1" || return 1 ; }
endswith   () { test "x${1%"$2"}" != "x$1" || return 1 ; }
contains   () { test "x${1#*"$2"}" != "x$1" || return 1 ; }

#
#   All of these functions check a string and return 0 (true) or 1 (false).
#   They are similar to Python's string methods of the same name.
#   isdigit -- for example -- returns true if the string is non-empty
#   and contains only decimal digits.
#   Similarly: isalpha, isalnum, isupper, islower.
#   Note that all of these functions are not locale-aware, i.e. they
#   recognize ASCII only (A-Z, a-z).  All of these functions return
#   1 (false) if the string is empty.
#

isdigit () { ! match "${1-}" '""|*[!0-9]*'; }
isalpha () { ! match "${1-}" '""|*[!A-Za-z]*'; }
isalnum () { ! match "${1-}" '""|*[!A-Za-z0-9]*'; }
isupper () { ! match "${1-}" '""|*[!A-Z]*'; }
islower () { ! match "${1-}" '""|*[!a-z]*'; }

#   Valid identifier (e.g. valid variable name):  Returns 0 (true)
#   if the string is non-empty and consists only of ASCII letters,
#   digits and underscores, and the first character is not a digit.
isident () { ! match "${1-}" '""|*[!A-Za-z0-9_]*|[0-9]*'; }

#   Natural decimal number >= 0.
isnatural () { ! match "${1-}" '""|*[!0-9]*|0?*'; }

#   An integer number, optionally signed (+ or -).
isinteger () { isnatural "${1#[-+]}"; }

#   Positive integer number >= 1.
ispositive () { ! match "${1-}" '""|*[!0-9]*|0*'; }

#   Usage:  in_range $VALUE $MIN $MAX
#   Returns 0 (true) if $VALUE is a valid integer number within the
#   range [$MIN...$MAX] (inclusive).  All numbers may be negative.
in_range () { isinteger "${1-}" && $(( $1 >= $2 && $1 <= $3 )); }

#   Usage:  zeropad <VARNAME> <WIDTH>
#
#   NUM=42
#   zeropad NUM 5
#   echo $NUM       # prints "00042"
zeropad ()
{
	local VARNAME="$1" WIDTH=$2
	local VALUE
	eval VALUE='"${'"$VARNAME}"'"'
	while $(( ${#VALUE} < $WIDTH )); do
		VALUE="0$VALUE"
	done
	setvar $VARNAME "$VALUE"
}

#
#   Syntactic sugar.  :-)
#
#   Examples:
#       if not match "$FOO" 'pattern'; then ...
#       if eq "$SOME_VAR" "foo"; then ...
#       if empty "$SOME_VAR"; then ...
#       if no "$RESULT"; then ...
#

not () { "$@" && return 1 || return 0 ; }

eq ()       { test "x${1-}"  = "x${2-}" || return 1 ; }
neq ()      { test "x${1-}" != "x${2-}" || return 1 ; }
have ()     { test -n "${1-}" || return 1 ; }
nonempty () { test -n "${1-}" || return 1 ; }
no ()       { test -z "${1-}" || return 1 ; }
empty ()    { test -z "${1-}" || return 1 ; }

#
#   Various tests for files.
#
#   Note that all tests -- except islink() -- follow symlinks, so
#   they test the target of the symlink, not the symlink itself.
#   In particular, exists() returns false for symlinks whose targets
#   don't exist.
#   Use islink() to check for a symlink, irrespective of its target.
#
#   All tests return false in the case of non-existence.
#

exists () { test -e "${1:-/NONEXISTENT}" || return 1 ; }
isfile () { test -f "${1:-/NONEXISTENT}" || return 1 ; }
isdir ()  { test -d "${1:-/NONEXISTENT}" || return 1 ; }
islink () { test -L "${1:-/NONEXISTENT}" || return 1 ; }
isfifo () { test -p "${1:-/NONEXISTENT}" || return 1 ; }
isatty () { test -t "${1:-/NONEXISTENT}" || return 1 ; }
isreadable () { test -r "${1:-/NONEXISTENT}" || return 1 ; }

newer () { test "${1:-/NONEXISTENT}" -nt "${2:-/NONEXISTENT}" || return 1 ; }
older () { test "${1:-/NONEXISTENT}" -ot "${2:-/NONEXISTENT}" || return 1 ; }

#   empty_file <file>
#   Returns success if <file> exists, and it is a plain file or a symlink
#   to a plain file, *AND* it has size zero.
empty_file () { test -f "${1:-/NONEXISTENT}" -a ! -s "${1:-/NONEXISTENT}" || return 1 ; }

#   nonempty_file <file>
#   Returns success if <file> exists, and it is a plain file or a symlink
#   to a plain file, *AND* it has a non-zero size.
nonempty_file () { test -f "${1:-/NONEXISTENT}" -a -s "${1:-/NONEXISTENT}" || return 1 ; }

#   empty_dir <dir>
#   Returns success if <dir> exists, and it is a directory or a symlink
#   to a directory, *AND* it has no entries (except "." and "..").
empty_dir () { test -d "${1:-/NONEXISTENT}" && test -z "$(/bin/ls -A "${1:-/NONEXISTENT}")" || return 1 ; }

#   empty_dir <dir>
#   Returns success if <dir> exists, and it is a directory or a symlink
#   to a directory, *AND* it contains entries (beyond "." and "..").
nonempty_dir () { test -d "${1:-/NONEXISTENT}" && test -n "$(/bin/ls -A "${1:-/NONEXISTENT}")" || return 1 ; }

#   safe_dir <dir>
#   Returns success if <dir> is "safe":
#     - It's a directory, not a symlink.
#     - I am the owner.
#     - Nobody else can write to it.
#     - No fancy bits (sticky or anything).

safe_dir ()
{
	local STAT

	STAT=$(stat -f '%u:%Sp' -- "${1:-/NONEXISTENT}")
	eq "${STAT%:*}" "$(id -u)" && match "${STAT##*:}" 'd[-r][-w][-x][-r]-[-x][-r]-[-x]' || return 1
}

#
#   same_file <file1> <file2>
#
#   Returns true if <file1> and <file2> refer to the same physical file,
#   i.e. if they are hardlinks of the same file object.
#   Note that symlinks are not being followed.
#

_getdevicenode () { stat -f '%d:%i' -- "${1:-/NONEXISTENT}" || return 1 ; }

same_file ()
{
        eq \
        	$(_getdevicenode "$1" || echo 0:-1) \
        	$(_getdevicenode "$2" || echo 0:-2)
}

#   Return metadata about a file.  If it's a symlink, the data is from
#   the target if it exists, otherwise from the link itself, see stat(1).
#    - size (in bytes)
getsize  () { stat -Lf '%z' -- "${1:-/NONEXISTENT}" || return 1 ; }
#    - owner or group (numerical UID or GID)
getowner () { stat -Lf '%u' -- "${1:-/NONEXISTENT}" || return 1 ; }
getgroup () { stat -Lf '%g' -- "${1:-/NONEXISTENT}" || return 1 ; }
#    - mtime, ctime or atime (as time_t in seconds)
getmtime () { stat -Lf '%m' -- "${1:-/NONEXISTENT}" || return 1 ; }
getctime () { stat -Lf '%c' -- "${1:-/NONEXISTENT}" || return 1 ; }
getatime () { stat -Lf '%a' -- "${1:-/NONEXISTENT}" || return 1 ; }
#    - modes as in "ls -l" (e.g. "-rw-r--r--")
getmodes () { stat -Lf '%Sp' -- "${1:-/NONEXISTENT}" || return 1 ; }
#    - permissions as a 4-digit octal number (e.g. 0644)
getperm  () { stat -Lf '%Mp%Lp' -- "${1:-/NONEXISTENT}" || return 1 ; }

#   Whether a path is absolute or relative, i.e. starts with a "/".
isabsolute () { test "x${1#/}" != "x$1" ; }
isrelative () { test "x${1#/}"  = "x$1" ; }

#
#   get_df <dir_or_file> [<TOTAL> <USED> <FREE>]
#
#   Call df(1) and return information about a file system.
#   <dir_or_file> is the root of the file system, or an arbitrary file
#   or directory on that file system.
#   <TOTAL>, <USED> and <FREE> are names of variables.  These will be
#   set to integer values specifying the respective information in KB.
#   If these three variable names are not specified, the function just
#   prints the amount of free space to standard output.
#
#   In case of errors, all values are returned as 0.
#   The return code is always 0, even in case of errors.  Checking the
#   existence of <dir_or_file> in advance is recommended.  Note that
#   checking the <TOTAL> value for 0 is not sufficient, because this
#   may be a legal value for synthetic file systems.
#
#   You may specify exactly one of these options:
#     -b   Return values in bytes.
#     -k   Return values in KBytes (default).
#     -m   Return values in MBytes.
#     -g   Return values in GBytes.
#

get_df ()
{
	local DIR_OR_FILE
	local TOTAL_NAME="" USED_NAME="" FREE_NAME=""
	local DF_OPT="-k" DF_MUL=""

	case "$1" in
		--)		shift ;;
		-k|-m|-g)	DF_OPT="$1"; shift ;;
		-b)		DF_MUL=" * 1024"; shift ;;
	esac
	DIR_OR_FILE="$1"

	if [ $# -ge 4 ]; then
		TOTAL_NAME="$2"
		USED_NAME="$3"
		FREE_NAME="$4"
	fi

	set -- $(
		command -p df $DF_OPT -- "$DIR_OR_FILE" \
		| awk '
			($2 ":" $3 ":" $4) ~ /^[0-9]+:[0-9]+:[0-9]+$/ {
				print $2'"$DF_MUL"', $3'"$DF_MUL"', $4'"$DF_MUL"'
			}
		'
	) || true

	if [ $# != 3 ]; then
		set -- 0 0 0
	fi

	if [ -n "$FREE_NAME" ]; then
		setvar $TOTAL_NAME $1
		setvar $USED_NAME $2
		setvar $FREE_NAME $3
	else
		echo $3
	fi
}

#
#   bool {<boolean> | (<arith_expr>) | <command> } [<true>] [<false>]
#
#   Evaluate a boolean expression $1 and return $2 (default "true")
#   or $3 (default "false").  The boolean expression is either:
#    - "true", "1", "on", "yes" (case-insensitive)
#    - "false", "0", "off", "no", "" (case-insensitive)
#    - an arithmetic expression enclosed in parentheses, e.g. "(BAR > 5)".
#      Any non-zero result is considered true.  The expression must be
#      quoted.
#    - Anything else is executed as a command, and a "success" return code
#      (i.e. 0) is taken as true, any other return code as false.  Note that
#      this includes conditionals like "[ -f myfile ]" or "test -f myfile",
#      and you can also use functions, e.g. "isfile myfile".
#      The operators like "||" and "&&" work, too.
#      Note that the command must be quoted, unless it is a simple word.
#   The return code of this function is always 0.
#

bool ()
{
	local COND="${1-}" TRUE_VAL="${2-true}" FALSE_VAL="${3-false}"

	#   Note:  We use printf instead of echo, because echo will
	#          break if $TRUE_VAL is "-n", for example.
	case "$COND" in
		[Tt][Rr][Uu][Ee]|1|[Oo][Nn]|[Yy][Ee][Ss])
			printf '%s\n' "$TRUE_VAL"
			;;
		[Ff][Aa][Ll][Ss][Ee]|0|[Oo][Ff][Ff]|[Nn][Oo]|"")
			printf '%s\n' "$FALSE_VAL"
			;;
		"("*")")
			COND="test \$(( $COND )) -ne 0"
			;&	# fallthrough
		*)
			eval "$COND" \
				&& printf '%s\n' "$TRUE_VAL" \
				|| printf '%s\n' "$FALSE_VAL"
			;;
	esac
	return 0
}

#
#   FreeBSD's sh knows "$((...))", but it doesn't know "((...))".
#   The following function cond() tries to mimic typical use of
#   "((...))" in other shells, in particular with "if" and "while".
#   Note that the arguments need to be quoted if they contain
#   special characters like "*", "<", ">", "(", ")", "&", "|".
#
#   X=5; while cond X '<' 10; do let X += 1; done
#
#   Alternatively, there is a "hack" that enables you to use the
#   following construct that works without quoting, mimicking
#   "(( ... ))" in other shells somewhat more closely:
#
#   X=5; while $(( X < 10 )); do let X += 1; done
#

cond ()
{
	eval "test \$(( $* )) -ne 0"
}

#
#   The following is a "hack" that can be used as an alternative to
#   the cond() function (see above).  Unlike cond() it doesn't require
#   quoting, and it's mimicking "(( ... ))" in other shells somewhat
#   more closely:
#
#   X=5; while $(( X < 10 )); do let X += 1; done
#
#   Note that the enclosed arithmetic expression *MUST* be a boolean
#   expression, i.e. its value must be either 0 or 1.
#

0 () { return 1 ; }
1 () { return 0 ; }

#
#   FreeBSD's sh has a "let" builtin, but it's not documented in the
#   man page, and it behaves differently from the same builtin of zsh
#   and bash (it echoes the result to stdout), so we define a new one.
#   It overrides the undocumented built-in.
#
#   This enables writing things like these (with or without the spaces
#   around the operators):
#
#   let FOO = 15
#   let BAR = 4
#   let BAZ = FOO + BAR
#   while [ some_condition ]; do
#       let BAZ += 1
#   done
#

let ()
{
	eval : "\$(( $* ))"
}

#
#   The "assert" function can be used in two ways:
#
#       [1] assert [not] <Test_Command> [<Args> ...] [-- <Fail_Command> [<Args> ...]]
#       [2] assert [not] <Test_Expression> [...] [-- <Fail_Command> [<Args> ...]]
#
#   [1] In the first form, <Test_Command> [<Args> ...] is executed, and
#       the return code is expected to be 0 (indicating success).
#       <Test_Command> *MUST* begin with an alphabetic character.
#   [2] In the second form, <Test_Expression> [...] is evaluated as an
#       arithmetic expression (exactly like the cond() function above).
#       The arithmetic result is expected to be non-zero (truth value).
#       <Test_Expression> must *NOT* begin with an alphabetic character.
#
#   In either case, the boolean value of the result can be negated by
#   preceding the test with the word "not".  If the end result is NOT the
#   expected one, then the <Fail_Command> [<Args> ...] is executed, if
#   present (it must be separated from the preceding parts by a double-
#   hyphen "--").  If there is no <Fail_Command>, the Usage() function
#   is called if it is defined, otherwise a generic error message is
#   printed, and the script exits.
#
#   assert $# == 1
#   assert isfile "$INPUT" -- Err "File not found: $INPUT"
#   assert match "$NAME" '[A-Z]*' -- Warn "No upper-case name!"
#
#   For backwards compatibility, the double-hyphen is optional and may
#   be omitted in these cases:
#   (A) The <Test_Command> is "match" or "nomatch" or "no[-_]match"
#       followed by two arguments.
#   (B) The <Test_Expression> is a single word (quoted if required)
#       containing at least one of the characters "=", "<", ">".
#

assert ()
{
	local EXPECT=true PREFIX=""
	local CONDITION RESET GET_TEST ARG SUCCESS

	if eq "${1-}" "not" || eq "${1-}" '!'; then
		EXPECT=false
		PREFIX="$1 "
		shift
	fi

	CONDITION="${1-}"
	if match "$CONDITION" "match|eq|neq|startswith|endswith|contains"; then
		#   Backwards compatibility:  <Binary_Op> <Str> <Pat> <Command ...>
		assign SUCCESS true false $CONDITION "$2" "$3"
		CONDITION="${PREFIX}$CONDITION '$2' '$3'"
		shift 3
		if eq "${1-}" "--"; then shift; fi
	elif match "$CONDITION" "nomatch|no[-_]match"; then
		#   Backwards compatibility:  nomatch <Str> <Pat> <Command ...>
		assign SUCCESS false true match "$2" "$3"
		CONDITION="${PREFIX}! match '$2' '$3'"
		shift 3
		if eq "${1-}" "--"; then shift; fi
	elif match "$CONDITION" "isdigit|isalpha|isalnum|isupper|islower|isnatural|no|empty|have|nonempty"; then
		#   Backwards compatibility:  <Unary_Op> <Str> <Command ...>
		assign SUCCESS true false $CONDITION "$2"
		CONDITION="${PREFIX}$CONDITION '$2'"
		shift 2
		if eq "${1-}" "--"; then shift; fi
	elif match "$CONDITION" '*[=\<\>]*'; then
		#   Backwards compatibility:  <Expr> <Command ...>
		assign SUCCESS true false eval "test \$(( $CONDITION )) -ne 0"
		CONDITION="${PREFIX}$CONDITION"
		shift
		if eq "${1-}" "--"; then shift; fi
	else
		IS_COMMAND=$(bool 'match "$CONDITION" "[A-Za-z]*"')
		GET_TEST=true
		RESET=true
		for ARG in "$@"; do
			if $GET_TEST && eq "$ARG" "--"; then
				CONDITION="${PREFIX}${*:-true}"
				if $(( $# == 0 )); then
					SUCCESS=true
				elif $IS_COMMAND; then
					assign SUCCESS true false "$@"
				else
					assign SUCCESS true false eval "test \$(( $* )) -ne 0"
				fi
				GET_TEST=false
				set --
				continue
			fi
			if $RESET; then
				RESET=false
				set --
			fi
			set -- "$@" "$ARG"
		done
		if $GET_TEST; then
			CONDITION="${PREFIX}${*:-true}"
			if $(( $# == 0 )); then
				SUCCESS=true
			elif $IS_COMMAND; then
				assign SUCCESS true false "$@"
			else
				assign SUCCESS true false eval "test \$(( $* )) -ne 0"
			fi
			set --
		fi
	fi

	if neq $SUCCESS $EXPECT; then
		if [ $# -ne 0 ]; then
			"$@"
		else
			if type Usage >/dev/null 2>&1; then
				Usage
			else
				echo "${ME}: Assertion failed: $CONDITION" >&2
			fi
			exit 1
		fi
	fi
}

#
#   The length() function is just a little bit of syntactic sugar.
#   There are two distinct usages:
#
#   1. If just one argument is given, echo the length of it.
#      The following is equivalent:
#
#        length "$FOO$BAR$BAZ"
#        echo $(( ${#FOO} + ${#BAR} + ${#BAZ} ))
#
#   2. If there are two or more arguments that look like a numeric
#      comparison, behave like a conditional statement.
#      The following is equivalent:
#
#        if length "$FOO" == 3; then ...
#        if cond ${#FOO} == 3; then ...
#

length ()
{
	local LENGTH=${#1}

	if match "${2-}" '[\<\>=!]*'; then
		shift
		cond LENGTH "$@"
	else
		echo $LENGTH
	fi
}

#
#   Usage:  range [<start=0>] <limit> [<step=1>]
#           range -e [<start=1>] <end> [<step=+/-1>]
#
#   Without the -e option (first case), the range() function works like
#   the one in Python.  <step> may be negative.  If the range is empty,
#   there is no output.  Examples:
#
#       for i in $(range 4); do echo -n $i. ; done
#       0.1.2.3.
#
#       for i in $(range 10 20 2); do echo -n $i. ; done
#       10.12.14.16.18.
#
#       for i in $(range 20 10 -2); do echo -n $i. ; done
#       20.18.16.14.12.
#
#   Note:  If one argument is given, it is interpreted as the <limit>.
#          If two arguments are given, they are <start> and <limit>.
#          If a third argument is given, it's <step>.
#
#   If the -e option is specified (second case), an alternative usage is
#   provided that may be easier, depending on circumstances.  It has the
#   following differences:
#    - The default <start> value is 1:
#      range -e 4   -->   1 2 3 4
#    - The <limit> is interpreted as the ending value, and it is always
#      included in the range:   range -e 4 8   -->   4 5 6 7 8
#    - If the start is greater than the end value, the default <step>
#      is -1:   range -e 8 4   -->   8 7 6 5 4
#

range ()
{
	local START END STEP
	local EASY=false

	if eq "$1" "-e"; then
		EASY=true
		shift
	fi

	START="${1-}"
	END="${2-}"
	STEP="${3-}"

	if no "$START"; then
		return
	elif no "$END"; then
		END="$START"
		START=$(bool $EASY 1 0)
	fi

	if no "$STEP"; then
		if $EASY && $(( START > END )); then
			STEP=-1
		else
			STEP=1
		fi
	fi

	if $EASY; then
		END=$(( END + ${STEP%%[0-9]*}1 ))
	fi

	if [ $START -lt $END -a $STEP -gt 0 ]; then
		#   Count up.
		while [ $START -lt $END ]; do
			echo $START
			START=$(( START + STEP ))
		done
	elif [ $START -gt $END -a $STEP -lt 0 ]; then
		#   Count down.
		while [ $START -gt $END ]; do
			echo $START
			START=$(( START + STEP ))
		done
	fi
}

#
#   Usage:  assign <VARIABLE> <TRUE> <FALSE> <CONDITION ...>
#
#   Tests <CONDITION> (an arbitrary simple command that could be
#   placed between "if" and "; then").  Depending on the result,
#   either <TRUE> or <FALSE> (strings) are assigned to <VARIABLE>
#   (a variable name).
#
#   Note that <CONDITION> must be a simple command, i.e. "||",
#   "&&" and "!" are not allowed.  However, you can use "not"
#   instead of "!".  If you need "||" or "&&", you can use
#   sh -c '<CONDITION>'.
#
#   Examples:
#     assign OPT_P true false eq ARG "-P"
#     assign ERRTEXT "$NUMERR error" "$NUMERR errors" cond NUMERR == 1
#     assign DEBUG_OPTS "-D" "" $DEBUG
#
#   Note that the bool() function can be used to do the same:
#     OPT_P=$(bool 'eq ARG "-P"')
#     ERRTEXT=$(bool 'cond NUMERR == 1' "$NUMERR error" "$NUMERR errors")
#     DEBUG_OPTS=$(bool '$DEBUG' "-D" "")
#

assign () {
	local VARNAME="$1" TRUE_TEXT="$2" FALSE_TEXT="$3"
	shift 3
	if "$@"; then
		setvar "$VARNAME" "$TRUE_TEXT"
	else
		setvar "$VARNAME" "$FALSE_TEXT"
	fi
}

#
#   Usage:  augment <VARIABLE> <STRING>
#
#   If <VARIABLE> is set and has a non-empty value, replace its value
#   with <STRING>, otherwise set it to the empty string.
#
#   If the name of <VARIABLE> is preceded by an exclamation mark, the
#   matching is inverted:  Its value is set to <STRING> if the variable
#   is empty or unset, otherwise it is not changed.  This is useful to
#   apply default settings.  For convenience, a function default() is
#   provided that does the same thing.
#
#   Examples:
#      augment GEO "-geometry $GEO"
#      augment !COLUMNS "80"
#      default COLUMNS "80"	# Same.
#

augment ()
{
	local VARNAME="$1" STRING="${2-}"
	local VALUE

	eval VALUE='"${'"${VARNAME#!}"'-}"'
	if startswith "$VARNAME" "!"; then
		if empty "$VALUE"; then
			setvar "${VARNAME#!}" "$STRING"
		#   NOTE:  No "else" here: Keep VARNAME unchanged
		#          if $VALUE is non-empty.
		fi
	else
		if empty "$VALUE"; then
			STRING=""
		fi
		setvar "$VARNAME" "$STRING"
	fi
}

default ()
{
	local VARNAME="$1"
	shift

	augment "!$VARNAME" "$@"
}

#
#   Usage:  split [<OPTS>] [--] <STRING> <CHARS> <VAR> [...]
#
#   Splits the <STRING> on any characters in <CHARS> and sets the list
#   of variables to the parts.  Empty parts may occur if the <STRING>
#   starts and/or ends with a separating character, of if it contains
#   two adjacent separating characters.  Use the option ``-s'' to omit
#   empty parts.
#
#   If there are too few variables, the last one receives the rest
#   of the string without further splitting.  If there are too many
#   variables, the remaining ones are set to the empty string.
#
#   IMPORTANT:  <CHARS> is used within a character class ("[...]"),
#   so the characters "[", "-", "!", "^" need to be handled specially.
#   To include a "]" in <CHARS>, put it at the start.  To include a
#   "-", put it at the start or at the end.  To include "!" or "^",
#   do NOT put them at the start.
#
#   The global variable SPLIT_COUNT is set to the number of elements
#   extracted from <STRING>, i.e. the number of splits + 1, including
#   empty parts, but not including variables that have been set to
#   the empty string because <STRING> was exhausted.  When -s is in
#   effect, only non-empty parts are counted.  You can use the option
#   ``-c <VARNAME>'' to specify the name of a different variable to
#   receive the count.
#
#   Finally, the -y option can be used to yield values within a loop.
#   Typical example:
#
#       while split -y -s -- "$DATA" "$TAB$NL" ID TITLE; do
#           #   Assuming that a title does not contain tabs.
#           echo "Document #$ID title: $TITLE"
#       done
#
#   Also see the str_split() function below.
#

split ()
{
	local STRING CHAR PART
	local COUNT=0 CLEAR_REST=false FINISHED=false
	local COUNT_VARNAME SQUEEZE YIELDS
	local OPT_INC OPT_ERR

	std_getopts -ln "
		c: {COUNT_VARNAME=SPLIT_COUNT}
		s  {SQUEEZE}
		y  {YIELDS}
	" "$@" || Err "[utils.sh] split(): $OPT_ERR"
	shift $OPT_INC

	STRING="${1-}"
	CHAR="${2-}"
	if $(( $# < 3 )) || no "$CHAR" ; then
		Err "[utils.sh] Usage: split [<OPTS>] [--] <VALUE> <CHAR> <VAR> [...]"
	fi
	shift 2

	if $YIELDS; then
		#   We use a few global variables to store state:
		#   __SY_*_ORIG  -  the original <STRING> passed to the
		#                   first invocation of split().
		#   __SY_*_REST  -  the remaining part of <STRING> after
		#                   previous invocations of split().
		#   __SY_*_FINI  -  "true" if we're finished splitting
		#                   and need to return 1.
		if eval eq '"$STRING"' '"${__SY_'"$COUNT_VARNAME"'_ORIG-}"'; then
			#   We had one or more previous invocations.
			if eval '${__SY_'"$COUNT_VARNAME"'_FINI}'; then
				setvar __SY_"$COUNT_VARNAME"_ORIG ""
				setvar __SY_"$COUNT_VARNAME"_FINI false
				return 1
			fi
			eval STRING='"$__SY_'"$COUNT_VARNAME"'_REST"'
		else
			#   This is the first invocation.
			setvar __SY_"$COUNT_VARNAME"_ORIG "$STRING"
		fi
	fi

	while $(( $# != 0 )) && ! $FINISHED; do
		if $SQUEEZE; then
			while match "$STRING" '["'"$CHAR"'"]*' ; do
				STRING="${STRING#[$CHAR]}"
			done
		fi
		if match "$STRING" '*["'"$CHAR"'"]*' && { $(( $# > 1 )) || $YIELDS; }; then
			PART="${STRING%%[$CHAR]*}"
			STRING="${STRING#*[$CHAR]}"
		else
			PART="$STRING"
			STRING=""
			FINISHED=true
			if $SQUEEZE && empty "$PART"; then
				break
			fi
		fi
		setvar $1 "$PART"
		let COUNT += 1
		shift
	done
	setvar $COUNT_VARNAME $COUNT

	while $(( $# != 0 )); do
		setvar $1 ""
		shift
	done

	if $YIELDS; then
		setvar __SY_"$COUNT_VARNAME"_REST "$STRING"
		setvar __SY_"$COUNT_VARNAME"_FINI "$FINISHED"
	fi
}

#   The following function is used for debugging split().
__stest ()
{
	local NUMVARS=$1
	shift

	for i in $(range 1 $(( NUMVARS + 1 )) ); do
		setvar A$i "<UNSET>"
		set -- "$@" A$i
	done
	split "$@"
	for i in $(range 1 $(( NUMVARS + 1 )) ); do
		eval echo -n '"\"$A'$i'\"  "'
	done
	echo "  $SPLIT_COUNT"
}

#
#   Usage:  str_split <string> <chars>
#
#   Split the <string> any character(s) in <chars>.
#   Each non-empty element is printed on a separate line.
#
#   The global variable SPLIT_COUNT is set to the number of non-empty
#   elements extracted from "$1", i.e. the number of elements printed.
#   Use the option ``-c VARNAME'' to specify the name of a different
#   variable to receive the count.  If you specify ``-c -'', the
#   count is printed on a separate line after all elements.
#
#   Also see the split() function above.
#
#   $ str_split foo,,,bar:baz ,:
#   foo
#   bar
#   baz
#

str_split ()
{
	local OLD_IFS ELEM
	local COUNT=0 COUNT_VARNAME="SPLIT_COUNT"

	if eq "${1-}" "-c"; then
		COUNT_VARNAME="$2"
		shift 2
	fi

	OLD_IFS="$IFS"
	IFS="$2"
	for ELEM in $1; do
		if have "$ELEM"; then
			#   Note that echo breaks if $ELEM is "-n".
			printf '%s\n' "$ELEM";
			#   We cannot use ``let'' here because of IFS.
			COUNT=$(( COUNT + 1 ))
		fi
	done
	IFS="$OLD_IFS"
	if eq "$COUNT_VARNAME" "-"; then
		echo "$COUNT"
	else
		setvar $COUNT_VARNAME $COUNT
	fi
}

#
#   Usage:  strip <VAR>
#
#   Remove leading and trailing whitespace from the variable named <VAR>.
#

strip ()
{
	local VARNAME="$1"
	local VALUE LSPACE RSPACE

	eval VALUE=\"\$$VARNAME\"
	LSPACE="${VALUE%%[! $TAB$NL$CR]*}"
	RSPACE="${VALUE##*[! $TAB$NL$CR]}"
	VALUE="${VALUE#$LSPACE}"
	VALUE="${VALUE%$RSPACE}"
	setvar $VARNAME "$VALUE"
}

#
#   Usage:  charcut <COUNT> <VAR1> <VAR2>
#
#   Cut <COUNT> characters from the beginning of the variable named <VAR1>
#   and return them in the variable named <VAR2>.
#   If <COUNT> is negative, cut from the end instead.
#
#   Example:
#      >  V="foobarbaz"
#      >  charcut 2 V U
#      >  echo $V $U
#      obarbaz fo
#      >  charcut -2 V U
#      >  echo $V $U
#      obarb az
#

charcut ()
{
	local COUNT="$1" VARNAME1="$2" VARNAME2="$3"
	local RESULT="" REST=""

	while $(( COUNT > 0 )); do
		eval REST='"${'$VARNAME1'#?}"'
		eval RESULT='"${RESULT}${'$VARNAME1'%$REST}"'
		eval $VARNAME1='"$REST"'
		let COUNT -= 1
	done
	while $(( COUNT < 0 )); do
		eval REST='"${'$VARNAME1'%?}"'
		eval RESULT='"${'$VARNAME1'#$REST}${RESULT}"'
		eval $VARNAME1='"$REST"'
		let COUNT += 1
	done
	setvar $VARNAME2 "$RESULT"
}

#
#   The "record" type is simply a way to store key-value pairs.
#   The keys must be valid identifiers, i.e. alphanumeric + underscore.
#   Usage:
#
#       record OBJ.elem1="foo bar" .elem2="laber fasel"    # "." is optional
#       record OBJ.elem1 .elem2       # prints them on separate lines
#
#   Or:
#
#       record OBJ
#       OBJ .elem1="foo bar" .elem2="laber fasel"    # "." is optional
#       OBJ .elem1 .elem2       # prints them on separate lines
#

record ()
{
	local NAME KEY VALUE SHIFT_COUNT IS_ASSIGNMENT
	local VIA_FUNCTION=false

	if [ "x${1-}" = "x-f" ]; then
		VIA_FUNCTION=true
		shift
	fi

	if contains "${1-}" "."; then
		NAME="${1%%.*}"
		KEY="${1#*.}"
		SHIFT_COUNT=0
	else
		NAME="${1-}"
		KEY="${2-}"
		KEY="${KEY#.}"
		SHIFT_COUNT=1
	fi

	if [ -z "$NAME" ]; then
		red "[utils.sh] record: Missing or empty record name." >&2
		exit 1
	elif [ -z "$KEY" ]; then
		if ! $VIA_FUNCTION; then
			eval "$NAME () { record -f $NAME \"\$@\"; }"
			return
		fi
		red "[utils.sh] record: Missing or empty record key." >&2
		exit 1
	fi

	shift $SHIFT_COUNT
	while [ -n "$KEY" ]; do
		shift
		if contains "$KEY" "="; then
			setvar _rec_${NAME}_${KEY%%=*} "${KEY#*=}"
		else
			eval printf "'%s\\n'" \"\$_rec_${NAME}_${KEY}\"
		fi
		KEY="${1-}"
		KEY="${KEY#.}"
	done
}

#
#   Functions to handle a "named argument vector".
#
#   -- OBSOLETE -- Instead, please use the array() function below!
#
#   Basically this is an array with indices starting at 0.
#   See the array() function below for a "prettier" front-end.
#
#   argv_init  <NAME>			# Must be called once, sets count to 0.
#   argv_add   <NAME> <VALUE> [...]	# Appends one or more values.
#   argv_count <NAME>			# Returns current count (note: same as
#					# maximum index - 1).  You can also
#					# simply use $ARGC_<NAME>.
#   argv_get   <NAME> <INDEX>		# Index may be >= count, in this case
#					# returns an empty string.
#   argv_set   <NAME> <INDEX> <VALUE>	# Index may be >= count, in this case
#					# advances count to index + 1.
#   argv_quote <NAME>			# Typical use to copy to "$@":
#					# eval set -- "$(argv_quote NAME)"
#   argv_doublequote <NAME>		# Same, but expands $ and backticks
#					# when passed to eval like above.
#   argv_words <NAME>			# Get all values space-separated and
#					# without quotes.
#   argv_lines <NAME>			# Ditto, but print each value on a
#					# separate line.
#
#   In the above synopsis, <INDEX> is an arithmetic expression, so the
#   following works:  i=3; j=5; argv_set myname i+j-1 some_word
#

_argv_check_usage ()
{
	#   sets global variables _argv_NAME and _argv_COUNT.

	local CHECK_COUNT=true
	local MIN_C MAX_C USAGE

	if eq "$1" "--nocount" ; then
		CHECK_COUNT=false
		shift
	fi

	MIN_C="$1"
	MAX_C="$2"
	USAGE="$3"
	shift 3

	if $(( $# < MIN_C || $# > MAX_C )) || no "${1-}"; then
		echo "[utils.sh] Usage: $USAGE" >&2
		exit 1
	fi
	_argv_NAME="$1"

	if $CHECK_COUNT ; then
		eval _argv_COUNT='"${ARGC_'"$1"'-}"'
		if ! isnatural "$_argv_COUNT"; then
			echo "[utils.sh] ${USAGE%%" "*}: \"$1\" doesn't seem to be an existing array." >&2
			exit 1
		fi
	fi
}

argv_init ()
{
	_argv_check_usage --nocount 1 1 "argv_init <NAME>" "$@"
	setvar ARGC_$1 0
}

argv_add ()
{
	local VALUE

	_argv_check_usage 1 99999 "argv_add <NAME> <VALUE> [...]" "$@"
	shift
	for VALUE in "$@"; do
		setvar ARGV_${_argv_NAME}_${_argv_COUNT} "$VALUE"
		let _argv_COUNT += 1
	done
	setvar ARGC_${_argv_NAME} ${_argv_COUNT}
}

argv_count ()
{
	_argv_check_usage 1 1 "argv_count <NAME>" "$@"
	echo $_argv_COUNT
}

argv_get ()
{
	local INDEX

	_argv_check_usage 2 2 "argv_get <NAME> <INDEX>" "$@"
	INDEX=$(( $2 ))
	if [ $INDEX -lt 0 ]; then
		INDEX=$(( _argv_COUNT + INDEX ))
	fi
	if [ $INDEX -lt 0 -o $INDEX -ge $_argv_COUNT ]; then
		return 1
	fi
	eval echo '"${ARGV_'"${1}_${INDEX}"'-}"'
}

argv_set ()
{
	local INDEX

	_argv_check_usage 3 3 "argv_set <NAME> <INDEX> <VALUE>" "$@"
	INDEX=$(( $2 ))
	if $(( INDEX >= _argv_COUNT )); then
		setvar ARGC_${_argv_NAME} $(( INDEX + 1 ))
	fi
	setvar ARGV_"$1"_$INDEX "$3"
}

argv_quote ()
{
	#   Hint:  You can copy the contents of an array to "$@" like this:
	#          eval set -- "$(argv_quote NAME)"
	local ARGS=""
	local I

	_argv_check_usage 1 1 "argv_quote <NAME>" "$@"
	let I = 0
	while $(( I < _argv_COUNT )); do
		ARGS="$ARGS \"\$ARGV_${1}_$I\""
		let I += 1
	done
	eval quote_args $ARGS
}

argv_doublequote ()
{
	local ARGS=""
	local I

	_argv_check_usage 1 1 "argv_doublequote <NAME>" "$@"
	let I = 0
	while $(( I < _argv_COUNT )); do
		ARGS="$ARGS \"\$ARGV_${1}_$I\""
		let I += 1
	done
	eval doublequote_args $ARGS
}

argv_words ()
{
	local ARGS=""
	local I

	_argv_check_usage 1 1 "argv_words <NAME>" "$@"
	let I = 0
	while $(( I < _argv_COUNT )); do
		eval ARGS='"${ARGS}${ARGS:+ }$ARGV_'$1'_'$I'"'
		let I += 1
	done
	printf '%s\n' "$ARGS"
}

argv_lines ()
{
	local ARGS=""
	local I

	_argv_check_usage 1 1 "argv_lines <NAME>" "$@"
	let I = 0
	while $(( I < _argv_COUNT )); do
		eval ARGS='"${ARGS}${ARGS:+$NL}$ARGV_'$1'_'$I'"'
		let I += 1
	done
	printf '%s\n' "$ARGS"
}

#
#   Alternative front-end for the argv_* functions above.
#   This is a more terse syntax.  Usage:
#
#   array <NAME> [init]			# Must be called once, sets count=0.
#   array <NAME> count			# Prints the number of elements.
#   array <NAME> empty			# Return code 0 (true) or 1 (false).
#   array <NAME> indices		# Returns the list of indices.
#   array <NAME> splitlines "<VALUE>"	# Initialize <NAME> with lines from
#			    [...]	# <VALUE> (must be quoted). NOTE that
#					# empty lines are ignored.
#   array <NAME> addlines "<VALUE>"	# Ditto, add to existing array.
#   array <NAME> iterate <CMD ...>	# Execute <COMMAND> for every element.
#   array <NAME> enumerate <CMD ...>	# Ditto, but include index as $1.
#   array <NAME> add "<VALUE>" [...]	# Append one or more values.
#   array <NAME>+="<VALUE>" [...]	# Ditto
#   array <NAME>="<VALUE>" [...]	# Same as init and +=.
#					# Typical example:  array NAME="$@"
#   array <NAME>:<INDEX>="<VALUE>"	# Value should be quoted.
#   array <NAME>:<INDEX> [:<INDEX> ...]	# Prints value.
#   array <NAME> pop <VNAME>		# Pop last element & assign to <VNAME>.
#   array <NAME> yields <VNAME>		# Generator, see below.
#   array <NAME> truncate <n>		# Truncate to <n> elements. If <n> is
#					# larger than the current size, set
#					# new elements to the empty string.
#					# If <n> is negative, truncate that
#					# many elements from the end.
#   array <NAME> reverse		# Reverse the elements in the array.
#   array <NAME> join <S>		# Print elements joined by string <S>.
#   array <NAME> joinf <F> <S>		# Ditto, with a printf format <F>.
#   array <NAME> echo			# All values space-separated, unquoted.
#   array <NAME> print			# All values, one per line, unquoted.
#   array <NAME> quote			# eval set -- "$(array NAME quote)"
#   array <NAME> doublequote		# With eval, expands $ and backticks.
#
#   Upon creation of an array (using "init" or "splitlines" or <NAME>=...),
#   a function with the name of the array is created, so you can omit the
#   "array" command word.
#
#   You can replace ":<INDEX>" with "[<INDEX>]" (square brackets), provided
#   that you have switched off globbing (shell option -f).
#
#   Note that there must be no spaces adjacent to ":", "[", "]", "=" and "+=",
#   except that there may be a space after <NAME> in each case (this is to
#   allow using the dynamically created funcion, e.g. ``MY_ARRAY :42'').
#
#   The "yields" subcommand can be used similarly to generators in Python:
#     while MY_ARRAY yields VALUE; do echo "<<<$VALUE>>>"; done
#   Note that "yields" works on the live array, so you should probably not
#   make modifications to the array that change its count within the loop.
#
#   The "pop" subcommand can be used similarly, but it removes the values
#   from the array:
#     while MY_ARRAY pop VALUE; do echo "<<<$VALUE>>>"; done
#     MY_ARRAY count   # prints "0".
#   Also note that "pop" starts at the last element ("yields" starts at the
#   first element).  For the opposite direction, use "reverse" to reverse
#   the elements in the array.
#

_array_init ()
{
	setvar ARGC_$1 0
	eval "$1 () { array -f $1 \"\$@\"; }"
}

array ()
{
	local NAME VNAME VALUE INDEX RINDEX CMD DO_ENUM COUNT TARGET
	local OLD_IFS FIRST FORM PART
	local VIA_FUNCTION=false
	local is_assignment has_index use_form

	if eq "${1-}" "-f"; then
		VIA_FUNCTION=true
		shift
	fi

	if empty "${1-}"; then
		red "[utils.sh] array: Missing or empty array name." >&2
		exit 1
	fi

	if ! match "$1" '*[][=:]*' && match "${2-}" ':*|"["*"]"*|=*|+=*'; then
		NAME="$1$2"
		shift 2
	else
		NAME="$1"
		shift
	fi

	split -c _SPLIT_COUNT -- "$NAME" "=" NAME VALUE
	is_assignment=$(bool '( _SPLIT_COUNT > 1)')
	split -c _SPLIT_COUNT -- "$NAME" ":[" NAME INDEX
	has_index=$(bool '( _SPLIT_COUNT > 1)')
	INDEX="${INDEX%"]"}"

	if $is_assignment ; then
		if $has_index ; then
			while :; do
				argv_set "$NAME" "$INDEX" "$VALUE"
				if $(( $# == 0 )); then
					return
				fi
				let INDEX += 1
				VALUE="$1"
				shift
			done
		else
			if endswith "$NAME" '+' ; then
				NAME="${NAME%+}"
			else
				_array_init $NAME
			fi
			argv_add "$NAME" "$VALUE" "$@"
			return
		fi
	else
		if $has_index ; then
			argv_get "$NAME" "$INDEX" || return 1
		elif $(( $# == 0 )); then
			if $VIA_FUNCTION; then
				#   For debugging, when you just type the
				#   array function name, print the array.
				set -- quote
			else
				set -- init
			fi
		fi
	fi

	while $(( $# != 0 )); do
		CMD="$1"
		shift
		case "$CMD" in
		[[:]*)
			CMD="${CMD#[[:]}"
			argv_get "$NAME" "${CMD%"]"}" || return 1
			;;
		add)
			argv_add "$NAME" "$@"
			return
			;;
		pop)
			VNAME="$1"
			shift
			COUNT=$(argv_count $NAME)
			if $(( COUNT == 0 )); then
				return 1
			fi
			setvar "$VNAME" "$(argv_get "$NAME" -1)"
			setvar ARGC_$NAME $(( COUNT - 1 ))
			;;
		yields)
			VNAME="$1"
			shift
			COUNT=$(argv_count $NAME)
			eval INDEX='"${_ARGV_'"$NAME"'_YIELD:-0}"'
			if $(( INDEX >= COUNT )); then
				setvar _ARGV_${NAME}_YIELD 0
				return 1
			fi
			setvar "$VNAME" "$(argv_get "$NAME" $INDEX)"
			setvar _ARGV_${NAME}_YIELD $(( INDEX + 1 ))
			;;
		truncate)
			COUNT=$(argv_count $NAME)
			TARGET=$1
			if [ $TARGET -lt 0 ]; then
				TARGET=$(( COUNT + TARGET ))
				if [ $TARGET -lt 0 ]; then
					TARGET=0
				fi
			fi
			while [ $COUNT -lt $TARGET ]; do
				setvar ARGV_${NAME}_$COUNT ""
				let COUNT += 1
			done
			setvar ARGC_$NAME $TARGET
			shift
			;;
		init|declare|define|reset|clear)
			_array_init $NAME
			setvar _ARGV_${NAME}_YIELD 0
			;;
		count|length|len)
			argv_count $NAME
			;;
		empty)
			return $(( $(argv_count $NAME) != 0 ))
			;;
		join|joinf)
			if eq "$CMD" "joinf"; then
				use_form=true
				FORM="$1"
				shift
			else
				use_form=false
			fi
			VALUE=""
			FIRST=true
			COUNT=$(argv_count $NAME)
			INDEX=0
			while $(( INDEX < COUNT )); do
				eval PART='"${ARGV_'"$NAME"'_'$INDEX'-}"'
				if $use_form; then
					PART=$(printf -- "$FORM" "$PART")
				fi
				if $FIRST; then
					VALUE="$PART"
					FIRST=false
				else
					VALUE="${VALUE}${1}${PART}"
				fi
				let INDEX += 1
			done
			printf '%s\n' "$VALUE"
			shift
			;;
		echo)
			argv_words $NAME
			;;
		print)
			argv_lines $NAME
			;;
		quote)
			argv_quote $NAME
			;;
		doublequote)
			argv_doublequote $NAME
			;;
		splitlines)
			_array_init $NAME
			;&
		addlines)
			INDEX=$(argv_count $NAME)
			OLD_IFS="$IFS"
			IFS="$NL"
			for VALUE in $*; do
				setvar ARGV_${NAME}_$INDEX "$VALUE"
				let INDEX += 1
			done
			IFS="$OLD_IFS"
			setvar ARGC_$NAME $INDEX
			return
			;;
		indices|keys)
			range $(argv_count $NAME)
			;;
		iterate|enumerate)
			assign DO_ENUM true "" eq "$CMD" enumerate
			COUNT=$(argv_count $NAME)
			INDEX=0
			while $(( INDEX < COUNT )); do
				eval VALUE='"${ARGV_'"$NAME"'_'$INDEX'-}"'
				"$@" ${DO_ENUM:+$INDEX} "$VALUE" \
				|| return $?
				let INDEX += 1
			done
			return
			;;
		reverse)
			COUNT=$(argv_count $NAME)
			INDEX=$(( COUNT / 2 - 1 ))
			while $(( INDEX >= 0 )); do
				RINDEX=$(( COUNT - INDEX - 1 ))
				eval VALUE='"${ARGV_'"$NAME"'_'$INDEX'-}"'
				eval setvar ARGV_${NAME}_$INDEX '"${ARGV_'"$NAME"'_'$RINDEX'-}"'
				setvar ARGV_${NAME}_$RINDEX "$VALUE"
				let INDEX -= 1
			done
			;;
		*)
			red "[utils.sh] array \"$NAME\": unknown sub-command \"$CMD\"." >&2
			exit 1
			;;
		esac
	done
}

#
#   "Set" is similar to the set type in Python and other languages.
#   (Note the upper-case letter S in "Set", because "set" is already
#   a reserved word in the shell).
#
#   NOTE:  This is meant only for small amounts of data, i.e. numbers,
#          words and short expressions.  The empty string can be added.
#          Do NOT use it for binary data, because bytes 0x00 and 0x01
#          cannot be used.
#
#   Set <NAME> init			# Must be called once.
#   Set <NAME>="<VALUE>" [...]		# Sames as init + add. [*]
#   Set <NAME> count			# Echoes number of elements.
#   Set <NAME> empty			# Return code 0 (true) or 1 (false).
#   Set <NAME> contains "<VALUE>"	# Return code 0 (true) or 1 (false).
#   Set <NAME> add "<VALUE>" [...]	# Add one or more values.
#   Set <NAME>+="<VALUE>" [...]		# ditto [*]
#   Set <NAME> remove "<VALUE>" [...]	# Remove one or more values.
#   Set <NAME>-="<VALUE>" [...]		# ditto [*]
#   Set <NAME> splitlines "<VALUE>"	# Initialize <NAME> with lines from
#			    [...]	# <VALUE> (must be quoted). NOTE that
#					# empty lines are ignored.
#   Set <NAME> addlines "<VALUE>"	# Ditto, add to existing Set.
#   Set <NAME> pop <VNAME>		# Pop 1st element & assign to <VNAME>.
#   Set <NAME> yields <VNAME>		# Generator, see below.
#   Set <NAME> toarray [<NAME>]		# Convert to array (default: same).
#   Set <NAME> fromarray [<NAME>]	# Add elements from array.
#   Set <NAME> iterate <COMMAND ...>	# Execute <COMMAND> for every element.
#   Set <NAME> join <S>			# Print elements joined by string <S>.
#   Set <NAME> joinf <F> <S>		# Ditto, with a printf format <F>.
#   Set <NAME> echo			# Print all elements, space-separated.
#   Set <NAME> print			# Print all elements, one per line.
#   Set <NAME> quote			# e.g. eval set -- "$(Set NAME quote)"
#
#   After "init" has been used the <NAME> becomes a function and can be
#   called without the "Set" command.  For example:
#       Set MY_SET init
#       MY_SET add "$@"
#       FOO_COUNT=$(MY_SET count)
#
#   [*] IMPORTANT:  The following statement:
#         Set MY_SET=
#   will *NOT* create an empty set, but a set with one element (the empty
#   string).  For that reason, things like these:
#         Set MY_SET="$@"
#         Set MY_SET=$(command)
#   may behave unexpectedly because they will never create an empty set,
#   even if "$@" is empty or the output from $(cmd) is empty.
#   Similar problems may arise with the += and -= features.
#   THEREFORE, use "=", "+=" and "-=" only if there's at least one element
#   being added or removed, respectively.
#   If the list might have zero elements, use the "add" and "remove"
#   subcommands instead.  For example:
#         Set MY_SET init; MY_SET add "$@"
#         Set MY_SET init; MY_SET add $(command)
#
#   The "yields" subcommand can be used similar to generators in Python:
#     while MY_SET yields VALUE; do echo "<<<$VALUE>>>"; done
#   Note that "yields" makes a temporary copy of the Set before it returns
#   the first element.  Therefore you can safely make changes to the Set
#   within the loop:
#       while MY_SET yields VALUE; do
#           if endswith "$VALUE" .BAK; then
#               MY_SET remove "$VALUE"
#           fi
#       done
#
#   The "pop" subcommand can be used similarly, but it removes the values
#   from the Set:
#     while MY_SET pop VALUE; do echo "<<<$VALUE>>>"; done
#     MY_SET count   # prints "0".
#

Set ()
{
	local SEP=$'\x01'
	local NAME VNAME VALUE SET CMD COUNT MID REST ARRNAME FIRST FORM PART
	local _SPLIT_COUNT
	local VIA_FUNCTION=false
	local use_form

	if eq "${1-}" "-f"; then
		VIA_FUNCTION=true
		shift
	fi

	if empty "${1-}"; then
		red "[utils.sh] Set: Missing or empty Set name." >&2
		exit 1
	fi

	if ! match "$1" '*=*' && match "${2-}" '=*|+=*|-=*'; then
		NAME="$1$2"
		shift 2
	else
		NAME="$1"
		shift
	fi

	split -c _SPLIT_COUNT -- "$NAME" "=" NAME VALUE
	if $(( _SPLIT_COUNT > 1 )); then
		if match "$NAME" '*-' ; then
			NAME="${NAME%-}"
			set -- remove "$VALUE" "$@"
		elif match "$NAME" '*+' ; then
			NAME="${NAME%+}"
			set -- add "$VALUE" "$@"
		else
			set -- init add "$VALUE" "$@"
		fi
	elif $(( $# == 0 )); then
		if $VIA_FUNCTION; then
			#   For debugging, when you just type the
			#   Set function name, print the Set.
			set -- quote
		else
			set -- init
		fi
	fi

	#   If the Set doesn't exist yet, prepend "init".
	eval COUNT='${_SETC_'$NAME':-"<UNDEF>"}'
	if eq "$COUNT" "<UNDEF>" && neq "$1" "init"; then
		set -- init "$@"
	fi

	while $(( $# != 0 )); do
		CMD="$1"
		shift
		case "$CMD" in
		init|declare|define|reset|clear)
			COUNT=0
			setvar _SET_$NAME "$SEP"
			setvar _SETC_$NAME 0
			setvar _SETY_$NAME ""	# used for "yields"
			eval "$NAME () { Set -f $NAME \"\$@\"; }"
			;;
		count|length|len)
			echo $COUNT
			;;
		empty)
			return $(( COUNT != 0 ))
			;;
		contains)
			eval SET='"${_SET_'$NAME'-$SEP}"'
			contains "$SET" "${SEP}${1-}${SEP}" || return 1
			return 0
			;;
		add)
			eval SET='"${_SET_'$NAME':-$SEP}"'
			for VALUE in "$@"; do
				if ! contains "$SET" "${SEP}${VALUE}${SEP}"; then
					SET="${SET}${VALUE}${SEP}"
					let COUNT += 1
				fi
			done
			setvar _SET_$NAME "$SET"
			setvar _SETC_$NAME $COUNT
			return
			;;
		splitlines)
			Set "$NAME" init
			;&
		addlines)
			eval SET='"${_SET_'$NAME':-$SEP}"'
			OLD_IFS="$IFS"
			IFS="$NL"
			for VALUE in $*; do
				if ! contains "$SET" "${SEP}${VALUE}${SEP}"; then
					SET="${SET}${VALUE}${SEP}"
					let COUNT += 1
				fi
			done
			IFS="$OLD_IFS"
			setvar _SET_$NAME "$SET"
			setvar _SETC_$NAME $COUNT
			return
			;;
		rem|remove|del|delete)
			eval SET='"${_SET_'$NAME':-$SEP}"'
			for VALUE in "$@"; do
				MID="${SEP}${VALUE}${SEP}"
				if contains "$SET" "$MID"; then
					SET="${SET%%$MID*}${SEP}${SET##*$MID}"
					let COUNT -= 1
				fi
			done
			setvar _SET_$NAME "$SET"
			setvar _SETC_$NAME $COUNT
			return
			;;
		pop)
			VNAME="$1"
			shift
			eval SET='"${_SET_'$NAME':-$SEP}"'
			if $(( COUNT == 0 )); then
				return 1
			fi
			VALUE="${SET#$SEP}"
			setvar "$VNAME" "${VALUE%%$SEP*}"
			setvar _SET_$NAME "$SEP${SET#$SEP*$SEP}"
			setvar _SETC_$NAME $(( COUNT - 1 ))
			;;
		yields)
			VNAME="$1"
			shift
			eval SET='"${_SETY_'$NAME'-}"'
			if no "$SET"; then
				#   First call to "yields": initialize.
				eval SET='"${_SET_'$NAME'-}"'
			fi
			if eq "$SET" "$SEP"; then
				#   Finished.
				setvar _SETY_$NAME ""
				return 1
			fi
			VALUE="${SET#$SEP}"
			setvar "$VNAME" "${VALUE%%$SEP*}"
			setvar _SETY_${NAME} "$SEP${VALUE#*$SEP}"
			;;
		join|joinf)
			if eq "$CMD" "joinf"; then
				use_form=true
				FORM="$1"
				shift
			else
				use_form=false
			fi
			VALUE=""
			FIRST=true
			eval REST='"${_SET_'$NAME'-}"'
			REST="${REST#$SEP}"
			while have "$REST"; do
				PART="${REST%%$SEP*}"
				if $use_form; then
					PART=$(printf -- "$FORM" "$PART")
				fi
				if $FIRST; then
					VALUE="$PART"
					FIRST=false
				else
					VALUE="${VALUE}${1}${PART}"
				fi
				REST="${REST#*$SEP}"
			done
			printf '%s\n' "$VALUE"
			shift
			;;
		echo)
			Set "$NAME" join " "
			;;
		print)
			Set "$NAME" iterate echo
			;;
		quote)
			VALUE=""
			eval REST='"${_SET_'$NAME'-}"'
			REST="${REST#$SEP}"
			while have "$REST"; do
				VALUE="${VALUE}${VALUE:+ }$(quote_args "${REST%%$SEP*}")"
				REST="${REST#*$SEP}"
			done
			printf '%s\n' "$VALUE"
			;;
		toarray|to[-_]array)
			if $(( $# != 0 )); then
				ARRNAME=$1
				shift
			else
				ARRNAME="$NAME"
			fi
			array $ARRNAME init
			eval REST='"${_SET_'$NAME'-}"'
			REST="${REST#$SEP}"
			while have "$REST"; do
				array ${ARRNAME}+="${REST%%$SEP*}"
				REST="${REST#*$SEP}"
			done
			;;
		fromarray|from[-_]array)
			if $(( $# != 0 )); then
				ARRNAME=$1
				shift
			else
				ARRNAME="$NAME"
			fi
			eval Set $NAME add "$(array $ARRNAME quote)"
			;;
		iterate)
			eval REST='"${_SET_'$NAME'-}"'
			REST="${REST#$SEP}"
			while have "$REST"; do
				"$@" "${REST%%$SEP*}" \
				|| return $?
				REST="${REST#*$SEP}"
			done
			return
			;;
		*)
			red "[utils.sh] Set \"$NAME\": unknown sub-command \"$CMD\"." >&2
			exit 1
			;;
		esac
	done
}

#
#   "dict" is a simple implementation of a dictionary (sometimes called
#   an associative array).  It can be used as an array where indices may
#   be arbitrary strings (instead of sequential numbers).  You can also
#   think of it as a collection of key/value pairs.
#
#   NOTE:  This is meant only for small amounts of data, because the
#          whole dictionary is stored internally as a single string.
#          The empty string can be used both as index and as value.
#          Do NOT use it for binary data, because 0x00, 0x01 and 0x02
#          cannot be used.
#
#   dict <NAME> [init]			# Must be called once.
#   dict <NAME> add <INDEX> <VALUE> ...	# Add one or more elements.
#   dict <NAME>:<INDEX>=<VALUE>		# ditto
#   dict <NAME> get <INDEX> ...		# Returns one or more values.
#   dict <NAME>:<INDEX>			# ditto
#   dict <NAME> count			# Echoes number of elements.
#   dict <NAME> empty			# Return code 0 (true) or 1 (false).
#   dict <NAME> indices		        # Returns the indices (one per line).
#   dict <NAME> keys		        # ditto
#   dict <NAME> contains <INDEX>	# Return code 0 (true) or 1 (false).
#   dict <NAME> remove <INDEX> ...	# Remove one or more elements.
#   dict <NAME> pop <KNAME> <VNAME>	# Pop 1st pair & assign to variables.
#   dict <NAME> yields <KNAME> <VNAME>	# Generator, see below.
#   dict <NAME> iterate <COMMAND ...>	# Execute <COMMAND> for every element.
#   dict <NAME> print			# Print all elements, one per line.
#   dict <NAME> quote			# Ditto, but use quoting.
#
#   Upon creation of a dictionary (using "init" or just "dict MY_DICT"),
#   a function with the name of the dictionary is created, so you can omit
#   the "dict" command word.
#
#   You can replace ":<INDEX>" with "[<INDEX>]" (square brackets), provided
#   that you have switched off globbing (shell option -f).  Note that this
#   "syntactic sugar" doesn't work if the index or the value contain any of
#   these special characters.  If in doubt, use "add" and "get" which always
#   work.
#
#   Note that there must be no spaces adjacent to ":", "[", "]" and "=",
#   except that there may be a space after <NAME> in each case (this is to
#   allow using the dynamically created funcion, e.g. ``MY_DICT :42'').
#
#   The "yields" subcommand can be used similar to generators in Python:
#     while MY_DICT yields KEY VALUE; do echo "$KEY = $VALUE"; done
#   Note that "yields" makes a temporary copy of the dict before it returns
#   the first element.  Therefore you can safely make changes to the dict
#   within the loop:
#     while MY_DICT yields KEY VALUE; do
#         if endswith "$VALUE" .BAK; then
#             MY_DICT remove "$KEY"
#         fi
#     done
#
#   The "pop" subcommand can be used similarly, but it removes the elements
#   from the dict:
#     while MY_DICT pop KEY VALUE; do echo "$KEY = $VALUE"; done
#     MY_DICT count   # prints "0".
#

dict ()
{
	local ESEP=$'\x01'	# element separator
	local VSEP=$'\x02'	# value separator
	local NAME KNAME VNAME DICT INDEX VALUE CMD MID COUNT REST
	local VIA_FUNCTION=false

	if eq "${1-}" "-f"; then
		VIA_FUNCTION=true
		shift
	fi

	if empty "${1-}"; then
		red "[utils.sh] dict: Missing or empty dict name." >&2
		exit 1
	fi

	if ! match "$1" '*[][:]*' && match "${2-}" ':*|"["*"]"*'; then
		NAME="$1$2"
		shift 2
	else
		NAME="$1"
		shift
	fi

	if contains "$NAME" ":" && ! contains "${NAME%%:*}" "["; then
		INDEX="${NAME#*:}"
		if contains "$INDEX" "="; then
			set -- add "${INDEX%%=*}" "${INDEX#*=}" "$@"
		else
			set -- get "$INDEX" "$@"
		fi
		NAME="${NAME%%:*}"
	elif contains "$NAME" "[" && contains "${NAME#*"["}" "]" ; then
		INDEX="${NAME#*"["}"
		VALUE="${INDEX#*"]"}"
		INDEX="${INDEX%%"]"*}"
		if startswith "$VALUE" "="; then
			set -- add "$INDEX" "${VALUE#=}" "$@"
		elif nonempty "$VALUE"; then
			set -- get "$INDEX" "$VALUE" "$@"
		else
			set -- get "$INDEX" "$@"
		fi
		NAME="${NAME%%"["*}"
	elif $(( $# == 0 )); then
		if $VIA_FUNCTION; then
			#   For debugging, when you just type the
			#   dict function name, print the dictionary.
			set -- quote
		else
			set -- init
		fi
	fi

	while $(( $# != 0 )); do
		CMD="$1"
		shift
		case "$CMD" in
		get)
			eval DICT='"${_DICT_'$NAME'-$ESEP}"'
			for INDEX in "$@"; do
				MID="${ESEP}${INDEX}${VSEP}"
				if contains "$DICT" "$MID"; then
					REST="${DICT##*$MID}"
					printf '%s\n' "${REST%%$ESEP*}"
				fi
			done
			return
			;;
		add|"set")
			eval DICT='"${_DICT_'$NAME'-$ESEP}"'
			eval COUNT='${_DICTC_'$NAME':-0}'
			while $(( $# != 0 )); do
				INDEX="$1"
				VALUE="${2-}"
				MID="${ESEP}${INDEX}${VSEP}"
				if contains "$DICT" "$MID"; then
					REST="${DICT##*$MID}"
					DICT="${DICT%%$MID*}${ESEP}${INDEX}${VSEP}${VALUE}${ESEP}${REST#*$ESEP}"
				else
					DICT="${DICT}${INDEX}${VSEP}${VALUE}${ESEP}"
					let COUNT += 1
				fi
				shift 2
			done
			setvar _DICT_$NAME "$DICT"
			setvar _DICTC_$NAME $COUNT
			return
			;;
		rem|remove|del|delete)
			eval DICT='"${_DICT_'$NAME'-$ESEP}"'
			eval COUNT='${_DICTC_'$NAME':-0}'
			for INDEX in "$@"; do
				MID="${ESEP}${INDEX}${VSEP}"
				if contains "$DICT" "$MID"; then
					REST="${DICT##*$MID}"
					DICT="${DICT%%$MID*}${ESEP}${REST#*$ESEP}"
					let COUNT -= 1
				fi
			done
			setvar _DICT_$NAME "$DICT"
			setvar _DICTC_$NAME $COUNT
			return
			;;
		pop)
			KNAME="$1"
			VNAME="$2"
			shift 2
			eval COUNT='${_DICTC_'$NAME':-0}'
			if $(( COUNT == 0 )); then
				return 1
			fi
			eval DICT='"${_DICT_'$NAME':-$ESEP}"'
			VALUE="${DICT#$ESEP}"
			VALUE="${VALUE%%$ESEP*}"
			setvar "$KNAME" "${VALUE%%$VSEP*}"
			setvar "$VNAME" "${VALUE#*$VSEP}"
			setvar _DICT_$NAME "$ESEP${DICT#$ESEP*$ESEP}"
			setvar _DICTC_$NAME $(( COUNT - 1 ))
			;;
		yields)
			KNAME="$1"
			VNAME="$2"
			shift 2
			eval DICT='"${_DICTY_'$NAME'-}"'
			if no "$DICT"; then
				#   First call to "yields": initialize.
				eval DICT='"${_DICT_'$NAME'-}"'
			fi
			if eq "$DICT" "$ESEP"; then
				#   Finished.
				setvar _DICTY_$NAME ""
				return 1
			fi
			VALUE="${DICT#$ESEP}"
			setvar _DICTY_${NAME} "$ESEP${VALUE#*$ESEP}"
			VALUE="${VALUE%%$ESEP*}"
			setvar "$KNAME" "${VALUE%%$VSEP*}"
			setvar "$VNAME" "${VALUE#*$VSEP}"
			;;
		init|declare|define|reset|clear)
			setvar _DICT_$NAME "$ESEP"
			setvar _DICTC_$NAME 0
			setvar _DICTY_$NAME ""	# used for "yields"
			eval "$NAME () { dict -f $NAME \"\$@\"; }"
			;;
		count|length|len)
			eval echo '${_DICTC_'$NAME':-0}'
			;;
		empty)
			eval return '$(( ${_DICTC_'$NAME':-0} != 0 ))'
			;;
		contains)
			eval DICT='"${_DICT_'$NAME'-$ESEP}"'
			contains "$DICT" "${ESEP}${1-}${VSEP}" || return 1
			return 0
			;;
		print)
			dict $NAME iterate echo
			;;
		quote)
			dict $NAME iterate quote_args
			;;
		indices|keys)
			eval REST='"${_DICT_'$NAME'-}"'
			REST="${REST#$ESEP}"
			while have "$REST"; do
				MID="${REST%%$ESEP*}"
				printf '%s\n' "${MID%%$VSEP*}"
				REST="${REST#*$ESEP}"
			done
			return
			;;
		values)
			eval REST='"${_DICT_'$NAME'-}"'
			REST="${REST#$ESEP}"
			while have "$REST"; do
				MID="${REST%%$ESEP*}"
				printf '%s\n' "${MID#*$VSEP}"
				REST="${REST#*$ESEP}"
			done
			return
			;;
		iterate)
			eval REST='"${_DICT_'$NAME'-}"'
			REST="${REST#$ESEP}"
			while have "$REST"; do
				MID="${REST%%$ESEP*}"
				"$@" "${MID%%$VSEP*}" "${MID#*$VSEP}" \
				|| return $?
				REST="${REST#*$ESEP}"
			done
			return
			;;
		*)
			red "[utils.sh] dict \"$NAME\": unknown sub-command \"$CMD\"." >&2
			exit 1
			;;
		esac
	done
}

#
#   Echo the arguments in a quoted form, suitable to display them
#   or pass them to eval (carefully!).  Typical usage:
#
#   if $VERBOSE; then
#           echo "Executing command:" >&2
#           quote_args some_command "$@" >&2
#   fi
#   some_command "$@"
#

quote_args ()
{
	local ARG
	local SEP=""

	for ARG in "$@"; do
		if match "$ARG" '*[!-A-Za-z0-9_+=:,./]*|""'; then
			#   Quoting required.
			if match "$ARG" '*[\"\$\`\\]*'; then
				#   Single-quoting required.
				if match "$ARG" "*\\'*"; then
					#   Internal single-quotes need to be escaped.
					ARG="'$(printf "%s\\n" "$ARG" | sed "s/'/'\\\\''/g")'"
				else
					#   There are no internal single-quotes.
					ARG="'$ARG'"
				fi
			else
				#   Double-quoting can be done.
				ARG="\"$ARG\""
			fi
		fi
		echo -n "$SEP$ARG"
		SEP=" "
	done
	echo
}

#
#   Quote special characters of regular expression, so it can be used as a
#   regular string within regular expression matching.
#
#   Note that some characters are quoted with backslashes, while others are
#   quoted with square brackets.  That's because of different behaviour for
#   some types of regular expressions, e.g. "\(" has a different meaning in
#   basic regex vs. extended regex, while "[(]" always means the same.
#

quote_regex ()
{
	# printf '%s\n "$@" | sed 's/\\/&&/g;s/[][*.+?^$(){}|]/[&]/g'
	printf '%s\n' "$@" | sed 's/[][\\*.^$]/\\&/g;s/[+?(){}|]/[&]/g'
}

#
#   This is similar to quote_args, but always uses double-quotes and does *NOT*
#   escape $-signs and backticks.  Therefore, these will be expanded when the
#   result is passed to eval.  Be careful!
#

doublequote_args ()
{
	local ARG
	local SEP=""

	for ARG in "$@"; do
		if match "$ARG" '*[!-A-Za-z0-9_+=:,./]*|""'; then
			#   Quoting required.
			if match "$ARG" '*[\"\\]*'; then
				#   Internal double-quotes or backslashes need to be escaped.
				ARG=\"$(printf '%s\n' "$ARG" | sed 's/["\\]/\\&/g')\"
			else
				#   There are no internal double-quotes or backslashes.
				ARG="\"$ARG\""
			fi
		fi
		echo -n "$SEP$ARG"
		SEP=" "
	done
	echo
}

#
#   Add one or more directories to $PATH, if they're not included yet.
#   Directories are appended at the end.
#

add_path ()
{
	local P

	for P in "$@"; do
		P="${P%/}"
		if match ":${PATH}:" '*:"${P}":*|*:"${P}/":*'; then
			continue
		fi
		export PATH="${PATH}:$P"
	done
}

#
#   std_getopts ()
#
#   Syntax:  std_getopts [-lnu] <options_definition> [<arguments> ...]
#
#   Typical example (simple case):
#       std_getopts "n i: v" "$@"
#       shift $OPT_INC
#
#
#   ========  INTRODUCTION AND BASIC USAGE
#
#   This is a wrapper for the getopts(1) function that is built into
#   FreeBSD's /bin/sh.  In the simple case, the <options_definition>
#   string is a sequence of alphanumeric characters (i.e. ASCII letters
#   and digits), each character specifying a supported command line
#   option.  If the character is followed by a colon, this indicates
#   that the option requires a parameter.  You may use white-space
#   (spaces, tabs and newlines) to improve the readability of the
#   <options_definition>.
#
#   For each option character, the function manages two shell variables
#   OPT_<char> and OPT_ARG_<char>, where <char> is the option character.
#
#   OPT_<char> is set to "false" by default.  If the option occurs in
#   the given <arguments>, it is set to "true".
#
#   OPT_ARG_<char> is handled as follows:
#     - For options that have parameters (with colon), it is set to an
#       empty string by default.  If the option occurs in the given
#       <arguments>, it is set to the parameter given for that option.
#     - For options that have no parameters (without colon), it acts as
#       a counter:  It is set to 0 by default.  For each occurence of
#       the option in the given <arguments>, it is incremented by 1.
#       This is useful for things like -vvv (verbosity level 3).
#
#   Upon success, the variable OPT_INC is set to the number of arguments
#   that have been parsed successfully.  You can use "shift $OPT_INC"
#   to remove them from the argument vector.
#
#   If an error occurs, the script exits using the Err() function with
#   an appropriate error message.  This behaviour can be modified by
#   passing one of these options to the std_getopts function:
#       -n    Do not exit right away if an error occurs, instead return
#             from the std_getopts function with return code 1, and
#             set the variable OPT_ERR to the error message.
#       -u    After the error message has been printed, also call the
#             Usage() function before exiting.
#
#   The description above is sufficient for simple cases, so you don't
#   have to read further if you just need to handle a few options in a
#   simple way.  Typical example:
#
#       Usage_Text "Usage:  $ME [-a] [-o <outfile>] [-v[v]] <infile>"
#       std_getopts "n o: v" "$@"
#       shift $OPT_INC
#       assert $# == 1
#       IN_FILE="$1"
#       OUT_FILE="${OPT_ARG_o:-$INFILE.out}"
#       NOT_REALLY=$OPT_n       # false / true
#       VERBOSITY=$OPT_ARG_v    # default 0
#       ...
#
#
#   ========  OVERRIDING VARIABLE NAMES
#
#   You can override the variable name by specifying a name in curly
#   braces ("{...}") following the option character; this name will
#   replace OPT_<char>.  You can also specify a name in curly braces
#   following the colon; this name will replace OPT_ARG_<char>.  If
#   there is no colon, just use a second pair of curly braces (leaving
#   the first pair empty if you don't need it).
#   Formal syntax:
#     <char>[{<opt_name>}][:][{<opt_arg_name>}]
#   Examples:
#
#     v             Use OPT_v and OPT_ARG_v (the former will be "false"
#                   or "true", the latter is counting the occurences of
#                   the option -v).
#     v{VERBOSE}    Use VERBOSE instead of OPT_v, but still use the
#                   default name OPT_ARG_v for counting the option.
#     v{VERBOSE}{VERBOSITY}   Use VERBOSE instead of OPT_v, and use
#                             VERBOSITY instead of OPT_ARG_v.
#     v{}{VERBOSITY}   Use the default OPT_v, but use VERBOSITY instead
#                      of OPT_ARG_v.
#     f:{INFILE}    Use the default OPT_f (false/true), but use INFILE
#                   instead of OPT_ARG_f.
#     f{}:{INFILE}  Ditto.  If there's a colon, the empty pair of
#                   braces can be omitted.
#     f{FOO}{BAR}:  Syntax error, the colon must be between the
#                   two pairs of braces.
#     f:{FOO}{BAR}  Syntax error, ditto.
#
#   Using this feature, the above example can be rewritten like this:
#
#       Usage_Text "Usage:  $ME [-a] [-o <outfile>] [-v] <infile>"
#       std_getopts "n{NOT_REALLY} o:{OUT_FILE} v{}{VERBOSITY}" "$@"
#       shift $OPT_INC
#       assert $# == 1
#       IN_FILE="$1"
#       default OUT_FILE "$INFILE.out"
#       ...
#
#   For long options definitions, it is recommended to split them across
#   multiple lines for readability.  For the given example, you can do
#   it like this:
#
#       std_getopts "
#           n   {NOT_REALLY}
#           o:  {OUT_FILE}
#           v   {}{VERBOSITY}
#       " "$@"
#
#   If you do not want to store a certain value at all, you can specify
#   a single dash within curly braces "{-}".  This is especially useful
#   when using std_getopts locally inside a function, so you don't have
#   do declare variables with "local" if you don't actyually need them.
#   Also see the -l option described below.
#
#
#   ========  DEFAULT VALUES
#
#   Within curly braces, you can also specify a default value for this
#   option, separated from the variable name (if any) by an equals sign
#   "=".  You can omit the variable name if you want to use the default
#   name (i.e. OPT_<char>, OPT_ARG_char), in this case the equals sign
#   follows the opening brace directly.
#
#   Only for the boolean variables (i.e. for OPT_<char>, but not for
#   OPT_ARG_<char>), you can specify another value separated by a second
#   equals sign.  This value is used instead of "true" when the option
#   occurs.  Examples:
#
#      f:{INFILE=/dev/stdin}   Use "/dev/stdin" as the default for
#                              INFILE if there is no -f option.
#      v{}{VERBOSITY=-1}  Start counting the verbosity level at -1
#                         instead of 0.
#      x{=}             Set OPT_x to "" (empty string) by default,
#                       instead of "false".
#      n{REALLY=true=false}   Invert the sense of this option: Set
#                       REALLY to "true" by default, and set it to
#                       "false" if option -n occurs (instead of the
#                       other way round).
#      n{REALLY=true}   Ditto.  This is a shortcut: If the default
#                       value is specified as "true", the other value
#                       is assumed to be "false".
#
#   Instead of an equals sign, you can use any character that does not
#   match [A-Za-z0-9_}] (i.e. not valid in an identifier, and not a
#   closing brace).  If you specify two values (to replace false/true),
#   you must use the same separating character for them.  Example:
#
#     4{FFOPT/lib=x265/lib=x264}  Set the variable FFOPT to the value
#                                 "lib=x265" by default, and set it to
#                                 "lib=x264" when the option -4 occurs.
#
#   Note that multiple options can use the same variable name, setting
#   the variable to different values.  In this case, the default value
#   should be the same for all options, otherwise the behaviour is
#   undefined.  Example:
#       d {MODE=default=dumb}
#       s {MODE=default=smart}
#   The variable MODE will be set to "dumb" if the option -d occurs,
#   and it will be set to "smart" if the otpion -s occurs.  If neither
#   occurs, it will be set to the string "default".
#
#
#   ========  LONG OPTIONS
#
#   You can define long options by prefixing them with a single dash "-"
#   in the <options_definition>, like this: "-foo-bar".  The option name
#   extends till the next character that is not valid in a long option
#   name (usually a colon ":", opening brace "{" or a white-space
#   character), or the end of the definition string.  Long option names
#   may consist of alphanumeric characters, underscores and dashes
#   (dashes are converted to underscores internally, so "foo-bar" is
#   the same as "foo_bar").  The first character of the actual name
#   (after the dash prefix) must not be a dash.  Long options must be
#   at least two characters long.
#
#   These long options work similar to GNU-style long options.  When
#   using them on the command line, they must be prefixed by a double
#   dash ("--foo-bar").  If they require a parameter, there are two
#   ways to specify them:
#      --foo-bar fasel    # As separate argument.
#      --foo-bar=fasel    # Appended with an equals sign.
#
#   Otherwise, long option definitions work exactly like short options
#   definitions, i.e. they can be followed by a colon (indicating that a
#   parameter is required), and you can use brace expressions to define
#   variable names and/or default values.  For example, the following
#   defines a long option "--input" that requires a parameter that is
#   stored in the variable INFILE, the default is "/dev/stdin" if the
#   option is not present.
#
#      -input: {INFILE=/dev/stdin}
#
#   Since the options definition can become rather long, you can put
#   arbitrary white-space (spaces, tabs, newlines) between options.
#   Also, the colon ":" (indicating the presence of a parameter for an
#   option) and the opening brace "{" (used for overriding variable
#   names and defaults) can be preceded by arbitrary white-space.
#
#
#   ========  SPECIAL INTERNAL OPTIONS
#
#   If you don't define "h" and/or "H" in your <options_definition>,
#   then they are implemented internally by calling the Usage() function
#   and exiting.  If there is no Usage() function, a very simple usage
#   message is generated.  See the Usage_Text() function for a simple
#   way to generate your own Usage() function.
#
#   If you don't define "D" in your <options_definition>, then it is
#   implemented internally to set the global variable DEBUG to "true"
#   (default "false").  See the Debug() function that prints a message
#   only if DEBUG is set to "true".
#
#   If you don't want those options to be defined automatically, pass
#   the -l option to std_getopts() (Note that this option does other
#   things, too, see below).  Usually this is only required when calling
#   std_getopts() locally within a function, otherwise it would reset
#   the global variable DEBUG to "false".
#
#
#   ========  CHECK FUNCTIONS
#
#   You can define a function OPT_CHECK_<char> that will be called each
#   time the option <char> occurs.  It will be passed the parameter as
#   first argument.  For options that don't take parameters, it will be
#   passed the counter (i.e. "1" for the first occurence).  If this
#   function detects an error, it should exit with an appropriate error
#   message.  Typically, this can be used to check the validity of
#   parameters, for example integer numbers:
#
#       OPT_CHECK_i ()
#       {
#           if ! in_range "$1" 1 10; then
#               Err "Invalid value \"$1\", must be a number between 1 and 10."
#           fi
#       }
#
#   The OPT_CHECK_<char> function can do other things beside checking
#   the validity of parameters.  For example, it can add the parameter
#   to an array.  This is useful if an option is allowed to occur more
#   than once, and its parameters are supposed to accumulate.  Example:
#
#       array INPUT_FILES
#       OPT_CHECK_f ()
#       {
#           assert isfile "$1" -- Err "File not found: $1"
#           INPUT_FILES add "$1"
#       }
#
#   This example adds the parameters to a comma-separated string:
#
#       WORDS=""
#       OPT_CHECK_w ()
#       {
#           WORDS="${WORDS}${WORDS:+,}$1"
#       }
#
#
#   ========  MISCELLANEOUS
#
#   Even if your script doesn't support any options, it's worth using
#   this wrapper, so you easily get support for the -h, -H and -D
#   options (printing a usage message, setting $DEBUG, see above for
#   details) and the standard behaviour of "--" (for stopping option
#   processing).  The following one-liner will do that:
#
#       std_getopts "" "$@"; shift $OPT_INC
#
#   Note that you can use std_getopts within a function to parse the
#   function's arguments.  In this case you should declare OPT_<char>
#   and OPT_ARG_<char> as local (for all options that you define), or
#   use other names using the brace syntax ("{}", see above), or use
#   "{-}" to not store the values at all if you don't need them.  If
#   you want to be on the safe side, you can also declare OPT_INC and
#   OPT_ERR as local, although these are usually only used right after
#   the std_getopts call.  It is recommended to pass the -l option to
#   std_getopts(); this does two things:
#     -  "{-}" is the default if no variable name is given.  In other
#        words, values are only stored when you specify variable names
#        explicitly; OPT_<char> and OPT_ARG_<char> are not used.
#     - The options -H, -h and -D are not defined automatically when
#       they don't appear in the options definition.  This prevents
#       std_getopts from messing with the global DEBUG variable.  
#   A typical example of using std_getopts in a function:
#
#   funcname ()
#   {
#       local ECHO_FUNC REALLY ARG
#       local OPT_INC
#
#       std_getopts -l "
#           e :{ECHO_FUNC=echo}
#           n {REALLY=true}
#       "
#       shift $OPT_INC
#       for ARG in "$@"; do
#           $ECHO_FUNC "Handling $ARG ..."
#           if $REALLY; then
#               do_something "$ARG"
#           fi
#       done
#   }
#
#
#   TODO:
#    - Provide a syntax to make a short option and a long option do the
#      same thing, so you don't have to duplicate definitions like this:
#          "i:{INFILE=/dev/stdin} -input:{INFILE=/dev/stdin}"
#
#   TODO:
#    - In addition to -h and -H, also provide --help as a default option
#      for printing the usage message (unless the user defines a long
#      option named "--help", of course).
#
#   TODO:
#    - Provide a syntax to have parameters be added to an array, without
#      having to define an OPT_CHECK_<char> function as in the example
#      above.  Suggestion: Use an empty pair of square brackets ("[]")
#      after the variable name inside curly braces, to indicate that
#      this is the name of an array.  For example:
#          "f: {INPUT_FILES[]}"
#      In this case, specifying a default value does not make sense, so
#      the square brackets must be followed by the closing brace.  The
#      array is initialized automatically (if it already exists, it is
#      cleared before the options are parsed).
#
#   TODO:
#    - Provide a syntax to specify arbitrary shell code to be executed
#      when an option occurs.  In many simple cases this could replace
#      using an OPT_CHECK_<char> function.  Suggestion:  Use a sequence
#      of characters that is unlikely to occur in shell code, in order
#      to avoid quoting hell, for example "{{ ... }}":
#          't: {{ TITLE=$(quote_html "$ARG") }}
#      Alternatively, allow shell code in place of a string value:
#          't: {TITLE=Unknown={{ $(quote_html "$ARG") }} }
#

_sgo_debug ()
{
	purple "std_getopts(): $*" >&2
}

_sgo_usage ()
{
	if type Usage >/dev/null 2>&1 ; then
		Usage
	else
		yellow "Usage: $SIMPLE_USAGE <ARG(s) ...>" >&2
	fi
	exit 1
}

_sgo_error ()
{
	OPT_ERR="$*"
	if $EXIT_ON_ERROR; then
		Err -n "$OPT_ERR"
		if $USAGE_ON_ERROR; then
			_sgo_usage
		fi
		exit 1
	fi
}

_sgo_get_var_name ()
{
	local DEFAULT_NAME="$1" DESCRIPTION="$2"
	local CHECK

	while match "$REST" '[\ $TAB$CR$NL]*'; do
		REST="${REST#?}"
	done
	if startswith "$REST" '{'; then
		REST="${REST#?}"
		if ! contains "$REST" '}'; then
			_sgo_error "Missing closing brace \"}\" in option definition for option $OPT_DISP."
			return 1
		fi
		VAR_NAME="${REST%%\}*}"

		#   Check if there is a non-identifier character
		#   that is used as a separator for default values.
		CHECK="${VAR_NAME%%[!A-Za-z0-9_]*}"
		if neq "$VAR_NAME" "$CHECK"; then
			DEFAULT="${VAR_NAME#$CHECK}"
			VAR_NAME="$CHECK"
			CHECK="${DEFAULT#?}"
			SEPARATOR="${DEFAULT%$CHECK}"
			DEFAULT="$CHECK"
		else
			SEPARATOR=""
		fi

		if no "$VAR_NAME"; then
			if $LOCAL_OPTIONS; then
				VAR_NAME="-"
				$UTILS_DEBUG && _sgo_debug "    ${OPT_DISP}: Not storing value for ${DESCRIPTION} (default would be $DEFAULT_NAME)."
			else
				VAR_NAME="$DEFAULT_NAME"
				$UTILS_DEBUG && _sgo_debug "    ${OPT_DISP}: Using default variable name for ${DESCRIPTION}: $DEFAULT_NAME"
			fi
		elif eq "$VAR_NAME" "-"; then
			$UTILS_DEBUG && _sgo_debug "    ${OPT_DISP}: Not storing value for ${DESCRIPTION} (default would be $DEFAULT_NAME)."
		elif ! isident "$VAR_NAME"; then
			_sgo_error "Invalid variable name \"$VAR_NAME\" in option definition for option $OPT_DISP."
			return 1
		elif $UTILS_DEBUG; then
			_sgo_debug "    ${OPT_DISP}: Setting variable name for ${DESCRIPTION}: $VAR_NAME"
		fi
		REST="${REST#*\}}"
	else
		if $LOCAL_OPTIONS; then
			VAR_NAME="-"
			$UTILS_DEBUG && _sgo_debug "    ${OPT_DISP}: Not storing value for ${DESCRIPTION} (default would be $DEFAULT_NAME)."
		else
			VAR_NAME="$DEFAULT_NAME"
			$UTILS_DEBUG && _sgo_debug "    ${OPT_DISP}: Using default variable name for ${DESCRIPTION}: $DEFAULT_NAME"
		fi
		SEPARATOR=""
	fi
}

_dash_to_underscore ()
{
	local STR="$1" RESULT_VAR="$2"
	local PART

	while :; do
		PART="${STR%%-*}"
		if eq "$PART" "$STR"; then
			setvar "$RESULT_VAR" "$STR"
			return
		fi
		STR="${PART}_${STR#*-}"
	done
}

std_getopts ()
{
	local LOCAL_OPTIONS=false EXIT_ON_ERROR=true USAGE_ON_ERROR=false
	local OPTDEFS
	local OPT_DEFS="" LONG_OPT_DEFS="/" USAGE_OPTS=""
	local HAVE_D=false HAVE_H=false HAVE_h=false HAVE_LONG=false
	local SIMPLE_USAGE="$ME"
	local OPTIND=1 OPT OPTARG REST VAR_NAME DEFAULT SEPARATOR
	local OPT_NAME OPT_DISP
	#   OPT_NAME is the the internal option name without leading dashes,
	#            and other dashes converted to underscores (long option).
	#   OPT_DISP is for display purposes only, with all dashes.

	#   We cannot call ourselves recursively, so we use a very simple
	#   option parser for our own options here.
	while match "${1-}" '-?*'; do
		if eq "$1" "--"; then
			shift
			break
		elif match "$1" '-*[!lnu]*'; then
			_sgo_error "Internal error: std_getopts(): \"$1\" unsupported."
			return 1
		fi
		match "$1" '-*l*' && LOCAL_OPTIONS=true
		match "$1" '-*n*' && EXIT_ON_ERROR=false
		match "$1" '-*u*' && USAGE_ON_ERROR=true
		shift
	done

	OPTDEFS="$1"
	shift

	$UTILS_DEBUG && _sgo_debug "Parsing option definitions ..."
	while have "$OPTDEFS"; do
		REST="${OPTDEFS#?}"
		OPT="${OPTDEFS%$REST}"
		if match "$OPT" '[\ $TAB$CR$NL]'; then
			OPTDEFS="$REST"
			continue
		fi
		if eq "$OPT" "-"; then
			#   Long option.
			OPT="${REST%%[!-A-Za-z0-9_]*}"
			$UTILS_DEBUG && _sgo_debug "    Defining long option --$OPT."
			if [ ${#OPT} -lt 2 ]; then
				_sgo_error "Invalid long option \"--$OPT\", must be at least 2 characters."
				return 1
			fi
			REST="${REST#$OPT}"
			_dash_to_underscore "$OPT" OPT_NAME
			OPT_DISP="--$OPT"
			LONG_OPT_DEFS="${LONG_OPT_DEFS}${OPT_NAME}/"
			HAVE_LONG=true
		elif match "$OPT" '[A-Za-z0-9_]'; then
			$UTILS_DEBUG && _sgo_debug "    Defining option -$OPT."
			OPT_NAME="$OPT"
			OPT_DISP="-$OPT"
			OPT_DEFS="${OPT_DEFS}$OPT_NAME"
			if match "$OPT" '[DHh]'; then
				setvar HAVE_$OPT true
			fi
		else
			_sgo_error "Invalid option \"-$OPT\" in option definition, must be alphanumeric."
			return 1
		fi

		DEFAULT=false
		_sgo_get_var_name OPT_$OPT_NAME "this option" || return 1
		setvar _VAR_NAME_$OPT_NAME "$VAR_NAME"
		if eq "$DEFAULT" "true"; then
			#   Inverted option:  true is the default, and
			#   it is set to false when the option is used.
			setvar _OPT_VALUE_$OPT_NAME "false"
			$UTILS_DEBUG && _sgo_debug "    ${OPT_DISP}: Using inverted truth values."
		elif have "$SEPARATOR" && contains "$DEFAULT" "$SEPARATOR"; then
			#   User specified both "false" and "true"
			#   replacements for this option.
			$UTILS_DEBUG && _sgo_debug "    ${OPT_DISP}: Using values \"${DEFAULT%%$SEPARATOR*}\"/\"${DEFAULT#*$SEPARATOR}\" instead of false/true."
			setvar _OPT_VALUE_$OPT_NAME "${DEFAULT#*$SEPARATOR}"
			DEFAULT="${DEFAULT%%$SEPARATOR*}"
		else
			setvar _OPT_VALUE_$OPT_NAME "true"
		fi
		if neq "$VAR_NAME" "-"; then
			setvar $VAR_NAME "$DEFAULT"
			$UTILS_DEBUG && _sgo_debug "    ${OPT_NAME}: Setting default ${VAR_NAME}=\"$DEFAULT\""
		fi

		while match "$REST" '[\ $TAB$CR$NL]*'; do
			REST="${REST#?}"
		done
		if startswith "$REST" ':'; then
			setvar _OPT_COLON_$OPT_NAME true
			if [ ${#OPT_NAME} -eq 1 ]; then
				OPT_DEFS="${OPT_DEFS}:"
			fi
			DEFAULT=""
			DESCRIPTION="option argument"
			REST="${REST#?}"
			SIMPLE_USAGE="$SIMPLE_USAGE [$OPT_DISP <ARG>]"
		else
			setvar _OPT_COLON_$OPT_NAME false
			DEFAULT=0
			DESCRIPTION="option counter"
			SIMPLE_USAGE="$SIMPLE_USAGE [$OPT_DISP]"
		fi

		_sgo_get_var_name OPT_ARG_$OPT_NAME "$DESCRIPTION" || return 1
		setvar _ARG_VAR_NAME_$OPT_NAME "$VAR_NAME"
		if neq "$VAR_NAME" "-"; then
			setvar $VAR_NAME "$DEFAULT"
			$UTILS_DEBUG && _sgo_debug "    ${OPT_DISP}: Setting default ${VAR_NAME}=\"$DEFAULT\""
		fi

		OPTDEFS="$REST"
	done
	$UTILS_DEBUG && _sgo_debug "Finished option definitions."

	if ! $LOCAL_OPTIONS; then
		if ! $HAVE_D; then
			OPT_DEFS="${OPT_DEFS}D"
			DEBUG=false
			$UTILS_DEBUG && _sgo_debug "Adding default option -D to enable debug mode."
		fi
		if ! $HAVE_H; then
			USAGE_OPTS="${USAGE_OPTS}H"
			$UTILS_DEBUG && _sgo_debug "Adding default option -H to print usage message."
		fi
		if ! $HAVE_h; then
			USAGE_OPTS="${USAGE_OPTS}h"
			$UTILS_DEBUG && _sgo_debug "Adding default option -h to print usage message."
		fi
	fi
	if have "$USAGE_OPTS"; then
		OPT_DEFS="${OPT_DEFS}${USAGE_OPTS}"
		USAGE_OPTS="[$USAGE_OPTS]"
	else
		USAGE_OPTS="%NONE%"
	fi

	if $HAVE_LONG; then
		OPT_DEFS="${OPT_DEFS}-:"
	fi

	if $UTILS_DEBUG; then
		_sgo_debug "Options definition: \"$OPT_DEFS\""
		$HAVE_LONG && _sgo_debug "Long options: $LONG_OPT_DEFS"
		_sgo_debug "Parsing argument vector ..."
	fi

	while getopts ":$OPT_DEFS" OPT ; do
		$UTILS_DEBUG && _sgo_debug "    Got character \"$OPT\"."
		if eq "$OPT" "-"; then
			#   Long option.
			$UTILS_DEBUG && _sgo_debug "    --> argument \"$OPTARG\""
			REST="$OPTARG"
			OPT="${OPTARG%%=*}"
			OPTARG="${OPTARG#$OPT}"
			OPTARG="${OPTARG#=}"
			$UTILS_DEBUG && _sgo_debug "    --> long option \"--$OPT\""
			_dash_to_underscore "$OPT" OPT_NAME
			OPT_DISP="--$OPT"
			if ! match "/$LONG_OPT_DEFS/" "*/$OPT_NAME/*"; then
				_sgo_error "Unknown option \"$OPT_DISP\"."
				return 1
			fi
			if eval \$_OPT_COLON_$OPT_NAME ; then
				if ! contains "$REST" "="; then
					if [ $# -lt $OPTIND ]; then
						_sgo_error "Missing argument for option $OPT_DISP."
						return 1
					fi
					eval OPTARG='"$'$OPTIND'"'
					let OPTIND += 1
				fi
				$UTILS_DEBUG && _sgo_debug "    --> argument \"$OPTARG\""
			elif have "$OPTARG"; then
				$UTILS_DEBUG && _sgo_debug "    --> unexpected argument \"$OPTARG\""
				_sgo_error "Option $OPT_DISP doesn't accept arguments."
				return 1
			fi
		else
			#   Short option.
			$UTILS_DEBUG && _sgo_debug "    --> option \"-$OPT\""
			if eq "$OPT" ":"; then
				_sgo_error "Missing argument for option -$OPTARG."
				return 1
			elif eq "$OPT" "?"; then
				_sgo_error "Unknown option \"-$OPTARG\"."
				return 1
			fi
			OPT_NAME="$OPT"
			OPT_DISP="-$OPT"
			if ! match "$OPT_NAME" "[$OPT_DEFS]"; then
				_sgo_error "Internal error: Unknown option \"$OPT_DISP\"."
				return 1
			fi
		fi

		if ! $LOCAL_OPTIONS; then
			if eq "$OPT_NAME" "D" && ! $HAVE_D; then
				$UTILS_DEBUG && _sgo_debug "    -D: Enabling debug mode."
				DEBUG=true
				continue
			fi
			if match "$OPT_NAME" "$USAGE_OPTS"; then
				$UTILS_DEBUG && _sgo_debug "    ${OPT_DISP}: Printing usage message."
				_sgo_usage
			fi
		fi

		eval VAR_NAME=\$_VAR_NAME_$OPT_NAME
		if neq "$VAR_NAME" "-"; then
			$UTILS_DEBUG && eval _sgo_debug '"    ${OPT_DISP}: Setting $VAR_NAME=\"$_OPT_VALUE_'$OPT_NAME'\"."'
			eval setvar $VAR_NAME \"\$_OPT_VALUE_$OPT_NAME\"
		fi

		eval VAR_NAME=\$_ARG_VAR_NAME_$OPT_NAME
		if neq "$VAR_NAME" "-"; then
			if eval \$_OPT_COLON_$OPT_NAME ; then
				$UTILS_DEBUG && _sgo_debug "    ${OPT_DISP}: Setting $VAR_NAME=\"$OPTARG\"."
				setvar $VAR_NAME "$OPTARG"
			else
				OPTARG=$(( $VAR_NAME + 1 ))
				$UTILS_DEBUG && _sgo_debug "    ${OPT_DISP}: Setting $VAR_NAME=$OPTARG."
				setvar $VAR_NAME $OPTARG
			fi
		fi

		if eval type OPT_CHECK_$OPT_NAME >/dev/null 2>&1 ; then
			$UTILS_DEBUG && _sgo_debug "    ${OPT_DISP}: Calling OPT_CHECK_$OPT_NAME \"${OPTARG-}\"."
			eval OPT_CHECK_$OPT_NAME '"${OPTARG-}"'
		fi
	done
	$UTILS_DEBUG && _sgo_debug "Finished argument vector."

	OPT_INC=$(( OPTIND - 1 ))
	$UTILS_DEBUG && _sgo_debug "Handled $OPT_INC arguments, $(( $# - OPT_INC )) arguments are left."
	return 0
}

#
#   enumerate <NVAR> <IVAR> <CMD> <ARG ...>
#
#   Evaluate <CMD> (should be single-quoted) for each <ARG ...>,
#   setting the variable named <IVAR> to the respective <ARG>,
#   and setting the variable named <NVAR> to a counter beginning
#   at 1.  Inside <CMD> you may use "break" to skip the remaining
#   arguments; in this case, <NVAR> and <IVAR> keep their last
#   values.  Example:
#
#   enumerate NUM ARG 'if match "$ARG" "$PATTERN"; then break; fi' "$@"
#   echo "Found argument \"$ARG\" at position $NUM."
#

enumerate ()
{
	local __NVAR="$1" __IVAR="$2" __CMD="$3"
	local __i
	shift 3

	setvar "${__NVAR}" 1
	for __i in "$@"; do
		setvar "${__IVAR}" "${__i}"
		eval "${__CMD}"
		let ${__NVAR} += 1
	done
}

#
#   repeat [<NVAR>] <COUNT> <CMD ...>
#
#   Execute <CMD ...> <COUNT> times.  If <NVAR> is given (must begin
#   with an alphabetic character), it is set to the current counter,
#   beginning at 1.
#

repeat ()
{
	local __NVAR

	if match "${1-}" '[A-Za-z]*'; then
		__NVAR="$1"
		shift
	else
		local __N
		__NVAR="__N"
	fi
	local __COUNT="${1:-0}"
	shift

	if $(( $# == 0 )); then
		DEBUG_repeat () { eval echo "${__NVAR} = \$${__NVAR}"; }
		set -- DEBUG_repeat
	fi

	setvar "${__NVAR}" 1
	while eval "test \$${__NVAR} -le \$__COUNT"; do
		"$@"
		eval "${__NVAR}=\$(( ${__NVAR} + 1 ))"
	done
}

#
#   Some variables and functions to support colorized output.
#
#   NOTE:  Most people use terminals with a black background.
#          The below settings will work fine with that by default.
#          HOWEVER, if you prefer to use terminals with a white
#          background, set "BG_WHITE=true" in your environment.
#          That will cause darker variants of the colors to be
#          used that provide a better contrast.
#

if ${BG_WHITE:-false}; then
	#   Some of the standard set of 16 ANSI colors are too bright for a
	#   white background, and some are too dark for a black background.
	#   Use variations from the 256-color palette for better readability.
	ATTR_RED="${ESC}[31m"
	# ATTR_GREEN="${ESC}[32m"
	ATTR_GREEN="${ESC}[38;5;28m"
	# ATTR_YELLOW="${ESC}[33m"
	ATTR_YELLOW="${ESC}[38;5;178m"
	ATTR_BLUE="${ESC}[34m"
	ATTR_PURPLE="${ESC}[35m"
	# ATTR_CYAN="${ESC}[36m"
	ATTR_CYAN="${ESC}[38;5;37m"
	ATTR_GREY="${ESC}[90m"
	ATTR_ORANGE="${ESC}[38;5;130m"	# actually brown, but better contrast.

	ATTR_BG_PURPLE="${ESC}[105m"
else
	# ATTR_RED="${ESC}[91m"
	ATTR_RED="${ESC}[38;5;203m"
	ATTR_GREEN="${ESC}[92m"
	ATTR_YELLOW="${ESC}[93m"
	# ATTR_BLUE="${ESC}[94m"
	ATTR_BLUE="${ESC}[38;5;105m"
	ATTR_PURPLE="${ESC}[95m"
	ATTR_CYAN="${ESC}[96m"
	ATTR_GREY="${ESC}[90m"
	ATTR_ORANGE="${ESC}[38;5;208m"

	ATTR_BG_PURPLE="${ESC}[45m"
fi
ATTR_OFF="${ESC}[m"	# Switch all colors and attributes to normal.
BOLD_ON="${ESC}[1m"
BOLD_OFF="${ESC}[22m"
ITAL_ON="${ESC}[3m"
ITAL_OFF="${ESC}[23m"
ULINE_ON="${ESC}[4m"
ULINE_OFF="${ESC}[24m"
REV_ON="${ESC}[7m"
REV_OFF="${ESC}[27m"

#
#   _attr_echo <ATTR> [-cdfr] [-e | -n] [...] [>&2]
#
#   This is an INTERNAL function used by other functions below.
#

_attr_echo ()
{
	local ECHO_OPT="" KNOWN_OPTS="bcdefinru" LINE
	local FORCE=false DOUBLE=false BE_CAT=false DO_REV
	local ATTR="$1"
	shift

	while match "${1-}" "-[-$KNOWN_OPTS]*"; do
		if eq "$1" "--"; then
			shift
			break
		elif match "$1" "-*[!$KNOWN_OPTS]*"; then
			#   Historic echo(1) behaviour:  Unsupported
			#   options are treated as regular arguments.
			break
		fi
		contains "$1" "b" && ATTR="${ATTR}${BOLD_ON}"
		contains "$1" "c" && BE_CAT=true
		contains "$1" "d" && DOUBLE=true
		contains "$1" "e" && ECHO_OPT="$1"	# Incompatible with -c.
		contains "$1" "f" && FORCE=true
		contains "$1" "i" && ATTR="${ATTR}${ITAL_ON}"
		contains "$1" "n" && ECHO_OPT="$1"	# Incompatible with -d and -c.
		contains "$1" "r" && ATTR="${ATTR}${REV_ON}"
		contains "$1" "u" && ATTR="${ATTR}${ULINE_ON}"
		shift
	done
	if [ ! -t 1 ] && ! $FORCE; then
		if $BE_CAT; then
			cat -- "$@"
		else
			echo $ECHO_OPT "$@"
		fi
		return
	fi
	if $BE_CAT; then
		OLD_IFS="$IFS"
		IFS=""
		cat -- "$@" \
		| while read -r LINE; do
			if $DOUBLE; then
				echo $ECHO_OPT "${ESC}#3${ATTR}$LINE${ATTR_OFF}"
				echo $ECHO_OPT "${ESC}#4${ATTR}$LINE${ATTR_OFF}"
			else
				echo $ECHO_OPT "${ATTR}$LINE${ATTR_OFF}"
			fi
		done
		IFS="$OLD_IFS"
	elif $DOUBLE; then
		echo $ECHO_OPT "${ESC}#3${ATTR}$*${ATTR_OFF}"
		echo $ECHO_OPT "${ESC}#4${ATTR}$*${ATTR_OFF}"
	else
		echo $ECHO_OPT "${ATTR}$*${ATTR_OFF}"
	fi
}

#
#   Various functions for output using attributes (bold, underline, ...)
#   or colors (red, green, ...).  They all have the same syntax:
#
#   <FUNC> [-dfr] [-e | -n] [--] [<TEXT> ...] [>&2]
#   <FUNC> -c [-dfr] [--] [<FILE> ...] [>&2]
#
#   In the first synopsis, the function behaves like echo(1), including
#   the options -e or -n that are passed as-is to echo (sh(1) builtin).
#   In the second synopsis (using -c), the function behaves like cat(1).
#   Attributes or colors are only used if the output stream is a TTY,
#   unless the -f option (force) is used.
#   Options:
#      -d   Print a double-sized line (does not work with -n).  Not all
#           terminals support this.  When used with xterm, requires at
#           least xterm-356 and Xft fonts (not bitmap fonts).
#      -c   Behave like cat(1) rather than echo(1), i.e. print lines
#           from the specified file(s) using the respective color, or
#           lines from stdin if no files are specified.
#      -e   Passed to echo: support escape codes.  Note that this is
#           not portable.  Using the $'...' syntax might be better.
#      -f   Enforce bold even if output is not to a terminal.  This is
#           useful when used in backticks like this:
#               echo "You must `bold -f not` do that!"
#           Note that you can do the same with the color() function:
#               color "You must <B>not<O> do that!"
#      -n   Passed to echo(1): suppress newline.
#      -r   Use reverse output, i.e. swap foreground and background
#           colors.
#

bold ()      { _attr_echo "$BOLD_ON" "$@"; }
italics ()   { _attr_echo "$ITAL_ON" "$@"; }
reverse ()   { _attr_echo "$REV_ON" "$@"; }
underline () { _attr_echo "$ULINE_ON" "$@"; }

red ()     { _attr_echo "$ATTR_RED" "$@"; }
green ()   { _attr_echo "$ATTR_GREEN" "$@"; }
yellow ()  { _attr_echo "$ATTR_YELLOW" "$@"; }
blue ()    { _attr_echo "$ATTR_BLUE" "$@"; }
purple ()  { _attr_echo "$ATTR_PURPLE" "$@"; }
cyan ()    { _attr_echo "$ATTR_CYAN" "$@"; }
magenta () { _attr_echo "$ATTR_PURPLE" "$@"; }	# Just an alias for purple().
grey ()    { _attr_echo "$ATTR_GREY" "$@"; }
orange ()  { _attr_echo "$ATTR_ORANGE" "$@"; }

bg_purple ()  { _attr_echo "$ATTR_BG_PURPLE" "$@"; }

#   Double-sized line, supported with Xft fonts since xterm-356.
#   See bold() for other options.

double ()  { _attr_echo "" -d "$@"; }

#
#   Same as above (including options), but allows colorized output
#   using a simple markup syntax.
#   Example:
#       color "Some words are <r>red<o> and some are <g>green<o>."
#   If you need to actually print letters surrounded by <...>,
#   you can insert an empty pair of angle brackets, for example:
#       color "Specify <<>r> to change to <r>red<o> output."
#   will print the line:
#       Specify <r> to change to red output.
#   where only the word "red" is output in red color.
#
#   Supports the echo(1) options -e and -n.
#   Supports these additional options:
#       -c    Behave like cat(1).  Cannot be used with -e / -n.
#       -d    Produce double-height lines.  Cannot be used with -n.
#             Requires xterm-356 or newer and Xft fonts.
#       -f    Force colorized output, even if stdout is not a TTY.
#   Supports these color codes (must be lower case):
#       <r> red      <g> green     <y> yellow    <b> blue
#       <p> purple   <m> magenta   <c> cyan      <a> orange
#       <o> off
#   Supports these monochrome codes (must be upper case):
#       <B> bold     <I> italics   <R> reverse   <U> underline
#

_COLOR_SED_CMD=\
"s/<r>/$ATTR_RED/g;"\
"s/<g>/$ATTR_GREEN/g;"\
"s/<y>/$ATTR_YELLOW/g;"\
"s/<b>/$ATTR_BLUE/g;"\
"s/<[pm]>/$ATTR_PURPLE/g;"\
"s/<m>/$ATTR_PURPLE/g;"\
"s/<c>/$ATTR_CYAN/g;"\
"s/<a>/$ATTR_ORANGE/g;"\
"s/<[oO]>/$ATTR_OFF/g;"\
"s/<B>/$BOLD_ON/g;"\
"s/<I>/$ITAL_ON/g;"\
"s/<R>/$REV_ON/g;"\
"s/<U>/$ULINE_ON/g;"\
"s/<[A-Za-z]*>//g;"

color ()
{
	local OPT="" DOUBLE=false FORCE=false BE_CAT=false LINE

	while match "${1-}" '-[-cedfn]'; do
		case "$1" in
			'--')	shift; break ;;
			'-c')	BE_CAT=true ;;
			'-d')	DOUBLE=true ;;
			'-e')	OPT="$1" ;;	# Incompatible with -c.
			'-f')	FORCE=true ;;
			'-n')	OPT="$1" ;;	# Incompatible with -c and -d.
		esac
		shift
	done
	if [ ! -t 1 ] && ! $FORCE; then
		if $BE_CAT; then
			cat -- "$@"
		else
			echo $OPT "$@"
		fi \
		| sed 's/<[A-Za-z]*>//g'
		return
	fi
	if $BE_CAT; then
		OLD_IFS="$IFS"
		IFS=""
		cat -- "$@" \
		| while read -r LINE; do
			if $DOUBLE; then
				echo $OPT "${ESC}#3$LINE"
				echo $OPT "${ESC}#4$LINE"
			else
				echo $OPT "$LINE"
			fi
		done
		IFS="$OLD_IFS"
	elif $DOUBLE; then
		echo $OPT "${ESC}#3$*${ATTR_OFF}"
		echo $OPT "${ESC}#4$*${ATTR_OFF}"
	else
		# echo $OPT $(echo "$@<o>" | sed "$_COLOR_SED_CMD")
		echo $OPT "$@${ATTR_OFF}"
	fi \
	| sed "$_COLOR_SED_CMD"
}

#
#   The following functions can be used to display progress information
#   if a certain operation takes a long time.  There are two ways to use
#   this function: verbose and simple.
#
#   VERBOSE USAGE:
#
#       progress_start <name> <min> <max>
#           <name> must be a valid identifier (alphanumeric + underscore).
#           <min> and <max> must be integers >= 0 and <min>  <  <max>.
#       --> Does not return anything.
#
#       v=$(progress_value <name> [<current>])
#           <name> must be the same as given to progress_start().
#           <current> must be between <min> and <max> (inclusive),
#                     if missing, <max> is assumed, so you can easily
#                     get the total runtime when your job is finished.
#       --> Returns four integers seperated by spaces:
#               <dur> <rest> <total> <perc>
#           <dur> is the duration so far in seconds.
#           <rest> is the estimated duration of the rest of the job.
#           <total> is the estimated total duration of the job.
#                   Note: <total> = <dur> + <rest>, modulo rounding errors.
#           <perc> is a percent value (integer).
#       Note that you can use the S_to_HMS() function to convert
#       a number in seconds to HH:MM:SS format.
#
#   SIMPLE USAGE:  If you only want to display the total duration so far (or
#                  even only at the end), but you're *not* interested in ETA
#                  or percent values, there's a simpler usage:
#
#       progress_start <name>
#           Like above, but the <min> and <max> values are omitted.
#       v=$(progress_value <name>)
#           Like above, but the <current> value is omitted, and the return
#           value is a single integer number that is the duration so far
#           in seconds (can be fed to the S_to_HMS() function).
#
#   IMPORTANT:  Don't call progress_value() too often because of the
#               overhead calling the external date(1) binary.
#
#   Example (verbose usage):
#
#       progress_start FOO 0 8000
#       i=0
#       while [ $i -le 8000 ]; do
#           ...
#           set -- $(progress_value FOO $i)
#           DUR=$1; REST=$2; TOTAL=$3; PERC=$4
#           #  ==== OR: ====
#           read DUR REST TOTAL PERC <<-EOT
#               $(progress_value FOO $i)
#           EOT
#           echo "$i of 8000 done ($PERC %), $REST seconds to go."
#           ...
#       done
#       DUR=$(progress_value FOO)
#       echo "Done! Duration: $(S_to_HMS ${DUR%% *})"
#
#   Example (simple usage):
#
#       progress_start FOO
#       ...
#       echo "Done! Duration: $(S_to_HMS $(progress_value FOO) )"
#

progress_start ()
{
	setvar PROGRESS_${1}_START $(date +'%s')
	if $(( $# != 1 )); then
		setvar PROGRESS_${1}_SIMPLE false
		setvar PROGRESS_${1}_MIN "$2"
		setvar PROGRESS_${1}_MAX "$3"
	else
		setvar PROGRESS_${1}_SIMPLE true
	fi
}

progress_value ()
{
	local NOW=$(date +'%s')
	local START MIN MAX CURRENT
	local DUR REST TOTAL PERC

	eval START=\$PROGRESS_${1}_START
	if $(( NOW <= START )); then
		echo "0 0 0 0"
		return
	fi
	let DUR = NOW - START

	if eval \$PROGRESS_${1}_SIMPLE; then
		echo "$DUR"
		return
	fi

	eval MIN=\$PROGRESS_${1}_MIN
	eval MAX=\$PROGRESS_${1}_MAX
	if have "$2"; then
		CURRENT="$2"
	else
		CURRENT=$MAX
	fi
	if $(( MIN >= MAX || CURRENT <= MIN )); then
		echo "0 0 0 0"
		return
	fi
	if $(( CURRENT >= MAX )); then
		echo "$DUR 0 $DUR 100"
		return
	fi
	let 'REST = (DUR * (MAX - CURRENT)) / (CURRENT - MIN)'
	let 'TOTAL = (DUR * (MAX - MIN)) / (CURRENT - MIN)'
	let 'PERC = (100 * (CURRENT - MIN)) / (MAX - MIN)'
	echo "$DUR $REST $TOTAL $PERC"
}

#   Parse a time in colon-format (H:M:S or M:S or just S), optionally
#   followed by a decimal fraction.
#   Returns the number of seconds (integer value).  If the HMS input
#   had a fraction, it is retained as-is, so "1:30.440" is converted
#   to "90.440", for example.
#   If the input is invalid, returns an empty string and return code 1.
#   The part before the first colon may be > 59, so "90:00" is valid
#   and means the same as "1:30:00" (return value is 5400).  All other
#   parts must be between 00 and 59.

HMS_to_S ()
{
	local HMS="${1%.*}" FRAC="${1#*.}"
	local SEC=0
	local FIRST=true
	local PART

	if eq "$HMS" "$FRAC"; then
		FRAC=""
	else
		FRAC=".$FRAC"
	fi
	if not empty "${2-}"; then
		#   Undocumented:  milliseconds in $2
		FRAC=$(awk 'BEGIN{printf "%.3f", '"$2"'}')
		FRAC=".${FRAC#*.}"
		# TODO: What if the value is >= 1.000?
	fi
	while not empty "$HMS"; do
		PART=${HMS%%:*}
		HMS=${HMS#$PART}
		HMS=${HMS#:}
		if ! isdigit "$PART"; then
			return 1
		elif not $FIRST && not match "$PART" '[0-5][0-9]'; then
			return 1
		fi
		while match "$PART" '0?*'; do
			PART=${PART#0}
		done
		SEC=$(( SEC * 60 + PART ))
		FIRST=false
	done
	echo ${SEC}${FRAC}
}

#   Convert a time given in seconds to a string in H:M:S format.
#   If the seconds value has a decimal fraction, it is retained as-is,
#   so "90.440" is converted to "0:01:30.440", for example.

S_to_HMS ()
{
	local S="${1%.*}" FRAC="${1#*.}"
	local H M

	if eq "$S" "$FRAC"; then
		FRAC=""
	else
		FRAC=".$FRAC"
	fi
	if not empty "${2-}"; then
		#   Undocumented:  milliseconds in $2
		FRAC=$(awk 'BEGIN{printf "%.3f", '"$2"'}')
		FRAC=".${FRAC#*.}"
		# TODO: What if the value is >= 1.000?
	fi
	M=$(( S / 60 ))
	S=$(( S - M * 60 ))
	H=$(( M / 60 ))
	M=$(( M - H * 60 ))
	printf '%d:%02d:%02d%s\n' $H $M $S "$FRAC"
}

#
#   Format a decimal number with thousands separators.
#   The number may begin with spaces and a sign character.
#   Decimal points are NOT supported.
#
#   NOTE:  If the number might be negative, be sure to use "--" for
#          terminating option processing!
#   Options:
#      -m <wid>    Specify minimum width.  The number is padded with
#                  spaces on the left.  Default is 0 (no padding).
#                  NOTE that the sign and separator characters are
#                  included in width calculation.
#      -s <sep>    Specify separator character.  Default is "·" (note
#                  that this is a Unicode UTF-8 character).
#                  NOTE that the width calculation (option -m) only works
#                  if the separator character has width 1 on the screen.
#

th_sep ()
{
	local MIN_WIDTH SEP OPT_ERR OPT_INC
	local NUM WIDTH FORM SIG REST CHAR

	std_getopts -ln "m:{MIN_WIDTH=0} s:{SEP=·}" "$@" || Err "[utils.sh] th_sep(): $OPT_ERR"
	shift $OPT_INC
	NUM="$1"

	SIG=""
	while [ "${#NUM}" -gt 1 ]; do
		REST="${NUM#?}"
		CHAR="${NUM%$REST}"
		case "$CHAR" in
			" ")	continue ;;
			[-+])	SIG="$CHAR"; NUM=$REST ;;
			*)	break ;;
		esac
	done

	WIDTH=$(length "${SIG}${NUM}")
	FORM=""
	while [ "${#NUM}" -gt 3 ]; do
		REST="${NUM%???}"
		FORM="${SEP}${NUM#$REST}${FORM}"
		WIDTH=$(( WIDTH + 1 ))
		NUM="$REST"
	done

	while [ $WIDTH -lt $MIN_WIDTH ]; do
		SIG=" $SIG"
		WIDTH=$(( WIDTH + 1 ))
	done

	echo "${SIG}${NUM}${FORM}"
}

#
#   The following functions handle X11 resources.
#   They aren't used often anymore nowadays, so I might move them
#   to a separate file.
#

#
#   Get and set the contents of an X11 resource (see xrdb(1)).
#

get_resource ()
{
	local RES="$1"

	/usr/local/bin/xrdb -query \
	| awk '
		BEGIN {
			res = tolower("'"$RES"'") ":"
			got = 0
		}
		tolower($1) == res {
			sub(/^[^:]*:[ 	]*/, "")
			print
			got = 1
		}
		END {
			if (got)
				exit (0)
			else
				exit (1)
		}
	'
}

set_resource ()
{
	local RES="$1" VAL="$2"

	echo "${RES}: $VAL" | /usr/local/bin/xrdb -merge
}

#
#   The following functions add and remove strings from
#   an X11 resource (see xrdb(1)) that contains a list.
#   Typically this is used to add window names to olwm/olvwm
#   resources like MinimalDecor or NoDecor.  Note that the
#   single strings of the list must NOT contain whitespace
#   or special characters.
#

add_resource_string ()
{
	local RES="$1" STR="$2"

	LIST=$(get_resource "$RES")

	if $UTILS_DEBUG; then
		echo "Adding \"$STR\" to resource ${RES}:" >&2
		echo "OLD: ${RES}: $LIST" >&2
		echo "NEW: ${RES}: $LIST $STR" >&2
	fi

	set_resource "$RES" "$LIST $STR"
}

remove_resource_string ()
{
	local RES="$1" STR="$2"

	LIST=$(get_resource "$RES")

	NEW_LIST=""
	for S in $LIST; do
		if [ "x$S" != "x$STR" ]; then
			NEW_LIST="$NEW_LIST $S"
		fi
	done

	if $UTILS_DEBUG; then
		echo "Removing \"$STR\" from resource ${RES}:" >&2
		echo "OLD: ${RES}: $LIST" >&2
		echo "NEW: ${RES}:$NEW_LIST" >&2
	fi

	set_resource "$RES" "${NEW_LIST# }"
}

#
#   Wait for the user to select something with the mouse
#   (e.g. inside an xterm).  autocutsel should be running,
#   so X11 selections and cutbuffers are synchronized.
#
#   If the -c option is given, don't wait, but return the
#   current selection immediately.
#

get_selection ()
{
	local BUF

	if no "${DISPLAY-}"; then
		echo "get_selection(): DISPLAY is not set!" >&2
		return 1
	fi

	if eq "${1-}" '-c'; then
		cutsel cut
		return 0
	fi

	if $UTILS_DEBUG; then
		echo "Clearing selection." >&2
	fi
	cutsel cut ''
	while :; do
		#   Wait until something is selected.
		sleep 1
		BUF=$(cutsel cut)
		if have "$BUF"; then
			if $UTILS_DEBUG; then
				echo "New selection: \"$BUF\"" >&2
			fi
			printf '%s\n' "$BUF"
			return
		fi
	done
}

#
#   cp_stat <SOURCE> <TARGET> [...]
#
#   Copies the file status from <SOURCE> to one or more <TARGET>s:
#    - atime and mtime
#    - permissions (set-id bits are NOT copied)
#    - owner (only if run as root)
#    - group (only if run as root, or the user is a member of the group)
#
#   If <TARGET> does not exist yet, it is created with size 0.
#   If <TARGET> already exists, its contents are not modified.
#

cp_stat ()
{
	local SOURCE="$1"
	shift
	local TARGET USR GRP PERM

	#   Unfortunately, FreeBSD's /bin/sh does not support $UID or $EUID.
	#   In order to save id(1) calls, we cache the result in a global
	#   variable.
	if no "${__MY_EUID:-}"; then
		__MY_EUID=$(id -u)
	fi

	if $(( __MY_EUID == 0 )); then
		USR=$(getowner "$SOURCE")
	fi
	GRP=$(getgroup "$SOURCE")
	PERM=$(getperm "$SOURCE")
	PERM=0${PERM#?}		# Remove set-id bits.

	for TARGET in "$@"; do
		#   Copy atime and mtime:
		touch -r "$SOURCE" -- "$TARGET"
		#   Copy permissions:
		chmod $PERM "$TARGET"
		if $(( __MY_EUID == 0 )); then
			#    Copy owner and group:
			chown "${USR}:${GRP}" "$TARGET"
		elif neq "$GRP" "$(getgroup "$TARGET")"; then
			#    Copy group if possible:
			if ! chgrp -- "$GRP" "$TARGET" 2>/dev/null; then
				Warn "Could not set group \"$GRP\": $TARGET"
			fi
		fi
	done
}

#
#   Arithmetic functions
#

#
#   round_down <VALUE> <MULT>
#   round_up   <VALUE> <MULT>
#
#   Round <VALUE> down / up to a multiple of <MULT>.
#
#   <VALUE> may be negative, rounding towards zero for round_down()
#   and rounding towards +/-infinity for round_up().
#   <MULT> must be > 0.
#

round_down()
{
	local VAL="$1" local MULT="$2"

	echo $(( ( VAL / MULT ) * MULT ))
}

round_up()
{
	local VAL="$1" local MULT="$2"

	if $(( VAL < 0 )); then
		let VAL -= MULT - 1
	else
		let VAL += MULT - 1
	fi
	echo $(( ( VAL / MULT ) * MULT ))
}

#
#   within_percent <P> <VAL_A> <VAL_B>
#
#   Returns success if <VAL_B> is within <P> percent of <VAL_A>.
#
#   All parameters must be integers, and <P> must be non-negative.
#   <P> == 0 is allowed (returning 0 if <VAL_A> == <VAL_B>).
#   <VAL_A> and/or <VAL_B> may be negative.
#

within_percent ()
{
	#   VAL_A and VAL_B are scaled by a factor of 100, in order
	#   to achieve sufficient precision.
	local PERCENT="$1" VAL_A="${2}00" VAL_B="${3}00"
	local DIFF MAX_DIFF

	DIFF=$(( VAL_A - VAL_B ))
	MAX_DIFF=$(( (VAL_A * PERCENT ) / 100 ))
	if $(( ${DIFF#-} > ${MAX_DIFF#-} )); then
		return 1
	else
		return 0
	fi
}

#-- 
