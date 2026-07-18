package com.mobilecode.app

import android.app.Activity
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowInsets
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.util.concurrent.atomic.AtomicInteger

/** Debug-only, non-production surface for end-to-end Phone Use acceptance. */
class PhoneUseTakeoutQaActivity : Activity() {
    @Volatile
    var stage: String = "launching"
        private set

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showSearch()
    }

    private fun showSearch(): Unit = render("search") {
        heading("QA Takeout Sandbox")
        editable("Search restaurants")
        button("Search") { showRestaurants() }
    }

    private fun showRestaurants(): Unit = render("restaurants") {
        heading("Restaurant results")
        button("Golden Noodle Shop") { showMenu(cartAdded = false) }
    }

    private fun showMenu(cartAdded: Boolean): Unit = render(if (cartAdded) "menu_cart" else "menu") {
        heading("Golden Noodle Shop menu")
        if (!cartAdded) {
            button("Add beef noodles") { showMenu(cartAdded = true) }
        } else {
            heading("Cart has 1 fake item")
            button("Open cart") { showCart() }
        }
    }

    private fun showCart(): Unit = render("cart") {
        heading("QA cart subtotal 18 credits")
        editable("Delivery note fake slot")
        button("Review order") { showReview() }
    }

    private fun showReview(): Unit = render("review") {
        heading("Final QA order preview digest bound")
        button("Confirm order") {
            commitAttempts.incrementAndGet()
            heading("QA commit attempted")
        }
    }

    private fun render(nextStage: String, content: LinearLayout.() -> Unit) {
        stage = nextStage
        currentStage = nextStage
        val density = resources.displayMetrics.density
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding((24 * density).toInt(), (32 * density).toInt(), (24 * density).toInt(), (32 * density).toInt())
            content()
        }
        val scrollView = ScrollView(this).apply {
            setBackgroundColor(Color.rgb(248, 248, 252))
            addView(column)
            setOnApplyWindowInsetsListener { view, insets ->
                val left: Int
                val top: Int
                val right: Int
                val bottom: Int
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val systemBars = insets.getInsets(WindowInsets.Type.systemBars())
                    left = systemBars.left
                    top = systemBars.top
                    right = systemBars.right
                    bottom = systemBars.bottom
                } else {
                    @Suppress("DEPRECATION")
                    left = insets.systemWindowInsetLeft
                    @Suppress("DEPRECATION")
                    top = insets.systemWindowInsetTop
                    @Suppress("DEPRECATION")
                    right = insets.systemWindowInsetRight
                    @Suppress("DEPRECATION")
                    bottom = insets.systemWindowInsetBottom
                }
                view.setPadding(left, top, right, bottom)
                insets
            }
        }
        setContentView(scrollView)
    }

    private fun LinearLayout.heading(value: String) {
        addView(TextView(this@PhoneUseTakeoutQaActivity).apply {
            text = value
            textSize = 22f
            setTextColor(Color.rgb(28, 28, 32))
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
            setPadding(0, 12, 0, 20)
        })
    }

    private fun LinearLayout.editable(label: String) {
        addView(EditText(this@PhoneUseTakeoutQaActivity).apply {
            hint = label
            contentDescription = label
            setTextColor(Color.rgb(28, 28, 32))
            setHintTextColor(Color.rgb(95, 95, 105))
            isSingleLine = true
            minHeight = 64
        })
    }

    private fun LinearLayout.button(label: String, action: () -> Unit) {
        addView(Button(this@PhoneUseTakeoutQaActivity).apply {
            text = label
            contentDescription = label
            minHeight = 72
            setOnClickListener { action() }
        })
    }

    companion object {
        val commitAttempts = AtomicInteger(0)

        @Volatile
        var currentStage: String = "not_started"
            private set
    }
}
