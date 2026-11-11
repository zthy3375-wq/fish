package org.handancampus.app.life
import org.junit.Assert.*
import org.junit.Test
import java.net.URI
import java.net.URLDecoder

class BikeCodeTest {
 private val hello="http://c3x.me/?n=9150978196"
 private val meituan="http://www.mobike.com/download/app.html?b=8646834293_1"
 @Test fun realPhotoCodesPreserveTheFullSourceAndVehicleNumber(){
  assertEquals(BikeCode("hello","9150978196",hello),BikeCodes.parse(hello))
  assertEquals(BikeCode("meituan","8646834293",meituan),BikeCodes.parse(meituan))
  assertEquals(meituan.replace("http:","https:"),BikeCodes.parse(meituan).web)
 }
 @Test fun rejectsHostSpoofingEncodedAndInjectedUrls(){
  for(s in listOf("https://c3x.me.evil.test/?n=9150978196","http://c3x.me@evil.test/?n=9150978196","http://evil.test/?n=9150978196",hello+"#intent;end",hello+"&url=https://evil.test",hello+"&n=1111111111",hello.replace("n=","%6e="),hello.replace("915","%39%31%35"),hello.replace("/?","/other?"),hello.replace("c3x.me","c3x.me:443"),hello.replace("http:","intent:"),hello+"\n",hello+" ",meituan.replace("_1","_2"),meituan.replace("8646834293","864683429")))
   assertThrows(s,Exception::class.java){BikeCodes.parse(s)}
 }
 @Test fun alipayCarriesExactlyTheScannedCodeWithoutInventingAnUnlockCall(){
  val routes=BikeCodes.routes(BikeCodes.parse(hello),"use")
  val u=URI(routes[0].uri);assertEquals("alipays",u.scheme)
  val query=u.rawQuery.split('&').associate { val p=it.split('=',limit=2);p[0] to URLDecoder.decode(p[1],"UTF-8") }
  assertEquals("2017050407110255",query["appId"]);assertEquals("qrCode=$hello",query["query"])
  assertEquals("link_requested",routes.last().status)
 }
 @Test fun meituanFallbackRetainsBothTheNumberAndSuffix(){
  val r=BikeCodes.routes(BikeCodes.parse(meituan),"use").single()
  assertEquals("https://www.mobike.com/download/app.html?b=8646834293_1",r.uri)
  assertEquals("link_requested",r.status)
 }
 @Test fun scannerFallbackIsExplicitAndHasNoVehicleOrArbitraryUrlParameters(){
  assertEquals("hellobike://hellobike.com/scan_qr",BikeCodes.routes(BikeCodes.parse(hello),"scanner").single().uri)
  assertEquals("imeituan://www.meituan.com/scanQRCode",BikeCodes.routes(BikeCodes.parse(meituan),"scanner").single().uri)
  assertEquals(1,BikeCodes.routes(BikeCodes.parse(hello),"web").size)
  assertThrows(Exception::class.java){BikeCodes.routes(BikeCodes.parse(hello),"unlock")}
 }
 @Test fun shortcutRoutesHaveStrictProviderAndTargetEnums(){
  assertEquals("com.eg.android.AlipayGphone",BikeCodes.homePackage("hello","alipay"))
  assertEquals("com.jingyao.easybike",BikeCodes.homePackage("hello","app"))
  assertEquals("com.sankuai.meituan",BikeCodes.homePackage("meituan","app"))
  assertThrows(Exception::class.java){BikeCodes.homePackage("meituan","alipay")}
  assertThrows(Exception::class.java){BikeCodes.homePackage("hello","https://evil.test")}
  assertThrows(Exception::class.java){BikeCodes.scanner("https://evil.test")}
 }
}
