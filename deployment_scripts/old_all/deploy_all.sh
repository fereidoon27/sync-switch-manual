#!/bin/bash

# Iterate over directories that start with "van-buren"
for dir in /home/ubuntu/van-buren*/; do
  # Check if the directory exists and is a directory
  if [ -d "$dir" ]; then
    echo "Entering directory: $dir"

    # Check if the script 111-ACTION-deploy-services.sh exists and is executable
    if [ -x "$dir/111-ACTION-deploy-services.sh" ]; then
      echo "Running 111-ACTION-deploy-services.sh in $dir"
      (cd "$dir" && ./111-ACTION-deploy-services.sh)
    else
      echo "111-ACTION-deploy-services.sh not found or not executable in $dir"
    fi
  fi
done