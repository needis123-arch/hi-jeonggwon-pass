# PERSONAL CENTER Android

기존 PERSONAL CENTER 웹앱을 Capacitor 8 Android 앱으로 감싸고, 네이티브 잠금화면 알림을 붙이는 프로젝트입니다.

## 현재 동작

- 웹 화면은 GitHub Pages의 `personal-center.html`을 직접 불러옵니다.
- 따라서 HTML/CSS/JS 수정은 APK 재설치 없이 다음 실행부터 반영됩니다.
- 앱에서 로그인 후 데이터가 로드되면 향후 7일의 할 일/일정/업무 루틴을 로컬 알림으로 예약합니다.
- 할 일/일정/루틴 알림에는 `완료` 액션을 등록합니다.
- 카드 확정일, 7일 잔고 점검, 일요일 토스 주간 캡처, 월말 수익 입력은 단순 입력 알림으로 예약합니다.
- 생성형 AI나 토큰을 사용하지 않습니다.

## 최초 Android 프로젝트 생성

Capacitor 8 기준 Node.js 22+와 최신 Android Studio/Android SDK가 필요합니다.

```bash
cd personal-app
npm install
npm run android:add
npm run sync
npm run open:android
```

Android Studio에서 실제 Android 휴대폰을 USB 디버깅으로 연결한 뒤 Run 하면 됩니다.

## APK 만들기

Android Studio:
Build > Build App Bundle(s) / APK(s) > Build APK(s)

테스트 단계에서는 debug APK로 충분합니다.

## 알림 권한

첫 실행 후 로그인하면 Android 알림 권한을 요청합니다. 허용해야 잠금화면에 표시됩니다.
잠금화면에서 알림 내용 표시가 꺼져 있으면 Android 설정 > 알림 > PERSONAL CENTER > 잠금화면에서 내용 표시를 허용해야 합니다.

## 알림 동기화 방식

앱이 데이터 로드를 마칠 때 향후 7일 알림을 다시 맞춥니다.
현재 1차 버전은 FCM 서버 푸시가 아니라 기기 로컬 알림입니다. 그래서 토큰 비용은 0원이고 별도 Firebase 계정도 필요 없습니다.

향후 앱을 며칠간 한 번도 열지 않아도 서버에서 즉시 새로운 일정을 푸시하려면 FCM을 추가할 수 있습니다.
