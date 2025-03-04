#!/bin/bash

# Define project directory
REPO_DIR="/home/amin/git_repos/automated-vm-migration-service"

# Navigate to the project directory
cd "$REPO_DIR" || { echo "Directory not found!"; exit 1; }

# Pull the latest changes from the remote repository (with rebase)
echo "Pulling the latest changes from the remote repository..."
git pull origin main --rebase

# Add all new/modified files
git add .

# Commit changes with a timestamp
git commit -m "Auto-commit: $(date +"%Y-%m-%d %H:%M:%S")"

# Push the changes to the remote repository
git push -u origin main

# Done
echo "Changes have been pushed successfully to GitHub!"
