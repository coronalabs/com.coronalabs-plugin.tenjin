//----------------------------------------------------------------------------
// CoronaBeaconTenjin.h
//
// Copyright (c) 2016 Corona Labs. All rights reserved.
//----------------------------------------------------------------------------

#ifndef _CoronaBeaconTenjin_H_
#define _CoronaBeaconTenjin_H_

#import "CoronaLua.h"

class CoronaBeaconTenjin
{
	public:
		static const char *REQUEST;
		static const char *IMPRESSION;
		static const char *DELIVERY;

	public:
		static int sendDeviceDataToBeacon(lua_State *L, const char *pluginName, const char *pluginVersion, const char *eventType, const char *placementId, int (*networkListener)(lua_State *L));
};

#endif // _CoronaBeaconTenjin_H_
