#!/usr/bin/env bash

cd tdesktop
for patch in ../*.patch; do
  echo "Applying patch: $patch"
  patch -p1 < "$patch"
  echo -e "\n"
done
