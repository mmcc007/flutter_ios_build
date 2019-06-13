#!/usr/bin/env bash

set -x
set -e

# run integration test on ios
# used on device clouds

show_help() {
    printf "\n\nusage: $0 [--build] [--test package] [--certs]

Utility for running integration test for pre-installed flutter app on iOS device.
(app must be built in debug mode with 'enableFlutterDriverExtension()')

where:
    --build
        build a debug ipa
        (for install on device in cloud, run locally)
    --certs
        create keychain and import certs
    --help
        print this message
"
    exit 1
}

build_ipa() {
    APP_NAME="Runner"
    SCHEME=$APP_NAME

#    IOS_BUILD_DIR=$PWD/build/ios/Release-iphoneos
    IOS_BUILD_DIR=$PWD/build/ios/Debug-iphoneos
#    CONFIGURATION=Release
    CONFIGURATION=Debug
#    export FLUTTER_BUILD_MODE=Release
    export FLUTTER_BUILD_MODE=Debug
    APP_COMMON_PATH="$IOS_BUILD_DIR/$APP_NAME"
    ARCHIVE_PATH="$APP_COMMON_PATH.xcarchive"


#    flutter build ios -t test_driver/main.dart --release

    flutter clean
#    flutter_dev build ios -t test_driver/main.dart --debug
    flutter build ios -t test_driver/main.dart --debug

    echo "Generating debug archive"
    xcodebuild archive \
      -workspace ios/$APP_NAME.xcworkspace \
      -scheme $SCHEME \
      -sdk iphoneos \
      -configuration $CONFIGURATION \
      -archivePath $ARCHIVE_PATH

#    xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -sdk iphoneos -configuration Release archive -archivePath build/ios/Release-iphoneos/Runner.xcarchive
    #-arch arm64
#    cd ..

    echo "Generating debug .ipa"
    xcodebuild -exportArchive \
      -archivePath $ARCHIVE_PATH \
      -exportOptionsPlist ios/exportOptions.plist \
      -exportPath $IOS_BUILD_DIR

    # build debug version of app
#    flutter clean
#    flutter drive
#    iphoneDir=build/ios/iphoneos
#    cd build/ios/iphoneos
#    mkdir Payload
#    cp -r Runner.app Payload
#    zip -r Runner.ipa Payload
#    cd ios
#    # start from scratch
#    flutter clean
#    # build release version
#    flutter build ios --release
#    # archive
##    export FLUTTER_BUILD_MODE=Release
#    CONFIGURATION=Release
#    rm -rf $PWD/build/ios/Runner.xcarchive
#    xcodebuild -workspace $PWD/ios/Runner.xcworkspace -scheme Runner -sdk iphoneos -configuration $CONFIGURATION archive -archivePath $IOS_BUILD_DIR/Runner.xcarchive
#    # export as ipa
#    xcodebuild -exportArchive -archivePath $IOS_BUILD_DIR/Runner.xcarchive -exportOptionsPlist $PWD/script/exportOptions.plist -exportPath $IOS_BUILD_DIR/Runner.ipa
#    ideviceinstall -i $IOS_BUILD_DIR/Runner.ipa/Runner.ipa

#    rm -rf $IOS_BUILD_DIR/Payload
#    mkdir $IOS_BUILD_DIR/Payload
#    cp -r $IOS_BUILD_DIR/Runner.app $IOS_BUILD_DIR/Payload
#    zip -r $IOS_BUILD_DIR/Runner.ipa $IOS_BUILD_DIR/Payload
}

# import certs
import_certs() {

  local ios_certs_dir='certs'
  local local_key_chain_pass='gaga5.4x'
#  local exported_cert='developer_cert.pem'
  local exported_certs='developer_certs.p12'

  local key_chain_name='device_farm_tmp.keychain'
  local key_chain_pass='devicefarm'

  security create-keychain -p $key_chain_pass $key_chain_name
  security unlock-keychain -p $key_chain_pass $key_chain_name
  security list-keychains -d user -s $key_chain_name # $local_key_chain_name
#  security default-keychain -s buildagent.keychain
  security import "$ios_certs_dir/$exported_certs" -k $key_chain_name -P $local_key_chain_pass -T /usr/bin/codesign
#  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k $key_chain_pass $key_chain_name
#  security delete-certificate -c "iPhone Distribution" $key_chain_name
  security find-identity -v -p codesigning $key_chain_name
}

# if no arguments passed
if [ -z $1 ]; then show_help; fi

case $1 in
    --help)
        show_help
        ;;
    --build)
        build_ipa
        ;;
    --test)
        if [ -z $2 ]; then show_help; fi
        run_test $2
        ;;
    --certs)
        import_certs
        ;;
esac