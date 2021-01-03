#import "TrackerPlugin.h"
#if __has_include(<tracker/tracker-Swift.h>)
#import <tracker/tracker-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "tracker-Swift.h"
#endif

@implementation TrackerPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftTrackerPlugin registerWithRegistrar:registrar];
}
@end
