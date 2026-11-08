package org.handancampus.app.life

import com.google.zxing.*
import com.google.zxing.common.HybridBinarizer

/** Image processing stays on-device; no scanned text or image is logged. */
internal object ScreenQrReader {
    fun reader(extra:Map<DecodeHintType,*> = emptyMap<DecodeHintType,Any>()):MultiFormatReader {
        val hints=HashMap<DecodeHintType,Any>();extra.forEach{(k,v)->if(v!=null)hints[k]=v}
        hints[DecodeHintType.POSSIBLE_FORMATS]=listOf(BarcodeFormat.QR_CODE)
        hints[DecodeHintType.TRY_HARDER]=true
        return MultiFormatReader().apply{setHints(hints)}
    }
    class Pixels(private val bytes:ByteArray,width:Int,height:Int):LuminanceSource(width,height) {
        override fun getMatrix()=bytes
        override fun getRow(y:Int,row:ByteArray?):ByteArray {
            val result=if(row!=null&&row.size>=width)row else ByteArray(width)
            System.arraycopy(bytes,y*width,result,0,width);return result
        }
    }
    /** Separable 5x5 Gaussian kernel suppresses LCD dot grids without moving coordinates. */
    fun soften(source:LuminanceSource):LuminanceSource {
        val w=source.width;val h=source.height;val input=source.matrix
        val weights=intArrayOf(1,4,6,4,1);val horizontal=IntArray(w*h);val out=ByteArray(w*h)
        for(y in 0 until h)for(x in 0 until w){var sum=0;for(k in -2..2)sum+=(input[y*w+(x+k).coerceIn(0,w-1)].toInt() and 255)*weights[k+2];horizontal[y*w+x]=sum}
        for(y in 0 until h)for(x in 0 until w){var sum=0;for(k in -2..2)sum+=horizontal[(y+k).coerceIn(0,h-1)*w+x]*weights[k+2];out[y*w+x]=((sum+128)/256).toByte()}
        return Pixels(out,w,h)
    }
    fun decodePixels(width:Int,height:Int,argb:IntArray):String? {
        require(width>0&&height>0&&width.toLong()*height<=2_000_000&&argb.size==width*height)
        val reader=reader()
        // Red-channel isolation improves contrast for blue LCD QR codes on bright white screens.
        for(channel in intArrayOf(16,-1,8,0)) {
            if(Thread.currentThread().isInterrupted)return null
            val bytes=ByteArray(argb.size){i->val p=argb[i];if(channel<0)(((p shr 16 and 255)+2*(p shr 8 and 255)+(p and 255))/4).toByte() else (p shr channel and 255).toByte()}
            val normal=Pixels(bytes,width,height)
            for(source in listOf(normal,soften(normal),normal.invert())){
                if(Thread.currentThread().isInterrupted)return null
                try{return reader.decodeWithState(BinaryBitmap(HybridBinarizer(source))).text}catch(_:ReaderException){}finally{reader.reset()}
            }
        }
        return null
    }
}
