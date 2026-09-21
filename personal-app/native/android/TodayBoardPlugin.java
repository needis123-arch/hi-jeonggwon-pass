package kr.co.hirealty.personalcenter.stable;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Intent;
import android.os.Build;
import android.provider.Settings;
import androidx.core.app.NotificationManagerCompat;

import org.json.JSONArray;

import java.util.HashSet;
import java.util.Set;

@CapacitorPlugin(name = "TodayBoard")
public class TodayBoardPlugin extends Plugin {

    @PluginMethod
    public void sync(PluginCall call) {
        try {
            JSArray items = call.getArray("items");
            JSArray times = call.getArray("reminderTimes");
            JSONArray itemJson = items == null ? new JSONArray() : new JSONArray(items.toString());
            JSONArray timeJson = times == null ? new JSONArray("[\"10:30\",\"13:00\",\"17:00\",\"20:00\",\"22:00\"]") : new JSONArray(times.toString());
            TodayBoardManager.savePayload(getContext(), itemJson, timeJson);
            TodayBoardManager.reschedule(getContext());
            TodayBoardManager.showBoard(getContext(), false);
            JSObject ret = new JSObject();
            ret.put("ok", true);
            ret.put("count", itemJson.length());
            ret.put("notificationsEnabled", NotificationManagerCompat.from(getContext()).areNotificationsEnabled());
            call.resolve(ret);
        } catch (Exception e) {
            call.reject("오늘 할 일 고정판 동기화 실패", e);
        }
    }

    @PluginMethod
    public void getCompleted(PluginCall call) {
        JSObject ret = new JSObject();
        ret.put("items", TodayBoardManager.getCompletedQueue(getContext()));
        call.resolve(ret);
    }

    @PluginMethod
    public void ackCompleted(PluginCall call) {
        try {
            JSArray keys = call.getArray("keys");
            Set<String> set = new HashSet<>();
            if (keys != null) {
                for (int i = 0; i < keys.length(); i++) {
                    String key = keys.optString(i);
                    if (!key.isEmpty()) set.add(key);
                }
            }
            TodayBoardManager.ackCompleted(getContext(), set);
            call.resolve();
        } catch (Exception e) {
            call.reject("완료 동기화 확인 실패", e);
        }
    }

    @PluginMethod
    public void refresh(PluginCall call) {
        TodayBoardManager.showBoard(getContext(), false);
        call.resolve();
    }
    @PluginMethod
    public void status(PluginCall call) {
        JSObject ret = new JSObject();
        ret.put("notificationsEnabled", NotificationManagerCompat.from(getContext()).areNotificationsEnabled());
        ret.put("todayCount", TodayBoardManager.itemsForDate(getContext(), TodayBoardManager.today()).size());
        call.resolve(ret);
    }

    @PluginMethod
    public void openNotificationSettings(PluginCall call) {
        try {
            Intent intent = new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS);
            intent.putExtra(Settings.EXTRA_APP_PACKAGE, getContext().getPackageName());
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            getContext().startActivity(intent);
            call.resolve();
        } catch (Exception e) {
            call.reject("알림 설정을 열 수 없습니다.", e);
        }
    }

    @PluginMethod
    public void requestWidget(PluginCall call) {
        try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                JSObject ret = new JSObject();
                ret.put("supported", false);
                ret.put("requested", false);
                call.resolve(ret);
                return;
            }

            AppWidgetManager manager = AppWidgetManager.getInstance(getContext());
            ComponentName provider = new ComponentName(getContext(), TodayBoardWidgetProvider.class);
            boolean supported = manager.isRequestPinAppWidgetSupported();
            boolean requested = false;
            if (supported) {
                requested = manager.requestPinAppWidget(provider, null, null);
            }

            JSObject ret = new JSObject();
            ret.put("supported", supported);
            ret.put("requested", requested);
            call.resolve(ret);
        } catch (Exception e) {
            call.reject("홈화면 위젯 추가 요청 실패", e);
        }
    }

}
