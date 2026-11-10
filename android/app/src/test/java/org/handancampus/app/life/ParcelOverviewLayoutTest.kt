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
@Config(sdk = [28], application = Application::class, qualifiers = "mdpi")
class ParcelOverviewLayoutTest {
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun field(activity: ParcelWebActivity, name: String) = ParcelWebActivity::class.java.getDeclaredField(name).apply { isAccessible = true }
    @Test fun overviewMeasuresRealNativeCardsAtNarrowWidthAndClearsWhenBackgrounded() {
        val controller = Robolectric.buildActivity(ParcelWebActivity::class.java, Intent().putExtra("provider", "taobao")).create().start().resume()
        val activity = controller.get()
        val session = field(activity, "readSession").get(activity) as ParcelReadSession
        session.snapshots["taobao"] = ParcelReadResult("partial", listOf(ParcelPickup("测试驿站 · 东区", "01-002-003")))
        session.snapshots["pinduoduo"] = ParcelReadResult("login", emptyList())
        field(activity, "overview").setBoolean(activity, true)
        ParcelWebActivity::class.java.getDeclaredMethod("renderOverview").apply { isAccessible = true }.invoke(activity)
        val root = activity.findViewById<View>(android.R.id.content)
        root.measure(View.MeasureSpec.makeMeasureSpec(360, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(760, View.MeasureSpec.EXACTLY))
        root.layout(0, 0, 360, 760)
        val texts = views(root).filterIsInstance<TextView>()
        assertTrue(texts.any { it.text.contains("已读取 1 条取件码") })
        assertTrue(texts.any { it.text.contains("请先完成官方登录") })
        val code = texts.single { it.text.toString() == "01-002-003" }
        assertTrue(code.height >= code.lineHeight)
        assertTrue(code.width <= 360)
        assertEquals(0, code.layout.getEllipsisCount(0))
        val bitmap = Bitmap.createBitmap(360, 760, Bitmap.Config.ARGB_8888)
        root.draw(Canvas(bitmap))
        java.io.File(System.getProperty("java.io.tmpdir"), "hyt-parcel-overview-native.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        }
        controller.pause()
        assertTrue(session.snapshots.isEmpty())
        assertFalse(views(root).filterIsInstance<TextView>().any { it.text.toString() == "01-002-003" })
        controller.stop().destroy()
    }
}
