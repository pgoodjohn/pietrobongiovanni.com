#!/bin/bash

# Check if the .env file exists
if [ ! -f .env ]; then
  echo "Error: .env file not found. Please create a .env file with the required environment variables."
  exit 1
fi

# Load environment variables from .env file
export $(grep -v '^#' .env | xargs)

# Build the Hugo project
echo "Building Hugo project..."
hugo

# Check for the "dryrun" option
if [ "$1" = "--dryrun" ] || [ "$1" = "-n" ]; then
    DRYRUN_OPTION="--dry-run"
    echo "Dryrun mode enabled. No files will be transferred."
else
    DRYRUN_OPTION=""
fi

# Sync the public directory with the remote server
echo "Deploying to remote server..."
rsync -avz --omit-dir-times --delete ${DRYRUN_OPTION} "./public/" "${SSH_USER}@${SSH_HOST}:${REMOTE_DEPLOY_PATH}"

if [ -z "${DRYRUN_OPTION}" ]; then
    echo "Deployment complete!"
else
    echo "Dryrun complete. No files were transferred."
fi