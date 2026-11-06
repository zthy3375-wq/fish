package org.handancampus.app.academic;
import org.junit.Test;
import static org.junit.Assert.*;
public class AcademicPolicyTest {
 @Test public void sessionIsRestrictedToExactOfficialOrigin(){
  assertTrue(AcademicPolicy.INSTANCE.allowed("https://jwgl.hdc.edu.cn/kbcx/xskbcx_cxXsgrkb.html"));
  for(String url:new String[]{"http://jwgl.hdc.edu.cn/","https://jwgl.hdc.edu.cn.evil.test/","https://jwgl.hdc.edu.cn@evil.test/","https://jwgl.hdc.edu.cn:444/","file:///etc/passwd","javascript:alert(1)"})assertFalse(AcademicPolicy.INSTANCE.allowed(url));
 }
 @Test public void loginAndUnknownDestinationsNeverEstablishAnAuthenticatedSession(){
  assertTrue(AcademicPolicy.INSTANCE.loginPage(AcademicPolicy.LOGIN));assertTrue(AcademicPolicy.INSTANCE.loginPage(null));
  assertFalse(AcademicPolicy.INSTANCE.loginPage(AcademicPolicy.HOME));
 }
}
