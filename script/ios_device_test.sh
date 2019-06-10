#!/usr/bin/env bash

set -e
set -x

# download project with pre-built testable .app
download_project_with_pre-built_testable_app(){
  local app_url_base='https://github.com/mmcc007'
  local app_name='flutter_ios_build'
  local release='untagged-9cac80b66fcd100c05d3'
  local testable_app='Runner.app'
  local app_src_url="$app_url_base/$app_name/archive/$release.zip"
  local testable_app_url="$app_url_base/$app_name/releases/download/$release/$testable_app.zip"
  local test_dir='tmp'
  local debug_build_dir='build/ios/Debug-iphoneos'
  local build_dir='build/ios/iphoneos'

  rm -rf $test_dir
  mkdir $test_dir
  cd $test_dir
  wget $app_src_url
  unzip "$release.zip"
  cd "$app_name-$release"
  wget $testable_app_url
  unzip "$testable_app.zip"
  mv $debug_build_dir $build_dir
}

# run test without flutter tools
run_test_custom() {
    local package_name='com.orbsoft.counter'
#    local IOS_BUNDLE=$PWD/build/ios/Debug-iphoneos/Runner.app
    local IOS_BUNDLE='build/ios/iphoneos/Runner.app'
    local device_udid='3b3455019e329e007e67239d9b897148244b5053'

    # kill all running iproxy processes (that are holding local ports open)
    echo "killing any iproxy processes"
    killall iproxy || true # ignore failure if no iproxy processes running

    # note: assumes ipa in debug mode already built and installed on device
    # see build_ipa()

    # uninstall/install app
#    ideviceinstaller -U $package_name
#    ideviceinstaller -i build/ios/iphoneos/Runner.app

    # use apple python for 'six' package used by ios-deploy
    # (in case there is another python installed)
    export PATH=/usr/bin:$PATH

#      --id $DEVICE_ID \
#    ios-deploy \
#      --bundle $IOS_BUNDLE \
#      --no-wifi \
#      --justlaunch \
#      --args '--enable-dart-profiling --start-paused --enable-checked-mode --verify-entry-points'

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
    # note 2: this call leaves an idevicesyslog process running in background
    obs_str=`( idevicesyslog & ) | grep -m 1 "Observatory listening on"`
    obs_port_str=`echo $obs_str | grep -Eo '[^:]*$'`
    obs_port=`echo $obs_port_str | grep -Eo '[0-9]+/'`
    device_port=${obs_port%?} # remove last char
    echo observatory on $device_port

    # forward port
    host_port=1024
#    host_port=4723 # re-use appium server port for now
    echo "forwarding device port $device_port to host port $host_port ..."
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


download_project_with_pre-built_testable_app
#run_test_custom
#run_test_flutter
run_test_flutter_no_build