package org.handancampus.app.life

import java.net.URI
import java.net.URLEncoder

data class BikeCode(val provider:String,val number:String,val raw:String) {
    val name get()=if(provider=="hello")"哈啰单车" else "美团单车"
    // Both HTTPS versions were fetched successfully, with vehicle parameters preserved.
    val web get()="https:"+raw.substringAfter(':')
}
data class BikeRoute(val uri:String,val status:String)

/** Only observed bicycle QR shapes. Unknown parameters and encoded authority tricks are rejected. */
object BikeCodes {
    fun parse(input:String):BikeCode {
        require(input.length<=512 && input==input.trim() && input.none { it.isWhitespace()||it.code<32 })
        val u=URI(input)
        require(u.scheme in setOf("http","https") && u.rawUserInfo==null && u.port==-1 && u.rawFragment==null)
        val q=u.rawQuery.orEmpty()
        return when(u.host?.lowercase()) {
            "c3x.me"->{require(u.rawPath=="/");require(q.matches(Regex("n=[0-9]{10}")));BikeCode("hello",q.substringAfter('='),input)}
            "www.mobike.com"->{require(u.rawPath=="/download/app.html");require(q.matches(Regex("b=[0-9]{10}_1")));BikeCode("meituan",q.substringAfter('=').substringBefore('_'),input)}
            else->throw IllegalArgumentException("QR")
        }
    }
    fun scanner(provider:String):BikeRoute {
        require(provider in setOf("hello","meituan"))
        return BikeRoute(if(provider=="hello")"hellobike://hellobike.com/scan_qr" else "imeituan://www.meituan.com/scanQRCode","scanner_requested")
    }
    fun homePackage(provider:String,target:String):String {
        require(provider in setOf("hello","meituan") && target in setOf("alipay","app"))
        require(provider=="hello" || target=="app")
        return if(target=="alipay")"com.eg.android.AlipayGphone" else if(provider=="hello")"com.jingyao.easybike" else "com.sankuai.meituan"
    }
    fun routes(code:BikeCode,mode:String):List<BikeRoute> {
        require(mode in setOf("use","web","scanner"))
        if(mode=="scanner")return listOf(scanner(code.provider))
        if(mode=="web"||code.provider=="meituan")return listOf(BikeRoute(code.web,"link_requested"))
        // Exact Alipay handoff from c3x.me's own live script, not a guessed unlock API.
        val query=URLEncoder.encode("qrCode="+code.raw,"UTF-8").replace("+","%20")
        return listOf(BikeRoute("alipays://platformapi/startapp?appId=2017050407110255&query=$query","alipay_requested"),BikeRoute(code.web,"link_requested"))
    }
}
