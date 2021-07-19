#!/usr/bin/env bash

# Copyright (c) 2021 https://github.com/slowpeek
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation files
# (the "Software"), to deal in the Software without restriction,
# including without limitation the rights to use, copy, modify, merge,
# publish, distribute, sublicense, and/or sell copies of the Software,
# and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
# BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
# ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Homepage: https://github.com/slowpeek/cal-hl

set -eu

_ () {
    printf -v DATE '%(%Y-%m-%d)T'
    IFS=- read -r YEAR MONTH DAY <<< "$DATE"
}; _; unset -f _

bye () {
    IFS=' '

    {
        local lvl=${#FUNCNAME[@]} lineno func file

        # Only print not empty messages.
        if (($# > 0)); then
            local prefix=${BYE_PREFIX:-}

            if [[ $prefix == auto ]]; then
                read -r lineno func file < <(caller 0)
                prefix="$file:$lineno"
                ((lvl <= 2)) || prefix+=" $func"
            fi

            [[ -z $prefix ]] || prefix="[$prefix] "

            printf "%s%s\n" "$prefix" "$*"
        fi

        if [[ ${BYE_VERBOSE:-} == y ]] && ((lvl > 2)); then
            local s n=0 stack=()
            while s=$(caller "$n"); do
                read -r lineno func file <<< "$s"
                ((++n))
                stack+=("$file:$lineno $func")
            done

            unset -v 'stack[-1]'

            echo -e '\nCall stack:'
            printf '%s\n' "${stack[@]}"
        fi
    } >&2

    exit "${BYE_EXIT:-1}"
}

is_num () {
    [[ $1 == +([[:digit:]]) ]]
}

# args: file required
# upvar: data marks
load_data () {
    data=()

    if [[ ! -e $1 ]]; then
        [[ $2 == n ]] || bye "${1@Q} doesnt exist."
        return
    fi

    [[ -f $1 ]] || bye "${1@Q} is not a regular file."
    [[ -r $1 ]] || bye "${1@Q} is not readable."

    local line date mark

    while read -r line; do
        [[ -n $line ]] || continue # Skip empty lines.

        read -r date mark <<< "$line"

        [[ -v marks[$mark] ]] || bye "Unknown mark ${mark@Q} in ${1@Q}"
        data[$date]=$mark
    done < "$1"
}

# upvar: data
save_data () {
    if [[ -e $1 ]]; then
        [[ -w $1 ]] || bye "${1@Q} is not writable."
    else
        # Try create $1
        : 2>/dev/null >"$1" || bye "Could not create ${1@Q}"
    fi

    paste <(printf '%s\n' "${!data[@]}") <(printf '%s\n' "${data[@]}") |
        sort > "$1"
}

# upvar: result
parse_date () {
    local y m d

    if [[ $1 =~ ^(20..)-?(..)-?(..)$ ]]; then
        y=${BASH_REMATCH[1]}
        m=${BASH_REMATCH[2]}
        d=${BASH_REMATCH[3]}
    elif [[ $1 =~ ^(..)-?(..)$ ]]; then
        y=$YEAR
        m=${BASH_REMATCH[1]}
        d=${BASH_REMATCH[2]}
    elif [[ $1 =~ ^(..?)$ ]]; then
        y=$YEAR
        m=$MONTH
        d=${BASH_REMATCH[1]}
        [[ $d == ?? ]] || d=0$d
    else
        bye "Invalid date ${1@Q}"
    fi

    is_num "$y" || bye "Invalid year in ${1@Q}"
    is_num "$m" || bye "Invalid month in ${1@Q}"
    is_num "$d" || bye "Invalid day in ${1@Q}"

    date -d "$y-$m-$d" &>/dev/null || bye "Invalid date ${1@Q}"

    result="$y$m$d"
}

# upvar: header cal year
get_cal () {
    {
        read -r header

        cal=()
        local m i line

        for ((m=0; m<12; m+=3)); do
            for ((i=0; i<8; i++)); do
                read -r line

                cal[m]+=${line::21}-
                cal[m+1]+=${line:22:21}-
                cal[m+2]+=${line:44:21}-
            done

            read -r || true
        done
    } < <(ncal -bhM "$year" | tr ' ' _)
}

# upvar: data year cal marks
hl_cal () {
    local date m d
    for date in "${!data[@]}"; do
        [[ ${date::4} == "$year" ]] || continue

        m=${date:4:2}
        m=${m#0}

        d=${date:6:2}
        d=${d#0}
        ((d > 9)) || d=_$d

        cal[m-1]=${cal[m-1]/${d}_/${marks[${data[$date]}]}${d}$'\e(B\e[m'_}
    done
}

# upvar: cal
print_month () {
    local m
    for m; do
        echo "${cal[$m]//-/$'_\n'}"
    done
}

# upvar: marks
mark () {
    marks[${1,,}]=$2
}

# upvar: aliases
alias () {
    aliases[${1,,}]=${2,,}
}

# upvar: marks aliases result
resolve () {
    if [[ -v marks[$1] ]]; then
        result=$1
        return
    fi

    [[ -v aliases[$1] ]] ||
        bye "${1@Q} is not a mark or an alias."

    local name=$1
    while [[ -v aliases[$name] ]]; do
        name=${aliases[$name]}
    done

    [[ -v marks[$name] ]] ||
        bye "Stuck at ${name@Q} while resolving alias ${1@Q}"

    result=$name
}

default_config () {
    mark c0 $'\e[30;7m'
    mark c1 $'\e[31;7m'
    mark c2 $'\e[32;7m'
    mark c3 $'\e[33;7m'
    mark c4 $'\e[34;7m'
    mark c5 $'\e[35;7m'
    mark c6 $'\e[36;7m'
    mark c7 $'\e[37;7m'

    alias black c0
    alias red c1
    alias green c2
    alias yellow c3
    alias blue c4
    alias magenta c5
    alias cyan c6
    alias white c7
}

usage () {
    cat <<'EOF'
USAGE

    cal-hl -h | -c
    cal-hl [-d <file>] [-y <year>]
    cal-hl [-d <file>] <-s <mark|alias> | -u> [<date> <date> ...]

Without any options, show calendar for the current year with marks
from ~/.config/cal-hl. Use '-y' option to pick another year and '-d'
option to specify a custom data file.

cal-hl operates on marks and aliases. Marks are named ANSI sequences
used to colorize output. Default marks are 'c0' to 'c7' corresponding
to ANSI colors 0 to 7. An alias is an alternative name for a mark or
another alias. Default aliases provide user friendly names for default
marks e.g. 'red' resolves to 'c1'. Even though the default aliases are
self-descriptive, the resulting color depends on particular color
scheme used in a terminal.

Complete list of default marks and aliases:

  c0 black
  c1 red
  c2 green
  c3 yellow
  c4 blue
  c5 magenta
  c6 cyan
  c7 white

One can customize marks and aliases with ~/.config/cal-hl-rc. Use '-c'
option to dump current config and see the supposed format.

Use '-s' option with some mark or alias to mark a list of dates. Such
formats for dates are accepted:

- full
    20YY-MM-DD
    20YYMMDD

- current year
    MM-DD
    MMDD

- current month
    DD
    D

Remove marks from a list of dates with '-u' option.


OPTIONS SUMMARY

-h  Show usage.
-c  Dump current config.

-d <file>
    Data file. By default ~/.config/cal-hl
-y <year>
    Year in 20YY format. By default current year.

-s <mark|alias>
    Mark a list of dates with a mark or alias.
-u  Unmark a list of dates.

In both cases above current date is assumed if the list is empty.


FILES

- default data file
    ~/.config/cal-hl

- config file
    ~/.config/cal-hl-rc

EOF
}

# upvar: marks aliases
dump_config () {
    local k

    {
        echo '# Marks'
        for k in "${!marks[@]}"; do
            printf 'mark %s %q\n' "$k" "${marks[$k]}"
        done | sort -k2,2V

        echo

        echo '# Aliases'
        for k in "${!aliases[@]}"; do
            printf 'alias %s %q\n' "$k" "${aliases[$k]}"
        done | sort -k3,3V
    } | sed 's/\E/\e/g'
}

main () {
    local -A marks=() aliases=()

    local mode=default year=$YEAR
    local data_file_default=~/.config/cal-hl
    local config_file=~/.config/cal-hl-rc

    default_config

    if [[ -f $config_file ]]; then
        [[ -r $config_file ]] || bye "${config_file@Q} is not readable."

        # shellcheck disable=SC1090
        source "$config_file"
    fi

    local data_file=$data_file_default

    while getopts ':d:s:y:uhc' opt; do
        case $opt in
            d)
                data_file=$OPTARG
                ;;
            s)
                mode=mark

                local result
                resolve "${OPTARG,,}"
                mark=$result
                ;;
            y)
                # shellcheck disable=SC2015
                is_num "$OPTARG" && [[ $OPTARG == 20?? ]] ||
                    bye "Invalid -y value."

                year=$OPTARG
                ;;
            u)
                mode=unmark
                ;;
            c)
                dump_config
                exit
                ;;
            h)
                usage
                exit
                ;;
            :)
                bye "Option ${OPTARG@Q} requires value."
                ;;
            \?)
                bye "Unknown option ${OPTARG@Q}"
                ;;
        esac
    done

    shift $((OPTIND-1))

    local required=n
    [[ $mode == mark || $data_file == "$data_file_default" ]] ||
        required=y

    local -A data
    load_data "$data_file" "$required"

    local update=n

    case $mode in
        mark)
            (($# > 0)) || set -- "$DAY" # By default operate on
                                        # current date.
            local date
            for date; do
                parse_date "$date"

                [[ -v data[$result] && ${data[$result]} == "$mark" ]] || {
                    update=y
                    data[$result]=$mark
                }
            done
            ;;

        unmark)
            (($# > 0)) || set -- "$DAY" # By default operate on
                                        # current date.
            local date
            for date; do
                parse_date "$date"

                if [[ -v data[$result] ]]; then
                    update=y
                    unset -v "data[$result]"
                fi
            done
            ;;

        default)
            local header cal
            get_cal
            hl_cal

            {
                echo "$header"
                paste -d '' \
                      <(print_month 0 3 6 9) \
                      <(print_month 1 4 7 10) \
                      <(print_month 2 5 8 11)
            } | tr _ ' '
            ;;
    esac

    [[ $update == n ]] || save_data "$data_file"
}

(return 0 2>/dev/null) || main "$@"
