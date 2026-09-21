package kr.co.hirealty.personalcenter.stable;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(TodayBoardPlugin.class);
        super.onCreate(savedInstanceState);
    }
}
