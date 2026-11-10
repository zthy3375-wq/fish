package org.handancampus.app.life

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28])
class ParcelAndroidLauncherTest {
    class TestActivity:Activity(){
        val sent=mutableListOf<Intent>()
        var failure:RuntimeException?=null
        override fun startActivity(intent:Intent){failure?.let{throw it};sent.add(intent)}
    }
    private fun activity()=Robolectric.buildActivity(TestActivity::class.java).setup().get()
    @Test fun packageAbsentFromQueriesDoesNotBlockDirectDispatch(){
        val a=activity();val t=ParcelShortcutContract.target("taobao",setOf("provider"))
        assertTrue(ParcelAndroidLauncher(a).open(t,ParcelLaunchRoute.APP_LINK))
        assertEquals(t.packageName,a.sent.single().`package`);assertEquals(t.uri,a.sent.single().dataString)
        assertTrue(a.sent.single().hasCategory(Intent.CATEGORY_BROWSABLE))
    }
    @Test fun compatibilityDispatchLetsSystemResolveTheFixedDestination(){
        val a=activity();val t=ParcelShortcutContract.target("pinduoduo",setOf("provider","mode"),"system")
        assertTrue(ParcelAndroidLauncher(a).open(t,ParcelLaunchRoute.SYSTEM_LINK))
        assertNull(a.sent.single().`package`);assertEquals(t.uri,a.sent.single().dataString)
    }
    @Test fun webFallbackIsOnlyTheFixedOfficialPage(){
        val a=activity();val t=ParcelShortcutContract.target("pinduoduo",setOf("provider","mode"),"system")
        assertTrue(ParcelAndroidLauncher(a).open(t,ParcelLaunchRoute.WEB_LINK))
        assertEquals("https://mobile.yangkeduo.com/",a.sent.single().dataString);assertNull(a.sent.single().`package`)
    }
    @Test fun activityNotFoundAllowsNextRouteButSecurityFailureIsNotSwallowed(){
        val a=activity();val t=ParcelShortcutContract.target("taobao",setOf("provider"));val launcher=ParcelAndroidLauncher(a)
        a.failure=ActivityNotFoundException();assertFalse(launcher.open(t,ParcelLaunchRoute.APP_LINK))
        a.failure=SecurityException("blocked");assertThrows(SecurityException::class.java){launcher.open(t,ParcelLaunchRoute.APP_LINK)}
        assertTrue(a.sent.isEmpty())
    }
    @Test fun missingHomeActivityReturnsFalseWithoutPretendingToOpen(){
        val a=activity();val t=ParcelShortcutContract.target("taobao",setOf("provider"))
        assertFalse(ParcelAndroidLauncher(a).open(t,ParcelLaunchRoute.APP_HOME));assertTrue(a.sent.isEmpty())
    }
}
