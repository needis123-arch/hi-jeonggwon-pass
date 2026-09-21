from pathlib import Path
import shutil

root = Path.cwd()
src = root / "native" / "android"
main = root / "android" / "app" / "src" / "main"
pkg = main / "java" / "kr" / "co" / "hirealty" / "personalcenter" / "stable"
pkg.mkdir(parents=True, exist_ok=True)

for name in [
    "TodayBoardManager.java",
    "TodayBoardReceiver.java",
    "TodayBoardPlugin.java",
    "TodayBoardWidgetProvider.java",
    "MainActivity.java",
]:
    shutil.copy2(src / name, pkg / name)

res_src = src / "res"
res_dst = main / "res"
for item in res_src.rglob("*"):
    if item.is_file():
        target = res_dst / item.relative_to(res_src)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(item, target)

manifest = main / "AndroidManifest.xml"
s = manifest.read_text()

today_receiver = '''        <receiver
            android:name=".TodayBoardReceiver"
            android:enabled="true"
            android:exported="false" />
'''

widget_receiver = '''        <receiver
            android:name=".TodayBoardWidgetProvider"
            android:enabled="true"
            android:exported="true">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data
                android:name="android.appwidget.provider"
                android:resource="@xml/today_board_widget_info" />
        </receiver>
'''

insert = ""
if ".TodayBoardReceiver" not in s:
    insert += today_receiver
if ".TodayBoardWidgetProvider" not in s:
    insert += widget_receiver
if insert:
    s = s.replace("    </application>", insert + "    </application>")
manifest.write_text(s)

gradle = root / "android" / "app" / "build.gradle"
g = gradle.read_text()
if "pcStableDebug" not in g:
    g = g.replace(
        "android {",
        '''android {
    signingConfigs {
        pcStableDebug {
            storeFile file("../../.signing/debug.keystore")
            storePassword "android"
            keyAlias "androiddebugkey"
            keyPassword "android"
        }
    }
''',
        1,
    )
    g = g.replace(
        "buildTypes {",
        '''buildTypes {
        debug {
            signingConfig signingConfigs.pcStableDebug
        }
''',
        1,
    )
gradle.write_text(g)
