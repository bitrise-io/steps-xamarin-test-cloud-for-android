#!/bin/bash

THIS_SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

ruby "${THIS_SCRIPTDIR}/step.rb" \
  -s "${xamarin_project}" \
  -t "${xamarin_test_project}" \
  -c "${xamarin_configuration}" \
  -p "${xamarin_platform}" \
  -i "${is_clean_build}" \
  -a "${api_key}" \
  -u "${user}" \
  -d "${devices}" \
  -n "${app_name}" \
  -y "${async}" \
  -e "${category}" \
  -f "${fixture}" \
  -r "${series}" \
  -l "${parallelization}"
