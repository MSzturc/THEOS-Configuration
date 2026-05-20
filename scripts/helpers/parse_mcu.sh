#!/bin/bash

# parse_mcu.sh — locate the primary [mcu] section across a Klipper-style
# printer.cfg tree, following [include ...] directives the same way the
# Klipper config parser does (paths resolved relative to the file that
# contains the include).
#
# Usage:
#   source helpers/parse_mcu.sh
#   find_mcu_in_config /path/to/printer.cfg
#
# On success prints two lines on stdout:
#   serial=<value>
#   cpu=<value>
# and exits 0. On failure (file missing or no [mcu] block with serial+cpu
# found) exits non-zero with no output.

# Read the [constants] block from the top-level config file into the global
# associative array _PARSE_MCU_CONSTANTS. Klipper config style: 'key: value'.
# Lines after the [constants] header until the next '[section]' are parsed.
# Inline '#' comments are stripped.
_parse_mcu_read_constants() {
    local file=$1
    declare -gA _PARSE_MCU_CONSTANTS=()
    [ -f "$file" ] || return 0

    local line stripped key val in_block=0
    while IFS= read -r line || [ -n "$line" ]; do
        stripped="${line#"${line%%[![:space:]]*}"}"
        if [ -z "$stripped" ] || [ "${stripped:0:1}" = "#" ]; then
            continue
        fi
        if [[ "$stripped" =~ ^\[constants\][[:space:]]*$ ]]; then
            in_block=1
            continue
        fi
        if [ "$in_block" -eq 1 ] && [[ "$stripped" =~ ^\[ ]]; then
            in_block=0
            continue
        fi
        if [ "$in_block" -eq 1 ] && [[ "$stripped" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*:[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
            val="${val%%#*}"
            val="${val%"${val##*[![:space:]]}"}"
            _PARSE_MCU_CONSTANTS[$key]="$val"
        fi
    done < "$file"
}

# Returns 0 if the conditional include should be followed, 1 if skipped.
# Supported forms: ${constants.<key> == '<val>'}  and  ${constants.<key> != '<val>'}.
# Any other form is skipped so an unrecognised conditional never leaks a
# wrong [mcu] into the result.
_parse_mcu_eval_condition() {
    local cond=$1
    local key op want actual
    if [[ "$cond" =~ ^\$\{constants\.([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*(==|!=)[[:space:]]*\'([^\']*)\'\}$ ]]; then
        key="${BASH_REMATCH[1]}"
        op="${BASH_REMATCH[2]}"
        want="${BASH_REMATCH[3]}"
        actual="${_PARSE_MCU_CONSTANTS[$key]:-}"
        if [ "$op" = "==" ]; then
            [ "$actual" = "$want" ]; return $?
        else
            [ "$actual" != "$want" ]; return $?
        fi
    fi
    return 1
}

# Flatten a Klipper config file by inlining (non-commented) [include ...]
# directives recursively. Missing include targets are silently skipped so
# that an unresolvable include never aborts the search for [mcu].
_parse_mcu_flatten() {
    local file=$1
    local abs
    abs=$(realpath "$file" 2>/dev/null) || return 0
    [ -z "$abs" ] && return 0
    [ -f "$abs" ] || return 0

    if [ -n "${_PARSE_MCU_VISITED[$abs]:-}" ]; then
        return 0
    fi
    _PARSE_MCU_VISITED[$abs]=1

    local dir
    dir=$(dirname "$abs")

    local line stripped inc target
    while IFS= read -r line || [ -n "$line" ]; do
        stripped="${line#"${line%%[![:space:]]*}"}"
        # Pass comments/blank lines through; never treat them as includes
        if [ -z "$stripped" ] || [ "${stripped:0:1}" = "#" ]; then
            printf '%s\n' "$line"
            continue
        fi
        if [[ "$stripped" =~ ^\[include[[:space:]]+([^]]+)\] ]]; then
            inc="${BASH_REMATCH[1]}"
            # Conditional include: '[include if:${...} path]'.
            # Evaluate the condition; skip the include entirely if the
            # condition is false or in an unsupported form. _cond and _path
            # are captured locally BEFORE calling the helper because
            # _parse_mcu_eval_condition itself uses [[ =~ ]] and would
            # otherwise overwrite BASH_REMATCH.
            if [[ "$inc" =~ ^if:(\$\{[^}]+\})[[:space:]]+(.+)$ ]]; then
                local _cond="${BASH_REMATCH[1]}"
                local _path="${BASH_REMATCH[2]}"
                if _parse_mcu_eval_condition "$_cond"; then
                    inc="$_path"
                else
                    continue
                fi
            fi
            # Trim surrounding whitespace
            inc="${inc#"${inc%%[![:space:]]*}"}"
            inc="${inc%"${inc##*[![:space:]]}"}"
            if [[ "$inc" = /* ]]; then
                target="$inc"
            else
                target="$dir/$inc"
            fi
            _parse_mcu_flatten "$target"
        else
            printf '%s\n' "$line"
        fi
    done < "$abs"
}

# Public entry point
find_mcu_in_config() {
    local file=$1
    [ -f "$file" ] || return 1

    declare -gA _PARSE_MCU_VISITED=()
    _parse_mcu_read_constants "$file"

    local flat serial cpu
    flat=$(_parse_mcu_flatten "$file")

    serial=$(printf '%s\n' "$flat" | awk '
        /^[[:space:]]*\[mcu\][[:space:]]*$/ { flag=1; next }
        /^[[:space:]]*\[/                  { flag=0 }
        flag && /^[[:space:]]*serial:/ {
            sub(/^[[:space:]]*serial:[[:space:]]*/, "")
            sub(/[[:space:]]*#.*$/, "")
            sub(/[[:space:]]+$/, "")
            print
            exit
        }')

    cpu=$(printf '%s\n' "$flat" | awk '
        /^[[:space:]]*\[mcu\][[:space:]]*$/ { flag=1; next }
        /^[[:space:]]*\[/                  { flag=0 }
        flag && /^[[:space:]]*cpu:/ {
            sub(/^[[:space:]]*cpu:[[:space:]]*/, "")
            sub(/[[:space:]]*#.*$/, "")
            sub(/[[:space:]]+$/, "")
            print
            exit
        }')

    if [ -z "$serial" ] || [ -z "$cpu" ]; then
        return 1
    fi

    printf 'serial=%s\n' "$serial"
    printf 'cpu=%s\n' "$cpu"
    return 0
}
