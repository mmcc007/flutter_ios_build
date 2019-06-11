#!/usr/bin/env bash

set -e
set -x

test_dir='tmp'
app_name='flutter_ios_build'
release='untagged-552378777d30e8c93f93'
base_dir=$PWD
app_dir="$base_dir/$test_dir/$app_name-$release"

# download project with signed testable .app and non-testable .ipa
download_test_artifacts(){
  local testable_app='Runner.app'
  local non_testable_ipa='Runner.ipa'
  local project_artifacts_base='https://github.com/mmcc007'
  local app_src_url="$project_artifacts_base/$app_name/archive/$release.zip"
  local testable_app_url="$project_artifacts_base/$app_name/releases/download/$release/$testable_app.zip"
  local non_testable_ipa_url="$project_artifacts_base/$app_name/releases/download/$release/$non_testable_ipa"
  local debug_build_dir='build/ios/Debug-iphoneos'
  local build_dir='build/ios/iphoneos'

  # download and setup app src (with test)
  rm -rf $test_dir
  mkdir $test_dir
  cd $test_dir
  wget $app_src_url
  unzip "$release.zip"

  # download and setup testable .app
  cd "$app_name-$release"
  wget $testable_app_url
  unzip "$testable_app.zip"
  mv $debug_build_dir $build_dir

  # download non-testable .ipa
  wget $non_testable_ipa_url
}

# run test without flutter tools
# note: assumes testable .app already built and installed on device
run_test_custom() {
    local package_name='com.orbsoft.counter'
#    local IOS_BUNDLE=$PWD/build/ios/Debug-iphoneos/Runner.app
    local IOS_BUNDLE='build/ios/iphoneos/Runner.app'
    local device_udid='3b3455019e329e007e67239d9b897148244b5053'

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
    flutter --verbose drive test_driver/main.dart
}

run_test_flutter_no_build() {
    flutter --verbose drive --no-build test_driver/main.dart
}

download_test_artifacts
cd $app_dir
#run_test_custom
#run_test_flutter
run_test_flutter_no_build