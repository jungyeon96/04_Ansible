# Copyright 2015 Koichi Murase <myoga.murase@gmail.com>. All rights reserved.
# This script is a part of blesh (https://github.com/akinomyoga/ble.sh)
# provided under the BSD-3-Clause license.  Do not edit this file because this
# is not the original source code: Various pre-processing has been applied.
# Also, the code comments and blank lines are stripped off in the installation
# process.  Please find the corresponding source file(s) in the repository
# "akinomyoga/ble.sh".
#
# Source: /lib/util.bgproc.sh
function ble/util/bgproc#open {
  if ! ble/string#match "$1" '^[_a-zA-Z][_a-zA-Z0-9]*$'; then
    ble/util/print "$FUNCNAME: $1: invalid prefix value." >&2
    return 2
  fi
  ble/util/bgproc#close "$1"
  local -a bgproc=()
  bgproc[0]=
  bgproc[1]=
  bgproc[2]=$2
  bgproc[3]=${3-}
  local -a bgproc_fname=()
  bgproc_fname[0]=$_ble_base_run/$$.util.bgproc.$1.response.pipe
  bgproc_fname[1]=$_ble_base_run/$$.util.bgproc.$1.request.pipe
  bgproc_fname[2]=$_ble_base_run/$$.util.bgproc.$1.pid
  ble/util/save-vars "${1}_" bgproc bgproc_fname
  [[ :${bgproc[3]}: == *:deferred:* ]] || ble/util/bgproc#start "$1"; local ext=$?
  if ((ext!=0)); then
    builtin eval -- "${1}_bgproc=() ${1}_bgproc_fname=()"
  fi
  return "$ext"
}
function ble/util/bgproc#opened {
  local bgpid_ref=${1}_bgproc[0]
  [[ ${!bgpid_ref+set} ]] || return 2
}
function ble/util/bgproc/.alive {
  [[ ${bgproc[4]-} ]] && kill -0 "${bgproc[4]}" 2>/dev/null
}
function ble/util/bgproc/.exec {
  builtin eval -- "${bgproc[2]}" <&"${bgproc[1]}" >&"${bgproc[0]}"
}
function ble/util/bgproc/.mkfifo {
  local -a pipe_remove=() pipe_create=()
  local i
  for i in 0 1; do
    [[ -p ${bgproc_fname[i]} ]] && continue
    ble/array#push pipe_create "${bgproc_fname[i]}"
    if [[ -e ${bgproc_fname[i]} || -h ${bgproc_fname[i]} ]]; then
      ble/array#push pipe_remove "${bgproc_fname[i]}"
    fi
  done
  ((${#pipe_remove[@]}==0)) || ble/bin/rm -f "${pipe_remove[@]}" 2>/dev/null
  ((${#pipe_create[@]}==0)) || ble/bin/mkfifo "${pipe_create[@]}" 2>/dev/null
}
function ble/util/bgproc#start {
  local bgproc bgproc_fname
  ble/util/restore-vars "${1}_" bgproc bgproc_fname
  if ((!${#bgproc[@]})); then
    ble/util/print "$FUNCNAME: $1: not an existing bgproc name." >&2
    return 2
  fi
  if ble/util/bgproc/.alive; then
    return 0
  fi
  [[ ! ${bgproc[0]-} ]] || ble/fd#close 'bgproc[0]'
  [[ ! ${bgproc[1]-} ]] || ble/fd#close 'bgproc[1]'
  local _ble_local_ext=0 _ble_local_bgproc0= _ble_local_bgproc1=
  if ble/util/bgproc/.mkfifo &&
    ble/fd#alloc _ble_local_bgproc0 '<> "${bgproc_fname[0]}"' &&
    ble/fd#alloc _ble_local_bgproc1 '<> "${bgproc_fname[1]}"'
  then
    bgproc[0]=$_ble_local_bgproc0
    bgproc[1]=$_ble_local_bgproc1
    ble/util/assign 'bgproc[4]' '(set -m; ble/util/joblist/__suppress__; ble/util/bgproc/.exec >/dev/null & bgpid=$!; ble/util/print "$bgpid")'
    if ble/util/bgproc/.alive; then
      [[ :${bgproc[3]}: == *:no-close-on-unload:* ]] ||
        ble/util/print "-${bgproc[4]}" >| "${bgproc_fname[2]}"
      [[ :${bgproc[3]}: == *:no-close-on-unload:* || :${bgproc[3]}: == *:owner-close-on-unload:* ]] ||
        blehook unload!="ble/util/bgproc#close $1"
      ble/util/bgproc#keepalive "$1"
    else
      builtin unset -v 'bgproc[4]'
      _ble_local_ext=1
    fi
  else
    _ble_local_ext=3
  fi
  if ((_ble_local_ext!=0)); then
    [[ ! ${bgproc[0]-} ]] || ble/fd#close 'bgproc[0]'
    [[ ! ${bgproc[1]-} ]] || ble/fd#close 'bgproc[1]'
    bgproc[0]=
    bgproc[1]=
    builtin unset -v 'bgproc[4]'
  fi
  ble/util/save-vars "${1}_" bgproc bgproc_fname
  if ((_ble_local_ext==0)); then
    ble/function#try ble/util/bgproc/onstart:"$1"
  fi
  return "$_ble_local_ext"
}
function ble/util/bgproc#stop/.kill {
  local pid=$1 opts=$2 ret
  local timeout=10000
  if ble/opts#extract-last-optarg "$opts" kill-timeout; then
    timeout=$ret
  fi
  ble/util/conditional-sync '' '((1))' 1000 progressive-weight:pid="$pid":no-wait-pid:timeout="$timeout"
  kill -0 "$pid" || return 0
  local timeout=10000
  if ble/opts#extract-last-optarg "$opts" kill9-timeout; then
    timeout=$ret
  fi
  ble/util/conditional-sync '' '((1))' 1000 progressive-weight:pid="$pid":no-wait-pid:timeout="$timeout":SIGKILL
}
function ble/util/bgproc#stop {
  local prefix=$1
  ble/util/bgproc#keepalive/.cancel-timeout "$prefix"
  local bgproc bgproc_fname
  ble/util/restore-vars "${prefix}_" bgproc bgproc_fname
  if ((!${#bgproc[@]})); then
    ble/util/print "$FUNCNAME: $prefix: not an existing bgproc name." >&2
    return 2
  fi
  [[ ${bgproc[4]-} ]] || return 1
  if ble/is-function ble/util/bgproc/onstop:"$prefix" && ble/util/bgproc/.alive; then
    ble/util/bgproc/onstop:"$prefix"
  fi
  ble/fd#close 'bgproc[0]'
  ble/fd#close 'bgproc[1]'
  >| "${bgproc_fname[2]}"
  if ble/util/bgproc/.alive; then
    (ble/util/nohup 'ble/util/bgproc#stop/.kill "-${bgproc[4]}" "${bgproc[3]}"')
  fi
  builtin eval -- "${prefix}_bgproc[0]="
  builtin eval -- "${prefix}_bgproc[1]="
  builtin unset -v "${prefix}_bgproc[4]"
  return 0
}
function ble/util/bgproc#alive {
  local prefix=$1 bgproc
  ble/util/restore-vars "${prefix}_" bgproc
  ((${#bgproc[@]})) || return 2
  [[ ${bgproc[4]-} ]] || return 1
  kill -0 "${bgproc[4]}" 2>/dev/null || return 3
  return 0
}
function ble/util/bgproc#keepalive/.timeout {
  local prefix=$1
  if ble/is-function ble/util/bgproc/ontimeout:"$prefix"; then
    if ! ble/util/bgproc/ontimeout:"$prefix"; then
      ble/util/bgproc#keepalive "$prefix"
      return 0
    fi
  fi
  ble/util/bgproc#stop "$prefix"
}
function ble/util/bgproc#keepalive/.cancel-timeout {
  local prefix=$1
  ble/function#try ble/util/idle.cancel "ble/util/bgproc#keepalive/.timeout $prefix"
}
function ble/util/bgproc#keepalive {
  local prefix=$1 bgproc
  ble/util/restore-vars "${prefix}_" bgproc
  ((${#bgproc[@]})) || return 2
  ble/util/bgproc/.alive || return 1
  ble/util/bgproc#keepalive/.cancel-timeout "$prefix"
  local ret
  ble/opts#extract-last-optarg "${bgproc[3]}" timeout || return 0; local bgproc_timeout=$ret
  if ((bgproc_timeout>0)); then
    local timeout_proc="ble/util/bgproc#keepalive/.timeout $1"
    ble/function#try ble/util/idle.push --sleep="$bgproc_timeout" "$timeout_proc"
  fi
  return 0
}
_ble_util_bgproc_onclose_processing=
function ble/util/bgproc#close {
  ble/util/bgproc#opened "$1" || return 2
  local prefix=${1}
  blehook unload-="ble/util/bgproc#close $prefix"
  ble/util/bgproc#keepalive/.cancel-timeout "$prefix"
  if ble/is-function ble/util/bgproc/onclose:"$prefix"; then
    if [[ :${_ble_util_bgproc_onclose_processing-}: != *:"$prefix":* ]]; then
      local _ble_util_bgproc_onclose_processing=${_ble_util_bgproc_onclose_processing-}:$prefix
      ble/util/bgproc/onclose:"$prefix"
    fi
  fi
  ble/util/bgproc#stop "$prefix"
  builtin eval -- "${prefix}_bgproc=() ${prefix}_bgproc_fname=()"
}
function ble/util/bgproc#use {
  local bgproc
  ble/util/restore-vars "${1}_" bgproc
  if ((!${#bgproc[@]})); then
    ble/util/print "$FUNCNAME: $1: not an existing bgproc name." >&2
    return 2
  fi
  if [[ ! ${bgproc[4]-} ]]; then
    ble/util/bgproc#start "$1" || return "$?"
  elif ! kill -0 "${bgproc[4]-}"; then
    if [[ :${bgproc[3]-}: == *:restart:* ]]; then
      ble/util/bgproc#start "$1" || return "$?"
    else
      return 1
    fi
  else
    ble/util/bgproc#keepalive "$1"
    return 0
  fi
}
function ble/util/bgproc#post {
  ble/util/bgproc#use "$1" || return "$?"
  local fd1_ref=${1}_bgproc[1]
  ble/util/print "$2" >&"${!fd1_ref}"
}
