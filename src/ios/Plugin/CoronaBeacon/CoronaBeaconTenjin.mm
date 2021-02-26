//----------------------------------------------------------------------------
// CoronaBeaconTenjin.mm
//
// Copyright (c) 2016 Corona Labs. All rights reserved.
//----------------------------------------------------------------------------

// Import the Plugin library header
#import "CoronaBeaconTenjin.h"

// Apple
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
#import <AdSupport/ASIdentifierManager.h>
#import <sys/utsname.h>

// Corona
#import "CoronaRuntime.h"
#import "CoronaAssert.h"
#import "CoronaEvent.h"
#import "CoronaLua.h"
#import "CoronaLuaIOS.h"
#import "CoronaLibrary.h"

// Constants
const char *CoronaBeaconTenjin::REQUEST = "request";
const char *CoronaBeaconTenjin::IMPRESSION = "impression";
const char *CoronaBeaconTenjin::DELIVERY = "delivery";

// Send device data to the corona beacon
int
CoronaBeaconTenjin::sendDeviceDataToBeacon(lua_State *L, const char *pluginName, const char *pluginVersion, const char *eventType, const char *placementId, int (*networkListener)(lua_State *L))
{
	// Ensure that the plugin name is not null
	if (pluginName == NULL)
	{
		NSLog(@"Warning: CB: Plugin name cannot be null. This should match your plugins name, i.e. plugin.applovin");
		return 0;
	}
	// Ensure that the plugin version is not null
	if (pluginVersion == NULL)
	{
		NSLog(@"Warning: CB: Plugin version cannot be null. This should match your plugins version number, i.e. 1.0");
		return 0;
	}
	// Ensure that the eventType is not null
	if (eventType == NULL)
	{
		NSLog(@"Warning: CB: eventType cannot be null. This should be one of the following strings: request, impression or delivery");
		return 0;
	}

	// Perk FAN Beacon endpoint
	NSString* const perkBeaconApiEndpoint = @"https://monetize-api.coronalabs.com/v1/plugin-beacon.json";

	// Get the system info
	struct utsname systemInfo;
	uname(&systemInfo);

	// Get the display table
	lua_getglobal(L, "display");
	// Get the pixelWidth key
	lua_getfield(L, -1, "pixelWidth");
	// Get the display pixel width
	const int screenPixelWidth = lua_tonumber(L, -1);
	// Pop the pixelWidth key
	lua_pop(L, 1);
	// Get the display pixelHeight key
	lua_getfield(L, -1, "pixelHeight");
	const int screenPixelHeight = lua_tonumber(L, -1);
	// Pop the pixelHeight key & the display table
	lua_pop(L, 2);

	// Store the http header in a dictionary
	const NSDictionary *header = [NSDictionary dictionaryWithObjectsAndKeys:
		[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"], @"app_name",
		[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"], @"app_version",
		[[NSBundle mainBundle] bundleIdentifier], @"app_bundle_id",
		@"apple", @"device_manufacturer",
		[NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding], @"device_model",
		[NSString stringWithFormat:@"%dx%d", screenPixelWidth, screenPixelHeight], @"device_resolution",
		@"iOS", @"os_name",
		[UIDevice currentDevice].systemVersion, @"os_version",
		[[[ASIdentifierManager sharedManager] advertisingIdentifier] UUIDString], @"ios_idfa",
		[[[UIDevice currentDevice] identifierForVendor] UUIDString], @"ios_idfv",
		@"1.0", @"sdk_version",
		@"corona", @"sdk_platform",
		[NSString stringWithUTF8String:pluginName], @"name",
		[NSString stringWithUTF8String:pluginVersion], @"version",
		nil
	];

	// The device info
	NSMutableString *deviceInfo = [NSMutableString stringWithString:@""];
	// Construct the device info string in a format the endpoint requires
	for (id key in header)
	{
		// Format the key value pair to conform with the server requirement
		NSString *keyValue = [NSString stringWithFormat:@"%@=%@;", key, [header objectForKey:key]];
		// Append this key/value pair to the device info string
		[deviceInfo appendString:keyValue];
	}

	// Remove the ";" character from the end of the device info string
	NSString *deviceInfoTruncated = [deviceInfo substringToIndex:[deviceInfo length]-1];
	// Construct the final endpoint
	NSString *endpoint = [NSString stringWithFormat:@"%@%@%s", perkBeaconApiEndpoint, @"?event=", eventType];

	// Add the placementId to the endpoint, if it exists
	if (placementId != NULL)
	{
		endpoint = [NSString stringWithFormat:@"%@%@%s%@%s", perkBeaconApiEndpoint, @"?event=", eventType, @"&placement=", placementId];
	}
	// Call the endpoint via the network.request api
	lua_getglobal(L, "network");
	lua_getfield(L, -1, "request");
	lua_pushstring(L, [endpoint UTF8String]);
	lua_pushstring(L, "POST");
	lua_pushcfunction(L, networkListener);
	lua_newtable(L);
	lua_newtable(L);
	lua_pushstring(L, "application/json");
	lua_setfield(L, -2, "Content-Type");
	lua_pushstring(L, [deviceInfoTruncated UTF8String]);
	lua_setfield(L, -2, "Device-Info");
	lua_setfield(L, -2, "headers");
	lua_call(L, 4, 0);
	lua_pop(L, 1);

	return 0;
}
