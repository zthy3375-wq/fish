package org.handancampus.app.life

import android.app.Activity
import android.app.Application
import android.graphics.Bitmap
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.Shadows.shadowOf
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.Duration
import java.net.HttpURLConnection
import java.net.URL

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28],application=Application::class)
class ParcelPollingTest {
    private class Sink:ParcelPageWorker.Listener {
        var batches=0
        override fun onBatch(worker:ParcelPageWorker,batch:NativeParcelBatch,scope:String){batches++}
        override fun onVerified(worker:ParcelPageWorker){}
        override fun onIssue(worker:ParcelPageWorker,issue:String){}
        override fun onIdentity(worker:ParcelPageWorker,bitmap:Bitmap){bitmap.recycle()}
    }
    private fun read(worker:ParcelPageWorker,raw:String) {
        ParcelPageWorker::class.java.getDeclaredMethod("read").apply{isAccessible=true}.invoke(worker)
        shadowOf(worker.web).lastEvaluatedJavascriptCallback.onReceiveValue(raw)
    }
    @Test fun emptyUnrecognisedParcelPageNeverEntersIdentityCaptureOrRedirectLoop() {
        val controller=Robolectric.buildActivity(Activity::class.java).create().start().resume()
        val worker=ParcelPageWorker(controller.get(),"taobao",Sink())
        worker.start()
        repeat(4) {
            read(worker,"""{"version":2,"provider":"taobao","phase":"loading","items":[]}""")
            assertTrue(shadowOf(worker.web).lastEvaluatedJavascript.contains("HytParcel.read()"))
            assertEquals(ParcelWebPolicy.TAOBAO_PARCELS,shadowOf(worker.web).lastLoadedUrl)
        }
        worker.destroy();controller.pause().stop().destroy()
    }
    @Test fun aStableRecognisedListStopsPollingAndDoesNotEmitDuplicates() {
        val controller=Robolectric.buildActivity(Activity::class.java).create().start().resume()
        val sink=Sink();val worker=ParcelPageWorker(controller.get(),"taobao",sink)
        worker.start()
        val raw="""{"version":2,"provider":"taobao","phase":"empty","items":[]}"""
        read(worker,raw);assertTrue(worker.isBusy)
        shadowOf(android.os.Looper.getMainLooper()).idleFor(Duration.ofSeconds(2))
        read(worker,raw)
        assertFalse(worker.isBusy);assertEquals(1,sink.batches)
        worker.destroy();controller.pause().stop().destroy()
    }
    @Test fun duplicateRefreshAndForegroundReturnDoNotRestartRunningQuery() {
        val controller=Robolectric.buildActivity(ParcelWebActivity::class.java).create().start().resume()
        val activity=controller.get()
        ParcelWebActivity::class.java.getDeclaredField("usable").apply{isAccessible=true}.setBoolean(activity,true)
        val worker=ParcelPageWorker(activity,"taobao",activity)
        @Suppress("UNCHECKED_CAST")
        val workers=ParcelWebActivity::class.java.getDeclaredField("workers").apply{isAccessible=true}.get(activity) as MutableMap<String,ParcelPageWorker>
        workers["taobao"]=worker;worker.start()
        val generation=ParcelPageWorker::class.java.getDeclaredField("generation").apply{isAccessible=true}
        val before=generation.getInt(worker)
        val sync=ParcelWebActivity::class.java.getDeclaredMethod("sync",String::class.java).apply{isAccessible=true}
        sync.invoke(activity,"taobao");sync.invoke(activity,"taobao")
        assertEquals(before,generation.getInt(worker))
        controller.pause();val paused=generation.getInt(worker);controller.resume()
        assertEquals(paused,generation.getInt(worker));assertFalse(worker.isBusy)
        controller.pause().stop().destroy()
    }
    @Test fun nativeQueryPublishesEachPageBeforeStartingTheNextRequest() {
        var opened=0;val delivered=mutableListOf<String>()
        ParcelTaobaoQuery.query("_m_h5_tk=synthetic_123", "synthetic", openConnection={url->
            assertEquals(opened,delivered.size);opened++
            object:HttpURLConnection(url) {
                override fun connect(){}
                override fun disconnect(){}
                override fun usingProxy()=false
                override fun getResponseCode()=200
                override fun getHeaderFields():Map<String,List<String>> = emptyMap()
                override fun getInputStream()="""{"ret":["SUCCESS"],"data":{"page":$opened}}""".byteInputStream()
            }
        },onPage={delivered.addAll(it.bodies)})
        assertEquals(3,opened);assertEquals(3,delivered.size)
        assertEquals(1,JSONObject(delivered[0]).getJSONObject("data").getInt("page"))
    }
}
