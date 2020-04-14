local metadata =
{
    plugin =
    {
        format = 'jar',
        manifest =
        {
            permissions = {},
            usesPermissions =
            {
                "android.permission.INTERNET"
            },
            usesFeatures =
            {
            },
            applicationChildElements =
            {
                [[
                <receiver android:name="com.tenjin.android.TenjinReferrerReceiver" android:exported="true">
                    <intent-filter>
                    <action android:name="com.android.vending.INSTALL_REFERRER"/>
                    </intent-filter>
                </receiver>
                ]]
            }
        }
    },

    coronaManifest =
    {
        dependencies =
        {
            ["shared.google.play.services.ads.identifier"] = "com.coronalabs"
            ["shared.google.play.services.analytics"] = "com.coronalabs"
        }
    }
}

return metadata
