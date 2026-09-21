package kr.co.hirealty.personalcenter.stable;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.view.View;
import android.widget.RemoteViews;

import org.json.JSONObject;

import java.util.List;

public class TodayBoardWidgetProvider extends AppWidgetProvider {
    private static final int[] ROW_IDS = {
        R.id.widget_row1, R.id.widget_row2, R.id.widget_row3
    };

    @Override
    public void onUpdate(Context context, AppWidgetManager manager, int[] appWidgetIds) {
        for (int id : appWidgetIds) updateOne(context, manager, id);
    }

    public static void updateAll(Context context) {
        AppWidgetManager manager = AppWidgetManager.getInstance(context);
        ComponentName provider = new ComponentName(context, TodayBoardWidgetProvider.class);
        int[] ids = manager.getAppWidgetIds(provider);
        for (int id : ids) updateOne(context, manager, id);
    }

    private static PendingIntent openPendingIntent(Context context) {
        Intent i = new Intent(context, MainActivity.class);
        i.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        return PendingIntent.getActivity(
            context, 420001, i,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
    }

    private static PendingIntent completePendingIntent(Context context, JSONObject item, int slot) {
        String key = item.optString("key", "");
        Intent i = new Intent(context, TodayBoardReceiver.class);
        i.setAction(TodayBoardManager.ACTION_COMPLETE);
        i.putExtra("key", key);
        i.putExtra("kind", item.optString("kind", ""));
        i.putExtra("itemId", item.optString("itemId", ""));
        i.putExtra("date", item.optString("date", TodayBoardManager.today()));
        i.putExtra("label", item.optString("label", ""));
        int request = Math.abs(("widget|" + key + "|" + slot).hashCode());
        return PendingIntent.getBroadcast(
            context, request, i,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
    }

    private static void updateOne(Context context, AppWidgetManager manager, int appWidgetId) {
        RemoteViews v = new RemoteViews(context.getPackageName(), R.layout.widget_today_board);
        List<JSONObject> items = TodayBoardManager.itemsForDate(context, TodayBoardManager.today());
        int total = items.size();

        v.setTextViewText(R.id.widget_title, "오늘 할 일");
        v.setTextViewText(R.id.widget_count, total > 0 ? total + "개 남음" : "오늘 완료");
        v.setOnClickPendingIntent(R.id.widget_header, openPendingIntent(context));

        if (total == 0) {
            v.setViewVisibility(R.id.widget_empty, View.VISIBLE);
            v.setTextViewText(R.id.widget_empty, "오늘 할 일을 모두 끝냈습니다 ✓");
            v.setOnClickPendingIntent(R.id.widget_empty, openPendingIntent(context));
        } else {
            v.setViewVisibility(R.id.widget_empty, View.GONE);
        }

        for (int i = 0; i < ROW_IDS.length; i++) {
            int rowId = ROW_IDS[i];
            if (i < total) {
                JSONObject item = items.get(i);
                String label = item.optString("label", "할 일");
                if (i == ROW_IDS.length - 1 && total > ROW_IDS.length) {
                    label = label + "  · +" + (total - ROW_IDS.length) + "개";
                }
                v.setViewVisibility(rowId, View.VISIBLE);
                v.setTextViewText(rowId, "☐  " + label);
                v.setOnClickPendingIntent(rowId, completePendingIntent(context, item, i));
            } else {
                v.setViewVisibility(rowId, View.GONE);
            }
        }

        v.setOnClickPendingIntent(R.id.widget_open, openPendingIntent(context));
        manager.updateAppWidget(appWidgetId, v);
    }
}
