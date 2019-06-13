#!/usr/bin/env bash

set -x
set -e

# run integration test on ios
# used on device clouds

main() {
  # if no arguments passed
  if [ -z $1 ]; then show_help; fi

  case $1 in
    --build)
        build_debug_ipa
        ;;
    --certs)
        import_certs
        ;;
    --help)
        show_help
        ;;
    *)
        show_help
        ;;
  esac
}

show_help() {
    printf "\n\nusage: $0 [--build] [--test package] [--certs] [--help]

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

build_debug_ipa() {
    DEFAULT_APP_NAME="Runner"
    DEBUG_IPA_NAME="Debug_$DEFAULT_APP_NAME.ipa"
    SCHEME=$DEFAULT_APP_NAME

#    IOS_BUILD_DIR=$PWD/build/ios/Release-iphoneos
    IOS_BUILD_DIR=$PWD/build/ios/Debug-iphoneos
#    CONFIGURATION=Release
    CONFIGURATION=Debug
#    export FLUTTER_BUILD_MODE=Release
    #export FLUTTER_BUILD_MODE=Debug
#    APP_COMMON_PATH="$IOS_BUILD_DIR/$DEFAULT_APP_NAME"
    ARCHIVE_PATH="$IOS_BUILD_DIR/$DEFAULT_APP_NAME.xcarchive"


#    flutter build ios -t test_driver/main.dart --release

    flutter clean
    flutter build ios -t test_driver/main.dart --debug

    echo "Generating debug archive"
    xcodebuild archive \
      -workspace ios/$DEFAULT_APP_NAME.xcworkspace \
      -scheme $SCHEME \
      -sdk iphoneos \
      -configuration $CONFIGURATION \
      -archivePath $ARCHIVE_PATH \
      | xcpretty

    echo "Generating debug .ipa"
    xcodebuild -exportArchive \
      -archivePath $ARCHIVE_PATH \
      -exportOptionsPlist ios/exportOptions.plist \
      -exportPath . \
      | xcpretty

    # rename to standardized name
    mv "$DEFAULT_APP_NAME.ipa" "Debug_$DEFAULT_APP_NAME.ipa"

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

main "$@"