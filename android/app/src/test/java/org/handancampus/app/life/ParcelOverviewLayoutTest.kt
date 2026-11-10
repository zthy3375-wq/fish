package org.handancampus.app.life

import android.app.Application
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk=[28],application=Application::class,qualifiers="mdpi")
class ParcelOverviewLayoutTest {
    private fun views(view:View):List<View> = listOf(view)+if(view is ViewGroup)(0 until view.childCount).flatMap{views(view.getChildAt(it))}else emptyList()
    @Test fun nativeCentreShowsGroupedCodesWithoutBrowserToolbarAndKeepsCardsOnBackground() {
        val controller=Robolectric.buildActivity(ParcelWebActivity::class.java,Intent().putExtra("provider","taobao")).create().start().resume()
        val activity=controller.get()
        val store=ParcelWebActivity::class.java.getDeclaredField("store").apply{isAccessible=true}.get(activity) as ParcelStore
        store.ledger.merge(NativeParcelBatch("taobao","partial",listOf(
            NativeParcel("taobao","waybill:SYNTHETIC001","01-02-003","合成东区驿站","SYNTHETIC001","测试快递",syncedAt=1000),
            NativeParcel("taobao","waybill:SYNTHETIC002","02-03-004","合成东区驿站","SYNTHETIC002","测试快递",syncedAt=1000))))
        store.ledger.updated["pinduoduo"]=1000
        ParcelWebActivity::class.java.getDeclaredMethod("renderList").apply{isAccessible=true}.invoke(activity)
        val root=activity.findViewById<View>(android.R.id.content)
        root.measure(View.MeasureSpec.makeMeasureSpec(360,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(760,View.MeasureSpec.EXACTLY))
        root.layout(0,0,360,760)
        val texts=views(root).filterIsInstance<TextView>()
        assertTrue(texts.any{it.text.toString()=="2 件待取"})
        assertFalse(texts.any{it.text.toString()=="全部待取" || it.text.toString()=="更多"})
        val code=texts.single{it.text.toString()=="01-02-003"}
        assertTrue(code.width<=360);assertEquals(0,code.layout.getEllipsisCount(0));assertTrue(code.height>=48)
        val bitmap=Bitmap.createBitmap(360,760,Bitmap.Config.ARGB_8888);root.draw(Canvas(bitmap))
        java.io.File(System.getProperty("java.io.tmpdir"),"hyt-parcel-native-360.png").outputStream().use{bitmap.compress(Bitmap.CompressFormat.PNG,100,it)}
        @Suppress("UNCHECKED_CAST")
        val phases=ParcelWebActivity::class.java.getDeclaredField("phases").apply{isAccessible=true}.get(activity) as MutableMap<String,String>
        phases["taobao"]="syncing"
        controller.pause();assertEquals(2,store.ledger.items.size)
        assertEquals("partial",phases["taobao"])
        assertTrue(views(root).filterIsInstance<TextView>().any{it.text.toString()=="01-02-003"})
        controller.stop().destroy()
    }
    @Test fun loginCompletionAlwaysReturnsAndUnconfirmedEmptyDoesNotClaimNoParcels() {
        val controller=Robolectric.buildActivity(ParcelWebActivity::class.java).create().start().resume()
        val activity=controller.get()
        val mode=ParcelWebActivity::class.java.getDeclaredField("mode").apply{isAccessible=true}
        mode.set(activity,"auth")
        val header=ParcelWebActivity::class.java.getDeclaredField("headerAction").apply{isAccessible=true}.get(activity) as TextView
        header.performClick()
        assertEquals("list",mode.get(activity))
        assertFalse(activity.isFinishing)
        val text=views(activity.findViewById(android.R.id.content)).filterIsInstance<TextView>().map{it.text.toString()}
        assertTrue(text.contains("尚未读取到包裹"))
        assertFalse(text.contains("暂无待取包裹"))
        controller.pause().stop().destroy()
    }
    @Test fun pausingWithoutParcelResultsDoesNotInventExpiredLoginAndEmptyIsExplicit() {
        val controller=Robolectric.buildActivity(ParcelWebActivity::class.java).create().start().resume()
        val activity=controller.get()
        @Suppress("UNCHECKED_CAST")
        val phases=ParcelWebActivity::class.java.getDeclaredField("phases").apply{isAccessible=true}.get(activity) as MutableMap<String,String>
        phases["taobao"]="syncing"
        ParcelWebActivity::class.java.getDeclaredMethod("pauseWorkers").apply{isAccessible=true}.invoke(activity)
        assertEquals("idle",phases["taobao"])
        phases["taobao"]="empty";phases["pinduoduo"]="empty"
        ParcelWebActivity::class.java.getDeclaredMethod("renderList").apply{isAccessible=true}.invoke(activity)
        assertTrue(views(activity.findViewById(android.R.id.content)).filterIsInstance<TextView>().any{it.text.toString()=="暂无待取包裹"})
        controller.pause().stop().destroy()
    }

}
