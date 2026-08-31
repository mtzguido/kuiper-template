#!/usr/bin/env bash

# Bound parallelism by both CPU count and available container memory.
set -euo pipefail

usage() {
  echo "usage: $0 MIB_PER_JOB [MAX_JOBS]" >&2
  exit 2
}

[[ $# -ge 1 && $# -le 2 ]] || usage
per_job_mib=$1
cpu_jobs=$(nproc)
max_jobs=${2:-$cpu_jobs}
[[ $per_job_mib =~ ^[1-9][0-9]*$ ]] || usage
[[ $max_jobs =~ ^[1-9][0-9]*$ ]] || usage

available_kib=$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)

if [[ -r /sys/fs/cgroup/memory.max && -r /sys/fs/cgroup/memory.current ]]; then
  limit=$(< /sys/fs/cgroup/memory.max)
  current=$(< /sys/fs/cgroup/memory.current)
  if [[ $limit =~ ^[0-9]+$ && $current =~ ^[0-9]+$ && $limit -gt $current ]]; then
    cgroup_available_kib=$(( (limit - current) / 1024 ))
    (( cgroup_available_kib >= available_kib )) || available_kib=$cgroup_available_kib
  fi
elif [[ -r /sys/fs/cgroup/memory/memory.limit_in_bytes &&
        -r /sys/fs/cgroup/memory/memory.usage_in_bytes ]]; then
  limit=$(< /sys/fs/cgroup/memory/memory.limit_in_bytes)
  current=$(< /sys/fs/cgroup/memory/memory.usage_in_bytes)
  if [[ $limit =~ ^[0-9]+$ && $current =~ ^[0-9]+$ && $limit -gt $current ]]; then
    cgroup_available_kib=$(( (limit - current) / 1024 ))
    (( cgroup_available_kib >= available_kib )) || available_kib=$cgroup_available_kib
  fi
fi

memory_jobs=$(( available_kib / 1024 / per_job_mib ))
(( memory_jobs >= 1 )) || memory_jobs=1

jobs=$cpu_jobs
(( jobs <= memory_jobs )) || jobs=$memory_jobs
(( jobs <= max_jobs )) || jobs=$max_jobs
echo "$jobs"
