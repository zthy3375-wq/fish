package org.handancampus.app.learning

import org.json.JSONObject

/** Native-only replay context; signed URLs and forms never cross the public bridge. */
object ChaoxingVerification {
    fun remember(state:JSONObject,show:String,read:String,form:Map<String,String>?,referer:String):Boolean {
        if(!ChaoxingPolicy.allowed(show)||!ChaoxingPolicy.safeRead(read))return false
        state.put("verificationUrl",show).put("verificationRead",read)
            .put("verificationReferer",referer.takeIf(ChaoxingPolicy::allowed) ?: ChaoxingPolicy.HOME)
        if(form!=null)state.put("verificationForm",JSONObject(form)) else state.remove("verificationForm")
        return true
    }
}
