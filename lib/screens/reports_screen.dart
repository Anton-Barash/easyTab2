import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/report_provider.dart';
import '../l10n/app_localizations.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Future<List<dynamic>>? _reportsFuture;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadReports() {
    _reportsFuture = Provider.of<ReportState>(
      context,
      listen: false,
    ).loadReportList();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.myReports),
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
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.toLowerCase();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: loc.searchReports,
                    prefixIcon: const Icon(
                      Icons.search,
                      color: Color(0xFF666666),
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFcccccc)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFcccccc)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: Color(0xFF333333),
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<dynamic>>(
                  future: _reportsFuture,
                  builder: (ctx, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(loc.loadError(snapshot.error.toString())),
                      );
                    }
                    final reports = snapshot.data ?? [];
                    final filteredReports = reports.where((report) {
                      if (_searchQuery.isEmpty) return true;
                      return report.name.toLowerCase().contains(_searchQuery);
                    }).toList();
                    if (filteredReports.isEmpty) {
                      return Center(
                        child: Text(
                          _searchQuery.isEmpty
                              ? loc.noReportsYet
                              : loc.reportsNotFound,
                          style: const TextStyle(
                            color: Color(0xFF666666),
                            fontSize: 16,
                          ),
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filteredReports.length,
                      itemBuilder: (ctx, index) {
                        final report = filteredReports[index];
                        return _buildReportCard(context, report);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: _buildActionButtons(),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FloatingActionButton(
          onPressed: _importProject,
          tooltip: 'Импорт проекта',
          child: const Icon(Icons.upload_file),
        ),
        const SizedBox(width: 10),
        FloatingActionButton(
          onPressed: () =>
              Navigator.of(context).pushReplacementNamed('/template'),
          tooltip: 'Новый отчет',
          child: const Icon(Icons.add),
        ),
      ],
    );
  }

  Future<void> _importProject() async {
    final loc = AppLocalizations.of(context)!;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );

      if (result != null && result.files.isNotEmpty) {
        final zipPath = result.files.single.path;
        if (zipPath != null) {
          final reportState = Provider.of<ReportState>(context, listen: false);

          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(loc.importingProject),
                ],
              ),
            ),
          );

          final importedPath = await reportState.importProjectFromZip(zipPath);

          if (!mounted) return;
          Navigator.pop(context);

          if (importedPath != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(loc.projectImported)));
            setState(() {
              _loadReports();
            });
          } else {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(loc.importError)));
          }
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.importError)));
    }
  }

  Widget _buildReportCard(BuildContext context, dynamic report) {
    final reportState = Provider.of<ReportState>(context, listen: false);
    final hasThumbnail =
        report.thumbnailPath != null && report.thumbnailPath!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      constraints: const BoxConstraints(maxWidth: 500),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(width: 2, color: const Color(0xFF333333)),
      ),
      child: InkWell(
        onTap: () async {
          final navigator = Navigator.of(context);
          await reportState.loadReport(report.folderName);
          if (!mounted) return;
          navigator.pushNamed('/fill');
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
                child: hasThumbnail
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          File('${report.folderName}/${report.thumbnailPath}'),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(
                                Icons.note,
                                size: 32,
                                color: Color(0xFF424242),
                              ),
                            );
                          },
                        ),
                      )
                    : const Center(
                        child: Icon(
                          Icons.note,
                          size: 32,
                          color: Color(0xFF424242),
                        ),
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
                  final loc = AppLocalizations.of(context)!;
                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                  final isMobile = MediaQuery.of(context).size.width <= 800;
                  final confirm = await showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      insetPadding: isMobile
                          ? EdgeInsets.zero
                          : const EdgeInsets.all(40),
                      contentPadding: isMobile
                          ? const EdgeInsets.all(16)
                          : const EdgeInsets.all(24),
                      shape: isMobile
                          ? const RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero,
                            )
                          : null,
                      title: isMobile ? null : Text(loc.deleteReport),
                      content: isMobile
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(loc.cannotUndo),
                                const SizedBox(height: 24),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: Text(loc.cancel),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: Text(loc.delete),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(loc.cannotUndo),
                                const SizedBox(height: 24),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: Text(loc.cancel),
                                    ),
                                    const SizedBox(width: 12),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: Text(loc.delete),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                    ),
                  );
                  if (confirm == true) {
                    await reportState.deleteReport(report.folderName);
                    setState(() {
                      _loadReports();
                    });
                    if (!mounted) return;
                    scaffoldMessenger.showSnackBar(
                      SnackBar(content: Text(loc.reportDeleted)),
                    );
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
