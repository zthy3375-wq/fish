package org.handancampus.app.life
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.ResolveInfo
import android.content.pm.ActivityInfo
import org.robolectric.Shadows.shadowOf
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28])
class BikeAndroidLauncherTest {
 class Host:Activity(){
  val sent=mutableListOf<Intent>();val attempted=mutableListOf<Intent>();var missing=false;var blocked=false
  override fun startActivity(i:Intent){attempted+=i;if(blocked)throw SecurityException();if(missing&&i.data?.scheme=="alipays")throw ActivityNotFoundException();sent+=i}
 }
 private fun host()=Robolectric.buildActivity(Host::class.java).setup().get()
 private val hello=BikeCodes.parse("http://c3x.me/?n=9150978196")
 @Test fun dispatchDoesNotDependOnPackageVisibilityOrClaimUnlockSuccess(){
  val h=host();assertEquals("alipay_requested",BikeAndroidLauncher(h).launch(hello,"use"))
  assertEquals(1,h.sent.size);assertNull(h.sent[0].`package`);assertTrue(h.sent[0].hasCategory(Intent.CATEGORY_BROWSABLE))
 }
 @Test fun missingAlipayFallsBackOnceToExactHttpsVehicleLink(){
  val h=host();h.missing=true;assertEquals("link_requested",BikeAndroidLauncher(h).launch(hello,"use"))
  assertEquals(2,h.attempted.size);assertEquals(hello.web,h.sent.single().dataString)
 }
 @Test fun securityDenialDoesNotTriggerOtherAutomaticLaunches(){
  val h=host();h.blocked=true;assertEquals("blocked",BikeAndroidLauncher(h).launch(hello,"use"));assertEquals(1,h.attempted.size)
 }
 @Test fun closedHostCannotDispatchAnyVehicle(){
  val h=host();h.finish();assertEquals("cancelled",BikeAndroidLauncher(h).launch(hello,"use"));assertTrue(h.sent.isEmpty())
 }
 @Test fun meituanShortcutDispatchesScannerWithoutNeedingAStoredVehicle(){
  val h=host();assertEquals("scanner_requested",BikeAndroidLauncher(h).shortcut("meituan","scanner"))
  assertEquals("imeituan://www.meituan.com/scanQRCode",h.sent.single().dataString)
 }
 @Test fun returningOpensOnlyTheLauncherWithoutVehicleData(){
  for((provider,target) in listOf("hello" to "alipay","hello" to "app","meituan" to "app")){
   val h=host();val pkg=BikeCodes.homePackage(provider,target)
   val info=ResolveInfo().apply{activityInfo=ActivityInfo().apply{packageName=pkg;name=pkg+".TestLauncher"}}
   shadowOf(h.packageManager).addResolveInfoForIntent(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER).setPackage(pkg),info)
   assertEquals("home_requested",BikeAndroidLauncher(h).shortcut(provider,"home",target))
   val i=h.sent.single();assertEquals(Intent.ACTION_MAIN,i.action);assertNull(i.data);assertEquals(pkg,i.component?.packageName);assertTrue(i.extras==null||i.extras!!.isEmpty)
  }
 }
 @Test fun missingHomeDoesNotFallBackToAUseOrScannerRoute(){
  val h=host();assertEquals("unavailable",BikeAndroidLauncher(h).shortcut("hello","home","alipay"));assertTrue(h.attempted.isEmpty())
 }
 @Test fun scannerSecurityDenialAndClosedHomeAreControlled(){
  val h=host();h.blocked=true;assertEquals("blocked",BikeAndroidLauncher(h).shortcut("meituan","scanner"));assertEquals(1,h.attempted.size)
  h.finish();assertEquals("cancelled",BikeAndroidLauncher(h).shortcut("meituan","home"));assertEquals(1,h.attempted.size)
 }
}
