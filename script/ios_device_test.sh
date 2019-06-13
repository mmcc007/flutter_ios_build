#!/usr/bin/env bash

set -e
set -x

project_artifacts_base='https://github.com/mmcc007'
app_name='flutter_ios_build'
test_dir='tmp'
base_dir=$PWD
debug_build_dir='build/ios/Debug-iphoneos'
test_build_dir='build/ios/iphoneos'
testable_app='Runner.app'
published_testable_app='Debug_Runner.app.zip'
published_testable_ipa='Debug_Runner.ipa'
published_non_testable_ipa='Release_Runner.ipa'

# area for unpacking
unpack_dir='/tmp/unpack_testable_ipa'

main(){
  # if no arguments passed
  if [[ "$#" -eq 0 ]]; then show_usage; exit 1; fi

  case $1 in
      --download)
          if [[ "$#" -ne 2 ]]; then show_usage; exit 1; fi
          download_project_artifacts $2
          ;;
      --install_app)
          install_testable_app
          ;;
      --install_ipa)
          install_testable_ipa
          ;;
      --resign)
          if [[ "$#" -ne 5 ]]; then show_usage; exit 1; fi
          re-sign $2 "${3}" "${5}"
          ;;
      --test)
          run_test_flutter_no_build
          ;;
      --install_local_ipa)
          # for dev testing
          install_testable_ipa_local .
          ;;
      *)
          show_usage
          exit 1
          ;;
  esac
}

show_usage() {
    local script_name=$(basename "$0")
    printf "\nusage: $script_name [--download <release tag>] [--install_app] [--install_ipa] [--resign <mode> <cert name> <provisioning path>] [--test]
where:
    --download
        downloads the src (with test), signed testable .app, signed testable .ipa,
        and signed non-testable .ipa.
        release tag can be found at $project_artifacts_base/$app_name/releases/latest
    --install_app
        (re)install testable .app
    --install_ipa
        (re)install testable .app from testable .ipa
    --resign
        re-sign and (re)install the testable .app or testable .ipa using local developer account.
        mode is 'app' or 'ipa'
    --test
        runs the integration test using the currently installed testable .app

Sample usage:
$script_name --resign ipa 'iPhone Distribution: Maurice McCabe (ABCDEFGHIJ)' /Users/jenkins/Library/MobileDevice/Provisioning\ Profiles/408fa202-3212-469d-916c-c7f2ae4d083a.mobileprovision
"
}

# download project with signed testable .app and non-testable .ipa
download_project_artifacts(){
  local release_tag=$1

  local non_testable_ipa='Runner.ipa'
  local app_src_url="$project_artifacts_base/$app_name/archive/$release_tag.zip"
  local testable_app_url="$project_artifacts_base/$app_name/releases/download/$release_tag/$published_testable_app"
  local testable_ipa_url="$project_artifacts_base/$app_name/releases/download/$release_tag/$published_testable_ipa"
  local non_testable_ipa_url="$project_artifacts_base/$app_name/releases/download/$release_tag/$published_non_testable_ipa"

  # clear test area
  rm -rf $test_dir
  mkdir $test_dir

  cd $test_dir

  # download app src (with test)
  wget $app_src_url
  unzip "$release_tag.zip"

  # download testable .app
  wget $testable_app_url

  # download testable .ipa
  wget "$testable_ipa_url"

  # download non-testable .ipa
  wget $non_testable_ipa_url
}

# install or re-install from testable .app artifact to build directory
install_testable_app(){
  # clear unpack directory
  clear_unpacking_dir

  unzip "$test_dir/$published_testable_app" -d $unpack_dir

  # install
  refresh_testable_app "$unpack_dir/$testable_app" "$(find_app_dir)"
}

# install or re-install from testable .ipa artifact to build directory
install_testable_ipa(){
  install_testable_ipa_local "$(find_app_dir)"
}

# unpack testable .app from .ipa and install
install_testable_ipa_local(){
  local dst_dir=$1

  # clear unpack directory
  clear_unpacking_dir

  unzip $published_testable_ipa -d $unpack_dir

  # install
  refresh_testable_app "$unpack_dir/Payload/$testable_app" $dst_dir
}

# clear unpacking dir
clear_unpacking_dir() {
  rm -rf $unpack_dir
  mkdir $unpack_dir
}

# clear build dir and install new testable .app
refresh_testable_app() {
  local new_testable_app_dir=$1
  local dst_app_dir=$2
  local dst_test_build_dir="$dst_app_dir/$test_build_dir"

  rm -rf $dst_test_build_dir
  mkdir -p $dst_test_build_dir
  mv $new_testable_app_dir $dst_test_build_dir
}

# re-sign testable .app or testable .ipa with local apple developer account
re-sign(){
  local resign_mode=$1
  local cert_name=$2
  local provisioning_profile_path=$3
  local resigned_app_dir='/tmp/resigned'

  cd $(find_app_dir)

  # todo: re-sign from original artifacts

  # resign testable .app or testable .ipa
  local input_file=''
  local output_file=''
  if [[ "$resign_mode" == 'app' ]]; then
    input_file="$debug_build_dir/$testable_app"
    output_file="$resigned_app_dir/$testable_app"
  else
    input_file="$archived_testable_ipa"
    output_file="$resigned_app_dir/$archived_testable_ipa"
  fi
  rm -rf $resigned_app_dir
  mkdir $resigned_app_dir
  ./script/resign.sh "$input_file" "$cert_name" --provisioning "$provisioning_profile_path" --verbose "$output_file"

  # over-write original testable .app with re-signed testable .app
  rm -rf "$test_build_dir/$testable_app"
  unzip $output_file -d $resigned_app_dir
  mv $resigned_app_dir/Payload/$testable_app $test_build_dir
}

# run test without flutter tools
# assumes testable .app already built
# similar to --no-build
run_test_custom() {
    local package_name='com.orbsoft.counter'
#    local IOS_BUNDLE=$PWD/build/ios/Debug-iphoneos/Runner.app
    local IOS_BUNDLE='build/ios/iphoneos/Runner.app'
    local device_udid='3b3455019e329e007e67239d9b897148244b5053'

    cd $(find_app_dir)

    # kill any running iproxy processes (that are holding local ports open)
    echo "killing any iproxy processes"
    killall iproxy || true # ignore failure if no iproxy processes running

    # uninstall/install app
#    ideviceinstaller -U $package_name
#    ideviceinstaller -i build/ios/iphoneos/Runner.app

    # use apple python for 'six' package used by ios-deploy
    # (in case there is another python installed)
    export PATH=/usr/bin:$PATH

     /usr/bin/env \
       ios-deploy \
       --id $device_udid \
       --bundle $IOS_BUNDLE \
       --no-wifi \
       --justlaunch \
       --args '--enable-dart-profiling --start-paused --enable-checked-mode --verify-entry-points'

#    idevicesyslog | while read LOGLINE
#    do
#        [[ "${LOGLINE}" == *"Observatory"* ]] && echo $LOGLINE && pkill -P $$ tail
#    done

    # wait for observatory
    # note: this method of waiting for the observatory to declare its info may not be reliable
    # as listening to the log may start after the observatory declaration.
    # So far this has not occurred. If it does retry (for now).
    # note 2: the following call leaves an idevicesyslog process running in background
    obs_str=`( idevicesyslog & ) | grep -m 1 "Observatory listening on"`
    obs_port_str=`echo $obs_str | grep -Eo '[^:]*$'`
    obs_port=`echo $obs_port_str | grep -Eo '[0-9]+/'`
    device_port=${obs_port%?} # remove last char
    echo observatory on $device_port

    # forward port
    host_port=1024
#    host_port=4723 # re-use appium server port for now
    echo "forwarding host port $host_port to device port $device_port ..."
    iproxy $host_port $device_port $device_udid
    echo "forwarding succeeded."

    # run test
    flutter packages get
    export VM_SERVICE_URL=http://127.0.0.1:$host_port
    dart test_driver/main_test.dart

}

run_test_flutter() {
  # builds a new testable .app using local cert and prov
  # will install and start it and then run test
  cd $(find_app_dir)
  flutter --verbose drive test_driver/main.dart
}

run_test_flutter_no_build() {
  # expects to find a testable .app in build directory
  # will install and start it and then run test
  cd $(find_app_dir)
  flutter --verbose drive --no-build test_driver/main.dart
}

# find just created app dir
find_app_dir(){
  local app_dir="`find $test_dir -type d -maxdepth 1 -mindepth 1`"
  echo $app_dir
}

main "$@"
