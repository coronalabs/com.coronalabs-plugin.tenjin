# tenjin.logEvent()

> --------------------- ------------------------------------------------------------------------------------------
> __Type__              [Function][api.type.Function]
> __Return value__		none
> __Revision__          [REVISION_LABEL](REVISION_URL)
> __Keywords__          analytics, attribution, Tenjin, logEvent
> __See also__			[tenjin.init()][plugin.tenjin.init]
>						[tenjin.*][plugin.tenjin]
> --------------------- ------------------------------------------------------------------------------------------


## Overview

Sets customer's userId.


## Syntax

	tenjin.setCustomerUserId( userId )

##### userId ~^(required)^~
_[String][api.type.String]._ The userId of the customer.


## Example

``````lua
local tenjin = require( "plugin.tenjin" )

local function tenjinListener( event )
	-- Handle events here
end

-- Initialize plugin
tenjin.init( tenjinListener, { apiKey="YOUR_API_KEY" } )

tenjin.setCustomerUserId( "userId" )
``````
