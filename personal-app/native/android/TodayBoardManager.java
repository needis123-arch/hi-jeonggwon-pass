package kr.co.hirealty.personalcenter.stable;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.view.View;
import android.widget.RemoteViews;

import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;

import org.json.JSONArray;
import org.json.JSONObject;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

public final class TodayBoardManager {
    public static final String PREFS = "pc_today_board";
    public static final String KEY_ITEMS = "items_json";
    public static final String KEY_TIMES = "times_json";
    public static final String KEY_COMPLETED = "completed_keys";
    public static final String KEY_QUEUE = "completed_queue";
    public static final String BOARD_CHANNEL_ID = "pc_today_board_v3";
    public static final String REMIND_CHANNEL_ID = "pc_today_remind_v3";
    public static final int NOTIFICATION_ID = 240921;
    public static final String ACTION_REMIND = "kr.co.hirealty.personalcenter.stable.TODAY_REMIND";
    public static final String ACTION_REFRESH = "kr.co.hirealty.personalcenter.stable.TODAY_REFRESH";
    public static final String ACTION_COMPLETE = "kr.co.hirealty.personalcenter.stable.TODAY_COMPLETE";

    private static final int[] BIG_ROW_IDS = {
        R.id.notif_row1, R.id.notif_row2, R.id.notif_row3, R.id.notif_row4, R.id.notif_row5
    };

    private TodayBoardManager() {}

    public static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    public static String today() {
        return new SimpleDateFormat("yyyy-MM-dd", Locale.KOREA).format(Calendar.getInstance().getTime());
    }

    public static void savePayload(Context context, JSONArray items, JSONArray times) {
        SharedPreferences p = prefs(context);
        Set<String> incoming = new HashSet<>();
        for (int i = 0; i < items.length(); i++) {
            JSONObject o = items.optJSONObject(i);
            if (o != null) {
                String key = o.optString("key", "");
                if (!key.isEmpty()) incoming.add(key);
            }
        }
        Set<String> completed = new HashSet<>(p.getStringSet(KEY_COMPLETED, new HashSet<>()));
        completed.retainAll(incoming);
        p.edit()
            .putString(KEY_ITEMS, items.toString())
            .putString(KEY_TIMES, times.toString())
            .putStringSet(KEY_COMPLETED, completed)
            .apply();

        TodayBoardWidgetProvider.updateAll(context);
    }

    public static JSONArray readItems(Context context) {
        try { return new JSONArray(prefs(context).getString(KEY_ITEMS, "[]")); }
        catch (Exception e) { return new JSONArray(); }
    }

    public static JSONArray readTimes(Context context) {
        try { return new JSONArray(prefs(context).getString(KEY_TIMES, "[\"10:30\",\"13:00\",\"17:00\",\"20:00\",\"22:00\"]")); }
        catch (Exception e) { return new JSONArray(); }
    }

    public static List<JSONObject> itemsForDate(Context context, String date) {
        JSONArray arr = readItems(context);
        Set<String> completed = prefs(context).getStringSet(KEY_COMPLETED, new HashSet<>());
        List<JSONObject> out = new ArrayList<>();
        for (int i = 0; i < arr.length(); i++) {
            JSONObject o = arr.optJSONObject(i);
            if (o == null) continue;
            if (!date.equals(o.optString("date"))) continue;
            if (completed.contains(o.optString("key"))) continue;
            out.add(o);
        }
        return out;
    }

    public static void createChannels(Context context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        NotificationManager nm = context.getSystemService(NotificationManager.class);

        NotificationChannel board = nm.getNotificationChannel(BOARD_CHANNEL_ID);
        if (board == null) {
            board = new NotificationChannel(BOARD_CHANNEL_ID, "오늘 할 일 고정판", NotificationManager.IMPORTANCE_DEFAULT);
            board.setDescription("잠금화면에서 오늘 미완료 할 일을 한 장으로 확인하고 바로 완료합니다.");
            board.setSound(null, null);
            board.enableVibration(false);
            board.setShowBadge(true);
            board.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
            nm.createNotificationChannel(board);
        }

        NotificationChannel remind = nm.getNotificationChannel(REMIND_CHANNEL_ID);
        if (remind == null) {
            remind = new NotificationChannel(REMIND_CHANNEL_ID, "오늘 할 일 시간 알림", NotificationManager.IMPORTANCE_HIGH);
            remind.setDescription("10:30, 13:00, 17:00, 20:00, 22:00에 같은 고정판을 다시 알려줍니다.");
            remind.enableVibration(true);
            remind.setShowBadge(true);
            remind.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
            nm.createNotificationChannel(remind);
        }
    }

    private static PendingIntent openPendingIntent(Context context) {
        Intent openIntent = new Intent(context, MainActivity.class);
        openIntent.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        return PendingIntent.getActivity(
            context, 240922, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
    }

    private static PendingIntent completePendingIntent(Context context, JSONObject item, String origin) {
        String key = item.optString("key", "");
        Intent completeIntent = new Intent(context, TodayBoardReceiver.class);
        completeIntent.setAction(ACTION_COMPLETE);
        completeIntent.putExtra("key", key);
        completeIntent.putExtra("kind", item.optString("kind", ""));
        completeIntent.putExtra("itemId", item.optString("itemId", ""));
        completeIntent.putExtra("date", item.optString("date", today()));
        completeIntent.putExtra("label", item.optString("label", ""));
        int request = Math.abs((origin + "|" + key).hashCode());
        return PendingIntent.getBroadcast(
            context, request, completeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
    }

    private static String actionLabel(JSONObject item) {
        String label = item.optString("label", "완료");
        if (label.length() > 12) label = label.substring(0, 12) + "…";
        return "✓ " + label;
    }

    public static void showBoard(Context context, boolean alert) {
        createChannels(context);
        List<JSONObject> items = itemsForDate(context, today());
        NotificationManagerCompat nm = NotificationManagerCompat.from(context);
        if (items.isEmpty()) {
            nm.cancel(NOTIFICATION_ID);
            TodayBoardWidgetProvider.updateAll(context);
            return;
        }

        JSONObject top = items.get(0);
        int total = items.size();
        PendingIntent openPi = openPendingIntent(context);

        RemoteViews compact = new RemoteViews(context.getPackageName(), R.layout.notification_today_board);
        compact.setTextViewText(R.id.notif_title, "오늘 할 일 · " + total + "개 남음");
        compact.setTextViewText(R.id.notif_top, "☐ " + top.optString("label", "할 일"));
        compact.setOnClickPendingIntent(R.id.notif_open, openPi);
        compact.setOnClickPendingIntent(R.id.notif_complete, completePendingIntent(context, top, "notif-top"));

        RemoteViews big = new RemoteViews(context.getPackageName(), R.layout.notification_today_board_big);
        big.setTextViewText(R.id.notif_big_title, "오늘 할 일");
        big.setTextViewText(R.id.notif_big_count, total + "개 남음");
        big.setOnClickPendingIntent(R.id.notif_big_open, openPi);

        for (int i = 0; i < BIG_ROW_IDS.length; i++) {
            int id = BIG_ROW_IDS[i];
            if (i < total) {
                JSONObject item = items.get(i);
                String label = item.optString("label", "할 일");
                if (i == BIG_ROW_IDS.length - 1 && total > BIG_ROW_IDS.length) {
                    label += "  · +" + (total - BIG_ROW_IDS.length) + "개";
                }
                big.setViewVisibility(id, View.VISIBLE);
                big.setTextViewText(id, "✓ 완료 · " + label);
                big.setOnClickPendingIntent(id, completePendingIntent(context, item, "notif-big-" + i));
            } else {
                big.setViewVisibility(id, View.GONE);
            }
        }

        NotificationCompat.Builder b = new NotificationCompat.Builder(context, REMIND_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_agenda)
            .setContentTitle("오늘 할 일 · " + total + "개 남음")
            .setContentText(top.optString("label", "할 일"))
            .setContentIntent(openPi)
            .setCustomContentView(compact)
            .setCustomBigContentView(big)
            .setCustomHeadsUpContentView(compact)
            .setStyle(new NotificationCompat.DecoratedCustomViewStyle())
            .setOngoing(true)
            .setAutoCancel(false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setPriority(alert ? NotificationCompat.PRIORITY_HIGH : NotificationCompat.PRIORITY_DEFAULT)
            .setOnlyAlertOnce(!alert);

        // Samsung/lock-screen compatibility: native Android actions are kept in addition
        // to the custom compact "완료" button. This gives us two independent tap paths.
        for (int i = 0; i < Math.min(3, items.size()); i++) {
            JSONObject item = items.get(i);
            b.addAction(
                android.R.drawable.checkbox_on_background,
                actionLabel(item),
                completePendingIntent(context, item, "native-action-" + i)
            );
        }

        if (alert) {
            b.setDefaults(Notification.DEFAULT_SOUND | Notification.DEFAULT_VIBRATE);
        } else {
            b.setSilent(true);
        }

        try { nm.notify(NOTIFICATION_ID, b.build()); } catch (SecurityException ignored) {}
        TodayBoardWidgetProvider.updateAll(context);
    }

    public static void markComplete(Context context, Intent intent) {
        String key = intent.getStringExtra("key");
        if (key == null || key.isEmpty()) return;

        SharedPreferences p = prefs(context);
        Set<String> completed = new HashSet<>(p.getStringSet(KEY_COMPLETED, new HashSet<>()));
        completed.add(key);

        JSONArray queue;
        try { queue = new JSONArray(p.getString(KEY_QUEUE, "[]")); }
        catch (Exception e) { queue = new JSONArray(); }

        boolean exists = false;
        for (int i = 0; i < queue.length(); i++) {
            JSONObject o = queue.optJSONObject(i);
            if (o != null && key.equals(o.optString("key"))) {
                exists = true;
                break;
            }
        }

        if (!exists) {
            JSONObject q = new JSONObject();
            try {
                q.put("key", key);
                q.put("kind", intent.getStringExtra("kind"));
                q.put("itemId", intent.getStringExtra("itemId"));
                q.put("date", intent.getStringExtra("date"));
                q.put("label", intent.getStringExtra("label"));
                queue.put(q);
            } catch (Exception ignored) {}
        }

        p.edit()
            .putStringSet(KEY_COMPLETED, completed)
            .putString(KEY_QUEUE, queue.toString())
            .apply();

        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID);
        showBoard(context, false);
        TodayBoardWidgetProvider.updateAll(context);
    }

    public static JSONArray getCompletedQueue(Context context) {
        try { return new JSONArray(prefs(context).getString(KEY_QUEUE, "[]")); }
        catch (Exception e) { return new JSONArray(); }
    }

    public static void ackCompleted(Context context, Set<String> keys) {
        JSONArray old = getCompletedQueue(context);
        JSONArray next = new JSONArray();
        for (int i = 0; i < old.length(); i++) {
            JSONObject o = old.optJSONObject(i);
            if (o == null || keys.contains(o.optString("key"))) continue;
            next.put(o);
        }
        prefs(context).edit().putString(KEY_QUEUE, next.toString()).apply();
    }

    private static int requestCode(String date, int slot) {
        return Math.abs((date + "|" + slot).hashCode());
    }

    private static PendingIntent alarmPi(Context context, String date, int slot, String action) {
        Intent i = new Intent(context, TodayBoardReceiver.class);
        i.setAction(action);
        i.putExtra("date", date);
        i.putExtra("slot", slot);
        return PendingIntent.getBroadcast(
            context, requestCode(date, slot), i,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
    }

    private static long atMillis(String date, String hhmm) {
        try {
            String[] d = date.split("-");
            String[] t = hhmm.split(":");
            Calendar c = Calendar.getInstance();
            c.set(Calendar.YEAR, Integer.parseInt(d[0]));
            c.set(Calendar.MONTH, Integer.parseInt(d[1]) - 1);
            c.set(Calendar.DAY_OF_MONTH, Integer.parseInt(d[2]));
            c.set(Calendar.HOUR_OF_DAY, Integer.parseInt(t[0]));
            c.set(Calendar.MINUTE, Integer.parseInt(t[1]));
            c.set(Calendar.SECOND, 0);
            c.set(Calendar.MILLISECOND, 0);
            return c.getTimeInMillis();
        } catch (Exception e) { return 0; }
    }

    private static void setAlarm(AlarmManager am, long when, PendingIntent pi) {
        if (when <= System.currentTimeMillis() + 3000) return;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && am.canScheduleExactAlarms()) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, when, pi);
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, when, pi);
        } else {
            am.set(AlarmManager.RTC_WAKEUP, when, pi);
        }
    }

    public static void reschedule(Context context) {
        AlarmManager am = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        JSONArray all = readItems(context);
        JSONArray times = readTimes(context);
        Set<String> dates = new LinkedHashSet<>();

        for (int i = 0; i < all.length(); i++) {
            JSONObject o = all.optJSONObject(i);
            if (o != null && !o.optString("date").isEmpty()) dates.add(o.optString("date"));
        }

        Calendar base = Calendar.getInstance();
        SimpleDateFormat f = new SimpleDateFormat("yyyy-MM-dd", Locale.KOREA);

        for (int day = 0; day < 10; day++) {
            Calendar x = (Calendar) base.clone();
            x.add(Calendar.DAY_OF_MONTH, day);
            String ds = f.format(x.getTime());
            for (int slot = 0; slot < 8; slot++) {
                PendingIntent pi = alarmPi(context, ds, slot, slot == 0 ? ACTION_REFRESH : ACTION_REMIND);
                am.cancel(pi);
            }
        }

        for (String date : dates) {
            setAlarm(am, atMillis(date, "00:05"), alarmPi(context, date, 0, ACTION_REFRESH));
            for (int i = 0; i < times.length(); i++) {
                String time = times.optString(i);
                setAlarm(am, atMillis(date, time), alarmPi(context, date, i + 1, ACTION_REMIND));
            }
        }
    }
}
