package kr.co.hirealty.personalcenter;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

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
}
