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
}
