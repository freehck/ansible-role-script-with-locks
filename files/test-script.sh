#!/bin/bash

for i in $(seq $@); do
    echo $i;
    sleep 1;
done

