import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/report_provider.dart';

class ReportsScreen extends StatefulWidget {
  ReportsScreen({super.key});

  @override
  _ReportsScreenState createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Future<List<dynamic>>? _reportsFuture;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  void _loadReports() {
    _reportsFuture = Provider.of<ReportState>(
      context,
      listen: false,
    ).loadReportList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои отчёты'),
        backgroundColor: const Color(0xFFe0e0e0),
        foregroundColor: const Color(0xFF424242),
        elevation: 0,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: const Color(0xFFf8f7f2),
              child: CustomPaint(painter: DottedPatternPainter()),
            ),
          ),
          FutureBuilder<List<dynamic>>(
            future: _reportsFuture,
            builder: (ctx, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text('Ошибка загрузки: ${snapshot.error}'),
                );
              }
              final reports = snapshot.data ?? [];
              if (reports.isEmpty) {
                return const Center(child: Text('У вас пока нет отчётов'));
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: reports.length,
                itemBuilder: (ctx, index) {
                  final report = reports[index];
                  return _buildReportCard(context, report);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(BuildContext context, dynamic report) {
    final reportState = Provider.of<ReportState>(context, listen: false);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(width: 2, color: const Color(0xFF333333)),
      ),
      child: InkWell(
        onTap: () async {
          await reportState.loadReport(report.folderName);
          if (mounted) {
            Navigator.pushNamed(context, '/fill');
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFe0e0e0),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(width: 2, color: const Color(0xFF333333)),
                ),
                child: const Center(
                  child: Icon(Icons.note, size: 32, color: Color(0xFF424242)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF424242),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      report.dateTime.toLocal().toString().substring(0, 16),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF666666),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Color(0xFFdc2626)),
                onPressed: () async {
                  final confirm = await showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Удалить отчёт?'),
                      content: const Text('Это действие нельзя отменить'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Отмена'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Удалить'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await reportState.deleteReport(report.folderName);
                    setState(() {
                      _loadReports();
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Отчёт удалён')),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DottedPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFcbc7bc)
      ..style = PaintingStyle.fill;
    const dotSize = 1.0;
    const spacing = 20.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), dotSize, paint);
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
