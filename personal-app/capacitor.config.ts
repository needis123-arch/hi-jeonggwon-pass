import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'kr.co.hirealty.personalcenter.stable',
  appName: 'PERSONAL CENTER',
  webDir: 'www',
  server: {
    url: 'https://needis123-arch.github.io/hi-jeonggwon-pass/personal-center.html?app=android&v=2.13',
    cleartext: false,
    allowNavigation: [
      'needis123-arch.github.io'
    ]
  },
  android: {
    backgroundColor: '#f4f6f8'
  }
};

export default config;
