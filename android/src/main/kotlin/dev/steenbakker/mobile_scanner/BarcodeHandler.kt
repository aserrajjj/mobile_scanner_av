package dev.steenbakker.mobile_scanner

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

class BarcodeHandler(binaryMessenger: BinaryMessenger) : EventChannel.StreamHandler {

    private var eventSink: EventChannel.EventSink? = null

    private val eventChannel = EventChannel(
        binaryMessenger,
        "dev.steenbakker.mobile_scanner/scanner/event"
    )

    init {
        eventChannel.setStreamHandler(this)
    }

    fun publishError(errorCode: String, errorMessage: String, errorDetails: Any?) {
        Handler(Looper.getMainLooper()).post {
            eventSink?.error(errorCode, errorMessage, errorDetails)
        }
    }

    fun publishEvent(event: Map<String, Any?>) {
        Handler(Looper.getMainLooper()).post {
            val outgoingEvent = event.toMutableMap()
            val performance = event["performance"] as? Map<*, *>

            if (performance != null) {
                val completedPerformance = performance.entries.associate {
                    it.key.toString() to it.value
                }.toMutableMap()
                completedPerformance["eventSentUs"] =
                    SystemClock.elapsedRealtimeNanos() / 1_000L
                completedPerformance["eventSentEpochUs"] =
                    System.currentTimeMillis() * 1_000L
                outgoingEvent["performance"] = completedPerformance
            }

            eventSink?.success(outgoingEvent)
        }
    }

    fun dispose() {
        eventChannel.setStreamHandler(null)
    }

    override fun onListen(event: Any?, eventSink: EventChannel.EventSink?) {
        this.eventSink = eventSink
    }

    override fun onCancel(event: Any?) {
        this.eventSink = null
    }
}
