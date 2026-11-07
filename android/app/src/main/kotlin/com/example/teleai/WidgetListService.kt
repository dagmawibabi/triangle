package com.example.teleai

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray
import java.io.File

/// The rows of a home-screen widget's list. BriefWidget.payload says what
/// the widget shows; pictures are files the app saved, scaled down here so
/// a row stays within what a launcher accepts.
class WidgetListService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        Factory(applicationContext, intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID))

    private class Row(val title: String, val text: String, val subtitle: String, val image: String?, val link: String?)

    private class Factory(private val context: Context, private val widgetId: Int) : RemoteViewsFactory {
        private var rows: List<Row> = emptyList()

        /// This widget's own choices: pictures, and links a tap opens.
        private var images = true
        private var links = true

        /// The brief: every row shown whole, whatever "lines per item" says,
        /// since the list scrolls to the end.
        private var full = false

        override fun onCreate() {}

        override fun onDataSetChanged() {
            val payload = BriefWidget.payload(context, widgetId)
            images = payload?.optBoolean("images", true) ?: true
            links = payload?.optBoolean("links", true) ?: true
            full = payload?.optBoolean("full", false) ?: false
            val items = payload?.optJSONArray("items") ?: JSONArray()
            rows = (0 until items.length()).mapNotNull { i ->
                val o = items.optJSONObject(i) ?: return@mapNotNull null
                Row(
                    o.optString("t"),
                    o.optString("x"),
                    o.optString("s"),
                    o.optString("img").ifEmpty { null },
                    o.optString("link").ifEmpty { null },
                )
            }
        }

        override fun onDestroy() {
            rows = emptyList()
        }

        override fun getCount() = rows.size

        override fun getViewAt(position: Int): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_item)
            val row = rows.getOrNull(position) ?: return views
            val look = BriefWidget.Look.read(context)
            fun text(id: Int, value: String, color: Int, size: Float) {
                if (value.isEmpty()) {
                    views.setViewVisibility(id, View.GONE)
                    return
                }
                views.setViewVisibility(id, View.VISIBLE)
                views.setTextViewText(id, value)
                views.setTextColor(id, color)
                views.setTextViewTextSize(id, TypedValue.COMPLEX_UNIT_SP, size)
            }
            text(R.id.item_title, row.title, look.title, look.bodySize + 0.5f)
            text(R.id.item_text, row.text, look.body, look.bodySize)
            text(R.id.item_subtitle, row.subtitle, look.body, 11f)
            views.setInt(R.id.item_text, "setMaxLines", if (full) Int.MAX_VALUE else look.maxLines)
            val bitmap = if (look.images && images && row.image != null) bitmap(row.image) else null
            if (bitmap != null) {
                views.setImageViewBitmap(R.id.item_image, bitmap)
                views.setViewVisibility(R.id.item_image, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.item_image, View.GONE)
            }
            val fill = Intent().apply { if (links) row.link?.let { putExtra(BriefWidget.EXTRA_LINK, it) } }
            views.setOnClickFillInIntent(R.id.item_root, fill)
            return views
        }

        /// The picture at [path], at most 720 px wide.
        private fun bitmap(path: String): Bitmap? = try {
            val file = File(path)
            if (!file.exists()) {
                null
            } else {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(path, bounds)
                var sample = 1
                while (bounds.outWidth / (sample * 2) >= 720) sample *= 2
                BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
            }
        } catch (e: Throwable) {
            null
        }

        override fun getLoadingView(): RemoteViews? = null

        override fun getViewTypeCount() = 1

        override fun getItemId(position: Int) = position.toLong()

        override fun hasStableIds() = false
    }
}
