package kr.co.hirealty.personalcenter.stable;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class TodayBoardReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent != null ? intent.getAction() : "";
        if (TodayBoardManager.ACTION_COMPLETE.equals(action)) {
            TodayBoardManager.markComplete(context, intent);
        } else if (TodayBoardManager.ACTION_REMIND.equals(action)) {
            TodayBoardManager.showOneShot(context, intent);
        } else if (TodayBoardManager.ACTION_REFRESH.equals(action)) {
            TodayBoardManager.showBoard(context, false);
        }
    }
}
