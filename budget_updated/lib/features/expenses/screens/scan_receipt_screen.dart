import 'dart:async';
import 'dart:convert';

import 'package:budget/colors.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/aiInsightsService.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/outlinedButtonStacked.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

const String _rateLimitedMessage = "AI is busy, try again in a minute";

class _ReceiptImageSelection {
  const _ReceiptImageSelection({
    required this.bytes,
    required this.fileName,
  });

  final Uint8List bytes;
  final String fileName;
}

class ReceiptScanResult {
  const ReceiptScanResult({
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
    required this.confidence,
    required this.notes,
    required this.source,
    required this.error,
    required this.debug,
    required this.rateLimited,
  });

  final String title;
  final double amount;
  final String category;
  final DateTime? date;
  final double confidence;
  final String notes;
  final String source;
  final String? error;
  final String? debug;
  final bool rateLimited;

  String get displayTitle => title.trim().isEmpty ? "Receipt" : title.trim();

  bool get hasUsableData {
    final String normalizedTitle = title.trim().toLowerCase();
    return amount > 0 ||
        (normalizedTitle.isNotEmpty && normalizedTitle != "receipt") ||
        date != null;
  }

  factory ReceiptScanResult.fromJson(Map<String, dynamic> json) {
    return ReceiptScanResult(
      title: _stringValue(json["title"], fallback: "Receipt"),
      amount: _doubleValue(json["amount"]),
      category: _stringValue(json["category"], fallback: "Other"),
      date: _dateValue(json["date"]),
      confidence: _doubleValue(json["confidence"]).clamp(0, 1).toDouble(),
      notes: _stringValue(json["notes"]),
      source: _stringValue(json["source"], fallback: "fallback"),
      error: _nullableString(json["error"]),
      debug: _nullableString(json["debug"]),
      rateLimited: json["rateLimited"] == true,
    );
  }
}

class ReceiptScanException implements Exception {
  ReceiptScanException(this.message, {this.rateLimited = false});

  final String message;
  final bool rateLimited;

  @override
  String toString() => message;
}

class FinWiseReceiptScanService {
  FinWiseReceiptScanService({http.Client? client}) : _client = client;

  final http.Client? _client;

  Future<ReceiptScanResult> scanReceipt(XFile image) async {
    final Uint8List bytes = await image.readAsBytes();
    return scanReceiptBytes(
      bytes: bytes,
      fileName: image.name.trim().isEmpty ? "receipt.jpg" : image.name,
    );
  }

  Future<ReceiptScanResult> scanReceiptBytes({
    required Uint8List bytes,
    required String fileName,
  }) async {
    http.Client? createdClient;
    try {
      if (bytes.isEmpty) {
        throw ReceiptScanException("No receipt image was selected.");
      }

      final Uri uri = Uri.parse(
        "${getFinWiseAiBaseUrl().replaceAll(RegExp(r'/$'), '')}/api/scan-receipt",
      );
      final http.MultipartRequest request = http.MultipartRequest("POST", uri);
      request.headers["Accept"] = "application/json";
      request.files.add(
        http.MultipartFile.fromBytes(
          "file",
          bytes,
          filename: fileName.trim().isEmpty ? "receipt.jpg" : fileName,
        ),
      );

      final http.Client client = _client ?? (createdClient = http.Client());
      final http.StreamedResponse streamedResponse =
          await client.send(request).timeout(const Duration(seconds: 35));
      final http.Response response = await http.Response.fromStream(
        streamedResponse,
      );

      if (response.statusCode == 429) {
        throw ReceiptScanException(
          _rateLimitedMessage,
          rateLimited: true,
        );
      }

      Map<String, dynamic> decoded = {};
      if (response.body.trim().isNotEmpty &&
          response.headers["content-type"]?.contains("application/json") ==
              true) {
        decoded = (json.decode(response.body) as Map).cast<String, dynamic>();
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        String message = _stringValue(decoded["error"]);
        if (message.isEmpty) {
          if (response.statusCode == 404) {
            message =
                "Receipt scanner endpoint not found. Please redeploy the AI backend.";
          } else if (response.statusCode >= 500) {
            message =
                "Receipt scanner server error. Please try again in a moment.";
          } else {
            message =
                "Could not scan this receipt right now (HTTP ${response.statusCode}).";
          }
        }
        throw ReceiptScanException(message);
      }

      return ReceiptScanResult.fromJson(decoded);
    } on TimeoutException {
      throw ReceiptScanException("Receipt scanning took too long. Try again.");
    } on ReceiptScanException {
      rethrow;
    } catch (error) {
      final String message = error.toString().contains("429")
          ? _rateLimitedMessage
          : error.toString().contains("404")
              ? "Receipt scanner endpoint not found. Please redeploy the AI backend."
              : "Receipt scanning is temporarily unavailable. Please enter the expense manually.";
      throw ReceiptScanException(
        message,
        rateLimited: message == _rateLimitedMessage,
      );
    } finally {
      createdClient?.close();
    }
  }
}

class ScanReceiptScreen extends StatefulWidget {
  const ScanReceiptScreen({super.key});

  @override
  State<ScanReceiptScreen> createState() => _ScanReceiptScreenState();
}

class _ScanReceiptScreenState extends State<ScanReceiptScreen> {
  final ImagePicker _picker = ImagePicker();
  final FinWiseReceiptScanService _service = FinWiseReceiptScanService();

  Uint8List? _imageBytes;
  ReceiptScanResult? _result;
  bool _isScanning = false;
  bool _openedInitialSheet = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_openedInitialSheet) return;
    _openedInitialSheet = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openSourceSheet();
    });
  }

  Future<void> _openSourceSheet() async {
    await openBottomSheet(
      context,
      PopupFramework(
        title: "Scan receipt",
        subtitle: "Choose a clear photo of the full receipt.",
        child: Column(
          children: [
            if (!kIsWeb)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 12),
                child: OutlinedButtonStacked(
                  filled: false,
                  alignStart: true,
                  alignBeside: true,
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 20,
                    vertical: 20,
                  ),
                  text: "Take photo",
                  iconData: appStateSettings["outlinedIcons"]
                      ? Icons.camera_alt_outlined
                      : Icons.camera_alt_rounded,
                  onTap: () {
                    popRoute(context);
                    _pickAndScan(ImageSource.camera);
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 12),
              child: OutlinedButtonStacked(
                filled: false,
                alignStart: true,
                alignBeside: true,
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 20,
                  vertical: 20,
                ),
                text: "Choose from gallery",
                iconData: appStateSettings["outlinedIcons"]
                    ? Icons.photo_library_outlined
                    : Icons.photo_library_rounded,
                onTap: () {
                  popRoute(context);
                  _pickAndScan(ImageSource.gallery);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndScan(ImageSource source) async {
    try {
      final _ReceiptImageSelection? pickedImage =
          await _pickReceiptImage(source);
      if (pickedImage == null) {
        _showMessage(
          title: source == ImageSource.camera
              ? "No photo taken"
              : "No receipt selected",
          description: source == ImageSource.gallery
              ? "Choose an image file (JPG, PNG, HEIC) from gallery."
              : null,
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        _imageBytes = pickedImage.bytes;
        _result = null;
        _isScanning = true;
      });

      final ReceiptScanResult result = await _service.scanReceiptBytes(
        bytes: pickedImage.bytes,
        fileName: pickedImage.fileName,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _isScanning = false;
      });

      if (result.rateLimited || result.error != null) {
        _showMessage(
          title: result.rateLimited ? "AI is busy" : "Scan needs review",
          description: result.error,
          isError: result.rateLimited,
        );
      }
    } on ReceiptScanException catch (error) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
      });
      _showMessage(
        title: error.rateLimited ? "AI is busy" : "Receipt scan failed",
        description: error.message,
        isError: true,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
      });
      _showMessage(
        title: "Receipt scan failed",
        description: "Please try again with a clearer photo.",
        isError: true,
      );
    }
  }

  Future<_ReceiptImageSelection?> _pickReceiptImage(ImageSource source) async {
    if (source == ImageSource.gallery) {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return null;

      final PlatformFile file = result.files.first;
      final String fileName =
          file.name.trim().isEmpty ? "receipt.jpg" : file.name;
      if (file.bytes != null && file.bytes!.isNotEmpty) {
        return _ReceiptImageSelection(bytes: file.bytes!, fileName: fileName);
      }

      final String? path = file.path;
      if (path == null || path.trim().isEmpty) return null;
      final XFile image = XFile(path);
      final Uint8List bytes = await image.readAsBytes();
      if (bytes.isEmpty) return null;
      return _ReceiptImageSelection(bytes: bytes, fileName: fileName);
    }

    final XFile? image = await _picker.pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (image != null) {
      final Uint8List bytes = await image.readAsBytes();
      if (bytes.isEmpty) return null;
      return _ReceiptImageSelection(
        bytes: bytes,
        fileName: image.name.trim().isEmpty ? "receipt.jpg" : image.name,
      );
    }

    return null;
  }

  void _showMessage({
    required String title,
    String? description,
    bool isError = false,
  }) {
    final bool outlinedIcons = appStateSettings["outlinedIcons"] == true;
    final IconData icon = isError
        ? (outlinedIcons ? Icons.error_outline_rounded : Icons.error_rounded)
        : (outlinedIcons ? Icons.info_outline_rounded : Icons.info_rounded);
    openSnackbar(
      SnackbarMessage(
        title: title,
        description: description,
        icon: icon,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      title: "Scan receipt",
      dragDownToDismiss: true,
      scrollbar: false,
      actions: [
        IconButton(
          tooltip: "Choose receipt image",
          onPressed: _isScanning ? null : _openSourceSheet,
          icon: Icon(
            appStateSettings["outlinedIcons"]
                ? Icons.add_a_photo_outlined
                : Icons.add_a_photo_rounded,
          ),
        ),
      ],
      listWidgets: [
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              if (_imageBytes == null)
                _EmptyReceiptScanCard(onChooseImage: _openSourceSheet)
              else
                _ReceiptImagePreview(imageBytes: _imageBytes!),
              const SizedBox(height: 12),
              if (_isScanning)
                const _ReceiptScanningCard()
              else if (_result != null)
                _ReceiptPreviewCard(result: _result!),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Button(
                      label: "Scan another",
                      icon: appStateSettings["outlinedIcons"]
                          ? Icons.camera_alt_outlined
                          : Icons.camera_alt_rounded,
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      textColor:
                          Theme.of(context).colorScheme.onSecondaryContainer,
                      disabled: _isScanning,
                      onTap: _openSourceSheet,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Button(
                      label: "Use in expense",
                      icon: appStateSettings["outlinedIcons"]
                          ? Icons.check_circle_outline_rounded
                          : Icons.check_circle_rounded,
                      disabled: _isScanning ||
                          _result == null ||
                          !_result!.hasUsableData,
                      onTap: () {
                        if (_result != null) popRoute(context, _result);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReceiptImagePreview extends StatelessWidget {
  const _ReceiptImagePreview({required this.imageBytes});

  final Uint8List imageBytes;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 220,
        color: getColor(context, "lightDarkAccent"),
        child: Image.memory(
          imageBytes,
          fit: BoxFit.cover,
          width: double.infinity,
        ),
      ),
    );
  }
}

class _EmptyReceiptScanCard extends StatelessWidget {
  const _EmptyReceiptScanCard({required this.onChooseImage});

  final VoidCallback onChooseImage;

  @override
  Widget build(BuildContext context) {
    return _ReceiptCard(
      child: Column(
        children: [
          Icon(
            appStateSettings["outlinedIcons"]
                ? Icons.receipt_long_outlined
                : Icons.receipt_long_rounded,
            size: 46,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          TextFont(
            text:
                "Capture a receipt and FinWise will read the expense details.",
            fontSize: 16,
            fontWeight: FontWeight.bold,
            textAlign: TextAlign.center,
            maxLines: 3,
          ),
          const SizedBox(height: 8),
          TextFont(
            text: "You can review and edit everything before saving.",
            fontSize: 14,
            textColor: getColor(context, "textLight"),
            textAlign: TextAlign.center,
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          Button(
            label: "Choose receipt",
            icon: appStateSettings["outlinedIcons"]
                ? Icons.add_a_photo_outlined
                : Icons.add_a_photo_rounded,
            onTap: onChooseImage,
          ),
        ],
      ),
    );
  }
}

class _ReceiptScanningCard extends StatelessWidget {
  const _ReceiptScanningCard();

  @override
  Widget build(BuildContext context) {
    return _ReceiptCard(
      child: Column(
        children: [
          CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          TextFont(
            text: "Reading receipt details...",
            fontSize: 16,
            fontWeight: FontWeight.bold,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          TextFont(
            text: "Looking for merchant, total, category, and date.",
            fontSize: 14,
            textColor: getColor(context, "textLight"),
            textAlign: TextAlign.center,
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}

class _ReceiptPreviewCard extends StatelessWidget {
  const _ReceiptPreviewCard({required this.result});

  final ReceiptScanResult result;

  @override
  Widget build(BuildContext context) {
    return _ReceiptCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                appStateSettings["outlinedIcons"]
                    ? Icons.auto_awesome_outlined
                    : Icons.auto_awesome_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFont(
                  text: "Extracted expense",
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  maxLines: 1,
                ),
              ),
              TextFont(
                text: "${(result.confidence * 100).round()}%",
                fontSize: 13,
                textColor: getColor(context, "textLight"),
                maxLines: 1,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ReceiptFieldRow(label: "Title", value: result.displayTitle),
          _ReceiptFieldRow(
            label: "Amount",
            value: result.amount <= 0
                ? "Not detected"
                : "PKR ${result.amount.toStringAsFixed(result.amount % 1 == 0 ? 0 : 2)}",
          ),
          _ReceiptFieldRow(label: "Category", value: result.category),
          _ReceiptFieldRow(label: "Date", value: _displayDate(result.date)),
          if (result.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            TextFont(
              text: result.notes,
              fontSize: 13.5,
              textColor: getColor(context, "textLight"),
              maxLines: 4,
            ),
          ],
          if (result.error != null) ...[
            const SizedBox(height: 10),
            TextFont(
              text: result.error!,
              fontSize: 13.5,
              textColor: getColor(context, "expenseAmount"),
              maxLines: 3,
            ),
          ],
          if (kDebugMode && result.debug != null) ...[
            const SizedBox(height: 6),
            TextFont(
              text: "Debug: ${result.debug!}",
              fontSize: 12.5,
              textColor: getColor(context, "textLight"),
              maxLines: 6,
            ),
          ],
        ],
      ),
    );
  }
}

class _ReceiptFieldRow extends StatelessWidget {
  const _ReceiptFieldRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: TextFont(
              text: label,
              fontSize: 13,
              textColor: getColor(context, "textLight"),
              maxLines: 1,
            ),
          ),
          Expanded(
            child: TextFont(
              text: value,
              fontSize: 15,
              fontWeight: FontWeight.bold,
              maxLines: 3,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: getColor(context, "lightDarkAccent")),
      ),
      child: child,
    );
  }
}

String _displayDate(DateTime? date) {
  if (date == null) return "Not detected";
  String twoDigits(int value) => value.toString().padLeft(2, "0");
  return "${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)}";
}

String _stringValue(dynamic value, {String fallback = ""}) {
  final String text = value?.toString() ?? "";
  return text.trim().isEmpty ? fallback : text.trim();
}

String? _nullableString(dynamic value) {
  final String text = value?.toString() ?? "";
  return text.trim().isEmpty ? null : text.trim();
}

double _doubleValue(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? "") ?? 0;
}

DateTime? _dateValue(dynamic value) {
  final String text = value?.toString() ?? "";
  if (text.trim().isEmpty) return null;
  return DateTime.tryParse(text.trim());
}
