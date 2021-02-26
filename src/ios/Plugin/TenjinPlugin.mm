//
//  TenjinPlugin.mm
//  Tenjin Plugin
//
//  Copyright (c) 2016 Corona Labs Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "CoronaRuntime.h"
#import "CoronaAssert.h"
#import "CoronaEvent.h"
#import "CoronaLua.h"
#import "CoronaLibrary.h"
#import "CoronaLuaIOS.h"
#import "AppTrackingTransparency/AppTrackingTransparency.h"

// Tenjin
#import "TenjinPlugin.h"
#import "TenjinSDK.h"

// some macros to make life easier, and code more readable
#define UTF8StringWithFormat(format, ...) [[NSString stringWithFormat:format, ##__VA_ARGS__] UTF8String]
#define UTF8IsEqual(utf8str1, utf8str2) (strcmp(utf8str1, utf8str2) == 0)
#define MsgFormat(format, ...) [NSString stringWithFormat:format, ##__VA_ARGS__]

// used to indicate no data given for a lua_Number since NULL can't be used
#define NO_DATA INT_MAX

// ----------------------------------------------------------------------------
// Plugin Constants
// ----------------------------------------------------------------------------

#define PLUGIN_NAME        "plugin.tenjin"
#define PLUGIN_VERSION     "1.0.9"
#define PLUGIN_SDK_VERSION "1.9.1" // no API function to get SDK version (yet)

static const char EVENT_NAME[]    = "analyticsRequest";
static const char PROVIDER_NAME[] = "tenjin";

// analytics types
static NSString * const TYPE_STANDARD = @"standard";
static NSString * const TYPE_PURCHASE = @"purchase";

// event phases
static NSString * const PHASE_INIT     = @"init";
static NSString * const PHASE_RECORDED = @"recorded";

// message constants
static NSString * const ERROR_MSG   = @"ERROR: ";
static NSString * const WARNING_MSG = @"WARNING: ";

@implementation NSData (HexString)

// ----------------------------------------------------------------------------
// NSData extension to convert hex string to data
// ----------------------------------------------------------------------------

+ (NSData *)dataFromHexString:(NSString *)string
{
	string = [string lowercaseString];
	NSMutableData *data= [NSMutableData new];
	unsigned char whole_byte;
	char byte_chars[3] = {'\0','\0','\0'};
	NSUInteger i = 0;
	NSUInteger length = string.length;
	
	while (i < length-1) {
		char c = [string characterAtIndex:i++];
		
		if (c < '0' || (c > '9' && c < 'a') || c > 'f') {
			continue;
		}
		
		byte_chars[0] = c;
		byte_chars[1] = [string characterAtIndex:i++];
		whole_byte = strtol(byte_chars, NULL, 16);
		[data appendBytes:&whole_byte length:1];
	}
	
	return data;
}

@end

// ----------------------------------------------------------------------------
// plugin class and delegate definitions
// ----------------------------------------------------------------------------

@interface TenjinDelegate: NSObject

@property (nonatomic, assign) CoronaLuaRef coronaListener;             // Reference to the Lua listener
@property (nonatomic, assign) CoronaLuaRef deepLinkListener;           // Reference to deep link listener
@property (nonatomic, assign) id<CoronaRuntime> coronaRuntime;         // Pointer to the Corona runtime

- (void)dispatchLuaEvent:(NSDictionary *)dict forListener:(CoronaLuaRef)listener;

@end

// ----------------------------------------------------------------------------

class TenjinPlugin
{
public:
	typedef TenjinPlugin Self;
	
public:
	static const char kName[];
	
public:
	static int Open(lua_State *L);
	static int Finalizer(lua_State *L);
	static Self *ToLibrary(lua_State *L);
	
protected:
	TenjinPlugin();
	bool Initialize(void *platformContext);
	
public: // plugin API
	static int init(lua_State *L);
	static int logEvent(lua_State *L);
	static int logPurchase(lua_State *L);
	static int getDeepLink(lua_State *L);
	static int updateConversionValue(lua_State *L);
	
private: // internal helper functions
	static void logMsg(lua_State *L, NSString *msgType,  NSString *errorMsg);
	static bool isSDKInitialized(lua_State *L);
	
private:
	NSString *functionSignature;                                  // used in logxxxMsg to identify function
	UIViewController *coronaViewController;                       // application's view controller
	TenjinDelegate *tenjinDelegate;                               // Tenjin delegate
};

const char TenjinPlugin::kName[] = PLUGIN_NAME;

// ----------------------------------------------------------------------------
// helper functions
// ----------------------------------------------------------------------------

// log message to console
void
TenjinPlugin::logMsg(lua_State *L, NSString* msgType, NSString* errorMsg)
{
	Self *context = ToLibrary(L);
	
	if (context) {
		Self& library = *context;
		
		NSString *functionID = [library.functionSignature copy];
		if (functionID.length > 0) {
			functionID = [functionID stringByAppendingString:@", "];
		}
		
		CoronaLuaLogPrefix(L, [msgType UTF8String], UTF8StringWithFormat(@"%@%@", functionID, errorMsg));
	}
}

// check if SDK calls can be made
bool
TenjinPlugin::isSDKInitialized(lua_State *L)
{
	Self *context = ToLibrary(L);
	
	if (context) {
		Self& library = *context;
		
		if (library.tenjinDelegate.coronaListener == NULL) {
			logMsg(L, ERROR_MSG, @"tenjin.init() must be called before calling other API methods.");
			return false;
		}
		
		return true;
	}
	
	return false;
}

// ----------------------------------------------------------------------------
// plugin implementation
// ----------------------------------------------------------------------------

int
TenjinPlugin::Open( lua_State *L )
{
	// Register __gc callback
	const char kMetatableName[] = __FILE__; // Globally unique string to prevent collision
	CoronaLuaInitializeGCMetatable( L, kMetatableName, Finalizer );
	
	void *platformContext = CoronaLuaGetContext(L);
	
	// Set library as upvalue for each library function
	Self *library = new Self;
	
	if (library->Initialize(platformContext)) {
		// Functions in library
		static const luaL_Reg kFunctions[] = {
			{"init", init},
			{"logEvent", logEvent},
			{"logPurchase", logPurchase},
			{"getDeepLink", getDeepLink},
			{"updateConversionValue", updateConversionValue},
			{NULL, NULL}
		};
		
		// Register functions as closures, giving each access to the
		// 'library' instance via ToLibrary()
		{
			CoronaLuaPushUserdata(L, library, kMetatableName);
			luaL_openlib(L, kName, kFunctions, 1); // leave "library" on top of stack
		}
	}
	
	return 1;
}

int
TenjinPlugin::Finalizer( lua_State *L )
{
	Self *library = (Self *)CoronaLuaToUserdata(L, 1);
	
	// Free the Lua listener
	CoronaLuaDeleteRef(L, library->tenjinDelegate.coronaListener);
	
	library->tenjinDelegate = nil;
	
	delete library;
	
	return 0;
}

TenjinPlugin*
TenjinPlugin::ToLibrary( lua_State *L )
{
	// library is pushed as part of the closure
	Self *library = (Self *)CoronaLuaToUserdata( L, lua_upvalueindex( 1 ) );
	return library;
}

TenjinPlugin::TenjinPlugin()
: coronaViewController(nil)
{
}

bool
TenjinPlugin::Initialize( void *platformContext )
{
	bool shouldInit = (! coronaViewController);
	
	if (shouldInit) {
		id<CoronaRuntime> runtime = (__bridge id<CoronaRuntime>)platformContext;
		coronaViewController = runtime.appViewController;
		
		functionSignature = @"";
		
		tenjinDelegate = [TenjinDelegate new];
		tenjinDelegate.coronaRuntime = runtime;
	}
	
	return shouldInit;
}

// [Lua] init(listener, options)
int
TenjinPlugin::init(lua_State *L)
{
	Self *context = ToLibrary(L);
	
	if (! context) { // abort if no valid context
		return 0;
	}
	
	Self& library = *context;
	
	library.functionSignature = @"tenjin.init(listener, options)";
	
	const char *apiKey = NULL;
	bool hasUserConsent = false;
	
	// prevent init from being called twice
	if (library.tenjinDelegate.coronaListener != NULL) {
		logMsg(L, ERROR_MSG, @"init() should only be called once");
		return 0;
	}
	
	// check number or args
	int nargs = lua_gettop(L);
	if (nargs != 2) {
		logMsg(L, ERROR_MSG, MsgFormat(@"Expected 2 arguments, got %d", nargs));
		return 0;
	}
	
	// Get the listener (required)
	if (CoronaLuaIsListener(L, 1, PROVIDER_NAME)) {
		library.tenjinDelegate.coronaListener = CoronaLuaNewRef(L, 1);
	}
	else {
		logMsg(L, ERROR_MSG, MsgFormat(@"Listener expected, got: %s", luaL_typename(L, 1)));
		return 0;
	}
	
	bool registerAppForAdNetworkAttribution = false;
	
	// check for options table (required)
	if (lua_type(L, 2) == LUA_TTABLE) {
		// traverse and validate all the options
		for (lua_pushnil(L); lua_next(L, 2) != 0; lua_pop(L, 1)) {
			const char *key = lua_tostring(L, -2);
			
			// check for appId (required)
			if (UTF8IsEqual(key, "apiKey")) {
				if (lua_type(L, -1) == LUA_TSTRING) {
					apiKey = lua_tostring(L, -1);
				}
				else {
					logMsg(L, ERROR_MSG, MsgFormat(@"options.apiKey (string) expected, got %s", luaL_typename(L, -1)));
					return 0;
				}
			} else if (UTF8IsEqual(key, "hasUserConsent")) {
				if (lua_type(L, -1) == LUA_TBOOLEAN) {
					hasUserConsent = lua_toboolean(L, -1);
				}
				else {
					logMsg(L, ERROR_MSG, MsgFormat(@"options.hasUserConsent (boolean) expected, got: %s", luaL_typename(L, -1)));
					return 0;
				}
			}
			else if (UTF8IsEqual(key, "registerAppForAdNetworkAttribution")) {
				registerAppForAdNetworkAttribution = lua_toboolean(L, -1);
			} else {
				logMsg(L, ERROR_MSG, MsgFormat(@"Invalid option '%s'", key));
				return 0;
			}
		}
	}
	else {
		logMsg(L, ERROR_MSG, MsgFormat(@"options table expected, got %s", luaL_typename(L, 2)));
		return 0;
	}
	
	// check required params
	if (apiKey == NULL) {
		logMsg(L, ERROR_MSG, MsgFormat(@"options.apiKey is required"));
		return 0;
	}
	
	// initialize the SDK
	[TenjinSDK init:@(apiKey)];
	
	if (hasUserConsent) {
		[TenjinSDK optIn];
	} else {
		[TenjinSDK optOut];
	}
	
	if(registerAppForAdNetworkAttribution) {
		[TenjinSDK registerAppForAdNetworkAttribution];
	}
	
	bool noAtt = true;
	if (@available(iOS 14, tvOS 14, *)) {
		if([[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSUserTrackingUsageDescription"]) {
			noAtt = false;
			[ATTrackingManager requestTrackingAuthorizationWithCompletionHandler:^(ATTrackingManagerAuthorizationStatus status) {
				[[NSOperationQueue mainQueue] addOperationWithBlock:^{
					[TenjinSDK connect];
					NSDictionary *coronaEvent = @{
						@(CoronaEventPhaseKey()) : PHASE_INIT
					};
					[library.tenjinDelegate dispatchLuaEvent:coronaEvent forListener:library.tenjinDelegate.coronaListener];
				}];
			}];
		}
	}
	if(noAtt) {
		[TenjinSDK connect];
		NSDictionary *coronaEvent = @{
			@(CoronaEventPhaseKey()) : PHASE_INIT
		};
		[library.tenjinDelegate dispatchLuaEvent:coronaEvent forListener:library.tenjinDelegate.coronaListener];
	}
	
	// log plugin version
	NSLog(@"%s: %s (SDK: %s)", PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_SDK_VERSION);
	
	return 0;
}

// [Lua] getDeepLink(listener)
int
TenjinPlugin::getDeepLink(lua_State *L)
{
	Self *context = ToLibrary(L);
	
	if (! context) { // abort if no valid context
		return 0;
	}
	
	Self& library = *context;
	
	library.functionSignature = @"tenjin.getDeepLink(listener)";
	
	// check number or args
	int nargs = lua_gettop(L);
	if (nargs != 1) {
		logMsg(L, ERROR_MSG, MsgFormat(@"Expected 1 argument, got %d", nargs));
		return 0;
	}
	
	// Get the listener (required)
	if (CoronaLuaIsListener(L, 1, PROVIDER_NAME)) {
		library.tenjinDelegate.deepLinkListener = CoronaLuaNewRef(L, 1);
	}
	else {
		logMsg(L, ERROR_MSG, MsgFormat(@"Listener expected, got: %s", luaL_typename(L, 1)));
		return 0;
	}
	
	[[TenjinSDK sharedInstance] registerDeepLinkHandler:^(NSDictionary *params, NSError *error) {
		if (!error) {
			[library.tenjinDelegate dispatchLuaEvent:params forListener:library.tenjinDelegate.deepLinkListener];
		}
	}];
	
	return 0;
}

// [Lua] getDeepLink(listener)
int
TenjinPlugin::updateConversionValue(lua_State *L)
{
	if (lua_type(L, 1) != LUA_TNUMBER) {
		logMsg(L, ERROR_MSG, MsgFormat(@"updateConversionValue (string) expected, got %s", luaL_typename(L, 1)));
		return 0;
	}
	[TenjinSDK updateConversionValue:(int)lua_tointeger(L, 1)];
	return 0;
}


// [Lua] logEvent(event [, value])
int
TenjinPlugin::logEvent(lua_State *L)
{
	Self *context = ToLibrary(L);
	
	if (! context) { // abort if no valid context
		return 0;
	}
	
	Self& library = *context;
	
	library.functionSignature = @"tenjin.logEvent(event [, value])";
	
	if (! isSDKInitialized(L)) {
		return 0;
	}
	
	const char *eventName = NULL;
	lua_Number eventValue = NO_DATA;
	
	// check number or args
	int nargs = lua_gettop(L);
	if (nargs < 1 || nargs > 2) {
		logMsg(L, ERROR_MSG, MsgFormat(@"Expected 1 or 2 arguments, got %d", nargs));
		return 0;
	}
	
	// get event name
	if (lua_type(L, 1) == LUA_TSTRING) {
		eventName = lua_tostring(L, 1);
	}
	else {
		logMsg(L, ERROR_MSG, MsgFormat(@"eventName (string) expected, got %s", luaL_typename(L, 1)));
		return 0;
	}
	
	// get event value
	if (! lua_isnoneornil(L, 2)) {
		if (lua_type(L, 2) == LUA_TNUMBER) {
			eventValue = lua_tonumber(L, 2);
		}
		else {
			logMsg(L, ERROR_MSG, MsgFormat(@"eventValue (number) expected, got %s", luaL_typename(L, 2)));
			return 0;
		}
	}
	
	// send event to Tenjin
	if (eventValue != NO_DATA) {
		[TenjinSDK sendEventWithName:@(eventName) andEventValue:[NSString stringWithFormat:@"%d", (int)eventValue]];
	}
	else {
		[TenjinSDK sendEventWithName:@(eventName)];
	}
	
	// send Corona Lua event
	NSDictionary *coronaEvent = @{
		@(CoronaEventPhaseKey()) : PHASE_RECORDED,
		@(CoronaEventTypeKey()) : TYPE_STANDARD
	};
	[library.tenjinDelegate dispatchLuaEvent:coronaEvent forListener:library.tenjinDelegate.coronaListener];
	
	return 0;
}

// [Lua] logPurchase(productData [, receiptData])
int
TenjinPlugin::logPurchase(lua_State *L)
{
	Self *context = ToLibrary(L);
	
	if (! context) { // abort if no valid context
		return 0;
	}
	
	Self& library = *context;
	
	library.functionSignature = @"tenjin.logPurchase(productData [, receiptData])";
	
	if (! isSDKInitialized(L)) {
		return 0;
	}
	
	const char *productId = NULL;
	const char *currencyCode = NULL;
	const char *transactionId = NULL;
	const char *receipt = NULL;
	lua_Number quantity = NO_DATA;
	lua_Number unitPrice = NO_DATA;
	
	// check number or args
	int nargs = lua_gettop(L);
	if (nargs < 1 || nargs > 2) {
		logMsg(L, ERROR_MSG, MsgFormat(@"Expected 1 or 2 arguments, got %d", nargs));
		return 0;
	}
	
	// check for productData table (required)
	if (lua_type(L, 1) == LUA_TTABLE) {
		// traverse and validate all the options
		for (lua_pushnil(L); lua_next(L, 1) != 0; lua_pop(L, 1)) {
			const char *key = lua_tostring(L, -2);
			
			if (UTF8IsEqual(key, "productId")) {
				if (lua_type(L, -1) == LUA_TSTRING) {
					productId = lua_tostring(L, -1);
				}
				else {
					logMsg(L, ERROR_MSG, MsgFormat(@"productData.productId (string) expected, got %s", luaL_typename(L, -1)));
					return 0;
				}
			}
			else if (UTF8IsEqual(key, "currencyCode")) {
				if (lua_type(L, -1) == LUA_TSTRING) {
					currencyCode = lua_tostring(L, -1);
				}
				else {
					logMsg(L, ERROR_MSG, MsgFormat(@"productData.currencyCode (string) expected, got %s", luaL_typename(L, -1)));
					return 0;
				}
			}
			else if (UTF8IsEqual(key, "quantity")) {
				if (lua_type(L, -1) == LUA_TNUMBER) {
					quantity = lua_tonumber(L, -1);
				}
				else {
					logMsg(L, ERROR_MSG, MsgFormat(@"productData.quantity (number) expected, got %s", luaL_typename(L, -1)));
					return 0;
				}
			}
			else if (UTF8IsEqual(key, "unitPrice")) {
				if (lua_type(L, -1) == LUA_TNUMBER) {
					unitPrice = lua_tonumber(L, -1);
				}
				else {
					logMsg(L, ERROR_MSG, MsgFormat(@"productData.unitPrice (string) expected, got %s", luaL_typename(L, -1)));
					return 0;
				}
			}
			else {
				logMsg(L, ERROR_MSG, MsgFormat(@"Invalid option '%s'", key));
				return 0;
			}
		}
	}
	else {
		logMsg(L, ERROR_MSG, MsgFormat(@"productData table expected, got %s", luaL_typename(L, 1)));
		return 0;
	}
	
	// get receipt data (optional)
	if (! lua_isnoneornil(L, 2)) {
		if (lua_type(L, 2) == LUA_TTABLE) {
			// traverse and validate all the options
			for (lua_pushnil(L); lua_next(L, 2) != 0; lua_pop(L, 1)) {
				const char *key = lua_tostring(L, -2);
				
				if (UTF8IsEqual(key, "transactionId")) {
					if (lua_type(L, -1) == LUA_TSTRING) {
						transactionId = lua_tostring(L, -1);
					}
					else {
						logMsg(L, ERROR_MSG, MsgFormat(@"receiptData.transactionId (string) expected, got %s", luaL_typename(L, -1)));
						return 0;
					}
				}
				else if (UTF8IsEqual(key, "signature")) {
					// signature only used on Android (type check only here)
					if (lua_type(L, -1) != LUA_TSTRING) {
						logMsg(L, ERROR_MSG, MsgFormat(@"receiptData.signature (string) expected, got %s", luaL_typename(L, -1)));
						return 0;
					}
				}
				else if (UTF8IsEqual(key, "receipt")) {
					if (lua_type(L, -1) == LUA_TSTRING) {
						receipt = lua_tostring(L, -1);
					}
					else {
						logMsg(L, ERROR_MSG, MsgFormat(@"receiptData.receipt (string) expected, got %s", luaL_typename(L, -1)));
						return 0;
					}
				}
				else {
					logMsg(L, ERROR_MSG, MsgFormat(@"Invalid option '%s'", key));
					return 0;
				}
			}
		}
		else {
			logMsg(L, ERROR_MSG, MsgFormat(@"receiptData table expected, got %s", luaL_typename(L, 2)));
			return 0;
		}
	}
	
	// validate productId
	if (productId == NULL) {
		logMsg(L, ERROR_MSG, MsgFormat(@"productData.productId required"));
		return 0;
	}
	
	// validate currencyCode
	if (currencyCode == NULL) {
		logMsg(L, ERROR_MSG, MsgFormat(@"productData.currencyCode required"));
		return 0;
	}
	
	// validate quantity
	if (quantity == NO_DATA) {
		logMsg(L, ERROR_MSG, MsgFormat(@"productData.quantity required"));
		return 0;
	}
	
	// validate unitPrice
	if (unitPrice == NO_DATA) {
		logMsg(L, ERROR_MSG, MsgFormat(@"productData.unitPrice required"));
		return 0;
	}
	
	// validate receipt / transactionId
	if ((transactionId != NULL) || (receipt != NULL)) {
		if (receipt == NULL) {
			logMsg(L, ERROR_MSG, MsgFormat(@"receiptData.receipt required"));
			return 0;
		}
		
		if (transactionId == NULL) {
			logMsg(L, ERROR_MSG, MsgFormat(@"receiptData.transactionId required "));
			return 0;
		}
	}
	
	// send event to Tenjin
	if (transactionId != NULL) {
		[TenjinSDK transactionWithProductName:@(productId)
							  andCurrencyCode:@(currencyCode).uppercaseString
								  andQuantity:(int)quantity
								 andUnitPrice:[[NSDecimalNumber alloc] initWithDouble:unitPrice]
							 andTransactionId:@(transactionId)
								   andReceipt:[NSData dataFromHexString:@(receipt)]
		 ];
	}
	else {
		[TenjinSDK transactionWithProductName:@(productId)
							  andCurrencyCode:@(currencyCode).uppercaseString
								  andQuantity:(int)quantity
								 andUnitPrice:[[NSDecimalNumber alloc] initWithDouble:unitPrice]
		 ];
	}
	
	// send Corona Lua event
	NSDictionary *coronaEvent = @{
		@(CoronaEventPhaseKey()) : PHASE_RECORDED,
		@(CoronaEventTypeKey()) : TYPE_PURCHASE
	};
	[library.tenjinDelegate dispatchLuaEvent:coronaEvent forListener:library.tenjinDelegate.coronaListener];
	
	return 0;
}

// ============================================================================
// delegate implementation
// ============================================================================

@implementation TenjinDelegate

- (instancetype)init {
	if (self = [super init]) {
		self.coronaListener = NULL;
		self.coronaRuntime = NULL;
	}
	
	return self;
}

// dispatch a new Lua event
- (void)dispatchLuaEvent:(NSDictionary *)dict forListener:(CoronaLuaRef)listener
{
	[[NSOperationQueue mainQueue] addOperationWithBlock:^{
		lua_State *L = self.coronaRuntime.L;
		CoronaLuaRef coronaListener = listener;
		bool hasErrorKey = false;
		
		// create new event
		CoronaLuaNewEvent(L, EVENT_NAME);
		
		for (NSString *key in dict) {
			CoronaLuaPushValue(L, [dict valueForKey:key]);
			lua_setfield(L, -2, key.UTF8String);
			
			if (! hasErrorKey) {
				hasErrorKey = [key isEqualToString:@(CoronaEventIsErrorKey())];
			}
		}
		
		// add error key if not in dict
		if (! hasErrorKey) {
			lua_pushboolean(L, false);
			lua_setfield(L, -2, CoronaEventIsErrorKey());
		}
		
		// add provider
		lua_pushstring(L, PROVIDER_NAME );
		lua_setfield(L, -2, CoronaEventProviderKey());
		
		CoronaLuaDispatchEvent(L, coronaListener, 0);
	}];
}

@end

// ----------------------------------------------------------------------------

CORONA_EXPORT int luaopen_plugin_tenjin(lua_State *L)
{
	return TenjinPlugin::Open(L);
}
