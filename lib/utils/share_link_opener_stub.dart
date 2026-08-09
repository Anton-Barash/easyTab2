/// Заглушка для открытия share-ссылок на non-web платформах.
/// На web используется share_link_opener_web.dart.

void openShareLink(String url) {
  throw UnsupportedError('openShareLink доступен только на web');
}

void downloadShareZip(String url, String fileName) {
  throw UnsupportedError('downloadShareZip доступен только на web');
}
