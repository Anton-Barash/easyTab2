// ============================================================
// Cover image provider (web-реализация).
//
// На web локального файла нет — обложка отчёта берётся с сервера
// (/view/report/:publicId/cover). Поэтому локальный ImageProvider
// не используется и возвращается null.
// ============================================================

import 'package:flutter/widgets.dart';

ImageProvider? localCoverImageProvider(String? path) => null;