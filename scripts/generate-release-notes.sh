#!/bin/bash

set -e

TAG_NAME="${1:-$(git describe --tags --abbrev=0)}"
PREV_TAG=$(git tag --sort=-v:refname | sed -n '2p')

if [ -z "$PREV_TAG" ]; then
  echo "No previous tag found. Using all commits."
  COMMITS=$(git log --oneline --pretty=format:"- %s" --reverse)
else
  COMMITS=$(git log "$PREV_TAG".."$TAG_NAME" --oneline --pretty=format:"- %s" --reverse)
fi

if [ -z "$COMMITS" ]; then
  echo "No commits found between $PREV_TAG and $TAG_NAME"
  exit 1
fi

echo "$COMMITS"
