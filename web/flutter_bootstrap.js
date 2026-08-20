{{flutter_js}}
{{flutter_build_config}}

// canvaskit загружается с локального сервера (build/web/canvaskit),
// а не с CDN Google (gstatic) — это убирает внешнюю зависимость,
// ускоряет первую загрузку и позволяет работать в сетях,
// где gstatic заблокирован.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
});
