add_swift_library(swiftMultipeerConnectivity IS_SDK_OVERLAY
  MultipeerConnectivity.swift

  TARGET_SDKS OSX IOS IOS_SIMULATOR
  SWIFT_MODULE_DEPENDS Foundation
  SWIFT_MODULE_DEPENDS_OSX AppKit
  SWIFT_MODULE_DEPENDS_IOS UIKit
  FRAMEWORK_DEPENDS_WEAK MultipeerConnectivity)
