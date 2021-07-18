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

# upvar: data
load_data () {
    data=()

    [[ -e $1 ]] || bye "${1@Q} doesnt exist."
    [[ -f $1 ]] || bye "${1@Q} is not a regular file."
    [[ -r $1 ]] || bye "Cant read ${1@Q}"

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
    [[ -w $1 ]] || bye "Cant write ${1@Q}"

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
    elif [[ $1 =~ ^(..)$ ]]; then
        y=$YEAR
        m=$MONTH
        d=${BASH_REMATCH[1]}
    else
        bye "Invalid date ${1@Q}"
    fi

    is_num "$y" || bye "Invalid year in ${1@Q}"
    is_num "$m" || bye "Invalid month in ${1@Q}"
    is_num "$d" || bye "Invalid day in ${1@Q}"

    date -d "$y-$m-$d" &>/dev/null || bye "Invalid date ${1@Q}"

    result="$y$m$d"
}

# upvar: header cal
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

        d=${date:6}
        d=${d/0/_}

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

main () {
    local -A marks=(
        [green]=$'\e[42;30m'
        [red]=$'\e[41;30m'
        [yellow]=$'\e[43;30m'
    )

    local mode=default
    local year=$YEAR
    local data_file=~/.config/cal-hl

    [[ -e $data_file ]] ||
        install -D /dev/stdin "$data_file" <<< '' 2>/dev/null ||
        bye "Cant create default data file ${data_file@Q}"

    while getopts ':d:m:y:u' opt; do
        case $opt in
            d)
                data_file=$OPTARG
                ;;
            m)
                mode=mark

                [[ -v marks[$OPTARG] ]] || bye "Unknown mark ${OPTARG@Q}"
                mark=$OPTARG
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
            :)
                bye "Option ${OPTARG@Q} requires value."
                ;;
            \?)
                bye "Unknown option ${OPTARG@Q}"
                ;;
        esac
    done

    shift $((OPTIND-1))

    local -A data
    load_data "$data_file"

    case $mode in
        mark)
            (($# > 0)) || set -- "$DAY" # By default operate on
                                        # current date.
            local update=n date

            for date; do
                parse_date "$date"

                [[ -v data[$result] && ${data[$result]} == "$mark" ]] || {
                    update=y
                    data[$result]=$mark
                }
            done

            [[ $update == n ]] || save_data "$data_file"
            ;;

        unmark)
            (($# > 0)) || set -- "$DAY" # By default operate on
                                        # current date.
            local update=n date

            for date; do
                parse_date "$date"

                if [[ -v data[$result] ]]; then
                    update=y
                    unset -v "data[$result]"
                fi
            done

            [[ $update == n ]] || save_data "$data_file"
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
}

(return 0 2>/dev/null) || main "$@"
