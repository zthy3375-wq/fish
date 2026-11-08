package org.handancampus.app.life

import com.google.zxing.BarcodeFormat
import com.google.zxing.MultiFormatWriter
import org.junit.Assert.*
import org.junit.Test

class ScreenQrReaderTest {
    private val code="https://h5.qiekj.com/skip?SN=123456789012345"
    @Test fun readsBlueScreenQrInPortraitPhoto() {
        val qr=MultiFormatWriter().encode(code,BarcodeFormat.QR_CODE,280,280)
        val width=480;val height=720;val image=IntArray(width*height){0xff222a35.toInt()}
        for(y in 0 until 320)for(x in 0 until 320)image[(y+160)*width+x+80]=0xfff5faff.toInt()
        for(y in 0 until 280)for(x in 0 until 280)image[(y+180)*width+x+100]=if(qr[x,y])0xff3159da.toInt() else 0xfff5faff.toInt()
        assertEquals(code,ScreenQrReader.decodePixels(width,height,image))
    }
    @Test fun retainsOrdinaryPrintedQrSupport() {
        val qr=MultiFormatWriter().encode(code,BarcodeFormat.QR_CODE,300,300)
        val pixels=IntArray(90000){if(qr[it%300,it/300])0xff000000.toInt() else 0xffffffff.toInt()}
        assertEquals(code,ScreenQrReader.decodePixels(300,300,pixels))
    }
    @Test fun invertedQrAndBlankImageAreHandled() {
        val qr=MultiFormatWriter().encode(code,BarcodeFormat.QR_CODE,300,300)
        assertEquals(code,ScreenQrReader.decodePixels(300,300,IntArray(90000){if(qr[it%300,it/300])0xffffffff.toInt() else 0xff000000.toInt()}))
        assertNull(ScreenQrReader.decodePixels(100,100,IntArray(10000){0xffffffff.toInt()}))
    }
    @Test fun smoothingRetainsDimensionsAndDoesNotMutateInput() {
        val bytes=byteArrayOf(0,100,100,0,100,100,0,0,0)
        val source=ScreenQrReader.Pixels(bytes,3,3);val result=ScreenQrReader.soften(source)
        assertEquals(3,result.width);assertEquals(3,result.height);assertTrue(result.matrix[0].toInt() in 1..99);assertEquals(0,bytes[0].toInt())
    }
    @Test(expected=IllegalArgumentException::class) fun rejectsUnboundedImages(){ScreenQrReader.decodePixels(3000,3000,intArrayOf())}
}
