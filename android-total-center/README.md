# HI · RAY 총괄센터 Android

기존 Google Apps Script 총괄센터를 Android 앱 아이콘으로 실행하는 내부용 앱입니다.

- 첫 실행 시 기존 총괄센터 `/exec` 주소를 입력합니다.
- 기본 실행 모드는 Google 로그인 호환성이 좋은 **Chrome 보안모드**입니다.
- 필요하면 설정에서 **앱 내부 WebView**로 바꿀 수 있습니다.
- 총괄센터 비밀번호나 고객정보는 APK 코드에 저장하지 않습니다.
- 직원 시트를 APK가 직접 수정하지 않습니다. 기존 총괄센터 웹앱을 표시하는 역할입니다.

## 로컬 빌드
Android Studio에서 이 폴더를 열고:
Build → Build App Bundle(s) / APK(s) → Build APK(s)

생성 위치:
`app/build/outputs/apk/debug/app-debug.apk`
