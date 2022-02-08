# Copyright 2016 Dart Mockito authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#!/bin/bash

if [ "$#" == "0" ]; then
  echo -e '\033[31mAt least one task argument must be provided!\033[0m'
  exit 1
fi

EXIT_CODE=0

while (( "$#" )); do
  TASK=$1
  case $TASK in
  dartfmt) echo
    echo -e '\033[1mTASK: dartfmt\033[22m'
    echo -e 'dartfmt -n --set-exit-if-changed .'
    dartfmt -n --set-exit-if-changed . || EXIT_CODE=$?
    ;;
  dartanalyzer) echo
    echo -e '\033[1mTASK: dartanalyzer\033[22m'
    echo -e 'dartanalyzer --fatal-warnings lib'
    dartanalyzer --fatal-warnings lib || EXIT_CODE=$?
    ;;
  vm_test) echo
    echo -e '\033[1mTASK: vm_test\033[22m'
    echo -e 'pub run build_runner test -- -p vm'
    pub run build_runner test -- -p vm || EXIT_CODE=$?
    ;;
  dartdevc_build) echo
    echo -e '\033[1mTASK: build\033[22m'
    echo -e 'pub run build_runner build --fail-on-severe'
    pub run build_runner build --fail-on-severe || EXIT_CODE=$?
    ;;
  dartdevc_test) echo
    echo -e '\033[1mTASK: dartdevc_test\033[22m'
    echo -e 'pub run build_runner test -- -p chrome'
    xvfb-run pub run build_runner test -- -p chrome || EXIT_CODE=$?
    ;;
  coverage) echo
    echo -e '\033[1mTASK: coverage\033[22m'
    if [ "$REPO_TOKEN" ]; then
      echo -e 'pub run dart_coveralls report test/all.dart'
      pub global activate dart_coveralls
      pub global run dart_coveralls report \
        --token $REPO_TOKEN \
        --retry 2 \
        --exclude-test-files \
        test/all.dart
    else
      echo -e "\033[33mNo token for coveralls. Skipping.\033[0m"
    fi
    ;;
  *) echo -e "\033[31mNot expecting TASK '${TASK}'. Error!\033[0m"
    EXIT_CODE=1
    ;;
  esac

  shift
done

exit $EXIT_CODE
