// ============================================================
// ViewReportHtmlScreen — экран просмотра HTML-отчёта внутри Flutter.
//
// Открывается в новой вкладке браузера (по адресу localhost:4000/#/view-report).
// Делает API-запрос к серверу (8000): GET /reports/:id/html,
// получает HTML-строку, отображает её в iframe srcdoc.
//
// Пользователь остаётся внутри Flutter (localhost:4000).
// Сервер (8000) используется только как API.
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import '../services/api_service.dart';
import '../utils/report_html_iframe.dart';

class ViewReportHtmlScreen extends StatefulWidget {
  final int reportId;
  final String? token;

  const ViewReportHtmlScreen({
    super.key,
    required this.reportId,
    this.token,
  });

  @override
  State<ViewReportHtmlScreen> createState() => _ViewReportHtmlScreenState();
}

class _ViewReportHtmlScreenState extends State<ViewReportHtmlScreen> {
  String? _html;
  String? _error;
  bool _loading = true;
  String? _viewType;

  @override
  void initState() {
    super.initState();
    _loadHtml();
  }

  Future<void> _loadHtml() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // Если передан токен (новая вкладка), устанавливаем его в ApiService
    if (widget.token != null && widget.token!.isNotEmpty) {
      ApiService.authToken = widget.token;
    }

    try {
      final result = await ApiService.getReportHtml(widget.reportId);
      if (!mounted) return;

      if (result.success && result.data?['html'] != null) {
        final htmlContent = result.data!['html'] as String;
        final viewType = createIframeView(htmlContent);
        setState(() {
          _html = htmlContent;
          _viewType = viewType;
          _loading = false;
        });
      } else {
        setState(() {
          _error = result.error ?? 'Не удалось загрузить отчёт';
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Ошибка: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Отчёт #${widget.reportId}'),
        backgroundColor: const Color(0xFFe0e0e0),
        foregroundColor: const Color(0xFF424242),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
            onPressed: _loading ? null : _loadHtml,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadHtml,
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    if (_viewType == null || _viewType!.isEmpty) {
      // Non-web платформа или stub — показываем HTML как текст
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Просмотр HTML доступен только на web-версии.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }

    // Web: отображаем iframe через HtmlElementView
    return HtmlElementView(viewType: _viewType!);
  }
}
