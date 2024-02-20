#!/bin/bash

## $1 : version
## $2 : destination: a directory or S3 path (eg. s3://...)
## $3 : last revision successfully build

set -euxo pipefail

ROOT=$(pwd)
VERSION="$1"
LAST_REVISION="$3"

if [[ -z "${VERSION}" ]]; then
    echo Please pass a version to this script
    exit
fi

if echo "${VERSION}" | grep 'trunk'; then
    VERSION=trunk-$(date +%Y%m%d)
    URL=https://github.com/google/souper
    BRANCH=main
else
	echo "Versions other than trunk are not currently supported"
	exit 1
fi

FULLNAME=souper-${VERSION}.tar.xz
OUTPUT=${ROOT}/${FULLNAME}
S3OUTPUT=
if [[ $2 =~ ^s3:// ]]; then
    S3OUTPUT=$2
else
    if [[ -d "${2}" ]]; then
        OUTPUT=$2/${FULLNAME}
    else
        OUTPUT=${2-$OUTPUT}
    fi
fi

SOUPER_REVISION=$(git ls-remote --heads ${URL} refs/heads/${BRANCH} | cut -f 1)
REVISION="souper-${SOUPER_REVISION}"

echo "ce-build-revision:${REVISION}"
echo "ce-build-output:${OUTPUT}"

if [[ "${REVISION}" == "${LAST_REVISION}" ]]; then
    echo "ce-build-status:SKIPPED"
    exit
fi

STAGING_DIR=/opt/compiler-explorer/souper-${VERSION}
SUBDIR="$STAGING_DIR"
export PATH=${PATH}:/cmake/bin

rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

rm -rf "${SUBDIR}"
git clone -q --depth 1 --single-branch -b "${BRANCH}" "${URL}" "${SUBDIR}"

pushd "${SUBDIR}"

./build_deps.sh Release

rm -rf \
    third_party/z3 \
    third_party/z3-build \
    third_party/llvm-project \
    third_party/llvm-Release-build

export LD_LIBRARY_PATH="${PWD}/third_party/z3-install/lib:${LD_LIBRARY_PATH}"

cmake \
    -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -B build \
    -S . \
    -DCMAKE_C_COMPILER="${PWD}/third_party/llvm-Release-install/bin/clang" \
    -DCMAKE_CXX_COMPILER="${PWD}/third_party/llvm-Release-install/bin/clang++"

ninja -C build

popd

mv "${SUBDIR}" "${OUTPUT}"

export XZ_DEFAULTS="-T 0"
tar Jcf "${OUTPUT}" --transform "s,^./,./${SUBDIR}/," -C "${STAGING_DIR}" .

if [[ -n "${S3OUTPUT}" ]]; then
    aws s3 cp --storage-class REDUCED_REDUNDANCY "${OUTPUT}" "${S3OUTPUT}"
fi

echo "ce-build-status:OK"
