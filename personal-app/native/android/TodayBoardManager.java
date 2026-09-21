package kr.co.hirealty.personalcenter.app;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;

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
    public static final String BOARD_CHANNEL_ID = "pc_today_board_v2";
    public static final String REMIND_CHANNEL_ID = "pc_today_remind_v2";
    public static final int NOTIFICATION_ID = 240921;
    public static final String ACTION_REMIND = "kr.co.hirealty.personalcenter.app.TODAY_REMIND";
    public static final String ACTION_REFRESH = "kr.co.hirealty.personalcenter.app.TODAY_REFRESH";
    public static final String ACTION_COMPLETE = "kr.co.hirealty.personalcenter.app.TODAY_COMPLETE";

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
            board.setDescription("오늘 미완료 일정과 할 일을 잠금화면에 한 장으로 계속 표시합니다.");
            board.setSound(null, null);
            board.enableVibration(false);
            board.setShowBadge(true);
            board.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
            nm.createNotificationChannel(board);
        }

        NotificationChannel remind = nm.getNotificationChannel(REMIND_CHANNEL_ID);
        if (remind == null) {
            remind = new NotificationChannel(REMIND_CHANNEL_ID, "오늘 할 일 시간 알림", NotificationManager.IMPORTANCE_HIGH);
            remind.setDescription("10:30, 13:00, 17:00, 20:00, 22:00에 미완료 할 일을 다시 알려줍니다.");
            remind.enableVibration(true);
            remind.setShowBadge(true);
            remind.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
            nm.createNotificationChannel(remind);
        }
    }

    public static void showBoard(Context context, boolean alert) {
        createChannels(context);
        List<JSONObject> items = itemsForDate(context, today());
        NotificationManagerCompat nm = NotificationManagerCompat.from(context);
        if (items.isEmpty()) {
            nm.cancel(NOTIFICATION_ID);
            return;
        }

        JSONObject top = items.get(0);
        int total = items.size();
        NotificationCompat.InboxStyle style = new NotificationCompat.InboxStyle()
            .setBigContentTitle("오늘 할 일 · " + total + "개 남음")
            .setSummaryText("완료하면 다음 항목이 맨 위로 올라옵니다.");

        for (int i = 0; i < Math.min(5, items.size()); i++) {
            String label = items.get(i).optString("label", "할 일");
            style.addLine("☐ " + label);
        }

        Intent openIntent = new Intent(context, MainActivity.class);
        openIntent.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent openPi = PendingIntent.getActivity(
            context, 240922, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        Intent completeIntent = new Intent(context, TodayBoardReceiver.class);
        completeIntent.setAction(ACTION_COMPLETE);
        completeIntent.putExtra("key", top.optString("key"));
        completeIntent.putExtra("kind", top.optString("kind"));
        completeIntent.putExtra("itemId", top.optString("itemId"));
        completeIntent.putExtra("date", top.optString("date"));
        completeIntent.putExtra("label", top.optString("label"));
        PendingIntent completePi = PendingIntent.getBroadcast(
            context, 240923, completeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        String compact = top.optString("label", "할 일");
        if (total > 1) compact += " 외 " + (total - 1) + "개";

        String channelId = alert ? REMIND_CHANNEL_ID : BOARD_CHANNEL_ID;
        NotificationCompat.Builder b = new NotificationCompat.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.ic_menu_agenda)
            .setContentTitle("오늘 할 일 · " + total + "개 남음")
            .setContentText(compact)
            .setStyle(style)
            .setContentIntent(openPi)
            .setOngoing(true)
            .setAutoCancel(false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setPriority(alert ? NotificationCompat.PRIORITY_HIGH : NotificationCompat.PRIORITY_DEFAULT)
            .setOnlyAlertOnce(!alert)
            .addAction(android.R.drawable.checkbox_on_background, "완료", completePi)
            .addAction(android.R.drawable.ic_menu_view, "열기", openPi);

        if (alert) {
            b.setDefaults(Notification.DEFAULT_SOUND | Notification.DEFAULT_VIBRATE);
        }

        try { nm.notify(NOTIFICATION_ID, b.build()); } catch (SecurityException ignored) {}
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
            if (key.equals(queue.optJSONObject(i) != null ? queue.optJSONObject(i).optString("key") : "")) {
                exists = true; break;
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

        p.edit().putStringSet(KEY_COMPLETED, completed).putString(KEY_QUEUE, queue.toString()).apply();
        showBoard(context, false);
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
