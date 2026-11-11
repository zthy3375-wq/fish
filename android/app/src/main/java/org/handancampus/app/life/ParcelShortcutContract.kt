package org.handancampus.app.life

import java.util.concurrent.CancellationException

/** Fixed public destinations. Android package visibility is never a launch prerequisite. */
data class ParcelShortcutTarget(val provider:String,val packageName:String,val uri:String,val webUri:String,val system:Boolean=false)
enum class ParcelLaunchStatus(val value:String) {
    OPENED("opened"), APP_OPENED("app_opened"), SYSTEM_OPENED("system_opened"), WEB_OPENED("web_opened"),
    UNAVAILABLE("unavailable"), CANCELLED("cancelled")
}
enum class ParcelLaunchRoute { APP_LINK, APP_HOME, SYSTEM_LINK, WEB_LINK }
interface ParcelLaunchHost {
    fun isActive():Boolean
    /** false means no activity handled this route; other failures must not silently retry. */
    fun open(target:ParcelShortcutTarget,route:ParcelLaunchRoute):Boolean
}
object ParcelShortcutContract {
    /** JS can select a provider and an explicit system retry, never a URL/package/activity. */
    fun target(provider:String?,argumentNames:Set<String>,mode:String?=null):ParcelShortcutTarget {
        require(argumentNames==setOf("provider")||argumentNames==setOf("provider","mode")){"INVALID_PROVIDER"}
        require(if("mode" in argumentNames)mode in setOf("app","system") else mode==null){"INVALID_PROVIDER"}
        val system=mode=="system"
        return when(provider){
            "taobao"->ParcelShortcutTarget("taobao","com.taobao.taobao",
                "https://pages-fast.m.taobao.com/wow/z/uniapp/1011717/last-mile-fe/end-collect-platform/identity-code",
                "https://pages-fast.m.taobao.com/wow/z/uniapp/1011717/last-mile-fe/end-collect-platform/identity-code",system)
            "pinduoduo"->ParcelShortcutTarget("pinduoduo","com.xunmeng.pinduoduo",
                "pinduoduo://com.xunmeng.pinduoduo/mdkd/package?tab=ID_CODE","https://mobile.yangkeduo.com/",system)
            else->throw IllegalArgumentException("INVALID_PROVIDER")
        }
    }
    /** Success means one dispatch accepted, not that an identity-code page actually appeared. */
    fun launch(target:ParcelShortcutTarget,host:ParcelLaunchHost):ParcelLaunchStatus=try {
        val routes=if(target.system)listOf(ParcelLaunchRoute.SYSTEM_LINK,ParcelLaunchRoute.WEB_LINK)
            else listOf(ParcelLaunchRoute.APP_LINK,ParcelLaunchRoute.APP_HOME)
        var result=ParcelLaunchStatus.UNAVAILABLE
        for(route in routes){
            if(!host.isActive()){result=ParcelLaunchStatus.CANCELLED;break}
            // Taobao's system link already is the official HTTPS page. Do not dispatch it twice.
            if(route==ParcelLaunchRoute.WEB_LINK&&target.webUri==target.uri)continue
            if(host.open(target,route)){
                result=when(route){
                    ParcelLaunchRoute.APP_LINK->ParcelLaunchStatus.OPENED
                    ParcelLaunchRoute.APP_HOME->ParcelLaunchStatus.APP_OPENED
                    ParcelLaunchRoute.SYSTEM_LINK->ParcelLaunchStatus.SYSTEM_OPENED
                    ParcelLaunchRoute.WEB_LINK->ParcelLaunchStatus.WEB_OPENED
                };break
            }
        };result
    }catch(_:CancellationException){ParcelLaunchStatus.CANCELLED}
    catch(_:Exception){ParcelLaunchStatus.UNAVAILABLE}
}
