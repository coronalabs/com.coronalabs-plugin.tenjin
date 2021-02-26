//
// LuaLoader.java
// Tenjin Plugin
//
// Copyright (c) 2016 CoronaLabs inc. All rights reserved.
//

package plugin.tenjin;

import com.ansca.corona.CoronaActivity;
import com.ansca.corona.CoronaLua;
import com.ansca.corona.CoronaLuaEvent;
import com.ansca.corona.CoronaRuntimeTask;
import com.ansca.corona.CoronaRuntimeTaskDispatcher;
import com.ansca.corona.CoronaEnvironment;
import com.ansca.corona.CoronaRuntime;
import com.ansca.corona.CoronaRuntimeListener;
import com.ansca.corona.CoronaBeacon;

import com.naef.jnlua.LuaState;
import com.naef.jnlua.JavaFunction;
import com.naef.jnlua.LuaType;
import com.naef.jnlua.NamedJavaFunction;

import java.util.HashMap;
import java.util.Map;

import android.os.Handler;
import android.util.Log;

// plugin imports
import com.tenjin.android.TenjinSDK;
import com.tenjin.android.Callback;


/**
 * Implements the Lua interface for the Tenjin Plugin.
 * <p>
 * Only one instance of this class will be created by Corona for the lifetime of the application.
 * This instance will be re-used for every new Corona activity that gets created.
 */
public class LuaLoader implements JavaFunction, CoronaRuntimeListener {
    private static final String PLUGIN_NAME = "plugin.tenjin";
    private static final String PLUGIN_VERSION = "1.1.2";
    private static final String PLUGIN_SDK_VERSION = "1.8.7"; // no API function to get SDK version (yet)

    private static final String EVENT_NAME = "analyticsRequest";
    private static final String PROVIDER_NAME = "tenjin";

    // analytics types
    private static final String TYPE_STANDARD = "standard";
    private static final String TYPE_PURCHASE = "purchase";

    // event phases
    private static final String PHASE_INIT = "init";
    private static final String PHASE_RECORDED = "recorded";

    // message constants
    private static final String CORONA_TAG = "Corona";
    private static final String ERROR_MSG = "ERROR: ";
    private static final String WARNING_MSG = "WARNING: ";

    // add missing keys
    private static final String EVENT_PHASE_KEY = "phase";
    private static final String EVENT_TYPE_KEY = "type";
    private static final String EVENT_DATA_KEY = "data";

    private static int coronaListener = CoronaLua.REFNIL;
    private static int deepLinkListener = CoronaLua.REFNIL;
    private static CoronaRuntimeTaskDispatcher coronaRuntimeTaskDispatcher = null;

    private static String functionSignature = "";
    private static final Map<String, Object> tenjinObjects = new HashMap<>();  // keep track of loaded objects
    private static double NO_DATA = Integer.MAX_VALUE;

    // object dictionary keys
    private static final String DEVELOPER_API_KEY = "apiKey";
    private static final String TENJIN_INSTANCE = "tenjinInstance";

    // -------------------------------------------------------
    // Plugin lifecycle events
    // -------------------------------------------------------

    /**
     * <p>
     * Note that a new LuaLoader instance will not be created for every CoronaActivity instance.
     * That is, only one instance of this class will be created for the lifetime of the application process.
     * This gives a plugin the option to do operations in the background while the CoronaActivity is destroyed.
     */
    @SuppressWarnings("unused")
    public LuaLoader() {
        // Set up this plugin to listen for Corona runtime events to be received by methods
        // onLoaded(), onStarted(), onSuspended(), onResumed(), and onExiting().

        CoronaEnvironment.addRuntimeListener(this);
    }

    /**
     * Called when this plugin is being loaded via the Lua require() function.
     * <p>
     * Note that this method will be called every time a new CoronaActivity has been launched.
     * This means that you'll need to re-initialize this plugin here.
     * <p>
     * Warning! This method is not called on the main UI thread.
     *
     * @param L Reference to the Lua state that the require() function was called from.
     * @return Returns the number of values that the require() function will return.
     * <p>
     * Expected to return 1, the library that the require() function is loading.
     */
    @Override
    public int invoke(LuaState L) {
        // Register this plugin into Lua with the following functions.
        NamedJavaFunction[] luaFunctions = new NamedJavaFunction[]{
                new Init(),
                new LogEvent(),
                new LogPurchase(),
                new GetDeepLink(),
                new NamedJavaFunction() {
                    @Override
                    public String getName() {
                        return "updateConversionValue";
                    }

                    @Override
                    public int invoke(LuaState luaState) {
                        return 0;
                    }
                }
        };
        String libName = L.toString(1);
        L.register(libName, luaFunctions);

        // Returning 1 indicates that the Lua require() function will return the above Lua library
        return 1;
    }

    /**
     * Called after the Corona runtime has been created and just before executing the "main.lua" file.
     * <p>
     * Warning! This method is not called on the main thread.
     *
     * @param runtime Reference to the CoronaRuntime object that has just been loaded/initialized.
     *                Provides a LuaState object that allows the application to extend the Lua API.
     */
    @Override
    public void onLoaded(CoronaRuntime runtime) {
        // Note that this method will not be called the first time a Corona activity has been launched.
        // This is because this listener cannot be added to the CoronaEnvironment until after
        // this plugin has been required-in by Lua, which occurs after the onLoaded() event.
        // However, this method will be called when a 2nd Corona activity has been created.

        if (coronaRuntimeTaskDispatcher == null) {
            coronaRuntimeTaskDispatcher = new CoronaRuntimeTaskDispatcher(runtime);
        }
    }

    /**
     * Called just after the Corona runtime has executed the "main.lua" file.
     * <p>
     * Warning! This method is not called on the main thread.
     *
     * @param runtime Reference to the CoronaRuntime object that has just been started.
     */
    @Override
    public void onStarted(CoronaRuntime runtime) {
    }

    /**
     * Called just after the Corona runtime has been suspended which pauses all rendering, audio, timers,
     * and other Corona related operations. This can happen when another Android activity (ie: window) has
     * been displayed, when the screen has been powered off, or when the screen lock is shown.
     * <p>
     * Warning! This method is not called on the main thread.
     *
     * @param runtime Reference to the CoronaRuntime object that has just been suspended.
     */
    @Override
    public void onSuspended(CoronaRuntime runtime) {
    }

    /**
     * Called just after the Corona runtime has been resumed after a suspend.
     * <p>
     * Warning! This method is not called on the main thread.
     *
     * @param runtime Reference to the CoronaRuntime object that has just been resumed.
     */
    @Override
    public void onResumed(CoronaRuntime runtime) {
        final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();

        if (coronaActivity != null) {
            Runnable runnableActivity = new Runnable() {
                public void run() {
                    // initialize the SDK
                    TenjinSDK instance = TenjinSDK.getInstance(coronaActivity, (String) tenjinObjects.get(DEVELOPER_API_KEY));
                    if (instance != null) {
                        instance.connect();
                    }
                }
            };

            // Run the activity on the UI thread
            coronaActivity.runOnUiThread(runnableActivity);
        }
    }

    /**
     * Called just before the Corona runtime terminates.
     * <p>
     * This happens when the Corona activity is being destroyed which happens when the user presses the Back button
     * on the activity, when the native.requestExit() method is called in Lua, or when the activity's finish()
     * method is called. This does not mean that the application is exiting.
     * <p>
     * Warning! This method is not called on the main thread.
     *
     * @param runtime Reference to the CoronaRuntime object that is being terminated.
     */
    @Override
    public void onExiting(final CoronaRuntime runtime) {
        // reset class variables
        CoronaLua.deleteRef(runtime.getLuaState(), coronaListener);
        CoronaLua.deleteRef(runtime.getLuaState(), deepLinkListener);
        coronaListener = CoronaLua.REFNIL;
        deepLinkListener = CoronaLua.REFNIL;

        tenjinObjects.clear();
        coronaRuntimeTaskDispatcher = null;
        functionSignature = "";
    }

    // --------------------------------------------------------------------------
    // helper functions
    // --------------------------------------------------------------------------

    // log message to console
    private void logMsg(String msgType, String errorMsg) {
        String functionID = functionSignature;
        if (!functionID.isEmpty()) {
            functionID += ", ";
        }

        Log.i(CORONA_TAG, msgType + functionID + errorMsg);
    }

    // return true if SDK is properly initialized
    private boolean isSDKInitialized() {
        if (coronaListener == CoronaLua.REFNIL) {
            logMsg(ERROR_MSG, "tenjin.init() must be called before calling other API functions");
            return false;
        }

        return true;
    }

    // dispatch a Lua event to our callback (dynamic handling of properties through map)
    private void dispatchLuaEvent(final Map<String, String> event, final int listener) {
        final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();

        if (coronaActivity == null) { // bail if no valid activity
            return;
        }

        // Create a new runnable object to invoke our activity
        Runnable runnableActivity = new Runnable() {
            public void run() {
                coronaRuntimeTaskDispatcher.send(new CoronaRuntimeTask() {
                    public void executeUsing(CoronaRuntime runtime) {
                        try {
                            LuaState L = runtime.getLuaState();
                            CoronaLua.newEvent(L, EVENT_NAME);
                            boolean hasErrorKey = false;

                            // add event parameters from map
                            for (String key : event.keySet()) {
                                CoronaLua.pushValue(L, event.get(key));           // push value
                                L.setField(-2, key);                              // push key

                                if (!hasErrorKey) {
                                    hasErrorKey = key.equals(CoronaLuaEvent.ISERROR_KEY);
                                }
                            }

                            // add error key if not in map
                            if (!hasErrorKey) {
                                L.pushBoolean(false);
                                L.setField(-2, CoronaLuaEvent.ISERROR_KEY);
                            }

                            // add provider
                            L.pushString(PROVIDER_NAME);
                            L.setField(-2, CoronaLuaEvent.PROVIDER_KEY);

                            CoronaLua.dispatchEvent(L, listener, 0);
                        } catch (Exception ex) {
                            ex.printStackTrace();
                        }
                    }
                });
            }
        };

        // Run the activity on the UI thread
        coronaActivity.runOnUiThread(runnableActivity);
    }

    // Corona beacon listener
    private class BeaconListener implements JavaFunction {
        // This method is executed when the Lua function is called
        @Override
        public int invoke(LuaState L) {
            // NOP (Debugging purposes only)
            // Listener called but the function body should be empty for public release
            return 0;
        }
    }

    // Corona beacon wrapper
    private void
    sendToBeacon(final String eventType, final String placementID) {
        final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();

        // ignore if invalid activity
        if (coronaActivity != null) {
            // Create a new runnable object to invoke our activity
            Runnable runnableActivity = new Runnable() {
                public void run() {
                    CoronaBeacon.sendDeviceDataToBeacon(coronaRuntimeTaskDispatcher, PLUGIN_NAME, PLUGIN_VERSION, eventType, placementID, new BeaconListener());
                }
            };

            coronaActivity.runOnUiThread(runnableActivity);
        }
    }
    // -------------------------------------------------------
    // plugin implementation
    // -------------------------------------------------------

    // [Lua] init(listener, options)
    private class Init implements NamedJavaFunction {
        /**
         * Gets the name of the Lua function as it would appear in the Lua script.
         *
         * @return Returns the name of the custom Lua function.
         */
        @Override
        public String getName() {
            return "init";
        }

        /**
         * This method is called when the Lua function is called.
         * <p>
         * Warning! This method is not called on the main UI thread.
         *
         * @param luaState Reference to the Lua state.
         *                 Needed to retrieve the Lua function's parameters and to return values back to Lua.
         * @return Returns the number of values to be returned by the Lua function.
         */
        @Override
        public int invoke(final LuaState luaState) {
            functionSignature = "tenjin.init(listener, options)";

            String apiKey = null;
            boolean hasUserConsent = false;

            // prevent init from being called twice
            if (coronaListener != CoronaLua.REFNIL) {
                logMsg(ERROR_MSG, "init() should only be called once");
                return 0;
            }

            // check number or args
            int nargs = luaState.getTop();
            if (nargs != 2) {
                logMsg(ERROR_MSG, "Expected 2 arguments, got " + nargs);
                return 0;
            }

            // Get the listener (required)
            if (CoronaLua.isListener(luaState, 1, PROVIDER_NAME)) {
                coronaListener = CoronaLua.newRef(luaState, 1);
            } else {
                logMsg(ERROR_MSG, "Listener expected, got: " + luaState.typeName(1));
                return 0;
            }

            // check for options table (required)
            if (luaState.type(2) == LuaType.TABLE) {
                // traverse and validate all the options
                for (luaState.pushNil(); luaState.next(2); luaState.pop(1)) {
                    String key = luaState.toString(-2);

                    if (key.equals("apiKey")) {
                        if (luaState.type(-1) == LuaType.STRING) {
                            apiKey = luaState.toString(-1);
                        } else {
                            logMsg(ERROR_MSG, "options.apiKey (string) expected, got " + luaState.typeName(-1));
                            return 0;
                        }
                    } else if (key.equals("registerAppForAdNetworkAttribution")) {

                    } else if (key.equals("hasUserConsent")) {
                        if (luaState.type(-1) == LuaType.BOOLEAN) {
                            hasUserConsent = luaState.toBoolean(-1);
                        } else {
                            logMsg(ERROR_MSG, "options.hasUserConsent expected (boolean). Got " + luaState.typeName(-1));
                            return 0;
                        }
                    } else {
                        logMsg(ERROR_MSG, "Invalid option '" + key + "'");
                        return 0;
                    }
                }
            } else {
                logMsg(ERROR_MSG, "options table expected, got " + luaState.typeName(2));
                return 0;
            }

            // check required params
            if (apiKey == null) {
                logMsg(ERROR_MSG, "options.apiKey is required");
                return 0;
            }

            // declare final variables for inner loop
            final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();
            final String fApiKey = apiKey;
            final boolean fHasUserConsent = hasUserConsent;

            if (coronaActivity != null) {
                Runnable runnableActivity = new Runnable() {
                    public void run() {
                        // initialize the SDK
                        TenjinSDK instance = TenjinSDK.getInstance(coronaActivity, fApiKey);

                        if (fHasUserConsent) {
                            instance.optIn();
                        } else {
                            instance.optOut();
                        }

                        instance.connect();

                        // store data in object dictionary for later use
                        tenjinObjects.put(DEVELOPER_API_KEY, fApiKey);
                        tenjinObjects.put(TENJIN_INSTANCE, instance);

                        // send Corona Lua event
                        Map<String, String> coronaEvent = new HashMap<>();
                        coronaEvent.put(EVENT_PHASE_KEY, PHASE_INIT);
                        dispatchLuaEvent(coronaEvent, coronaListener);

                        // log plugin version to device
                        Log.i(CORONA_TAG, PLUGIN_NAME + ": " + PLUGIN_VERSION + " (SDK: " + PLUGIN_SDK_VERSION + ")");

                        // send beacon data to our server (placement set to null. placements not used)
                        // wait for 2 seconds for CoronaBeacon.getDeviceInfo() to initialize
                        Handler handler = new Handler();
                        handler.postDelayed(new Runnable() {
                            @Override
                            public void run() {
                                sendToBeacon(CoronaBeacon.IMPRESSION, null);
                            }
                        }, 2000);
                    }
                };

                coronaActivity.runOnUiThread(runnableActivity);
            }

            return 0;
        }
    }

    // [Lua] getDeepLink(listener)
    private class GetDeepLink implements NamedJavaFunction {
        /**
         * Gets the name of the Lua function as it would appear in the Lua script.
         *
         * @return Returns the name of the custom Lua function.
         */
        @Override
        public String getName() {
            return "getDeepLink";
        }

        /**
         * This method is called when the Lua function is called.
         * <p>
         * Warning! This method is not called on the main UI thread.
         *
         * @param luaState Reference to the Lua state.
         *                 Needed to retrieve the Lua function's parameters and to return values back to Lua.
         * @return Returns the number of values to be returned by the Lua function.
         */
        @Override
        public int invoke(final LuaState luaState) {
            functionSignature = "tenjin.getDeepLink(listener)";

            // check number or args
            int nargs = luaState.getTop();
            if (nargs != 1) {
                logMsg(ERROR_MSG, "Expected 1 arguments, got " + nargs);
                return 0;
            }

            // Get the listener (required)
            if (CoronaLua.isListener(luaState, 1, PROVIDER_NAME)) {
                deepLinkListener = CoronaLua.newRef(luaState, 1);
            } else {
                logMsg(ERROR_MSG, "Listener expected, got: " + luaState.typeName(1));
                return 0;
            }

            // declare final variables for inner loop
            final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();

            if (coronaActivity != null) {
                Runnable runnableActivity = new Runnable() {
                    public void run() {
                        TenjinSDK instance = (TenjinSDK) tenjinObjects.get(TENJIN_INSTANCE);

                        instance.getDeeplink(new Callback() {
                            @Override
                            public void onSuccess(boolean clickedTenjinLink, boolean isFirstSession, Map<String, String> data) {
                                dispatchLuaEvent(data, deepLinkListener);
                            }
                        });
                    }
                };

                coronaActivity.runOnUiThread(runnableActivity);
            }

            return 0;
        }
    }

    // [Lua] logEvent(event [, value])
    private class LogEvent implements NamedJavaFunction {
        /**
         * Gets the name of the Lua function as it would appear in the Lua script.
         *
         * @return Returns the name of the custom Lua function.
         */
        @Override
        public String getName() {
            return "logEvent";
        }

        /**
         * This method is called when the Lua function is called.
         * <p>
         * Warning! This method is not called on the main UI thread.
         *
         * @param luaState Reference to the Lua state.
         *                 Needed to retrieve the Lua function's parameters and to return values back to Lua.
         * @return Returns the number of values to be returned by the Lua function.
         */
        @Override
        public int invoke(LuaState luaState) {
            functionSignature = "tenjin.logEvent(event [, value])";

            if (!isSDKInitialized()) {
                return 0;
            }

            String eventName = null;
            double eventValue = NO_DATA;

            // check number or args
            int nargs = luaState.getTop();
            if (nargs < 1 || nargs > 2) {
                logMsg(ERROR_MSG, "Expected 1 or 2 arguments, got " + nargs);
                return 0;
            }

            // get event name
            if (luaState.type(1) == LuaType.STRING) {
                eventName = luaState.toString(1);
            } else {
                logMsg(ERROR_MSG, "eventName (string) expected, got " + luaState.typeName(1));
                return 0;
            }

            // get event value
            if (!luaState.isNoneOrNil(2)) {
                if (luaState.type(2) == LuaType.NUMBER) {
                    eventValue = luaState.toNumber(2);
                } else {
                    logMsg(ERROR_MSG, "eventValue (number) expected, got " + luaState.typeName(2));
                    return 0;
                }
            }

            // declare final variables for inner loop
            final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();
            final String fEventName = eventName;
            final double fEventValue = eventValue;

            if (coronaActivity != null) {
                Runnable runnableActivity = new Runnable() {
                    public void run() {
                        // get the tenjin instance
                        TenjinSDK instance = (TenjinSDK) tenjinObjects.get(TENJIN_INSTANCE);

                        // send event to Tenjin
                        if (fEventValue != NO_DATA) {
                            // verify if truncating value
                            String value = Integer.toString((int) fEventValue);
                            if (Double.parseDouble(value) != fEventValue) {
                                logMsg(WARNING_MSG, "event value has been truncated from " + fEventValue + " to " + value);
                            }
                            instance.eventWithNameAndValue(fEventName, value);
                        } else {
                            instance.eventWithName(fEventName);
                        }

                        // send Corona Lua event
                        Map<String, String> coronaEvent = new HashMap<>();
                        coronaEvent.put(EVENT_PHASE_KEY, PHASE_RECORDED);
                        coronaEvent.put(EVENT_TYPE_KEY, TYPE_STANDARD);
                        dispatchLuaEvent(coronaEvent, coronaListener);
                    }
                };

                coronaActivity.runOnUiThread(runnableActivity);
            }

            return 0;
        }
    }

    // [Lua] logPurchase(productData [, receiptData])
    private class LogPurchase implements NamedJavaFunction {
        /**
         * Gets the name of the Lua function as it would appear in the Lua script.
         *
         * @return Returns the name of the custom Lua function.
         */
        @Override
        public String getName() {
            return "logPurchase";
        }

        /**
         * This method is called when the Lua function is called.
         * <p>
         * Warning! This method is not called on the main UI thread.
         *
         * @param luaState Reference to the Lua state.
         *                 Needed to retrieve the Lua function's parameters and to return values back to Lua.
         * @return Returns the number of values to be returned by the Lua function.
         */
        @Override
        public int invoke(LuaState luaState) {
            functionSignature = "tenjin.logPurchase(productData [, receiptData])";

            if (!isSDKInitialized()) {
                return 0;
            }

            String productId = null;
            String currencyCode = null;
            String signature = null;
            String receipt = null;
            double quantity = NO_DATA;
            double unitPrice = NO_DATA;

            // check number or args
            int nargs = luaState.getTop();
            if (nargs < 1 || nargs > 2) {
                logMsg(ERROR_MSG, "Expected 1 or 2 arguments, got " + nargs);
                return 0;
            }

            // check for productData table (required)
            if (luaState.type(1) == LuaType.TABLE) {
                // traverse and validate all the options
                for (luaState.pushNil(); luaState.next(1); luaState.pop(1)) {
                    String key = luaState.toString(-2);

                    if (key.equals("productId")) {
                        if (luaState.type(-1) == LuaType.STRING) {
                            productId = luaState.toString(-1);
                        } else {
                            logMsg(ERROR_MSG, "productData.productId (string) expected, got " + luaState.typeName(-1));
                            return 0;
                        }
                    } else if (key.equals("currencyCode")) {
                        if (luaState.type(-1) == LuaType.STRING) {
                            currencyCode = luaState.toString(-1);
                        } else {
                            logMsg(ERROR_MSG, "productData.currencyCode (string) expected, got " + luaState.typeName(-1));
                            return 0;
                        }
                    } else if (key.equals("quantity")) {
                        if (luaState.type(-1) == LuaType.NUMBER) {
                            quantity = luaState.toNumber(-1);
                        } else {
                            logMsg(ERROR_MSG, "productData.quantity (number) expected, got " + luaState.typeName(-1));
                            return 0;
                        }
                    } else if (key.equals("unitPrice")) {
                        if (luaState.type(-1) == LuaType.NUMBER) {
                            unitPrice = luaState.toNumber(-1);
                        } else {
                            logMsg(ERROR_MSG, "productData.unitPrice (string) expected, got " + luaState.typeName(-1));
                            return 0;
                        }
                    } else {
                        logMsg(ERROR_MSG, "Invalid option '" + key + "'");
                        return 0;
                    }
                }
            } else {
                logMsg(ERROR_MSG, "productData table expected, got " + luaState.typeName(1));
                return 0;
            }

            // get receipt data (optional)
            if (!luaState.isNoneOrNil(2)) {
                if (luaState.type(2) == LuaType.TABLE) {
                    // traverse and validate all the options
                    for (luaState.pushNil(); luaState.next(2); luaState.pop(1)) {
                        String key = luaState.toString(-2);

                        if (key.equals("signature")) {
                            if (luaState.type(-1) == LuaType.STRING) {
                                signature = luaState.toString(-1);
                            } else {
                                logMsg(ERROR_MSG, "receiptData.signature (string) expected, got " + luaState.typeName(-1));
                                return 0;
                            }
                        } else if (key.equals("transactionId")) {
                            // transactionId only used on iOS (type check only here)
                            if (luaState.type(-1) != LuaType.STRING) {
                                logMsg(ERROR_MSG, "receiptData.transactionId (string) expected, got " + luaState.typeName(-1));
                                return 0;
                            }
                        } else if (key.equals("receipt")) {
                            if (luaState.type(-1) == LuaType.STRING) {
                                receipt = luaState.toString(-1);
                            } else {
                                logMsg(ERROR_MSG, "receiptData.receipt (string) expected, got " + luaState.typeName(-1));
                                return 0;
                            }
                        } else {
                            logMsg(ERROR_MSG, "Invalid option '" + key + "'");
                            return 0;
                        }
                    }
                } else {
                    logMsg(ERROR_MSG, "receiptData table expected, got " + luaState.typeName(2));
                    return 0;
                }
            }

            // validate productId
            if (productId == null) {
                logMsg(ERROR_MSG, "productData.productId required");
                return 0;
            }

            // validate currencyCode
            if (currencyCode == null) {
                logMsg(ERROR_MSG, "productData.currencyCode required");
                return 0;
            }

            // validate quantity
            if (quantity == NO_DATA) {
                logMsg(ERROR_MSG, "productData.quantity required");
                return 0;
            }

            // validate unitPrice
            if (unitPrice == NO_DATA) {
                logMsg(ERROR_MSG, "productData.unitPrice required");
                return 0;
            }

            // validate receipt / transactionId
            if ((signature != null) || (receipt != null)) {
                if (receipt == null) {
                    logMsg(ERROR_MSG, "receiptData.receipt required");
                    return 0;
                }

                if (signature == null) {
                    logMsg(ERROR_MSG, "receiptData.transactionId required ");
                    return 0;
                }
            }
            // declare final variables for inner loop
            final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();
            final String fProductId = productId;
            final String fSignature = signature;
            final String fCurrencyCode = currencyCode.toUpperCase();
            final String fReceipt = receipt;
            final double fUnitPrice = unitPrice;
            final int fQuantity = (int) quantity;

            if (coronaActivity != null) {
                Runnable runnableActivity = new Runnable() {
                    public void run() {
                        TenjinSDK instance = (TenjinSDK) tenjinObjects.get(TENJIN_INSTANCE);

                        // send event to Tenjin
                        if (fSignature != null) {
                            instance.transaction(fProductId, fCurrencyCode, fQuantity, fUnitPrice, fReceipt, fSignature);
                        } else {
                            instance.transaction(fProductId, fCurrencyCode, fQuantity, fUnitPrice);
                        }

                        // send Corona Lua event
                        Map<String, String> coronaEvent = new HashMap<>();
                        coronaEvent.put(EVENT_PHASE_KEY, PHASE_RECORDED);
                        coronaEvent.put(EVENT_TYPE_KEY, TYPE_PURCHASE);
                        dispatchLuaEvent(coronaEvent, coronaListener);
                    }
                };

                coronaActivity.runOnUiThread(runnableActivity);
            }

            return 0;
        }
    }
}
