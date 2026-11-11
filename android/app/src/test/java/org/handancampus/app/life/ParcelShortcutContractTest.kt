package org.handancampus.app.life

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CancellationException

class ParcelShortcutContractTest {
    private val taobao=ParcelShortcutContract.target("taobao",setOf("provider"))
    private class Host:ParcelLaunchHost {
        var active=true
        val attempts=mutableListOf<ParcelLaunchRoute>()
        var succeeds=ParcelLaunchRoute.APP_LINK
        var failure:Exception?=null
        var stopAfterFailure=false
        override fun isActive()=active
        override fun open(target:ParcelShortcutTarget,route:ParcelLaunchRoute):Boolean {
            attempts.add(route);failure?.let{throw it}
            if(route==succeeds)return true
            if(stopAfterFailure)active=false
            return false
        }
    }
    @Test fun destinationsStayFixed(){
        assertEquals("com.taobao.taobao",taobao.packageName)
        assertTrue(taobao.uri.startsWith("https://pages-fast.m.taobao.com/"))
        val pdd=ParcelShortcutContract.target("pinduoduo",setOf("provider"))
        assertEquals("com.xunmeng.pinduoduo",pdd.packageName)
        assertEquals("pinduoduo://com.xunmeng.pinduoduo/mdkd/package?tab=ID_CODE",pdd.uri)
        assertEquals("https://mobile.yangkeduo.com/",pdd.webUri)
    }
    @Test fun rejectsUnknownIdsDestinationOverridesAndModes(){
        for(id in listOf(null,"","TAOBAO"," taobao","taobao ","https://example.org","javascript:alert(1)","com.taobao.taobao"))
            assertThrows(IllegalArgumentException::class.java){ParcelShortcutContract.target(id,setOf("provider"))}
        for(keys in listOf(emptySet(),setOf("uri"),setOf("provider","uri"),setOf("provider","package"),setOf("provider","mode","url")))
            assertThrows(IllegalArgumentException::class.java){ParcelShortcutContract.target("taobao",keys,"system")}
        for(mode in listOf(null,"","SYSTEM","browser","https://example.org"))
            assertThrows(IllegalArgumentException::class.java){ParcelShortcutContract.target("taobao",setOf("provider","mode"),mode)}
        assertThrows(IllegalArgumentException::class.java){ParcelShortcutContract.target("taobao",setOf("provider"),"system")}
    }
    @Test fun directDispatchNeverRequiresPackageInspection(){
        val h=Host();assertEquals(ParcelLaunchStatus.OPENED,ParcelShortcutContract.launch(taobao,h))
        assertEquals(listOf(ParcelLaunchRoute.APP_LINK),h.attempts)
    }
    @Test fun unsupportedDeepLinkFallsBackToOfficialAppHome(){
        val h=Host().apply{succeeds=ParcelLaunchRoute.APP_HOME}
        assertEquals(ParcelLaunchStatus.APP_OPENED,ParcelShortcutContract.launch(taobao,h))
        assertEquals(listOf(ParcelLaunchRoute.APP_LINK,ParcelLaunchRoute.APP_HOME),h.attempts)
    }
    @Test fun missingRoutesDoNotClaimAppUninstalledOrOpenBrowserAutomatically(){
        val h=Host().apply{succeeds=ParcelLaunchRoute.WEB_LINK}
        assertEquals(ParcelLaunchStatus.UNAVAILABLE,ParcelShortcutContract.launch(taobao,h))
        assertEquals(listOf(ParcelLaunchRoute.APP_LINK,ParcelLaunchRoute.APP_HOME),h.attempts)
    }
    @Test fun explicitCompatibilityRequestUsesSystemLinkWithoutPackageGate(){
        for(provider in listOf("taobao","pinduoduo")){
            val t=ParcelShortcutContract.target(provider,setOf("provider","mode"),"system")
            val h=Host().apply{succeeds=ParcelLaunchRoute.SYSTEM_LINK}
            assertEquals(ParcelLaunchStatus.SYSTEM_OPENED,ParcelShortcutContract.launch(t,h))
            assertEquals(listOf(ParcelLaunchRoute.SYSTEM_LINK),h.attempts)
        }
    }
    @Test fun pddSystemSchemeCanFallBackToItsOfficialWebPage(){
        val t=ParcelShortcutContract.target("pinduoduo",setOf("provider","mode"),"system")
        val h=Host().apply{succeeds=ParcelLaunchRoute.WEB_LINK}
        assertEquals(ParcelLaunchStatus.WEB_OPENED,ParcelShortcutContract.launch(t,h))
        assertEquals(listOf(ParcelLaunchRoute.SYSTEM_LINK,ParcelLaunchRoute.WEB_LINK),h.attempts)
    }
    @Test fun taobaoDoesNotRetrySameHttpsLinkTwice(){
        val t=ParcelShortcutContract.target("taobao",setOf("provider","mode"),"system")
        val h=Host().apply{succeeds=ParcelLaunchRoute.WEB_LINK}
        assertEquals(ParcelLaunchStatus.UNAVAILABLE,ParcelShortcutContract.launch(t,h))
        assertEquals(listOf(ParcelLaunchRoute.SYSTEM_LINK),h.attempts)
    }
    @Test fun destroyedActivityCancelsWithoutLaunching(){
        val h=Host().apply{active=false};assertEquals(ParcelLaunchStatus.CANCELLED,ParcelShortcutContract.launch(taobao,h));assertTrue(h.attempts.isEmpty())
    }
    @Test fun activityDisappearingBetweenRoutesCancelsFallback(){
        val h=Host().apply{succeeds=ParcelLaunchRoute.APP_HOME;stopAfterFailure=true}
        assertEquals(ParcelLaunchStatus.CANCELLED,ParcelShortcutContract.launch(taobao,h))
        assertEquals(listOf(ParcelLaunchRoute.APP_LINK),h.attempts)
    }
    @Test fun securityFailureDoesNotSilentlyRetryAnotherRoute(){
        val h=Host().apply{failure=SecurityException("private payload")}
        assertEquals(ParcelLaunchStatus.UNAVAILABLE,ParcelShortcutContract.launch(taobao,h));assertEquals(1,h.attempts.size)
    }
    @Test fun cancellationDoesNotLaunchFallback(){
        val h=Host().apply{failure=CancellationException()}
        assertEquals(ParcelLaunchStatus.CANCELLED,ParcelShortcutContract.launch(taobao,h));assertEquals(1,h.attempts.size)
    }
}
