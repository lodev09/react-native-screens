package com.swmansion.rnscreens.gamma.tabs.event

import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.events.Event
import com.swmansion.rnscreens.gamma.common.NamingAwareEventType

class TabScreenWillAppearEvent(
    surfaceId: Int,
    viewId: Int,
) : Event<TabScreenWillAppearEvent>(surfaceId, viewId),
    NamingAwareEventType {
    override fun getEventName() = EVENT_NAME

    override fun getEventRegistrationName() = EVENT_REGISTRATION_NAME

    // All events for a given view can be coalesced.
    override fun getCoalescingKey(): Short = 0

    override fun getEventData(): WritableMap? = Arguments.createMap()

    companion object : NamingAwareEventType {
        const val EVENT_NAME = "topWillAppear"
        const val EVENT_REGISTRATION_NAME = "onWillAppear"

        override fun getEventName() = EVENT_NAME

        override fun getEventRegistrationName() = EVENT_REGISTRATION_NAME
    }
}
