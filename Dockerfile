{%- set GIT = "https://github.com" -%}
{%- set GIT_FREEDESKTOP = GIT ~ "/gitlab-freedesktop-mirrors" -%}
{%- set GIT_UPDATE_M4 = "git submodule set-url m4 https://gitlab.freedesktop.org/xorg/util/xcb-util-m4 && git config -f .gitmodules submodule.m4.shallow true && git submodule init && git submodule update" -%}
{%- set QT = "6.8.0" -%}
{%- set QT_TAG = "v" ~ QT ~ "-beta4" -%}
{%- set CFLAGS_DEBUG = "$CFLAGS -O0 -fno-lto -U_FORTIFY_SOURCE" -%}
{%- set LibrariesPath = "/usr/src/Libraries" -%}

# syntax=docker/dockerfile:1

FROM rockylinux:8 AS builder
ENV LANG C.UTF-8
ENV LIBRARY_PATH /usr/local/lib64:/usr/local/lib:/lib64:/lib:/usr/lib64:/usr/lib
ENV LD_LIBRARY_PATH $LIBRARY_PATH
ENV PKG_CONFIG_PATH /usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/local/share/pkgconfig

RUN dnf -y install epel-release \
	&& dnf config-manager --set-enabled powertools \
	&& dnf -y install cmake autoconf automake libtool pkgconfig make patch git \
		python3.11-pip python3.11-devel gperf flex bison clang lld nasm yasm \
		file which perl-open perl-XML-Parser perl-IPC-Cmd xorg-x11-util-macros \
		gcc-toolset-12-gcc gcc-toolset-12-gcc-c++ gcc-toolset-12-binutils \
		gcc-toolset-12-libasan-devel libffi-devel fontconfig-devel freetype-devel \
		libX11-devel alsa-lib-devel pulseaudio-libs-devel mesa-libGL-devel \
		mesa-libEGL-devel mesa-libgbm-devel libdrm-devel vulkan-devel libva-devel \
		libvdpau-devel glib2-devel at-spi2-core-devel gtk3-devel boost1.78-devel fmt-devel \
	&& dnf clean all

SHELL [ "bash", "-c", ". /opt/rh/gcc-toolset-12/enable; exec bash -c \"$@\"", "-s"]

WORKDIR {{ LibrariesPath }}

RUN python3 -m pip install meson ninja

ENV AR gcc-ar
ENV RANLIB gcc-ranlib
ENV NM gcc-nm
ENV CFLAGS {% if DEBUG %}-g{% endif %} -O3 {% if LTO %}-flto=auto -ffat-lto-objects{% endif %} -pipe -fPIC -fno-strict-aliasing -fexceptions -fasynchronous-unwind-tables -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer -fstack-protector-strong -fstack-clash-protection -fcf-protection -D_FORTIFY_SOURCE=3 -D_GLIBCXX_ASSERTIONS
ENV CXXFLAGS $CFLAGS

FROM builder AS patches
RUN git init patches \
	&& cd patches \
	&& git remote add origin {{ GIT }}/desktop-app/patches.git \
	&& git fetch --depth=1 origin 5361159037f844567cfffbd98c90d48d052fb5d0 \
	&& git reset --hard FETCH_HEAD \
	&& rm -rf .git

FROM builder AS zlib
RUN git init zlib \
	&& cd zlib \
	&& git remote add origin {{ GIT }}/madler/zlib.git \
	&& git fetch --depth=1 origin 643e17b7498d12ab8d15565662880579692f769d \
	&& git reset --hard FETCH_HEAD \
	&& ./configure \
	&& make -j$(nproc) \
	&& make DESTDIR="{{ LibrariesPath }}/zlib-cache" install \
	&& cd .. \
	&& rm -rf zlib

FROM builder AS xz
RUN git clone -b v5.4.4 --depth=1 {{ GIT }}/tukaani-project/xz.git \
	&& cd xz \
	&& cmake -B build . -DCMAKE_BUILD_TYPE=None \
	&& cmake --build build -j$(nproc) \
	&& DESTDIR="{{ LibrariesPath }}/xz-cache" cmake --install build \
	&& cd .. \
	&& rm -rf xz

FROM builder AS protobuf
RUN git clone -b v21.9 --depth=1 --recursive --shallow-submodules {{ GIT }}/protocolbuffers/protobuf.git \
	&& cd protobuf \
	&& git init third_party/abseil-cpp \
	&& cd third_party/abseil-cpp \
	&& git remote add origin {{ GIT }}/abseil/abseil-cpp.git \
	&& git fetch --depth=1 origin 273292d1cfc0a94a65082ee350509af1d113344d \
	&& git reset --hard FETCH_HEAD \
	&& cd ../.. \
	&& cmake -GNinja -B build . \
		-DCMAKE_BUILD_TYPE=None \
		-Dprotobuf_BUILD_TESTS=OFF \
		-Dprotobuf_BUILD_PROTOBUF_BINARIES=ON \
		-Dprotobuf_BUILD_LIBPROTOC=ON \
		-Dprotobuf_WITH_ZLIB=OFF \
	&& cmake --build build --parallel \
	&& DESTDIR="{{ LibrariesPath }}/protobuf-cache" cmake --install build \
	&& cd .. \
	&& rm -rf protobuf

FROM builder AS lcms2
RUN git clone -b lcms2.15 --depth=1 {{ GIT }}/mm2/Little-CMS.git \
	&& cd Little-CMS \
	&& meson build \
		--buildtype=plain \
		--default-library=both \
	&& meson compile -C build \
	&& DESTDIR="{{ LibrariesPath }}/lcms2-cache" meson install -C build \
	&& cd .. \
	&& rm -rf Little-CMS

FROM builder AS brotli
RUN git clone -b v1.1.0 --depth=1 {{ GIT }}/google/brotli.git \
	&& cd brotli \
	&& cmake -GNinja -B build . \
		-DCMAKE_BUILD_TYPE=None \
		-DBUILD_SHARED_LIBS=OFF \
		-DBROTLI_DISABLE_TESTS=ON \
	&& cmake --build build --parallel \
	&& DESTDIR="{{ LibrariesPath }}/brotli-cache" cmake --install build \
	&& cd .. \
	&& rm -rf brotli

FROM builder AS highway
RUN git clone -b 1.0.7 --depth=1 {{ GIT }}/google/highway.git \
	&& cd highway \
	&& cmake -GNinja -B build . \
		-DCMAKE_BUILD_TYPE=None \
		-DBUILD_TESTING=OFF \
		-DHWY_ENABLE_CONTRIB=OFF \
		-DHWY_ENABLE_EXAMPLES=OFF \
	&& cmake --build build --parallel \
	&& DESTDIR="{{ LibrariesPath }}/highway-cache" cmake --install build \
	&& cd .. \
	&& rm -rf highway

FROM builder AS opus
RUN git clone -b v1.4 --depth=1 {{ GIT }}/xiph/opus.git \
	&& cd opus \
	&& ./autogen.sh \
	&& ./configure \
	&& make -j$(nproc) \
	&& make DESTDIR="{{ LibrariesPath }}/opus-cache" install \
	&& cd .. \
	&& rm -rf opus

FROM builder AS dav1d
RUN git clone -b 1.4.1 --depth=1 {{ GIT }}/videolan/dav1d.git \
	&& cd dav1d \
	&& meson build \
		--buildtype=plain \
		--default-library=both \
		-Denable_tools=false \
		-Denable_tests=false \
	&& meson compile -C build \
	&& DESTDIR="{{ LibrariesPath }}/dav1d-cache" meson install -C build \
	&& cd .. \
	&& rm -rf dav1d

FROM builder AS openh264
RUN git clone -b v2.4.1 --depth=1 {{ GIT }}/cisco/openh264.git \
	&& cd openh264 \
	&& meson build \
		--buildtype=plain \
		--default-library=both \
	&& meson compile -C build \
	&& DESTDIR="{{ LibrariesPath }}/openh264-cache" meson install -C build \
	&& cd .. \
	&& rm -rf openh264

FROM builder AS libde265
RUN git clone -b v1.0.15 --depth=1 {{ GIT }}/strukturag/libde265.git \
	&& cd libde265 \
	&& cmake -GNinja . \
		-DCMAKE_BUILD_TYPE=None \
		-DBUILD_SHARED_LIBS=OFF \
		-DENABLE_DECODER=OFF \
		-DENABLE_SDL=OFF \
	&& cmake --build . --parallel \
	&& DESTDIR="{{ LibrariesPath }}/libde265-cache" cmake --install . \
	&& cd .. \
	&& rm -rf libde265

FROM builder AS libvpx
RUN git init libvpx \
	&& cd libvpx \
	&& git remote add origin {{ GIT }}/webmproject/libvpx.git \
	&& git fetch --depth=1 origin 12f3a2ac603e8f10742105519e0cd03c3b8f71dd \
	&& git reset --hard FETCH_HEAD \
	&& CFLAGS="$CFLAGS -fno-lto" CXXFLAGS="$CXXFLAGS -fno-lto" ./configure \
		--disable-examples \
		--disable-unit-tests \
		--disable-tools \
		--disable-docs \
		--enable-vp8 \
		--enable-vp9 \
		--enable-webm-io \
		--size-limit=4096x4096 \
	&& make -j$(nproc) \
	&& make DESTDIR="{{ LibrariesPath }}/libvpx-cache" install \
	&& cd .. \
	&& rm -rf libvpx

FROM builder AS libwebp
RUN git clone -b chrome-m116-5845 --depth=1 {{ GIT }}/webmproject/libwebp.git \
	&& cd libwebp \
	&& cmake -GNinja -B build . \
		-DCMAKE_BUILD_TYPE=None \
		-DWEBP_BUILD_ANIM_UTILS=OFF \
		-DWEBP_BUILD_CWEBP=OFF \
		-DWEBP_BUILD_DWEBP=OFF \
		-DWEBP_BUILD_GIF2WEBP=OFF \
		-DWEBP_BUILD_IMG2WEBP=OFF \
		-DWEBP_BUILD_VWEBP=OFF \
		-DWEBP_BUILD_WEBPMUX=OFF \
		-DWEBP_BUILD_WEBPINFO=OFF \
		-DWEBP_BUILD_EXTRAS=OFF \
	&& cmake --build build --parallel \
	&& DESTDIR="{{ LibrariesPath }}/libwebp-cache" cmake --install build \
	&& cd .. \
	&& rm -rf libwebp

FROM builder AS libavif
COPY  --from=dav1d {{ LibrariesPath }}/dav1d-cache /

RUN git clone -b v1.0.4 --depth=1 {{ GIT }}/AOMediaCodec/libavif.git \
	&& cd libavif \
	&& cmake -GNinja -B build . \
		-DCMAKE_BUILD_TYPE=None \
		-DBUILD_SHARED_LIBS=OFF \
		-DAVIF_CODEC_DAV1D=ON \
	&& cmake --build build --parallel \
	&& DESTDIR="{{ LibrariesPath }}/libavif-cache" cmake --install build \
	&& cd .. \
	&& rm -rf libavif

FROM builder AS libheif
COPY  --from=libde265 {{ LibrariesPath }}/libde265-cache /

RUN git clone -b v1.17.6 --depth=1 {{ GIT }}/strukturag/libheif.git \
	&& cd libheif \
	&& cmake -GNinja -B build . \
		-DCMAKE_BUILD_TYPE=None \
		-DBUILD_SHARED_LIBS=OFF \
		-DBUILD_TESTING=OFF \
		-DENABLE_PLUGIN_LOADING=OFF \
		-DWITH_X265=OFF \
		-DWITH_AOM_DECODER=OFF \
		-DWITH_AOM_ENCODER=OFF \
		-DWITH_RAV1E=OFF \
		-DWITH_RAV1E_PLUGIN=OFF \
		-DWITH_SvtEnc=OFF \
		-DWITH_SvtEnc_PLUGIN=OFF \
		-DWITH_DAV1D=OFF \
		-DWITH_EXAMPLES=OFF \
		-DCMAKE_CXX_FLAGS="-Wno-error" \
		-DCMAKE_C_FLAGS="-Wno-error" \
	&& cmake --build build --parallel \
	&& DESTDIR="{{ LibrariesPath }}/libheif-cache" cmake --install build \
	&& cd .. \
	&& rm -rf libheif

FROM patches AS libjxl
COPY  --from=lcms2 {{ LibrariesPath }}/lcms2-cache /
COPY  --from=brotli {{ LibrariesPath }}/brotli-cache /
COPY  --from=highway {{ LibrariesPath }}/highway-cache /

RUN git clone -b v0.10.3 --depth=1 {{ GIT }}/libjxl/libjxl.git \
	&& cd libjxl \
	&& git apply ../patches/libjxl.patch \
	&& git submodule update --init --recursive --depth=1 third_party/libjpeg-turbo \
	&& cmake -GNinja -B build . \
		-DCMAKE_BUILD_TYPE=None \
		-DBUILD_SHARED_LIBS=OFF \
		-DBUILD_TESTING=OFF \
		-DJPEGXL_ENABLE_DEVTOOLS=OFF \
		-DJPEGXL_ENABLE_TOOLS=OFF \
		-DJPEGXL_INSTALL_JPEGLI_LIBJPEG=ON \
		-DJPEGXL_ENABLE_DOXYGEN=OFF \
		-DJPEGXL_ENABLE_MANPAGES=OFF \
		-DJPEGXL_ENABLE_BENCHMARK=OFF \
		-DJPEGXL_ENABLE_EXAMPLES=OFF \
		-DJPEGXL_ENABLE_JNI=OFF \
		-DJPEGXL_ENABLE_SJPEG=OFF \
		-DJPEGXL_ENABLE_OPENEXR=OFF \
		-DJPEGXL_ENABLE_SKCMS=OFF \
	&& cmake --build build --parallel \
	&& export DESTDIR="{{ LibrariesPath }}/libjxl-cache" \
	&& cmake --install build \
	&& cp build/lib/libjpegli-static.a $DESTDIR/usr/local/lib64/libjpeg.a \
	&& ar rcs $DESTDIR/usr/local/lib64/libjpeg.a build/lib/CMakeFiles/jpegli-libjpeg-obj.dir/jpegli/libjpeg_wrapper.cc.o \
	&& cd .. \
	&& rm -rf libjxl

FROM builder AS rnnoise
RUN git clone -b master --depth=1 {{ GIT }}/desktop-app/rnnoise.git \
	&& cd rnnoise \
	&& cmake -GNinja -B build . -DCMAKE_BUILD_TYPE=None \
	&& cmake --build build --parallel \
	&& mkdir -p "{{ LibrariesPath }}/rnnoise-cache/usr/local/include" \
	&& cp "include/rnnoise.h" "{{ LibrariesPath }}/rnnoise-cache/usr/local/include/" \
	&& mkdir -p "{{ LibrariesPath }}/rnnoise-cache/usr/local/lib" \
	&& cp "build/librnnoise.a" "{{ LibrariesPath }}/rnnoise-cache/usr/local/lib/" \
	&& cd .. \
	&& rm -rf rnnoise

FROM builder AS xcb-proto
RUN git clone -b xcb-proto-1.16.0 --depth=1 {{ GIT_FREEDESKTOP }}/xcbproto.git \
	&& cd xcbproto \
	&& ./autogen.sh \
	&& make -j$(nproc) \
	&& make DESTDIR="{{ LibrariesPath }}/xcb-proto-cache" install \
	&& cd .. \
	&& rm -rf xcbproto

FROM builder AS xcb
COPY  --from=xcb-proto {{ LibrariesPath }}/xcb-proto-cache /

RUN git clone -b libxcb-1.16 --depth=1 {{ GIT_FREEDESKTOP }}/libxcb.git \
	&& cd libxcb \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="{{ LibrariesPath }}/xcb-cache" install \
	&& cd .. \
	&& rm -rf libxcb

FROM builder AS xcb-wm
RUN git clone -b xcb-util-wm-0.4.2 --depth=1 {{ GIT_FREEDESKTOP }}/libxcb-wm.git \
	&& cd libxcb-wm \
	&& {{ GIT_UPDATE_M4 }} \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="{{ LibrariesPath }}/xcb-wm-cache" install \
	&& cd .. \
	&& rm -rf libxcb-wm

FROM builder AS xcb-util
RUN git clone -b xcb-util-0.4.1 --depth=1 {{ GIT_FREEDESKTOP }}/libxcb-util.git \
	&& cd libxcb-util \
	&& {{ GIT_UPDATE_M4 }} \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="{{ LibrariesPath }}/xcb-util-cache" install \
	&& cd .. \
	&& rm -rf libxcb-util

FROM builder AS xcb-image
COPY  --from=xcb-util {{ LibrariesPath }}/xcb-util-cache /

RUN git clone -b xcb-util-image-0.4.1 --depth=1 {{ GIT_FREEDESKTOP }}/libxcb-image.git \
	&& cd libxcb-image \
	&& {{ GIT_UPDATE_M4 }} \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="{{ LibrariesPath }}/xcb-image-cache" install \
	&& cd .. \
	&& rm -rf libxcb-image

FROM builder AS xcb-keysyms
RUN git clone -b xcb-util-keysyms-0.4.1 --depth=1 {{ GIT_FREEDESKTOP }}/libxcb-keysyms.git \
	&& cd libxcb-keysyms \
	&& {{ GIT_UPDATE_M4 }} \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="{{ LibrariesPath }}/xcb-keysyms-cache" install \
	&& cd .. \
	&& rm -rf libxcb-keysyms

FROM builder AS xcb-render-util
RUN git clone -b xcb-util-renderutil-0.3.10 --depth=1 {{ GIT_FREEDESKTOP }}/libxcb-render-util.git \
	&& cd libxcb-render-util \
	&& {{ GIT_UPDATE_M4 }} \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="{{ LibrariesPath }}/xcb-render-util-cache" install \
	&& cd .. \
	&& rm -rf libxcb-render-util

FROM builder AS xcb-cursor
COPY  --from=xcb-util {{ LibrariesPath }}/xcb-util-cache /
COPY  --from=xcb-image {{ LibrariesPath }}/xcb-image-cache /
COPY  --from=xcb-render-util {{ LibrariesPath }}/xcb-render-util-cache /

RUN git clone -b xcb-util-cursor-0.1.4 --depth=1 {{ GIT_FREEDESKTOP }}/libxcb-cursor.git \
	&& cd libxcb-cursor \
	&& {{ GIT_UPDATE_M4 }} \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="{{ LibrariesPath }}/xcb-cursor-cache" install \
	&& cd .. \
	&& rm -rf libxcb-cursor

FROM builder AS libXext
RUN git clone -b libXext-1.3.5 --depth=1 {{ GIT_FREEDESKTOP }}/libxext.git \
	&& cd libxext \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="{{ LibrariesPath }}/libXext-cache" install \
	&& cd .. \
	&& rm -rf libxext

FROM builder AS libXtst
RUN git clone -b libXtst-1.2.4 --depth=1 {{ GIT_FREEDESKTOP }}/libxtst.git \
	&& cd libxtst \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="{{ LibrariesPath }}/libXtst-cache" install \
	&& cd .. \
	&& rm -rf libxtst

FROM builder AS libXfixes
RUN git clone -b libXfixes-5.0.3 --depth=1 {{ GIT_FREEDESKTOP }}/libxfixes.git \
	&& cd libxfixes \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="{{ LibrariesPath }}/libXfixes-cache" install \
	&& cd .. \
	&& rm -rf libxfixes

FROM builder AS libXv
COPY  --from=libXext {{ LibrariesPath }}/libXext-cache /

RUN git clone -b libXv-1.0.12 --depth=1 {{ GIT_FREEDESKTOP }}/libxv.git \
	&& cd libxv \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="{{ LibrariesPath }}/libXv-cache" install \
	&& cd .. \
	&& rm -rf libxv

FROM builder AS libXrandr
RUN git clone -b libXrandr-1.5.3 --depth=1 {{ GIT_FREEDESKTOP }}/libxrandr.git \
	&& cd libxrandr \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="{{ LibrariesPath }}/libXrandr-cache" install \
	&& cd .. \
	&& rm -rf libxrandr

FROM builder AS libXrender
RUN git clone -b libXrender-0.9.11 --depth=1 {{ GIT_FREEDESKTOP }}/libxrender.git \
	&& cd libxrender \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="{{ LibrariesPath }}/libXrender-cache" install \
	&& cd .. \
	&& rm -rf libxrender

FROM builder AS libXdamage
RUN git clone -b libXdamage-1.1.6 --depth=1 {{ GIT_FREEDESKTOP }}/libxdamage.git \
	&& cd libxdamage \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="{{ LibrariesPath }}/libXdamage-cache" install \
	&& cd .. \
	&& rm -rf libxdamage

FROM builder AS libXcomposite
RUN git clone -b libXcomposite-0.4.6 --depth=1 {{ GIT_FREEDESKTOP }}/libxcomposite.git \
	&& cd libxcomposite \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="{{ LibrariesPath }}/libXcomposite-cache" install \
	&& cd .. \
	&& rm -rf libxcomposite

FROM builder AS wayland
RUN git clone -b 1.19.0 --depth=1 {{ GIT_FREEDESKTOP }}/wayland.git \
	&& cd wayland \
	&& sed -i "/subdir('tests')/d" meson.build \
	&& meson build \
		--buildtype=plain \
		--default-library=both \
		-Ddocumentation=false \
		-Ddtd_validation=false \
		-Dicon_directory=/usr/share/icons \
	&& meson compile -C build \
	&& DESTDIR="{{ LibrariesPath }}/wayland-cache" meson install -C build \
	&& cd .. \
	&& rm -rf wayland

FROM builder AS nv-codec-headers
RUN git clone -b n12.1.14.0 --depth=1 {{ GIT }}/FFmpeg/nv-codec-headers.git \
	&& DESTDIR="{{ LibrariesPath }}/nv-codec-headers-cache" make -C nv-codec-headers install \
	&& rm -rf nv-codec-headers

FROM builder AS ffmpeg
COPY  --from=opus {{ LibrariesPath }}/opus-cache /
COPY  --from=dav1d {{ LibrariesPath }}/dav1d-cache /
COPY  --from=libvpx {{ LibrariesPath }}/libvpx-cache /
COPY  --from=libXext {{ LibrariesPath }}/libXext-cache /
COPY  --from=libXv {{ LibrariesPath }}/libXv-cache /
COPY  --from=nv-codec-headers {{ LibrariesPath }}/nv-codec-headers-cache /

RUN git clone -b n6.1.1 --depth=1 {{ GIT }}/FFmpeg/FFmpeg.git \
	&& cd FFmpeg \
	&& ./configure \
		--extra-cflags="-DCONFIG_SAFE_BITSTREAM_READER=1" \
		--extra-cxxflags="-DCONFIG_SAFE_BITSTREAM_READER=1" \
		--disable-debug \
		--disable-optimizations \
		--disable-inline-asm \
		--disable-programs \
		--disable-doc \
		--disable-network \
		--disable-autodetect \
		--disable-everything \
		--enable-libdav1d \
		--enable-libopus \
		--enable-libvpx \
		--enable-vaapi \
		--enable-vdpau \
		--enable-xlib \
		--enable-libdrm \
		--enable-ffnvcodec \
		--enable-nvdec \
		--enable-cuvid \
		--enable-protocol=file \
		--enable-hwaccel=av1_vaapi \
		--enable-hwaccel=av1_nvdec \
		--enable-hwaccel=h264_vaapi \
		--enable-hwaccel=h264_vdpau \
		--enable-hwaccel=h264_nvdec \
		--enable-hwaccel=hevc_vaapi \
		--enable-hwaccel=hevc_vdpau \
		--enable-hwaccel=hevc_nvdec \
		--enable-hwaccel=mpeg2_vaapi \
		--enable-hwaccel=mpeg2_vdpau \
		--enable-hwaccel=mpeg2_nvdec \
		--enable-hwaccel=mpeg4_vaapi \
		--enable-hwaccel=mpeg4_vdpau \
		--enable-hwaccel=mpeg4_nvdec \
		--enable-hwaccel=vp8_vaapi \
		--enable-hwaccel=vp8_nvdec \
		--enable-decoder=aac \
		--enable-decoder=aac_fixed \
		--enable-decoder=aac_latm \
		--enable-decoder=aasc \
		--enable-decoder=ac3 \
		--enable-decoder=alac \
		--enable-decoder=av1 \
		--enable-decoder=av1_cuvid \
		--enable-decoder=eac3 \
		--enable-decoder=flac \
		--enable-decoder=gif \
		--enable-decoder=h264 \
		--enable-decoder=hevc \
		--enable-decoder=libdav1d \
		--enable-decoder=libvpx_vp8 \
		--enable-decoder=libvpx_vp9 \
		--enable-decoder=mp1 \
		--enable-decoder=mp1float \
		--enable-decoder=mp2 \
		--enable-decoder=mp2float \
		--enable-decoder=mp3 \
		--enable-decoder=mp3adu \
		--enable-decoder=mp3adufloat \
		--enable-decoder=mp3float \
		--enable-decoder=mp3on4 \
		--enable-decoder=mp3on4float \
		--enable-decoder=mpeg4 \
		--enable-decoder=msmpeg4v2 \
		--enable-decoder=msmpeg4v3 \
		--enable-decoder=opus \
		--enable-decoder=pcm_alaw \
		--enable-decoder=pcm_f32be \
		--enable-decoder=pcm_f32le \
		--enable-decoder=pcm_f64be \
		--enable-decoder=pcm_f64le \
		--enable-decoder=pcm_lxf \
		--enable-decoder=pcm_mulaw \
		--enable-decoder=pcm_s16be \
		--enable-decoder=pcm_s16be_planar \
		--enable-decoder=pcm_s16le \
		--enable-decoder=pcm_s16le_planar \
		--enable-decoder=pcm_s24be \
		--enable-decoder=pcm_s24daud \
		--enable-decoder=pcm_s24le \
		--enable-decoder=pcm_s24le_planar \
		--enable-decoder=pcm_s32be \
		--enable-decoder=pcm_s32le \
		--enable-decoder=pcm_s32le_planar \
		--enable-decoder=pcm_s64be \
		--enable-decoder=pcm_s64le \
		--enable-decoder=pcm_s8 \
		--enable-decoder=pcm_s8_planar \
		--enable-decoder=pcm_u16be \
		--enable-decoder=pcm_u16le \
		--enable-decoder=pcm_u24be \
		--enable-decoder=pcm_u24le \
		--enable-decoder=pcm_u32be \
		--enable-decoder=pcm_u32le \
		--enable-decoder=pcm_u8 \
		--enable-decoder=pcm_zork \
		--enable-decoder=vorbis \
		--enable-decoder=vp8 \
		--enable-decoder=wavpack \
		--enable-decoder=wmalossless \
		--enable-decoder=wmapro \
		--enable-decoder=wmav1 \
		--enable-decoder=wmav2 \
		--enable-decoder=wmavoice \
		--enable-encoder=libopus \
		--enable-filter=atempo \
		--enable-parser=aac \
		--enable-parser=aac_latm \
		--enable-parser=flac \
		--enable-parser=gif \
		--enable-parser=h264 \
		--enable-parser=hevc \
		--enable-parser=mpeg4video \
		--enable-parser=mpegaudio \
		--enable-parser=opus \
		--enable-parser=vorbis \
		--enable-demuxer=aac \
		--enable-demuxer=flac \
		--enable-demuxer=gif \
		--enable-demuxer=h264 \
		--enable-demuxer=hevc \
		--enable-demuxer=matroska \
		--enable-demuxer=m4v \
		--enable-demuxer=mov \
		--enable-demuxer=mp3 \
		--enable-demuxer=ogg \
		--enable-demuxer=wav \
		--enable-muxer=ogg \
		--enable-muxer=opus \
	&& make -j$(nproc) \
	&& make DESTDIR="{{ LibrariesPath }}/ffmpeg-cache" install \
	&& cd .. \
	&& rm -rf ffmpeg

FROM builder AS pipewire
RUN git clone -b 0.3.62 --depth=1 {{ GIT }}/PipeWire/pipewire.git \
	&& cd pipewire \
	&& meson build \
		--buildtype=plain \
		-Dtests=disabled \
		-Dexamples=disabled \
		-Dsession-managers=media-session \
		-Dspa-plugins=disabled \
	&& meson compile -C build \
	&& DESTDIR="{{ LibrariesPath }}/pipewire-cache" meson install -C build \
	&& cd .. \
	&& rm -rf pipewire

FROM builder AS openal
COPY  --from=pipewire {{ LibrariesPath }}/pipewire-cache /

RUN git clone -b 1.23.1 --depth=1 {{ GIT }}/kcat/openal-soft.git \
	&& cd openal-soft \
	&& cmake -GNinja -B build . \
		-DCMAKE_BUILD_TYPE=None \
		-DLIBTYPE:STRING=STATIC \
		-DALSOFT_EXAMPLES=OFF \
		-DALSOFT_UTILS=OFF \
		-DALSOFT_INSTALL_CONFIG=OFF \
	&& cmake --build build --parallel \
	&& DESTDIR="{{ LibrariesPath }}/openal-cache" cmake --install build \
	&& cd .. \
	&& rm -rf openal-soft

FROM builder AS openssl
RUN git clone -b openssl-3.2.1 --depth=1 {{ GIT }}/openssl/openssl.git \
	&& cd openssl \
	&& ./config \
		--openssldir=/etc/ssl \
		no-tests \
		no-dso \
	&& make -j$(nproc) \
	&& make DESTDIR="{{ LibrariesPath }}/openssl-cache" install_sw \
	&& cd .. \
	&& rm -rf openssl

FROM builder AS xkbcommon
COPY  --from=xcb {{ LibrariesPath }}/xcb-cache /

RUN git clone -b xkbcommon-1.6.0 --depth=1 {{ GIT }}/xkbcommon/libxkbcommon.git \
	&& cd libxkbcommon \
	&& meson build \
		--buildtype=plain \
		--default-library=both \
		-Denable-docs=false \
		-Denable-wayland=false \
		-Denable-xkbregistry=false \
		-Dxkb-config-root=/usr/share/X11/xkb \
		-Dxkb-config-extra-path=/etc/xkb \
		-Dx-locale-root=/usr/share/X11/locale \
	&& meson compile -C build \
	&& DESTDIR="{{ LibrariesPath }}/xkbcommon-cache" meson install -C build \
	&& cd .. \
	&& rm -rf libxkbcommon

FROM builder AS glib
RUN git clone -b 2.78.1 --depth=1 {{ GIT }}/GNOME/glib.git \
	&& cd glib \
	&& meson build \
		--buildtype=plain \
		--default-library=both \
		-Dtests=false \
		-Dmm-common:use-network=true \
	&& meson compile -C build \
	&& DESTDIR="{{ LibrariesPath }}/glib-cache" meson install -C build \
	&& cd .. \
	&& rm -rf glib

FROM builder AS gobject-introspection
COPY  --from=glib {{ LibrariesPath }}/glib-cache /

RUN git clone -b 1.78.1 --depth=1 {{ GIT }}/GNOME/gobject-introspection.git \
	&& cd gobject-introspection \
	&& meson build --buildtype=plain \
	&& meson compile -C build \
	&& DESTDIR="{{ LibrariesPath }}/gobject-introspection-cache" meson install -C build \
	&& cd .. \
	&& rm -rf gobject-introspection

FROM patches AS qt
COPY  --from=zlib {{ LibrariesPath }}/zlib-cache /
COPY  --from=lcms2 {{ LibrariesPath }}/lcms2-cache /
COPY  --from=libjxl {{ LibrariesPath }}/libjxl-cache /
COPY  --from=xcb {{ LibrariesPath }}/xcb-cache /
COPY  --from=xcb-wm {{ LibrariesPath }}/xcb-wm-cache /
COPY  --from=xcb-util {{ LibrariesPath }}/xcb-util-cache /
COPY  --from=xcb-image {{ LibrariesPath }}/xcb-image-cache /
COPY  --from=xcb-keysyms {{ LibrariesPath }}/xcb-keysyms-cache /
COPY  --from=xcb-render-util {{ LibrariesPath }}/xcb-render-util-cache /
COPY  --from=xcb-cursor {{ LibrariesPath }}/xcb-cursor-cache /
COPY  --from=wayland {{ LibrariesPath }}/wayland-cache /
COPY  --from=openssl {{ LibrariesPath }}/openssl-cache /
COPY  --from=xkbcommon {{ LibrariesPath }}/xkbcommon-cache /
COPY  --from=libwebp {{ LibrariesPath }}/libwebp-cache /

RUN git clone -b {{ QT_TAG }} --depth=1 {{ GIT }}/qt/qt5.git \
	&& cd qt5 \
	&& git submodule update --init --recursive --depth=1 qtbase qtdeclarative qtwayland qtimageformats qtsvg qtshadertools \
	&& cd qtbase \
	&& find ../../patches/qtbase_{{ QT }} -type f -print0 | sort -z | xargs -r0 git apply \
	&& cd ../qtwayland \
	&& find ../../patches/qtwayland_{{ QT }} -type f -print0 | sort -z | xargs -r0 git apply \
	&& cd .. \
	&& echo "int main(int argc, char **argv) { return 0; }" > /usr/src/Libraries/qt5/qtbase/config.tests/x86intrin/main.cpp \
	&& source /opt/rh/gcc-toolset-12/enable \
	&& cmake -GNinja -B build . \
		-DCMAKE_BUILD_TYPE=None \
		-DBUILD_SHARED_LIBS=OFF \
		-DINPUT_libpng=qt \
		-DINPUT_harfbuzz=qt \
		-DINPUT_pcre=qt \
		-DFEATURE_icu=OFF \
		-DFEATURE_xcb_sm=OFF \
		-DINPUT_dbus=runtime \
		-DINPUT_openssl=linked \
		-DCMAKE_CXX_FLAGS=-fno-lto \
		-DCMAKE_C_FLAGS=-fno-lto \
	&& cmake --build build --parallel \
	&& DESTDIR="{{ LibrariesPath }}/qt-cache" cmake --install build \
	&& cd .. \
	&& rm -rf qt5

FROM builder AS breakpad
RUN git clone -b v2023.06.01 --depth=1 https://chromium.googlesource.com/breakpad/breakpad.git \
	&& cd breakpad \
	&& git clone -b v2022.10.12 --depth=1 https://chromium.googlesource.com/linux-syscall-support.git src/third_party/lss \
	&& env -u CFLAGS -u CXXFLAGS ./configure \
	&& make -j$(nproc) \
	&& make DESTDIR="{{ LibrariesPath }}/breakpad-cache" install \
	&& cd .. \
	&& rm -rf breakpad

FROM builder AS webrtc
COPY  --from=opus {{ LibrariesPath }}/opus-cache /
COPY  --from=openh264 {{ LibrariesPath }}/openh264-cache /
COPY  --from=libvpx {{ LibrariesPath }}/libvpx-cache /
COPY  --from=libjxl {{ LibrariesPath }}/libjxl-cache /
COPY  --from=ffmpeg {{ LibrariesPath }}/ffmpeg-cache /
COPY  --from=openssl {{ LibrariesPath }}/openssl-cache /
COPY  --from=libXtst {{ LibrariesPath }}/libXtst-cache /
COPY  --from=pipewire {{ LibrariesPath }}/pipewire-cache /

# Shallow clone on a specific commit.
RUN git init tg_owt \
	&& cd tg_owt \
	&& git remote add origin {{ GIT }}/desktop-app/tg_owt.git \
	&& git fetch --depth=1 origin 4a60ce1ab9fdb962004c6a959f682ace3db50cbd \
	&& git reset --hard FETCH_HEAD \
	&& git submodule update --init --recursive --depth=1 \
	&& rm -rf .git \
	&& sed -i 's/RTC_CHECK_NOTREACHED();//g' /usr/src/Libraries/tg_owt/src/api/video/video_frame_type.h \
	&& source /opt/rh/gcc-toolset-12/enable \
	&& env -u CFLAGS -u CXXFLAGS cmake -G"Ninja Multi-Config" -B out . \
		-DCMAKE_C_FLAGS_RELEASE="$CFLAGS" \
		-DCMAKE_C_FLAGS_DEBUG="{{ CFLAGS_DEBUG }}" \
		-DCMAKE_CXX_FLAGS_RELEASE="$CXXFLAGS" \
		-DCMAKE_CXX_FLAGS_DEBUG="{{ CFLAGS_DEBUG }}" \
		-DTG_OWT_SPECIAL_TARGET=linux \
		-DTG_OWT_LIBJPEG_INCLUDE_PATH=/usr/local/include \
		-DTG_OWT_OPENSSL_INCLUDE_PATH=/usr/local/include \
		-DTG_OWT_OPUS_INCLUDE_PATH=/usr/local/include/opus \
		-DTG_OWT_LIBVPX_INCLUDE_PATH=/usr/local/include \
		-DTG_OWT_OPENH264_INCLUDE_PATH=/usr/local/include \
		-DTG_OWT_FFMPEG_INCLUDE_PATH=/usr/local/include

WORKDIR tg_owt

FROM webrtc AS webrtc_release
RUN cmake --build out --config Release --parallel \
	&& find out -mindepth 1 -maxdepth 1 ! -name Release -exec rm -rf {} \;

{%- if DEBUG %}

FROM webrtc AS webrtc_debug
RUN cmake --build out --config Debug --parallel \
	&& find out -mindepth 1 -maxdepth 1 ! -name Debug -exec rm -rf {} \;
{%- endif %}

FROM builder AS ada
RUN git clone -b v2.9.0 --depth=1 {{ GIT }}/ada-url/ada.git \
	&& cd ada \
	&& cmake -GNinja -B build . \
		-D CMAKE_BUILD_TYPE=None \
        -D ADA_TESTING=OFF \
        -D ADA_TOOLS=OFF \
	&& cmake --build build --parallel \
	&& DESTDIR="{{ LibrariesPath }}/ada-cache" cmake --install build \
	&& cd .. \
	&& rm -rf ada

FROM builder
COPY  --from=zlib {{ LibrariesPath }}/zlib-cache /
COPY  --from=xz {{ LibrariesPath }}/xz-cache /
COPY  --from=protobuf {{ LibrariesPath }}/protobuf-cache /
COPY  --from=lcms2 {{ LibrariesPath }}/lcms2-cache /
COPY  --from=brotli {{ LibrariesPath }}/brotli-cache /
COPY  --from=highway {{ LibrariesPath }}/highway-cache /
COPY  --from=opus {{ LibrariesPath }}/opus-cache /
COPY  --from=dav1d {{ LibrariesPath }}/dav1d-cache /
COPY  --from=openh264 {{ LibrariesPath }}/openh264-cache /
COPY  --from=libde265 {{ LibrariesPath }}/libde265-cache /
COPY  --from=libvpx {{ LibrariesPath }}/libvpx-cache /
COPY  --from=libavif {{ LibrariesPath }}/libavif-cache /
COPY  --from=libheif {{ LibrariesPath }}/libheif-cache /
COPY  --from=libjxl {{ LibrariesPath }}/libjxl-cache /
COPY  --from=rnnoise {{ LibrariesPath }}/rnnoise-cache /
COPY  --from=xcb {{ LibrariesPath }}/xcb-cache /
COPY  --from=xcb-wm {{ LibrariesPath }}/xcb-wm-cache /
COPY  --from=xcb-util {{ LibrariesPath }}/xcb-util-cache /
COPY  --from=xcb-image {{ LibrariesPath }}/xcb-image-cache /
COPY  --from=xcb-keysyms {{ LibrariesPath }}/xcb-keysyms-cache /
COPY  --from=xcb-render-util {{ LibrariesPath }}/xcb-render-util-cache /
COPY  --from=xcb-cursor {{ LibrariesPath }}/xcb-cursor-cache /
COPY  --from=libXext {{ LibrariesPath }}/libXext-cache /
COPY  --from=libXfixes {{ LibrariesPath }}/libXfixes-cache /
COPY  --from=libXv {{ LibrariesPath }}/libXv-cache /
COPY  --from=libXtst {{ LibrariesPath }}/libXtst-cache /
COPY  --from=libXrandr {{ LibrariesPath }}/libXrandr-cache /
COPY  --from=libXrender {{ LibrariesPath }}/libXrender-cache /
COPY  --from=libXdamage {{ LibrariesPath }}/libXdamage-cache /
COPY  --from=libXcomposite {{ LibrariesPath }}/libXcomposite-cache /
COPY  --from=wayland {{ LibrariesPath }}/wayland-cache /
COPY  --from=ffmpeg {{ LibrariesPath }}/ffmpeg-cache /
COPY  --from=openal {{ LibrariesPath }}/openal-cache /
COPY  --from=openssl {{ LibrariesPath }}/openssl-cache /
COPY  --from=xkbcommon {{ LibrariesPath }}/xkbcommon-cache /
COPY  --from=glib {{ LibrariesPath }}/glib-cache /
COPY  --from=gobject-introspection {{ LibrariesPath }}/gobject-introspection-cache /
COPY  --from=qt {{ LibrariesPath }}/qt-cache /
COPY  --from=breakpad {{ LibrariesPath }}/breakpad-cache /
COPY  --from=webrtc {{ LibrariesPath }}/tg_owt tg_owt
COPY  --from=webrtc_release {{ LibrariesPath }}/tg_owt/out/Release tg_owt/out/Release
COPY  --from=libwebp {{ LibrariesPath }}/libwebp-cache /
COPY  --from=ada {{ LibrariesPath }}/ada-cache /

{%- if DEBUG %}
COPY  --from=webrtc_debug {{ LibrariesPath }}/tg_owt/out/Debug tg_owt/out/Debug
{%- endif %}

WORKDIR ../tdesktop
ENV QT {{ QT }}
ENV BOOST_INCLUDEDIR /usr/include/boost1.78
ENV BOOST_LIBRARYDIR /usr/lib64/boost1.78

VOLUME [ "/usr/src/tdesktop" ]
ENTRYPOINT [ "scl", "enable", "gcc-toolset-12", "--" ]
CMD [ "/usr/src/tdesktop/Telegram/build/docker/centos_env/build.sh" ]
