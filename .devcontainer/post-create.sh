#!/bin/bash

# Ensure UTF-8 locale so tools like hspec can output Unicode characters
echo "export LANG=C.UTF-8" >> ~/.zshrc
echo "export LC_ALL=C.UTF-8" >> ~/.zshrc
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# Install hspec-discover for test discovery
echo "Installing hspec-discover..."
cabal install hspec-discover --overwrite-policy=always
echo "hspec-discover installed."

# Check if .envrc file exists and automatically allow it with direnv
if [ -f "/workspaces/haskell/.envrc" ]; then
  echo "Found .envrc file, running direnv allow..."
  direnv allow /workspaces/haskell
  echo "direnv allow completed."
else
  echo "No .envrc file found, skipping direnv allow."
fi
