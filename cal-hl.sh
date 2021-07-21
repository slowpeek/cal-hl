#!/usr/bin/env bash

# MIT license (c) 2021 https://github.com/slowpeek
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

# args: var ?val
temp () {
    [[ $1 == var ]] || local -n var=$1
    local -n old=QLD_$1

    if (($# > 1)); then
        [[ ! -v var ]] || old=$var
        var=$2
    else
        if [[ -v old ]]; then
            var=$old
            unset -v old
        else
            unset -v var
        fi
    fi
}

is_num () {
    [[ $1 == +([[:digit:]]) ]]
}

is_name () {
    [[ $1 == +([a-z0-9_]) ]]
}

# args: file required
# upvar: data marks token
load_data () {
    data=()

    if [[ ! -e $1 ]]; then
        [[ $2 == n ]] || bye "${1@Q} doesnt exist."
        return
    fi

    [[ -f $1 ]] || bye "${1@Q} is not a regular file."
    [[ -r $1 ]] || bye "${1@Q} is not readable."

    local line date mark

    {
        read -r line || return 0 # Empty file.

        [[ $line == "$token" ]] ||
            bye "${1@Q} doesnt look like a cal-hl data file."

        while read -r line; do
            read -r date mark <<< "$line"

            [[ -v marks[$mark] ]] || bye "Unknown mark ${mark@Q} in ${1@Q}"
            data[$date]=$mark
        done
    } < "$1"
}

# args: file
# upvar: data token
save_data () {
    if [[ -e $1 ]]; then
        [[ -w $1 ]] || bye "${1@Q} is not writable."
    else
        # Try create $1
        : 2>/dev/null >"$1" || bye "Could not create ${1@Q}"
    fi

    {
        echo "$token"
        paste <(printf '%s\n' "${!data[@]}") <(printf '%s\n' "${data[@]}") |
            sort
    } >"$1"
}

# args: raw_date
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

    result=$y$m$d
}

# upvar: cal year week_start
get_cal () {
    _header () {
        local s=${line:$1:20}
        local pad=${s%%[^.]*}
        # Month to the left, YYYY to the right.
        s=${s#$pad}${pad:4}YYYY
        # Underline space between month and year.
        cal[m+$2]=${s//./_}.-
    }

    local opts=(-bh)
    [[ $week_start == auto ]] || opts+=(-"$week_start")
    opts+=("$year")

    {
        cal=()
        local m i line

        for ((m=0; m<12; m+=3)); do
            read -r line

            _header 0 0
            _header 22 1
            _header 44 2

            for ((i=0; i<7; i++)); do
                read -r line

                cal[m]+=${line::21}-
                cal[m+1]+=${line:22:21}-
                cal[m+2]+=${line:44:21}-
            done

            read -r || true
        done
    } < <(ncal "${opts[@]}" | sed 1d | tr ' ' .)

    unset -f _header
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
        ((d > 9)) || d=.$d

        cal[m-1]=${cal[m-1]/${d}./${marks[${data[$date]}]}${d}$'\e(B\e[m'.}
    done
}

# args: list of {0..11}
# upvar: cal
print_month () {
    local m
    for m; do
        echo "${cal[$m]//-/$'.\n'}"
    done
}

# args: name ansiseq
# upvar: marks
mark () {
    (($# > 1)) || bye "'mark' command requires two args."
    [[ -n $1 ]] || bye 'Empty mark name.'

    local name=${1,,}

    is_name "$name" ||
        bye "Invalid mark name ${name@Q}. Only latin letters, numbers" \
            "and underscore are allowed."

    marks[$name]=$2
}

# args: src dst
# upvar: aliases
alias () {
    (($# > 1)) || bye "'alias' command requires two args."
    local src=${1,,} dst=${2,,}

    [[ -n $src ]] || bye 'Empty alias name.'
    [[ -n $dst ]] || bye "Empty target name for alias ${src@Q}"

    # shellcheck disable=SC2015
    is_name "$src" && is_name "$dst" ||
            bye "Invalid name in alias ${src@Q} -> ${dst@Q}. Only latin" \
                "letters, numbers and underscore are allowed."

    [[ ! -v marks[$src] ]] ||
        bye "Alias ${src@Q} has the same name as a mark."

    [[ ! $src == "$dst" ]] || bye "Alias ${src@Q} points to itself."

    if [[ -v marks[$dst] ]]; then
        aliases[$src]=$dst
        return
    fi

    [[ -v aliases[$dst] ]] ||
        bye "Alias ${src@Q} points to an unknown name ${dst@Q}"

    local -A seen=([$src]=t [$dst]=t)
    local el=${aliases[$dst]}

    while true; do
        if [[ -v marks[$el] ]]; then
            aliases[$src]=$dst
            return
        fi

        [[ ! -v seen[$el] ]] ||
            bye "Alias ${src@Q} -> ${dst@Q} results in a cycle."

        seen[$el]=t
        el=${aliases[$el]}
    done
}

# args: raw_name
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

    result=$name
}

default_config () {
    mark c0 $'\e[30m'
    mark c1 $'\e[31m'
    mark c2 $'\e[32m'
    mark c3 $'\e[33m'
    mark c4 $'\e[34m'
    mark c5 $'\e[35m'
    mark c6 $'\e[36m'
    mark c7 $'\e[37m'

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
    cal-hl [-f <file>] [-M|-S] [-y <year>]
    cal-hl [-f <file>] <-s <mark|alias> | -u> [<date> <date> ...]

Without any options, show calendar for the current year with marks
from ~/.config/cal-hl. Use '-y' option to pick another year and '-f'
option to specify a custom data file. Week start by default is derived
from the current locale. You can override that with '-M' for Monday
and '-S' for Sunday.

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

You can customize marks and aliases with ~/.config/cal-hl-rc. Use '-c'
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

Remove marks for a list of dates with '-u' option.


OPTIONS SUMMARY

-h  Show usage.
-c  Dump current config.

-f <file>
    Data file. By default ~/.config/cal-hl
-y <year>
    Year in 20YY format. By default current year.
-M  Week start is Monday.
-S  Week start is Sunday.

-s <mark|alias>
    Mark a list of dates with a mark or alias.
-u  Unmark a list of dates.

In both cases above the current date is assumed if the list is empty.


FILES

- default data file
    ~/.config/cal-hl

- config file
    ~/.config/cal-hl-rc

EOF
}

# upvar: marks aliases
dump_config () {
    local k filter=cat

    # Only show the first 3 cols if not on terminal.
    [[ $(readlink /proc/$$/fd/1) == /dev/@(tty|pts)* ]] || filter='cut -f1-3'

    {
        echo '# Marks'
        for k in "${!marks[@]}"; do
            printf 'mark\t%s\t%q\t# %s%s\e(B\e[m\n' \
                   "$k" \
                   "${marks[$k]}" \
                   "${marks[$k]}" \
                   "$k"
        done | $filter | sort -k2,2V | column -t -s$'\t'

        echo

        echo '# Aliases'
        local result
        for k in "${!aliases[@]}"; do
            resolve "${aliases[$k]}"
            printf 'alias\t%s\t%s\t# %s%s\e(B\e[m\n' \
                   "$k" \
                   "${aliases[$k]}" \
                   "${marks[$result]}" \
                   "$k"
        done | $filter | sort -k3,3V | column -t -s$'\t'
    } | sed 's/\E/\e/g'
}

main () {
    local -A marks=() aliases=()

    local mode=default year=$YEAR week_start=auto
    local data_file_default=~/.config/cal-hl
    local config_file=~/.config/cal-hl-rc
    local token='# cal-hl'      # Data file format marker.

    temp BYE_PREFIX config
    default_config

    if [[ -f $config_file ]]; then
        [[ -r $config_file ]] || bye "${config_file@Q} is not readable."

        # shellcheck disable=SC1090
        source "$config_file"
    fi

    temp BYE_PREFIX

    local data_file=$data_file_default opt mark

    while getopts ':f:s:y:uhcMS' opt; do
        case $opt in
            f)
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
            M|S)
                week_start=$opt
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
            local date result
            for date; do
                parse_date "$date"

                if [[ -v data[$result] ]]; then
                    update=y
                    unset -v "data[$result]"
                fi
            done
            ;;

        default)
            local cal
            get_cal
            hl_cal

            echo
            {
                paste -d '' \
                      <(print_month 0 3 6 9) \
                      <(print_month 1 4 7 10) \
                      <(print_month 2 5 8 11)
            } | tr . ' ' | sed "s/YYYY/$year/g"
            ;;
    esac

    [[ $update == n ]] || save_data "$data_file"
}

(return 0 2>/dev/null) || main "$@"
