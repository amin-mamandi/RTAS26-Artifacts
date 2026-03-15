#!/bin/bash

#mount -t hugetlbfs none /mnt/huge
#echo 128 > /proc/sys/vm/nr_hugepages
. ./functions
. ./floatfunc

if [ -z "$1" -o -z "$2" ]; then
    echo "usage: mlptest.sh <maxmlp> <corun>"
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAP_FILE="$REPO_ROOT/IsolBench/bench/map.txt"

mlp=$1
corun=$2
memsize=512 # in MB (you can adjust this based on your system's hugepage size and availability)

echoerr() { echo "$@" 1>&2; }

[ -z "$3" ] && st=0 || st=$3

c_start=$((st + 1))
c_end=$((st + corun))

killall pll >& /dev/null

# Prepare output file and clear any old data
outfile="mlp-allbanks-bw_corun${corun}.dat"
: > "$outfile"   # truncate or create the file

for l in $(seq 1 "$mlp"); do
    for c in $(seq "$c_start" "$c_end"); do
        pll -f "$MAP_FILE" -c "$c" -l "$l" -i 20000 -m "$memsize" >& "./pll-$l-$c.log" & # use "-m" instead of "-g" if you want to allocate memory in MB instead of GB
    done
    sleep 1.5
    pll -f "$MAP_FILE" -c "$st" -l "$l" -i 50 -m "$memsize" 2> ./err.txt # use "-m" instead of "-g" if you want to allocate memory in MB instead of GB

    if grep -qi "alloc failed" ./err.txt; then
        echo "Error: Failed to allocate memory for mlp $l, please allocate more hugepages." >&2
        echo "Hint: Check /proc/meminfo and init-hugetlbfs.sh" >&2
        exit 1
    fi

    killall pll >& /dev/null
    echoerr "$l" "$(tail -n 1 ./test.txt)"
done > ./test.txt

# Extract bandwidth values and compute aggregate
BWS=$(grep bandwidth ./test.txt | awk '{ print $2 }')

i=1
for b in $BWS; do
    agg=$(float_eval "$b * ( $corun + 1 )")
    printf "%d %s\n" "$i" "$agg" >> "$outfile"
    i=$((i + 1))
done

cat "$outfile"

# Log summary (truncate previous one too)
logfile="out_corun${corun}.log"
{
    echo "maxmlp=$mlp, corun=$corun, outfile=$outfile"
    awk '{ print $2 }' "$outfile"
} > "$logfile"

# Cleanup
rm -f ./err.txt ./pll-*.log ./test.txt
