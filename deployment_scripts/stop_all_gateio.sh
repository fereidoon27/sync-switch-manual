#!/bin/bash

# Iterate over directories that start with "van-buren"
for dir in /home/ubuntu/van-buren-rlc-router-gateio*/; do
  # Check if the directory exists and is a directory
  if [ -d "$dir" ]; then
    echo "Entering directory: $dir"

    # Check if the script 111-ACTION-deploy-services.sh exists and is executable
    if [ -x "$dir/000-ACTION-stop-services.sh" ]; then
      echo "Running 000-ACTION-stop-services.sh in $dir"
      (cd "$dir" && ./000-ACTION-stop-services.sh)
    else
      echo "000-ACTION-stop-services.sh not found or not executable in $dir"
    fi
  fi
done