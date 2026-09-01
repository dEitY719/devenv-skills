#!/bin/sh
# lib/ux.sh — minimal output helpers for devenv:ssh-delegate.
#
# Standalone by design: prefers the dotfiles ux_lib when SHELL_COMMON points
# at it, otherwise falls back to plain printf so the skill works on a bare
# machine (issue #877: "ux_lib 부재 환경에서도 plain printf fallback").
#
# Sourced — no shebang execution. POSIX sh only.

# shellcheck disable=SC2034  # color vars are consumed by the printf helpers
if [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != "dumb" ] && command -v tput >/dev/null 2>&1; then
    _UX_BOLD="$(tput bold 2>/dev/null || printf '')"
    _UX_RESET="$(tput sgr0 2>/dev/null || printf '')"
    _UX_BLUE="$(tput setaf 4 2>/dev/null || printf '')"
    _UX_GREEN="$(tput setaf 2 2>/dev/null || printf '')"
    _UX_YELLOW="$(tput setaf 3 2>/dev/null || printf '')"
    _UX_RED="$(tput setaf 1 2>/dev/null || printf '')"
    _UX_CYAN="$(tput setaf 6 2>/dev/null || printf '')"
else
    _UX_BOLD=''
    _UX_RESET=''
    _UX_BLUE=''
    _UX_GREEN=''
    _UX_YELLOW=''
    _UX_RED=''
    _UX_CYAN=''
fi

ux_header() { printf '%s%s== %s ==%s\n' "$_UX_BOLD" "$_UX_BLUE" "$1" "$_UX_RESET"; }
ux_success() { printf '%s[OK]%s %s\n' "$_UX_GREEN" "$_UX_RESET" "$1"; }
ux_info() { printf '%s[..]%s %s\n' "$_UX_CYAN" "$_UX_RESET" "$1"; }
ux_warning() { printf '%s[WARN]%s %s\n' "$_UX_YELLOW" "$_UX_RESET" "$1" >&2; }
ux_error() { printf '%s[FAIL]%s %s\n' "$_UX_RED" "$_UX_RESET" "$1" >&2; }
ux_alert() { printf '%s%s[ALERT]%s %s\n' "$_UX_BOLD" "$_UX_RED" "$_UX_RESET" "$1" >&2; }
