package org.handancampus.app.life

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.*
import com.google.zxing.LuminanceSource
import com.google.zxing.Result
import com.google.zxing.client.android.Intents
import com.journeyapps.barcodescanner.*
import com.journeyapps.barcodescanner.camera.CameraSettings
import java.util.concurrent.Executors

/** Explicit portrait activity: the library's default CaptureActivity requests landscape. */
class CampusScanActivity:CaptureActivity() {
    private lateinit var scanner:DecoratedBarcodeView
    private lateinit var hint:TextView
    private lateinit var album:Button
    private val worker=Executors.newSingleThreadExecutor()
    private var readingImage=false
    private var torch=false
    private fun dp(value:Int)=(value*resources.displayMetrics.density).toInt()
    override fun initializeContent():DecoratedBarcodeView {
        val root=FrameLayout(this).apply{setBackgroundColor(Color.BLACK);fitsSystemWindows=true}
        scanner=DecoratedBarcodeView(this)
        root.addView(scanner,FrameLayout.LayoutParams(-1,-1))
        val top=LinearLayout(this).apply{orientation=LinearLayout.HORIZONTAL;gravity=Gravity.CENTER_VERTICAL;setPadding(dp(12),dp(8),dp(12),dp(8));setBackgroundColor(0xCC101722.toInt())}
        fun button(label:String,action:()->Unit)=Button(this).apply{text=label;isAllCaps=false;setTextColor(Color.WHITE);setBackgroundColor(Color.TRANSPARENT);minHeight=dp(48);setOnClickListener{action()}}
        top.addView(button("返回"){setResult(Activity.RESULT_CANCELED);finish()})
        top.addView(TextView(this).apply{text="扫一扫";textSize=19f;setTextColor(Color.WHITE);gravity=Gravity.CENTER},LinearLayout.LayoutParams(0,dp(48),1f))
        val light=button("手电筒"){}
        light.isEnabled=packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_FLASH)
        light.setOnClickListener{torch=!torch;if(torch)scanner.setTorchOn() else scanner.setTorchOff();light.text=if(torch)"关闭手电" else "手电筒"}
        top.addView(light)
        root.addView(top,FrameLayout.LayoutParams(-1,-2,Gravity.TOP))
        val bottom=LinearLayout(this).apply{orientation=LinearLayout.VERTICAL;gravity=Gravity.CENTER;setPadding(dp(20),dp(14),dp(20),dp(18));setBackgroundColor(0xDD101722.toInt())}
        hint=TextView(this).apply{text="将二维码完整放入方框\n屏幕码请关闭手电，稍微移远并避开反光";textSize=15f;gravity=Gravity.CENTER;setTextColor(Color.WHITE)}
        bottom.addView(hint)
        val actions=LinearLayout(this).apply{gravity=Gravity.CENTER}
        actions.addView(button("重新对焦"){if(!readingImage){scanner.pause();scanner.barcodeView.cameraSettings.focusMode=CameraSettings.FocusMode.AUTO;scanner.resume()}})
        album=button("从相册识别"){
            try {startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply{type="image/*";addCategory(Intent.CATEGORY_OPENABLE)},41)}
            catch(_:Exception){hint.text="无法打开相册，请继续扫描机身二维码"}
        }
        actions.addView(album);bottom.addView(actions)
        root.addView(bottom,FrameLayout.LayoutParams(-1,-2,Gravity.BOTTOM))
        setContentView(root)
        return scanner
    }
    override fun onCreate(savedInstanceState:Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.statusBarColor=Color.BLACK;window.navigationBarColor=Color.BLACK
        scanner.setStatusText("")
        val side=minOf(dp(280),(resources.displayMetrics.widthPixels*.74).toInt())
        scanner.barcodeView.framingRectSize=Size(side,side)
        scanner.barcodeView.cameraSettings.apply{isAutoFocusEnabled=true;isContinuousFocusEnabled=true;isAutoTorchEnabled=false}
        scanner.barcodeView.decoderFactory=DecoderFactory{hints->
            object:Decoder(ScreenQrReader.reader(hints)) {
                private var frame=0
                private val nativeReader=runCatching{NativeScreenQrReader()}.getOrNull()
                override fun decode(source:LuminanceSource):Result? {
                    val input=if(frame++%2==1)ScreenQrReader.soften(source) else source
                    val text=runCatching{nativeReader?.read(input)}.getOrNull()
                    return if(text!=null)Result(text,null,emptyArray(),com.google.zxing.BarcodeFormat.QR_CODE) else super.decode(input)
                }
            }
        }
    }
    override fun onResume(){super.onResume();if(readingImage)scanner.pause()}
    @Deprecated("Android Activity callback retained for CaptureActivity compatibility")
    override fun onActivityResult(requestCode:Int,resultCode:Int,data:Intent?) {
        super.onActivityResult(requestCode,resultCode,data)
        if(requestCode!=41||resultCode!=Activity.RESULT_OK)return
        val uri=data?.data ?: return
        readingImage=true;album.isEnabled=false;scanner.pause();hint.text="正在手机上识别图片…"
        worker.execute {
            val value=runCatching {
                val bounds=BitmapFactory.Options().apply{inJustDecodeBounds=true}
                contentResolver.openInputStream(uri)?.use{BitmapFactory.decodeStream(it,null,bounds)}
                if(bounds.outWidth<=0||bounds.outHeight<=0||bounds.outWidth>30000||bounds.outHeight>30000)error("invalid image")
                var sample=1
                while((bounds.outWidth.toLong()/sample)*(bounds.outHeight/sample)>2_000_000)sample*=2
                val bitmap=contentResolver.openInputStream(uri)?.use{BitmapFactory.decodeStream(it,null,BitmapFactory.Options().apply{inSampleSize=sample})} ?: error("invalid image")
                try{val pixels=IntArray(bitmap.width*bitmap.height);bitmap.getPixels(pixels,0,bitmap.width,0,0,bitmap.width,bitmap.height);runCatching{NativeScreenQrReader().readPixels(bitmap.width,bitmap.height,pixels)}.getOrNull() ?: ScreenQrReader.decodePixels(bitmap.width,bitmap.height,pixels)}finally{bitmap.recycle()}
            }.getOrNull()
            runOnUiThread {
                if(isFinishing||isDestroyed)return@runOnUiThread
                readingImage=false;album.isEnabled=true
                if(value!=null){setResult(Activity.RESULT_OK,Intent().putExtra(Intents.Scan.RESULT,value).putExtra(Intents.Scan.RESULT_FORMAT,"QR_CODE"));finish()}
                else{hint.text="图片未识别到二维码\n请选清晰近照，或返回相机调整距离与角度";scanner.resume()}
            }
        }
    }
    override fun onDestroy(){worker.shutdownNow();super.onDestroy()}
}
