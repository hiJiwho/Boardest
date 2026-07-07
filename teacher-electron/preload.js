const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('boardestAPI', {
  searchSchool: (keyword) => ipcRenderer.invoke('search-school', keyword),
  getTimetable: (schoolCode, teacherName) => ipcRenderer.invoke('get-timetable', schoolCode, teacherName),
  checkUpdate: () => ipcRenderer.invoke('check-update'),
  performUpdate: (url) => ipcRenderer.invoke('perform-update', url),
});
