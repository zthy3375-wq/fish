package org.handancampus.app.life

import android.graphics.Bitmap
import com.google.zxing.LuminanceSource
import zxingcpp.BarcodeReader

/** One instance per decoding thread; all pixels and decoded data remain local. */
internal class NativeScreenQrReader {
    private val reader=BarcodeReader(BarcodeReader.Options(formats=setOf(BarcodeReader.Format.QR_CODE),
        tryHarder=true,tryRotate=true,tryInvert=true,tryDownscale=true,maxNumberOfSymbols=1))
    fun read(source:LuminanceSource):String? {
        val bytes=source.matrix
        val pixels=IntArray(source.width*source.height){val v=bytes[it].toInt() and 255;0xff000000.toInt() or (v shl 16) or (v shl 8) or v}
        val bitmap=Bitmap.createBitmap(pixels,source.width,source.height,Bitmap.Config.ARGB_8888)
        return try{reader.read(bitmap).firstOrNull{it.error==null}?.text}finally{bitmap.recycle()}
    }
    fun readPixels(width:Int,height:Int,argb:IntArray):String? {
        require(width>0&&height>0&&width.toLong()*height<=2_000_000&&argb.size==width*height)
        for(channel in intArrayOf(16,-1,8,0)) {
            if(Thread.currentThread().isInterrupted)return null
            val bytes=ByteArray(argb.size){i->val p=argb[i];if(channel<0)(((p shr 16 and 255)+2*(p shr 8 and 255)+(p and 255))/4).toByte() else (p shr channel and 255).toByte()}
            val normal=ScreenQrReader.Pixels(bytes,width,height)
            read(normal)?.let{return it}
            read(ScreenQrReader.soften(normal))?.let{return it}
        }
        return null
    }
}
