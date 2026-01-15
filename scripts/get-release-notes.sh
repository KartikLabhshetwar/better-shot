#!/bin/bash

set -e

CURRENT_TAG=$(git tag --sort=-v:refname | sed -n '1p')
PREV_TAG=$(git tag --sort=-v:refname | sed -n '2p')

if [ -z "$CURRENT_TAG" ]; then
  echo "No tags found"
  exit 1
fi

if [ -z "$PREV_TAG" ]; then
  echo "No previous tag found. Showing all commits for $CURRENT_TAG:"
  git log --oneline --pretty=format:"%h - %s" --reverse
else
  echo "Commits between $PREV_TAG and $CURRENT_TAG:"
  git log "$PREV_TAG".."$CURRENT_TAG" --oneline --pretty=format:"%h - %s" --reverse
fi
