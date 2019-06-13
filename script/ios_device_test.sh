#!/usr/bin/env bash

set -e
set -x

project_artifacts_base='https://github.com/mmcc007'
app_name='flutter_ios_build'
test_dir='tmp'
base_dir=$PWD
debug_build_dir='build/ios/Debug-iphoneos'
build_dir='build/ios/iphoneos'
testable_app='Runner.app'
testable_ipa='Debug_Runner.ipa'

main(){
  # if no arguments passed
  if [[ "$#" -eq 0 ]]; then show_help; fi

  case $1 in
      --download)
          if [[ "$#" -ne 2 ]]; then show_help; fi
          download_test_artifacts $2
          ;;
      --resign)
          if [[ "$#" -ne 4 ]]; then show_help; fi
          re-sign "${2}" "${4}"
          ;;
      --test)
          run_test_flutter_no_build
          ;;
      --unpack)
          unpack_testable_app
          ;;
      *)
          show_help
          ;;
  esac
}

show_help() {
    local script_name=$(basename "$0")
    printf "\nusage: $script_name [--download <release tag>] [--unpack] [--resign <cert name> <provisioning path>] [--test]
where:
    --download
        downloads the src (with test), signed testable .app and signed non-testable .ipa.
        release tag can be found at $project_artifacts_base/$app_name/releases/latest
    --unpack
        unpack and install the testable .ipa
    --resign
        re-signs the testable .app using local developer account
    --test
        runs the integration test

Sample usage:
$script_name --resign 'iPhone Distribution: Maurice McCabe (ABCDEFGHIJ)' /Users/jenkins/Library/MobileDevice/Provisioning\ Profiles/408fa202-3212-469d-916c-c7f2ae4d083a.mobileprovision
"
    exit 1
}

# download project with signed testable .app and non-testable .ipa
download_test_artifacts(){
  local release_tag=$1

  local non_testable_ipa='Runner.ipa'
  local app_src_url="$project_artifacts_base/$app_name/archive/$release_tag.zip"
  local testable_app_url="$project_artifacts_base/$app_name/releases/download/$release_tag/Debug_$testable_app.zip"
  local testable_ipa_url="$project_artifacts_base/$app_name/releases/download/$release_tag/$testable_ipa"
  local non_testable_ipa_url="$project_artifacts_base/$app_name/releases/download/$release_tag/$non_testable_ipa"

  # clear test area
  rm -rf $test_dir
  mkdir $test_dir

  # download and setup app src (with test)
  cd $test_dir
  wget $app_src_url
  unzip "$release_tag.zip"

  # download and setup testable .app
  cd "$app_name-$release_tag"
  wget $testable_app_url
  unzip "$testable_app.zip"
  mkdir $build_dir
  # keep a copy of testable .app for repeated re-signing
  cp -r "$debug_build_dir/$testable_app" $build_dir

  # download testable .ipa
  wget "$testable_ipa_url"

  # download non-testable .ipa
  wget $non_testable_ipa_url
}

# re-sign signed testable .app with local developer account
re-sign(){
  local cert_name=$1
  local provisioning_profile_path=$2
  local resigned_app_dir='/tmp/resigned'

  cd $(find_app_dir)

  # resign testable .app
  rm -rf $resigned_app_dir
  mkdir $resigned_app_dir
  ./script/resign.sh "$debug_build_dir/$testable_app" "$cert_name" --provisioning "$provisioning_profile_path" --verbose "$resigned_app_dir/$testable_app"

  # over-write original testable .app with re-signed testable .app
  rm -rf "$build_dir/$testable_app"
  unzip $resigned_app_dir/$testable_app -d $resigned_app_dir
  mv $resigned_app_dir/Payload/$testable_app $build_dir

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
  flutter_dev --verbose drive --no-build test_driver/main.dart
}

# find just created app dir
find_app_dir(){
  local app_dir="`find $test_dir -type d -maxdepth 1 -mindepth 1`"
  echo $app_dir
}

# unpack testable .app from .ipa and install
unpack_testable_app(){
  local testable_ipa_path='build/ios/Debug-iphoneos/Runner.ipa'
  local unpack_dir='/tmp/unpack_testable_ipa'

  # clear unpack directory
  rm -rf $unpack_dir
  mkdir $unpack_dir

  unzip $testable_ipa_path -d $unpack_dir

  # move to build area
  rm -rf "$build_dir/$testable_app"
  mv $unpack_dir/Payload/$testable_app $build_dir

}

main "$@"
