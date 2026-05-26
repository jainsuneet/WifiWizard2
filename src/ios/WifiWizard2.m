#import "WifiWizard2.h"
#include <ifaddrs.h>
#import <net/if.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import <NetworkExtension/NetworkExtension.h>

@implementation WifiWizard2

- (id)fetchSSIDInfo {
    // For iOS 14+, use NEHotspotNetwork.fetchCurrent instead of deprecated CNCopyCurrentNetworkInfo
    NSLog(@"[WifiWizard2] fetchSSIDInfo called");

    if (@available(iOS 14.0, *)) {
        NSLog(@"[WifiWizard2] iOS 14+ detected - returning nil to avoid deprecated API");
        // NEHotspotNetwork.fetchCurrent is the modern API but requires entitlements and location permission
        // Return nil to indicate we should not rely on this for verification on iOS 14+
        return nil;
    } else {
        NSLog(@"[WifiWizard2] iOS 11-13 detected - using legacy CNCopyCurrentNetworkInfo");
        // iOS 11-13: Still use the old method
        NSArray *ifs = (__bridge_transfer NSArray *)CNCopySupportedInterfaces();
        NSLog(@"Supported interfaces: %@", ifs);
        NSDictionary *info;
        for (NSString *ifnam in ifs) {
            info = (__bridge_transfer NSDictionary *)CNCopyCurrentNetworkInfo((__bridge CFStringRef)ifnam);
            NSLog(@"%@ => %@", ifnam, info);
            if (info && [info count]) { break; }
        }
        return info;
    }
}

- (BOOL) isWiFiEnabled {
    // see http://www.enigmaticape.com/blog/determine-wifi-enabled-ios-one-weird-trick
    NSCountedSet * cset = [NSCountedSet new];

    struct ifaddrs *interfaces = NULL;
    // retrieve the current interfaces - returns 0 on success
    int success = getifaddrs(&interfaces);
    if(success == 0){
        for( struct ifaddrs *interface = interfaces; interface; interface = interface->ifa_next) {
            if ( (interface->ifa_flags & IFF_UP) == IFF_UP ) {
                [cset addObject:[NSString stringWithUTF8String:interface->ifa_name]];
            }
        }
    }

    return [cset countForObject:@"awdl0"] > 1 ? YES : NO;
}

- (void)iOSConnectNetwork:(CDVInvokedUrlCommand*)command {

    __block CDVPluginResult *pluginResult = nil;

	NSString * ssidString;
	NSString * passwordString;
	NSDictionary* options = [[NSDictionary alloc]init];

	options = [command argumentAtIndex:0];
	ssidString = [options objectForKey:@"Ssid"];
	passwordString = [options objectForKey:@"Password"];

	if (@available(iOS 11.0, *)) {
	    if (ssidString && [ssidString length]) {
            NSLog(@"[WifiWizard2] iOSConnectNetwork - Attempting to connect to SSID: %@", ssidString);

			NEHotspotConfiguration *configuration = [[NEHotspotConfiguration
				alloc] initWithSSID:ssidString
					passphrase:passwordString
						isWEP:(BOOL)false];

			configuration.joinOnce = false;

            [[NEHotspotConfigurationManager sharedManager] applyConfiguration:configuration completionHandler:^(NSError * _Nullable error) {

                if (error) {
                    // Connection failed
                    NSLog(@"[WifiWizard2] iOSConnectNetwork - Connection FAILED with error: %@", error.description);
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.description];
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                    return;
                }

                // iOS 14+: Trust NEHotspotConfigurationManager result
                // CNCopyCurrentNetworkInfo is deprecated and unreliable, requires location permission
                if (@available(iOS 14.0, *)) {
                    // On iOS 14+, if no error was returned, connection is successful
                    NSLog(@"[WifiWizard2] iOSConnectNetwork - iOS 14+ SUCCESS (trusting NEHotspotConfigurationManager)");
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:ssidString];
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                } else {
                    // iOS 11-13: Verify using the old method
                    NSLog(@"[WifiWizard2] iOSConnectNetwork - iOS 11-13: Verifying connection with legacy method");
                    NSDictionary *r = [self fetchSSIDInfo];
                    NSString *ssid = [r objectForKey:(id)kCNNetworkInfoKeySSID];

                    if ([ssid isEqualToString:ssidString]){
                        NSLog(@"[WifiWizard2] iOSConnectNetwork - iOS 11-13 SUCCESS (verified: %@)", ssid);
                        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:ssidString];
                    } else {
                        NSLog(@"[WifiWizard2] iOSConnectNetwork - iOS 11-13 FAILED (expected: %@, got: %@)", ssidString, ssid);
                        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Connection verification failed"];
                    }
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                }
            }];


		} else {
			pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"SSID Not provided"];
            [self.commandDelegate sendPluginResult:pluginResult
                                        callbackId:command.callbackId];
		}
	} else {
		pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"iOS 11+ not available"];
        [self.commandDelegate sendPluginResult:pluginResult
                                    callbackId:command.callbackId];
	}


}

- (void)iOSConnectOpenNetwork:(CDVInvokedUrlCommand*)command {

    __block CDVPluginResult *pluginResult = nil;

    NSString * ssidString;
    NSDictionary* options = [[NSDictionary alloc]init];

    options = [command argumentAtIndex:0];
    ssidString = [options objectForKey:@"Ssid"];

    if (@available(iOS 11.0, *)) {
        if (ssidString && [ssidString length]) {
            NSLog(@"[WifiWizard2] iOSConnectOpenNetwork - Attempting to connect to open network SSID: %@", ssidString);

            NEHotspotConfiguration *configuration = [[NEHotspotConfiguration
                    alloc] initWithSSID:ssidString];

            configuration.joinOnce = false;

            [[NEHotspotConfigurationManager sharedManager] applyConfiguration:configuration completionHandler:^(NSError * _Nullable error) {

                if (error) {
                    // Connection failed
                    NSLog(@"[WifiWizard2] iOSConnectOpenNetwork - Connection FAILED with error: %@", error.description);
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.description];
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                    return;
                }

                // iOS 14+: Trust NEHotspotConfigurationManager result
                // CNCopyCurrentNetworkInfo is deprecated and unreliable, requires location permission
                if (@available(iOS 14.0, *)) {
                    // On iOS 14+, if no error was returned, connection is successful
                    NSLog(@"[WifiWizard2] iOSConnectOpenNetwork - iOS 14+ SUCCESS (trusting NEHotspotConfigurationManager)");
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:ssidString];
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                } else {
                    // iOS 11-13: Verify using the old method
                    NSLog(@"[WifiWizard2] iOSConnectOpenNetwork - iOS 11-13: Verifying connection with legacy method");
                    NSDictionary *r = [self fetchSSIDInfo];
                    NSString *ssid = [r objectForKey:(id)kCNNetworkInfoKeySSID];

                    if ([ssid isEqualToString:ssidString]){
                        NSLog(@"[WifiWizard2] iOSConnectOpenNetwork - iOS 11-13 SUCCESS (verified: %@)", ssid);
                        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:ssidString];
                    } else {
                        NSLog(@"[WifiWizard2] iOSConnectOpenNetwork - iOS 11-13 FAILED (expected: %@, got: %@)", ssidString, ssid);
                        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Connection verification failed"];
                    }
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                }
            }];


        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"SSID Not provided"];
            [self.commandDelegate sendPluginResult:pluginResult
                                        callbackId:command.callbackId];
        }
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"iOS 11+ not available"];
        [self.commandDelegate sendPluginResult:pluginResult
                                    callbackId:command.callbackId];
    }


}

- (void)iOSDisconnectNetwork:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;

	NSString * ssidString;
	NSDictionary* options = [[NSDictionary alloc]init];

	options = [command argumentAtIndex:0];
	ssidString = [options objectForKey:@"Ssid"];

	if (@available(iOS 11.0, *)) {
	    if (ssidString && [ssidString length]) {
			[[NEHotspotConfigurationManager sharedManager] removeConfigurationForSSID:ssidString];
			pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:ssidString];
		} else {
			pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"SSID Not provided"];
		}
	} else {
		pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"iOS 11+ not available"];
	}

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)getConnectedSSID:(CDVInvokedUrlCommand*)command {
    __block CDVPluginResult *pluginResult = nil;
    NSLog(@"[WifiWizard2] getConnectedSSID called");

    if (@available(iOS 14.0, *)) {
        // iOS 14+: Use NEHotspotNetwork.fetchCurrent
        NSLog(@"[WifiWizard2] getConnectedSSID - Using iOS 14+ NEHotspotNetwork.fetchCurrent API");
        [NEHotspotNetwork fetchCurrentWithCompletionHandler:^(NEHotspotNetwork * _Nullable currentNetwork) {
            if (currentNetwork && currentNetwork.SSID) {
                NSLog(@"[WifiWizard2] getConnectedSSID - iOS 14+ SUCCESS: %@", currentNetwork.SSID);
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:currentNetwork.SSID];
            } else {
                NSLog(@"[WifiWizard2] getConnectedSSID - iOS 14+ FAILED: currentNetwork is nil or no SSID");
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not available"];
            }
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }];
    } else {
        // iOS 11-13: Use legacy method
        NSLog(@"[WifiWizard2] getConnectedSSID - Using iOS 11-13 legacy CNCopyCurrentNetworkInfo");
        NSDictionary *r = [self fetchSSIDInfo];
        NSString *ssid = [r objectForKey:(id)kCNNetworkInfoKeySSID];

        if (ssid && [ssid length]) {
            NSLog(@"[WifiWizard2] getConnectedSSID - iOS 11-13 SUCCESS: %@", ssid);
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:ssid];
        } else {
            NSLog(@"[WifiWizard2] getConnectedSSID - iOS 11-13 FAILED: No SSID available");
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not available"];
        }
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
}

- (void)getConnectedBSSID:(CDVInvokedUrlCommand*)command {
    __block CDVPluginResult *pluginResult = nil;
    NSLog(@"[WifiWizard2] getConnectedBSSID called");

    if (@available(iOS 14.0, *)) {
        // iOS 14+: Use NEHotspotNetwork.fetchCurrent
        NSLog(@"[WifiWizard2] getConnectedBSSID - Using iOS 14+ NEHotspotNetwork.fetchCurrent API");
        [NEHotspotNetwork fetchCurrentWithCompletionHandler:^(NEHotspotNetwork * _Nullable currentNetwork) {
            if (currentNetwork && currentNetwork.BSSID) {
                NSLog(@"[WifiWizard2] getConnectedBSSID - iOS 14+ SUCCESS: %@", currentNetwork.BSSID);
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:currentNetwork.BSSID];
            } else {
                NSLog(@"[WifiWizard2] getConnectedBSSID - iOS 14+ FAILED: currentNetwork is nil or no BSSID");
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not available"];
            }
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }];
    } else {
        // iOS 11-13: Use legacy method
        NSLog(@"[WifiWizard2] getConnectedBSSID - Using iOS 11-13 legacy CNCopyCurrentNetworkInfo");
        NSDictionary *r = [self fetchSSIDInfo];
        NSString *bssid = [r objectForKey:(id)kCNNetworkInfoKeyBSSID];

        if (bssid && [bssid length]) {
            NSLog(@"[WifiWizard2] getConnectedBSSID - iOS 11-13 SUCCESS: %@", bssid);
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:bssid];
        } else {
            NSLog(@"[WifiWizard2] getConnectedBSSID - iOS 11-13 FAILED: No BSSID available");
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not available"];
        }
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
}

- (void)isWifiEnabled:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    NSString *isWifiOn = [self isWiFiEnabled] ? @"1" : @"0";

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:isWifiOn];

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)setWifiEnabled:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)scan:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

// Android functions

- (void)addNetwork:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)removeNetwork:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)androidConnectNetwork:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)androidDisconnectNetwork:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)listNetworks:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)getScanResults:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)startScan:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)disconnect:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)isConnectedToInternet:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)canConnectToInternet:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)canPingWifiRouter:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)canConnectToRouter:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}


@end
