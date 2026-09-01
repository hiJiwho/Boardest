importScripts('https://www.gstatic.com/firebasejs/10.8.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.8.0/firebase-messaging-compat.js');

const firebaseConfig = {
  apiKey: "AIzaSyBMoJZHMBN4eYJtiZR2iGePcmIB7bg8wGo",
  authDomain: "jiwhosboardest.firebaseapp.com",
  projectId: "jiwhosboardest",
  storageBucket: "jiwhosboardest.appspot.com",
  messagingSenderId: "287519871774",
  appId: "1:287519871774:web:d259c730cb85b001a1c34a"
};

firebase.initializeApp(firebaseConfig);

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message: ', payload);
  const title = payload.notification?.title || payload.data?.title || 'Boardest 알림';
  const options = {
    body: payload.notification?.body || payload.data?.body || '',
    icon: 'icons/Icon-192.png',
    badge: 'icons/Icon-192.png',
    data: payload.data,
    vibrate: [200, 100, 200]
  };
  self.registration.showNotification(title, options);
});
