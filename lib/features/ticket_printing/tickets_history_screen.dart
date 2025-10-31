import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class TicketsHistoryScreen extends StatefulWidget {
  const TicketsHistoryScreen({super.key});

  @override
  State<TicketsHistoryScreen> createState() => _TicketsHistoryScreenState();
}

class _TicketsHistoryScreenState extends State<TicketsHistoryScreen> {
  List<FileSystemEntity> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _loading = true;
    });
    final dir = await getApplicationDocumentsDirectory();
    final entries = await dir.list().toList();
    // Filter for our ticket PDFs
    final pdfs = entries
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.pdf') && f.path.contains('tickets_'))
        .toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    setState(() {
      _files = pdfs;
      _loading = false;
    });
  }

  Future<void> _deleteFile(File file) async {
    await file.delete();
    await _loadFiles();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tickets History'),
        actions: [
          IconButton(
            onPressed: _loadFiles,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
              ? const Center(child: Text('No saved ticket PDFs found.'))
              : ListView.separated(
                  itemCount: _files.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final file = _files[index] as File;
                    final stat = file.statSync();
                    final name = file.uri.pathSegments.isNotEmpty
                        ? file.uri.pathSegments.last
                        : file.path.split('/').last;
                    return ListTile(
                      leading: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
                      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${stat.modified.toLocal()} • ${(stat.size / 1024).toStringAsFixed(1)} KB'),
                      onTap: () => OpenFilex.open(file.path),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'view') {
                            await OpenFilex.open(file.path);
                          } else if (value == 'share') {
                            await Share.shareXFiles([XFile(file.path)], text: 'Tickets PDF');
                          } else if (value == 'delete') {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete PDF'),
                                content: Text('Delete "$name"?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(ctx).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.of(ctx).pop(true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await _deleteFile(file);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('File deleted')),
                                );
                              }
                            }
                          }
                        },
                        itemBuilder: (ctx) => const [
                          PopupMenuItem(value: 'view', child: Text('View')),
                          PopupMenuItem(value: 'share', child: Text('Share')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
