#!/bin/bash

trials=10
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 [compression]"
    exit 1
fi

rm compress_time.csv
rm decompress_time.csv

make clean
make bootstrap driver
make "$1"
echo -e "$1 compress" >> compress_time.csv
echo -e "$1 decompress" >> decompress_time.csv
for filename in ../../../well_rounded_tests/*;
do
    echo "Running $1 on $filename $trials times..."
    echo "$filename" >> compress_time.csv
    echo "$filename" >> decompress_time.csv
    for i in `seq 1 $trials`
    do
        results_valid=$(./bin/driver -v -f "$filename";)
        time_valid=$(echo "$results_valid" | grep 'Time spent on compress:' | awk '{print $5}')
        results_c=$(./bin/driver -f "$filename";)
        time_c=$(echo "$results_c" | grep 'Time spent on compress:' | awk '{print $5}')
        echo "$time_c" >> compress_time.csv
        echo "scale = 10; $time_valid - $time_c" | bc >> decompress_time.csv
    done
done