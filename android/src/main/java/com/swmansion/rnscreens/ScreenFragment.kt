package com.swmansion.rnscreens

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.ViewParent
import android.widget.FrameLayout
import androidx.fragment.app.Fragment
import com.facebook.react.bridge.ReactContext
import com.facebook.react.bridge.UiThreadUtil
import com.facebook.react.uimanager.UIManagerHelper
import com.facebook.react.uimanager.events.Event
import com.facebook.react.uimanager.events.EventDispatcher
import com.swmansion.rnscreens.events.HeaderBackButtonClickedEvent
import com.swmansion.rnscreens.events.ScreenAppearEvent
import com.swmansion.rnscreens.events.ScreenDisappearEvent
import com.swmansion.rnscreens.events.ScreenDismissedEvent
import com.swmansion.rnscreens.events.ScreenTransitionProgressEvent
import com.swmansion.rnscreens.events.ScreenWillAppearEvent
import com.swmansion.rnscreens.events.ScreenWillDisappearEvent
import com.swmansion.rnscreens.ext.recycle
import kotlin.math.max
import kotlin.math.min

open class ScreenFragment :
    Fragment,
    ScreenFragmentWrapper {
    enum class ScreenLifecycleEvent {
        DID_APPEAR,
        WILL_APPEAR,
        DID_DISAPPEAR,
        WILL_DISAPPEAR,
    }

    override val fragment: Fragment
        get() = this

    // if we call empty constructor, there is no screen to be assigned so not sure why it is suggested
    @Suppress("JoinDeclarationAndAssignment")
    override lateinit var screen: Screen

    override val childScreenContainers: MutableList<ScreenContainer> = ArrayList()

    private var shouldUpdateOnResume = false

    // if we don't set it, it will be 0.0f at the beginning so the progress will not be sent
    // due to progress value being already 0.0f
    private var transitionProgress = -1f

    // those 2 vars are needed since sometimes the events would be dispatched twice in child containers
    // (should only happen if parent has `NONE` animation) and we don't need too complicated logic.
    // We just check if, after the event was dispatched, its "counter-event" has been also dispatched before sending the same event again.
    // We do it for 'willAppear' -> 'willDisappear' and 'appear' -> 'disappear'
    private var canDispatchWillAppear = true
    private var canDispatchAppear = true

    // we want to know if we are currently transitioning in order not to fire lifecycle events
    // in nested fragments. See more explanation in dispatchViewAnimationEvent
    private var isTransitioning = false

    constructor() {
        throw IllegalStateException(
            "Screen fragments should never be restored. Follow instructions from https://github.com/software-mansion/react-native-screens/issues/17#issuecomment-424704067 to properly configure your main activity.",
        )
    }

    @SuppressLint("ValidFragment")
    constructor(screenView: Screen) : super() {
        screen = screenView
    }

    override fun onResume() {
        super.onResume()
        if (shouldUpdateOnResume) {
            shouldUpdateOnResume = false
            ScreenWindowTraits.trySetWindowTraits(screen, tryGetActivity(), tryGetContext())
        }
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View? {
        screen.layoutParams =
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        val wrapper =
            context?.let { ScreensFrameLayout(it) }?.apply {
                addView(screen.recycle())
            }
        return wrapper
    }

    private class ScreensFrameLayout(
        context: Context,
    ) : FrameLayout(context) {
        /**
         * This method implements a workaround for RN's autoFocus functionality. Because of the way
         * autoFocus is implemented it dismisses soft keyboard in fragment transition
         * due to change of visibility of the view at the start of the transition. Here we override the
         * call to `clearFocus` when the visibility of view is `INVISIBLE` since `clearFocus` triggers the
         * hiding of the keyboard in `ReactEditText.java`.
         */
        override fun clearFocus() {
            if (visibility != INVISIBLE) {
                super.clearFocus()
            }
        }
    }

    override fun onContainerUpdate() {
        updateWindowTraits()
    }

    private fun updateWindowTraits() {
        val activity: Activity? = activity
        if (activity == null) {
            shouldUpdateOnResume = true
            return
        }
        ScreenWindowTraits.trySetWindowTraits(screen, activity, tryGetContext())
    }

    // Plain ScreenFragments can not be translucent
    override fun isTranslucent() = false

    override fun tryGetActivity(): Activity? {
        activity?.let { return it }
        val context = screen.context
        if (context is ReactContext && context.currentActivity != null) {
            return context.currentActivity
        }
        var parent: ViewParent? = screen.container
        while (parent != null) {
            if (parent is Screen) {
                val fragment = parent.fragment
                fragment?.activity?.let { return it }
            }
            parent = parent.parent
        }
        return null
    }

    override fun tryGetContext(): ReactContext? {
        if (context is ReactContext) {
            return context as ReactContext
        }
        if (screen.context is ReactContext) {
            return screen.context as ReactContext
        }
        var parent: ViewParent? = screen.container
        while (parent != null) {
            if (parent is Screen) {
                if (parent.context is ReactContext) {
                    return parent.context as ReactContext
                }
            }
            parent = parent.parent
        }
        return null
    }

    override fun canDispatchLifecycleEvent(event: ScreenLifecycleEvent): Boolean =
        when (event) {
            ScreenLifecycleEvent.WILL_APPEAR -> canDispatchWillAppear
            ScreenLifecycleEvent.DID_APPEAR -> canDispatchAppear
            ScreenLifecycleEvent.WILL_DISAPPEAR -> !canDispatchWillAppear
            ScreenLifecycleEvent.DID_DISAPPEAR -> !canDispatchAppear
        }

    override fun updateLastEventDispatched(event: ScreenLifecycleEvent) {
        when (event) {
            ScreenLifecycleEvent.WILL_APPEAR -> canDispatchWillAppear = false
            ScreenLifecycleEvent.DID_APPEAR -> canDispatchAppear = false
            ScreenLifecycleEvent.WILL_DISAPPEAR -> canDispatchWillAppear = true
            ScreenLifecycleEvent.DID_DISAPPEAR -> canDispatchAppear = true
        }
    }

    private fun dispatchOnWillAppear() {
        dispatchLifecycleEvent(ScreenLifecycleEvent.WILL_APPEAR, this)
        dispatchTransitionProgressEvent(0.0f, false)
    }

    private fun dispatchOnAppear() {
        dispatchLifecycleEvent(ScreenLifecycleEvent.DID_APPEAR, this)
        dispatchTransitionProgressEvent(1.0f, false)
    }

    private fun dispatchOnWillDisappear() {
        dispatchLifecycleEvent(ScreenLifecycleEvent.WILL_DISAPPEAR, this)
        dispatchTransitionProgressEvent(0.0f, true)
    }

    private fun dispatchOnDisappear() {
        dispatchLifecycleEvent(ScreenLifecycleEvent.DID_DISAPPEAR, this)
        dispatchTransitionProgressEvent(1.0f, true)
    }

    override fun dispatchLifecycleEvent(
        event: ScreenLifecycleEvent,
        fragmentWrapper: ScreenFragmentWrapper,
    ) {
        val fragment = fragmentWrapper.fragment
        if (fragment is ScreenStackFragment && fragment.canDispatchLifecycleEvent(event)) {
            fragment.screen.let {
                fragmentWrapper.updateLastEventDispatched(event)
                val surfaceId = UIManagerHelper.getSurfaceId(it)
                val lifecycleEvent: Event<*> =
                    when (event) {
                        ScreenLifecycleEvent.WILL_APPEAR -> ScreenWillAppearEvent(surfaceId, it.id)
                        ScreenLifecycleEvent.DID_APPEAR -> ScreenAppearEvent(surfaceId, it.id)
                        ScreenLifecycleEvent.WILL_DISAPPEAR -> ScreenWillDisappearEvent(surfaceId, it.id)
                        ScreenLifecycleEvent.DID_DISAPPEAR -> ScreenDisappearEvent(surfaceId, it.id)
                    }
                val screenContext = screen.context as ReactContext
                val eventDispatcher: EventDispatcher? =
                    UIManagerHelper.getEventDispatcherForReactTag(screenContext, screen.id)
                eventDispatcher?.dispatchEvent(lifecycleEvent)
                fragmentWrapper.dispatchLifecycleEventInChildContainers(event)
            }
        }
    }

    override fun dispatchLifecycleEventInChildContainers(event: ScreenLifecycleEvent) {
        childScreenContainers.filter { it.screenCount > 0 }.forEach {
            it.topScreen?.fragmentWrapper?.let { fragment -> dispatchLifecycleEvent(event, fragment) }
        }
    }

    override fun dispatchHeaderBackButtonClickedEvent() {
        val screenContext = screen.context as ReactContext
        val surfaceId = UIManagerHelper.getSurfaceId(screenContext)
        UIManagerHelper
            .getEventDispatcherForReactTag(screenContext, screen.id)
            ?.dispatchEvent(HeaderBackButtonClickedEvent(surfaceId, screen.id))
    }

    override fun dispatchTransitionProgressEvent(
        alpha: Float,
        closing: Boolean,
    ) {
        if (this is ScreenStackFragment) {
            if (transitionProgress != alpha) {
                transitionProgress = max(0.0f, min(1.0f, alpha))
                val coalescingKey = getCoalescingKey(transitionProgress)
                val container: ScreenContainer? = screen.container
                val goingForward = if (container is ScreenStack) container.goingForward else false
                val screenContext = screen.context as ReactContext
                UIManagerHelper
                    .getEventDispatcherForReactTag(screenContext, screen.id)
                    ?.dispatchEvent(
                        ScreenTransitionProgressEvent(
                            UIManagerHelper.getSurfaceId(screenContext),
                            screen.id,
                            transitionProgress,
                            closing,
                            goingForward,
                            coalescingKey,
                        ),
                    )
            }
        }
    }

    override fun addChildScreenContainer(container: ScreenContainer) {
        childScreenContainers.add(container)
    }

    override fun removeChildScreenContainer(container: ScreenContainer) {
        childScreenContainers.remove(container)
    }

    override fun onViewAnimationStart() {
        dispatchViewAnimationEvent(false)
    }

    override fun onViewAnimationEnd() {
        dispatchViewAnimationEvent(true)
    }

    private fun dispatchViewAnimationEvent(animationEnd: Boolean) {
        isTransitioning = !animationEnd
        // if parent fragment is transitioning, we do not want the events dispatched from the child,
        // since we subscribe to parent's animation start/end and dispatch events in child from there
        // check for `isTransitioning` should be enough since the child's animation should take only
        // 20ms due to always being `StackAnimation.NONE` when nested stack being pushed
        val parent = parentFragment
        if (parent == null || (parent is ScreenFragment && !parent.isTransitioning)) {
            // onViewAnimationStart/End is triggered from View#onAnimationStart/End method of the fragment's root
            // view. We override an appropriate method of the StackFragment's
            // root view in order to achieve this.
            if (isResumed) {
                // Android dispatches the animation start event for the fragment that is being added first
                // however we want the one being dismissed first to match iOS. It also makes more sense from
                // a navigation point of view to have the disappear event first.
                // Since there are no explicit relationships between the fragment being added / removed the
                // practical way to fix this is delaying dispatching the appear events at the end of the
                // frame.
                UiThreadUtil.runOnUiThread {
                    if (animationEnd) dispatchOnAppear() else dispatchOnWillAppear()
                }
            } else {
                if (animationEnd) dispatchOnDisappear() else dispatchOnWillDisappear()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        val container = screen.container
        if (container == null || !container.hasScreen(this.screen.fragmentWrapper)) {
            // we only send dismissed even when the screen has been removed from its container
            val screenContext = screen.context
            if (screenContext is ReactContext) {
                val surfaceId = UIManagerHelper.getSurfaceId(screenContext)
                UIManagerHelper
                    .getEventDispatcherForReactTag(screenContext, screen.id)
                    ?.dispatchEvent(ScreenDismissedEvent(surfaceId, screen.id))
            }
        }
        childScreenContainers.clear()
    }

    companion object {
        const val TAG = "ScreenFragment"

        fun getCoalescingKey(progress: Float): Short {
            /* We want value of 0 and 1 to be always dispatched so we base coalescing key on the progress:
                 - progress is 0 -> key 1
                 - progress is 1 -> key 2
                 - progress is between 0 and 1 -> key 3
             */
            return (
                if (progress == 0.0f) {
                    1
                } else if (progress == 1.0f) {
                    2
                } else {
                    3
                }
            ).toShort()
        }
    }
}
