package kr.co.hiray.totalcenter;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.os.IBinder;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.CookieManager;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.TextView;
import android.widget.Toast;

public class MainActivity extends Activity {
    private static final String PREFS = "hiray_total_center";
    private static final String KEY_URL = "web_url";
    private static final String KEY_MODE = "open_mode";
    private static final String MODE_CHROME = "chrome";
    private static final String MODE_WEBVIEW = "webview";

    private SharedPreferences prefs;
    private WebView webView;
    private LinearLayout root;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        buildUi();

        String url = prefs.getString(KEY_URL, "");
        if (url.isEmpty()) {
            showSetupDialog(true);
        } else {
            openSavedCenter();
        }
    }

    private void buildUi() {
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.rgb(245, 246, 248));

        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);
        top.setPadding(dp(14), dp(8), dp(8), dp(8));
        top.setBackgroundColor(Color.rgb(17, 19, 24));

        TextView title = new TextView(this);
        title.setText("HI · RAY 총괄센터");
        title.setTextColor(Color.WHITE);
        title.setTextSize(17);
        title.setTypeface(null, android.graphics.Typeface.BOLD);
        top.addView(title, new LinearLayout.LayoutParams(0, dp(48), 1));

        Button refresh = topButton("새로고침");
        refresh.setOnClickListener(v -> {
            if (webView != null && webView.getVisibility() == View.VISIBLE) webView.reload();
            else openSavedCenter();
        });
        top.addView(refresh);

        Button chrome = topButton("Chrome");
        chrome.setOnClickListener(v -> openChrome(prefs.getString(KEY_URL, "")));
        top.addView(chrome);

        Button settings = topButton("설정");
        settings.setOnClickListener(v -> showSetupDialog(false));
        top.addView(settings);

        root.addView(top, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(64)));

        webView = new WebView(this);
        WebSettings ws = webView.getSettings();
        ws.setJavaScriptEnabled(true);
        ws.setDomStorageEnabled(true);
        ws.setLoadsImagesAutomatically(true);
        ws.setSupportZoom(false);
        ws.setBuiltInZoomControls(false);
        ws.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        ws.setUserAgentString(ws.getUserAgentString() + " HIRAY-TotalCenter/1.0");

        CookieManager cm = CookieManager.getInstance();
        cm.setAcceptCookie(true);
        cm.setAcceptThirdPartyCookies(webView, true);

        webView.setWebChromeClient(new WebChromeClient());
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                String host = uri.getHost() == null ? "" : uri.getHost().toLowerCase();

                if (host.contains("accounts.google.com")) {
                    Toast.makeText(MainActivity.this,
                            "Google 로그인은 Chrome 보안모드로 여는 게 가장 안정적입니다.",
                            Toast.LENGTH_LONG).show();
                    openChrome(prefs.getString(KEY_URL, ""));
                    return true;
                }

                if (isAllowedHost(host)) return false;

                Intent external = new Intent(Intent.ACTION_VIEW, uri);
                startActivity(external);
                return true;
            }
        });

        root.addView(webView, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));

        setContentView(root);
    }

    private Button topButton(String text) {
        Button b = new Button(this);
        b.setText(text);
        b.setAllCaps(false);
        b.setTextSize(11);
        b.setTextColor(Color.WHITE);
        b.setBackgroundColor(Color.TRANSPARENT);
        b.setPadding(dp(8), 0, dp(8), 0);
        b.setMinWidth(0);
        b.setMinimumWidth(0);
        return b;
    }

    private void openSavedCenter() {
        String url = prefs.getString(KEY_URL, "");
        if (url.isEmpty()) {
            showSetupDialog(true);
            return;
        }
        String mode = prefs.getString(KEY_MODE, MODE_CHROME);
        if (MODE_WEBVIEW.equals(mode)) {
            webView.setVisibility(View.VISIBLE);
            webView.loadUrl(url);
        } else {
            webView.setVisibility(View.VISIBLE);
            showBrowserModeLanding();
            openChrome(url);
        }
    }

    private void showBrowserModeLanding() {
        String html = "<html><body style='font-family:sans-serif;background:#f5f6f8;color:#111;padding:28px'>" +
                "<h2>HI · RAY 총괄센터</h2>" +
                "<p>Google 로그인 호환성을 위해 Chrome 보안모드로 실행 중입니다.</p>" +
                "<p style='color:#737b86'>앱으로 돌아와도 상단 Chrome 버튼으로 다시 열 수 있습니다.</p>" +
                "</body></html>";
        webView.loadDataWithBaseURL(null, html, "text/html", "UTF-8", null);
    }

    private void showSetupDialog(boolean firstRun) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(dp(20), dp(8), dp(20), 0);

        TextView help = new TextView(this);
        help.setText("총괄센터 Apps Script의 /exec 주소를 넣으세요.\n예: https://script.google.com/macros/s/…/exec");
        help.setTextSize(13);
        help.setTextColor(Color.DKGRAY);
        box.addView(help);

        EditText input = new EditText(this);
        input.setSingleLine(true);
        input.setHint("https://script.google.com/macros/s/.../exec");
        input.setText(prefs.getString(KEY_URL, ""));
        box.addView(input, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        TextView modeTitle = new TextView(this);
        modeTitle.setText("\n실행 방식");
        modeTitle.setTypeface(null, android.graphics.Typeface.BOLD);
        box.addView(modeTitle);

        RadioGroup group = new RadioGroup(this);
        group.setOrientation(RadioGroup.VERTICAL);
        RadioButton chrome = new RadioButton(this);
        chrome.setText("Chrome 보안모드 (추천 · Google 로그인 안정적)");
        chrome.setId(View.generateViewId());
        RadioButton web = new RadioButton(this);
        web.setText("앱 내부 보기 (주소창 없음 · 로그인 제한 가능)");
        web.setId(View.generateViewId());
        group.addView(chrome);
        group.addView(web);

        String currentMode = prefs.getString(KEY_MODE, MODE_CHROME);
        group.check(MODE_WEBVIEW.equals(currentMode) ? web.getId() : chrome.getId());
        box.addView(group);

        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle(firstRun ? "총괄센터 연결" : "앱 설정")
                .setView(box)
                .setCancelable(!firstRun)
                .setNegativeButton(firstRun ? null : "취소", null)
                .setPositiveButton("저장", null)
                .create();

        dialog.setOnShowListener(d -> dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
            String url = input.getText().toString().trim();
            if (!isValidUrl(url)) {
                input.setError("Apps Script /exec HTTPS 주소를 확인해주세요.");
                return;
            }
            String mode = group.getCheckedRadioButtonId() == web.getId() ? MODE_WEBVIEW : MODE_CHROME;
            prefs.edit().putString(KEY_URL, url).putString(KEY_MODE, mode).apply();
            dialog.dismiss();
            openSavedCenter();
        }));
        dialog.show();
    }

    private boolean isValidUrl(String url) {
        if (url == null || !url.startsWith("https://")) return false;
        try {
            Uri uri = Uri.parse(url);
            String host = uri.getHost() == null ? "" : uri.getHost().toLowerCase();
            return (host.equals("script.google.com") || host.endsWith("googleusercontent.com"))
                    && url.contains("/macros/") && url.contains("/exec");
        } catch (Exception e) {
            return false;
        }
    }

    private boolean isAllowedHost(String host) {
        return host.equals("script.google.com") || host.endsWith("googleusercontent.com")
                || host.equals("accounts.google.com");
    }

    private void openChrome(String url) {
        if (url == null || url.isEmpty()) {
            showSetupDialog(true);
            return;
        }
        Uri uri = Uri.parse(url);
        try {
            Intent custom = new Intent(Intent.ACTION_VIEW, uri);
            custom.setPackage("com.android.chrome");
            Bundle extras = new Bundle();
            extras.putBinder("android.support.customtabs.extra.SESSION", (IBinder) null);
            custom.putExtras(extras);
            custom.putExtra("android.support.customtabs.extra.SHOW_TITLE", false);
            custom.putExtra("android.support.customtabs.extra.ENABLE_URLBAR_HIDING", true);
            custom.putExtra("android.support.customtabs.extra.SHARE_MENU_ITEM", false);
            custom.putExtra("android.support.customtabs.extra.TOOLBAR_COLOR", Color.rgb(17, 19, 24));
            startActivity(custom);
        } catch (ActivityNotFoundException e) {
            Intent fallback = new Intent(Intent.ACTION_VIEW, uri);
            startActivity(fallback);
        }
    }

    @Override
    public void onBackPressed() {
        if (webView != null && webView.getVisibility() == View.VISIBLE && webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
