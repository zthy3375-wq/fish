package org.handancampus.app.life

import android.content.ClipboardManager
import android.os.Looper
import android.os.PersistableBundle
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class ParcelCenterUiTest {
    private fun views(view: View): Sequence<View> = sequence {
        yield(view)
        if (view is ViewGroup) for (i in 0 until view.childCount) yieldAll(views(view.getChildAt(i)))
    }

    private fun find(activity: ParcelDirectoryActivity, label: String): View =
        views(activity.window.decorView).first {
            it.contentDescription == label || it is TextView && it.text.toString() == label
        }

    private fun render(activity: ParcelDirectoryActivity, state: JSONObject) {
        // Supply view state only in the test process. The installable APK has no fixture entry.
        activity.javaClass.getDeclaredField("latest").apply { isAccessible = true }.set(activity, state)
        activity.javaClass.getDeclaredMethod("render", Boolean::class.javaPrimitiveType).apply { isAccessible = true }
            .invoke(activity, false)
        shadowOf(Looper.getMainLooper()).idle()
    }

    @Test fun settingsBackAndMissingDataAreActionable() {
        Robolectric.buildActivity(ParcelDirectoryActivity::class.java).create().start().use { controller ->
            val activity = controller.get()
            render(activity, JSONObject().put("state", "unconfigured"))
            assertNotNull(find(activity, "校园取件"))
            assertNotNull(find(activity, "待取件数量未知"))
            assertNotNull(find(activity, "取件数据源未配置"))
            assertTrue(views(activity.window.decorView).any { it is SwipeRefreshLayout && it.isEnabled })
            assertTrue(find(activity, "设置").performClick())
            assertNotNull(find(activity, "手机号绑定"))
            assertNotNull(find(activity, "脱敏诊断"))
            assertTrue(views(activity.window.decorView).any { it is SwipeRefreshLayout && !it.isEnabled })
            activity.onBackPressedDispatcher.onBackPressed()
            assertNotNull(find(activity, "校园取件"))
            assertTrue(find(activity, "返回").performClick())
            assertTrue(activity.isFinishing)
        }
    }

    @Test fun authenticFieldsShapePreservesLeadingZerosAndCopiesOnlyTheCode() {
        Robolectric.buildActivity(ParcelDirectoryActivity::class.java).create().start().use { controller ->
            val activity = controller.get()
            val parcels = JSONArray().put(JSONObject().put("carrier", "zto").put("pickupCode", "000-A")
                .put("trackingNumber", "TEST0001"))
            render(activity, JSONObject().put("state", "ready").put("items", parcels).put("maskedPhone", "130****0000"))
            assertNotNull(find(activity, "中通快递"))
            assertNotNull(find(activity, "入库时间未提供"))
            assertNotNull(find(activity, "000-A"))
            assertTrue(find(activity, "复制").performClick())
            val clip = activity.getSystemService(ClipboardManager::class.java).primaryClip!!
            assertEquals("000-A", clip.getItemAt(0).text)
            val extras: PersistableBundle = clip.description.extras!!
            assertTrue(extras.getBoolean("android.content.extra.IS_SENSITIVE"))
            render(activity, JSONObject().put("state", "empty").put("items", JSONArray()))
            assertNotNull(find(activity, "暂无待取快递"))
            render(activity, JSONObject().put("state", "expired"))
            assertNotNull(find(activity, "授权已失效"))
        }
    }
}
