#!/bin/bash
set -ex
THIS_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

tmp_gopath_dir="$(mktemp -d)"

go_package_name="github.com/bitrise-steplib/steps-xamarin-test-cloud-for-android"
full_package_path="${tmp_gopath_dir}/src/${go_package_name}"
mkdir -p "${full_package_path}"

rsync -avh --quiet "${THIS_SCRIPT_DIR}/" "${full_package_path}/"

export GOPATH="${tmp_gopath_dir}"
export GO15VENDOREXPERIMENT=1
go run "${full_package_path}/main.go"

# #!/bin/bash

# THIS_SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# ruby "${THIS_SCRIPTDIR}/step.rb" \
#   -s "${xamarin_project}" \
#   -c "${xamarin_configuration}" \
#   -p "${xamarin_platform}" \
#   -u "${xamarin_user}" \
#   -a "${test_cloud_api_key}" \
#   -d "${test_cloud_devices}" \
#   -y "${test_cloud_is_async}" \
#   -r "${test_cloud_series}" \
#   -l "${test_cloud_parallelization}" \
#   -g "${sign_parameters}" \
#   -m "${other_parameters}"
