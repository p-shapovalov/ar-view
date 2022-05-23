#import "ArPlugin.h"
#if __has_include(<ar/ar-Swift.h>)
#import <ar/ar-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "ar-Swift.h"
#endif

@implementation ArPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftArPlugin registerWithRegistrar:registrar];
}
@end
