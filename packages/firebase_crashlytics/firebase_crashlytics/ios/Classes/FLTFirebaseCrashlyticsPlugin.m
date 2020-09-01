// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "FLTFirebaseCrashlyticsPlugin.h"

#import <Firebase/Firebase.h>
#import <firebase_core/FLTFirebasePluginRegistry.h>

NSString *const kFLTFirebaseCrashlyticsChannelName = @"plugins.flutter.io/firebase_crashlytics";

// Argument Keys
NSString *const kCrashlyticsArgumentException = @"exception";
NSString *const kCrashlyticsArgumentInformation = @"information";
NSString *const kCrashlyticsArgumentStackTraceElements = @"stackTraceElements";
NSString *const kCrashlyticsArgumentContext = @"context";
NSString *const kCrashlyticsArgumentIdentifier = @"identifier";
NSString *const kCrashlyticsArgumentKey = @"key";
NSString *const kCrashlyticsArgumentValue = @"value";

NSString *const kCrashlyticsArgumentFile = @"file";
NSString *const kCrashlyticsArgumentLine = @"line";
NSString *const kCrashlyticsArgumentMethod = @"method";

NSString *const kCrashlyticsArgumentEnabled = @"enabled";
NSString *const kCrashlyticsArgumentUnsentReports = @"unsentReports";
NSString *const kCrashlyticsArgumentDidCrashOnPreviousExecution = @"didCrashOnPreviousExecution";

@interface FLTFirebaseCrashlyticsPlugin ()
@end

@implementation FLTFirebaseCrashlyticsPlugin

#pragma mark - FlutterPlugin

// Returns a singleton instance of the Firebase Crashlytics plugin.
+ (instancetype)sharedInstance {
  static dispatch_once_t onceToken;
  static FLTFirebaseCrashlyticsPlugin *instance;

  dispatch_once(&onceToken, ^{
    instance = [[FLTFirebaseCrashlyticsPlugin alloc] init];
    // Register with the Flutter Firebase plugin registry.
    [[FLTFirebasePluginRegistry sharedInstance] registerFirebasePlugin:instance];
  });

  return instance;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel =
      [FlutterMethodChannel methodChannelWithName:kFLTFirebaseCrashlyticsChannelName
                                  binaryMessenger:[registrar messenger]];
  FLTFirebaseCrashlyticsPlugin *instance = [FLTFirebaseCrashlyticsPlugin sharedInstance];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)flutterResult {
  FLTFirebaseMethodCallErrorBlock errorBlock =
      ^(NSString *_Nullable code, NSString *_Nullable message, NSDictionary *_Nullable details,
        NSError *_Nullable error) {
        // `result.error` is not called in this plugin so this block does nothing.
        flutterResult(nil);
      };

  FLTFirebaseMethodCallResult *methodCallResult =
      [FLTFirebaseMethodCallResult createWithSuccess:flutterResult andErrorBlock:errorBlock];

  if ([@"Crashlytics#recordError" isEqualToString:call.method]) {
    [self recordError:call.arguments withMethodCallResult:methodCallResult];
  } else if ([@"Crashlytics#setUserIdentifier" isEqualToString:call.method]) {
    [self setUserIdentifier:call.arguments withMethodCallResult:methodCallResult];
  } else if ([@"Crashlytics#setCustomKey" isEqualToString:call.method]) {
    [self setCustomKey:call.arguments withMethodCallResult:methodCallResult];
  } else if ([@"Crashlytics#log" isEqualToString:call.method]) {
    [self log:call.arguments withMethodCallResult:methodCallResult];
  } else if ([@"Crashlytics#crash" isEqualToString:call.method]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wall"
    @throw
        [NSException exceptionWithName:@"FirebaseCrashlyticsTestCrash"
                                reason:@"This is a test crash caused by calling .crash() in Dart."
                              userInfo:nil];
#pragma clang diagnostic pop
  } else if ([@"Crashlytics#setCrashlyticsCollectionEnabled" isEqualToString:call.method]) {
    [self setCrashlyticsCollectionEnabled:call.arguments withMethodCallResult:methodCallResult];
  } else if ([@"Crashlytics#checkForUnsentReports" isEqualToString:call.method]) {
    [self checkForUnsentReportsWithMethodCallResult:methodCallResult];
  } else if ([@"Crashlytics#sendUnsentReports" isEqualToString:call.method]) {
    [self sendUnsentReportsWithMethodCallResult:methodCallResult];
  } else if ([@"Crashlytics#deleteUnsentReports" isEqualToString:call.method]) {
    [self deleteUnsentReportsWithMethodCallResult:methodCallResult];
  } else if ([@"Crashlytics#didCrashDuringPreviousExecution" isEqualToString:call.method]) {
    [self didCrashOnPreviousExecutionWithMethodCallResult:methodCallResult];
  } else {
    methodCallResult.success(FlutterMethodNotImplemented);
  }
}

#pragma mark - Firebase Crashlytics API

- (void)recordError:(id)arguments withMethodCallResult:(FLTFirebaseMethodCallResult *)result {
  NSString *context = arguments[kCrashlyticsArgumentContext];
  NSString *information = arguments[kCrashlyticsArgumentInformation];
  NSString *dartExceptionMessage = arguments[kCrashlyticsArgumentException];
  NSArray *errorElements = arguments[kCrashlyticsArgumentStackTraceElements];

  // Log additional information so it's captured on the Firebase Crashlytics dashboard.
  if ([information length] != 0) {
    [[FIRCrashlytics crashlytics] logWithFormat:@"%@", information];
  }

  // Report crash.
  NSMutableArray *frames = [NSMutableArray array];
  for (NSDictionary *errorElement in errorElements) {
    [frames addObject:[self generateFrame:errorElement]];
  }

  NSString *reason;
  if (![context isEqual:[NSNull null]]) {
    reason = [NSString stringWithFormat:@"%@. Error thrown %@.", dartExceptionMessage, context];
    // Log additional custom value to match Android.
    [[FIRCrashlytics crashlytics] setCustomValue:[NSString stringWithFormat:@"thrown %@", context]
                                          forKey:@"flutter_error_reason"];
  } else {
    reason = dartExceptionMessage;
  }

  // Log additional custom value to match Android.
  [[FIRCrashlytics crashlytics] setCustomValue:dartExceptionMessage
                                        forKey:@"flutter_error_exception"];

  FIRExceptionModel *exception = [FIRExceptionModel exceptionModelWithName:@"FlutterError"
                                                                    reason:reason];

  exception.stackTrace = frames;
  [[FIRCrashlytics crashlytics] recordExceptionModel:exception];
  result.success(nil);
}

- (void)setUserIdentifier:(id)arguments withMethodCallResult:(FLTFirebaseMethodCallResult *)result {
  [[FIRCrashlytics crashlytics] setUserID:arguments[kCrashlyticsArgumentIdentifier]];
  result.success(nil);
}

- (void)setCustomKey:(id)arguments withMethodCallResult:(FLTFirebaseMethodCallResult *)result {
  NSString *key = arguments[kCrashlyticsArgumentKey];
  NSString *value = arguments[kCrashlyticsArgumentValue];
  [[FIRCrashlytics crashlytics] setCustomValue:value forKey:key];
  result.success(nil);
}

- (void)log:(id)arguments withMethodCallResult:(FLTFirebaseMethodCallResult *)result {
  NSString *msg = arguments[@"log"];
  [[FIRCrashlytics crashlytics] logWithFormat:@"%@", msg];
  result.success(nil);
}

- (void)setCrashlyticsCollectionEnabled:(id)arguments
                   withMethodCallResult:(FLTFirebaseMethodCallResult *)result {
  BOOL enabled = [arguments[kCrashlyticsArgumentEnabled] boolValue];
  [[FIRCrashlytics crashlytics] setCrashlyticsCollectionEnabled:enabled];
  result.success(@{
    @"isCrashlyticsCollectionEnabled" :
        @([FIRCrashlytics crashlytics].isCrashlyticsCollectionEnabled)
  });
}

- (void)checkForUnsentReportsWithMethodCallResult:(FLTFirebaseMethodCallResult *)result {
  [[FIRCrashlytics crashlytics] checkForUnsentReportsWithCompletion:^(BOOL unsentReports) {
    result.success(@{kCrashlyticsArgumentUnsentReports : @(unsentReports)});
  }];
}

- (void)sendUnsentReportsWithMethodCallResult:(FLTFirebaseMethodCallResult *)result {
  [[FIRCrashlytics crashlytics] sendUnsentReports];
  result.success(nil);
}

- (void)deleteUnsentReportsWithMethodCallResult:(FLTFirebaseMethodCallResult *)result {
  [[FIRCrashlytics crashlytics] deleteUnsentReports];
  result.success(nil);
}

- (void)didCrashOnPreviousExecutionWithMethodCallResult:(FLTFirebaseMethodCallResult *)result {
  BOOL didCrash = [[FIRCrashlytics crashlytics] didCrashDuringPreviousExecution];
  result.success(@{kCrashlyticsArgumentDidCrashOnPreviousExecution : @(didCrash)});
}

#pragma mark - Utilities

- (FIRStackFrame *)generateFrame:(NSDictionary *)errorElement {
  FIRStackFrame *frame = [FIRStackFrame
      stackFrameWithSymbol:[errorElement valueForKey:kCrashlyticsArgumentMethod]
                      file:[errorElement valueForKey:kCrashlyticsArgumentFile]
                      line:[[errorElement valueForKey:kCrashlyticsArgumentLine] intValue]];
  return frame;
}

#pragma mark - FLTFirebasePlugin

- (void)didReinitializeFirebaseCore:(void (^)(void))completion {
  // Not required for this plugin, nothing to cleanup between reloads.
}

- (NSDictionary *_Nonnull)pluginConstantsForFIRApp:(FIRApp *)firebase_app {
  return @{
    @"isCrashlyticsCollectionEnabled" :
        @([FIRCrashlytics crashlytics].isCrashlyticsCollectionEnabled)
  };
}

- (NSString *_Nonnull)firebaseLibraryName {
  return LIBRARY_NAME;
}

- (NSString *_Nonnull)firebaseLibraryVersion {
  return LIBRARY_VERSION;
}

- (NSString *_Nonnull)flutterChannelName {
  return kFLTFirebaseCrashlyticsChannelName;
}

@end
