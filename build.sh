#!/usr/bin/env bash

cd tdesktop
for patch in ../*.patch; do
  echo "Applying patch: $patch"
  patch -p1 < "$patch"
  echo -e ""
done

podman run --rm -it \
  -v "$PWD:/usr/src/tdesktop" \
  ghcr.io/telegramdesktop/tdesktop/centos_env:latest \
  /usr/src/tdesktop/Telegram/build/docker/centos_env/build.sh \
  -D TDESKTOP_API_ID=611335 \
  -D TDESKTOP_API_HASH=d524b414d21f4d37f08684c1df41ac9c \
  -D DESKTOP_APP_DISABLE_AUTOUPDATE=ON

strip out/Release/Telegram
