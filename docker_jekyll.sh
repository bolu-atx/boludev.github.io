#!/usr/bin/env bash

export JEKYLL_VERSION=3.8

which docker 2>&1 > /dev/null
if [[ $? -ne 0 ]]; then
  echo "No docker found. cannot continue"
fi


docker run --rm \
  --volume="$PWD:/srv/jekyll:Z" \
  --volume="$PWD/.bundle:/usr/local/bundle:Z" \
  --platform linux/amd64 \
  -p 4000:4000 \
  -it jekyll/jekyll:$JEKYLL_VERSION \
  jekyll "$@"
