importScripts('https://www.gstatic.com/firebasejs/10.8.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.8.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBMoJZHMBN4eYJtiZR2iGePcmIB7bg8wGo',
  authDomain: 'jiwhosboardest.firebaseapp.com',
  projectId: 'jiwhosboardest',
  storageBucket: 'jiwhosboardest.appspot.com',
  messagingSenderId: '287519871774',
  appId: '1:287519871774:web:d259c730cb85b001a1c34a'
});

firebase.messaging().onBackgroundMessage((payload) => {
  const title = payload.notification?.title || payload.data?.title || 'Boardest 알림';
  self.registration.showNotification(title, {
    body: payload.notification?.body || payload.data?.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: payload.data,
  });
});
