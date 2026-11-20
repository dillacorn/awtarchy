#!/usr/bin/env bash
# Read-only Quickshell resident/proportional/private memory inventory.
# Compare the same workload after the compositor session settles.
set -euo pipefail

printf 'Quickshell memory report (%s)\n' "$(date -Is)"
printf 'Session: %s\n' "${XDG_CURRENT_DESKTOP:-unknown}"
printf 'PSS accounts proportionally for shared memory; USS is the private portion.\n'
printf '%-8s %-22s %12s %12s %12s %8s\n' PID PROFILE RSS_MiB PSS_MiB USS_MiB THREADS

found=0
for proc in /proc/[0-9]*; do
    [[ -r "$proc/cmdline" && -r "$proc/status" ]] || continue
    pid="${proc##*/}"
    read -r uid < <(awk '/^Uid:/ {print $2; exit}' "$proc/status") || continue
    [[ "$uid" == "$(id -u)" ]] || continue
    cmd=( )
    while IFS= read -r -d '' arg; do cmd+=("$arg"); done < "$proc/cmdline" || true
    (( ${#cmd[@]} > 0 )) || continue
    executable="${cmd[0]##*/}"
    [[ "$executable" == qs || "$executable" == quickshell ]] || continue

    profile="(unknown)"
    for ((i = 1; i + 1 < ${#cmd[@]}; i++)); do
        if [[ "${cmd[i]}" == "-c" || "${cmd[i]}" == "--config" ]]; then
            profile="${cmd[i+1]}"
            break
        fi
    done

    rss=0
    threads=0
    read -r rss < <(awk '/^VmRSS:/ {print $2; exit}' "$proc/status") || true
    read -r threads < <(awk '/^Threads:/ {print $2; exit}' "$proc/status") || true
    [[ "$rss" =~ ^[0-9]+$ ]] || rss=0
    [[ "$threads" =~ ^[0-9]+$ ]] || threads=0
    pss="?"
    uss="?"
    if [[ -r "$proc/smaps_rollup" ]]; then
        read -r pss uss < <(awk '
            /^Pss:/ {pss=$2}
            /^Private_Clean:/ {priv+=$2}
            /^Private_Dirty:/ {priv+=$2}
            END {printf "%d %d\n", pss, priv}
        ' "$proc/smaps_rollup") || true
    fi
    format_mib() {
        if [[ "$1" =~ ^[0-9]+$ ]]; then
            awk -v k="$1" 'BEGIN {printf "%.1f", k/1024}'
        else
            printf '?'
        fi
    }
    printf '%-8s %-22.22s %12s %12s %12s %8s\n' \
        "$pid" "$profile" "$(format_mib "$rss")" \
        "$(format_mib "$pss")" "$(format_mib "$uss")" "$threads"
    found=$((found+1))
done
if (( found == 0 )); then
    printf 'No user-owned Quickshell process found.\n'
fi
