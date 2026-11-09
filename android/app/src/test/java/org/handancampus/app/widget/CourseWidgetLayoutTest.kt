package org.handancampus.app.widget

import android.app.Application
import android.content.Context
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import org.handancampus.app.R
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.time.LocalDateTime

/** Inflate the production RemoteViews: tests actual Android measurement, not a web imitation. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [28], application = Application::class, qualifiers = "mdpi")
class CourseWidgetLayoutTest {
    private val now = LocalDateTime.parse("2026-11-10T03:05:00")
    private fun model(many: Boolean = false): WidgetSchedule {
        val json = JSONObject(javaClass.classLoader!!.getResourceAsStream("compact-sparse.json")!!.bufferedReader().use { it.readText() })
        if (many) for (i in 0..2) json.getJSONArray("courses").put(JSONObject("""{"name":"课程$i","room":"D10$i","teacher":"教师","color":"green","day":3,"weeks":[9],"start":"${"%02d".format(8+i)}:00","end":"${10+i}:30"}"""))
        return WidgetSchedule(json)
    }
    private fun inflate(width: Int, height: Int, many: Boolean = false): View {
        val context = RuntimeEnvironment.getApplication() as Context
        val remote = CourseWidgetProvider.render(context,model(many),0,now,width,height)
        val view = remote.apply(context,FrameLayout(context))
        view.measure(View.MeasureSpec.makeMeasureSpec(width,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(height,View.MeasureSpec.EXACTLY))
        view.layout(0,0,width,height)
        return view
    }
    private fun tree(view: View, depth: Int = 0): String {
        val name = if(view.id == View.NO_ID) view.javaClass.simpleName else runCatching { view.resources.getResourceEntryName(view.id) }.getOrDefault("unknown")
        val own = " ".repeat(depth)+name+"="+view.width+"x"+view.height+" lp="+view.layoutParams.height+" text="+(if(view is TextView)view.text else "")+"\n"
        return own+if(view is android.view.ViewGroup)(0 until view.childCount).joinToString(""){tree(view.getChildAt(it),depth+1)} else ""
    }
    @Test fun sparseCardDoesNotFillOldTallSlot() {
        val view = inflate(344,300)
        val card = view.findViewById<View>(R.id.widget_root)
        assertTrue("Sparse widget should wrap below 170dp, was ${card.height}\n${tree(view)}",card.height < 170)
        assertEquals(300,view.height)
        val bitmap = android.graphics.Bitmap.createBitmap(344,300,android.graphics.Bitmap.Config.ARGB_8888)
        view.draw(android.graphics.Canvas(bitmap))
        java.io.File(java.lang.System.getProperty("java.io.tmpdir"),"hyt-compact-widget-native.png").outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) }
        assertEquals("形势与政策七",view.findViewById<TextView>(R.id.widget_course_name).text.toString())
        assertTrue(view.findViewById<TextView>(R.id.widget_course_time).text.contains("14:30"))
    }
    @Test fun smallCardKeepsRoomAndTimeInsideBounds() {
        val view = inflate(300,150)
        assertTrue(view.findViewById<View>(R.id.widget_root).height <= 150)
        val time = view.findViewById<TextView>(R.id.widget_course_time)
        assertTrue("Time text must remain fully visible", time.height >= time.lineHeight)
        assertEquals(0,time.layout.getEllipsisCount(0))
        assertEquals(View.GONE,view.findViewById<View>(R.id.widget_updated).visibility)
        assertTrue(view.findViewById<TextView>(R.id.widget_course_place).text.contains("A06J104"))
        assertTrue(view.findViewById<TextView>(R.id.widget_course_time).text.contains("15:55"))
    }
    @Test fun tinyCardCombinesPlaceWithTime() {
        val view = inflate(300,117)
        assertTrue("Tiny card exceeds its slot",view.findViewById<View>(R.id.widget_root).height <= 117)
        assertTrue(view.findViewById<TextView>(R.id.widget_course_time).text.contains("A06J104"))
    }
    @Test fun overflowHasAnExplicitCountInsteadOfPartialRows() {
        val view = inflate(300,150,true)
        assertTrue(view.findViewById<View>(R.id.widget_root).height <= 150)
        val tomorrow = view.findViewById<android.widget.LinearLayout>(R.id.widget_tomorrow)
        assertEquals(2,tomorrow.childCount)
        assertTrue(tomorrow.getChildAt(1).findViewById<TextView>(R.id.widget_empty).text.contains("还有 3 节"))
    }
    @Test @Config(qualifiers = "night-mdpi") fun darkTextHasTheNightPalette() {
        val view = inflate(344,170)
        assertEquals(0xfff1edf7.toInt(),view.findViewById<TextView>(R.id.widget_course_name).currentTextColor)
    }
}
