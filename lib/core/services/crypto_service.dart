import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// CryptoService - Ed25519 signature verification for offline ticket validation.
///
/// This service handles cryptographic operations on the Flutter side:
/// - Signature verification using event public keys
/// - Canonical payload creation for comparison
///
/// Note: Key generation and signing are done server-side only.
class CryptoService {
  final Ed25519 _algorithm = Ed25519();

  /// Verify a ticket signature using the event's public key.
  ///
  /// Returns true if the signature is valid, false otherwise.
  Future<bool> verifySignature({
    required String payload,
    required String signatureBase64,
    required String publicKeyBase64,
  }) async {
    try {
      final payloadBytes = utf8.encode(payload);
      final signatureBytes = base64Decode(signatureBase64);
      final publicKeyBytes = base64Decode(publicKeyBase64);

      final publicKey = SimplePublicKey(
        publicKeyBytes,
        type: KeyPairType.ed25519,
      );

      final signature = Signature(signatureBytes, publicKey: publicKey);

      return await _algorithm.verify(payloadBytes, signature: signature);
    } catch (e) {
      // Any decoding or verification error means invalid
      return false;
    }
  }

  /// Parse and verify a QR code payload.
  ///
  /// QR codes can contain multiple formats:
  /// - Crypto JSON: {"payload": "...", "signature": "..."}
  /// - URL format: https://domain/ticket/validate/{reference_no}
  /// - Plain string: TUID or reference_no
  Future<QrVerificationResult> verifyQrCode({
    required String qrContent,
    required String eventPublicKey,
    Map<String, String>? trustedDevicePublicKeys,
    Set<String>? revokedDeviceUids,
  }) async {
    try {
      // 1. Try crypto JSON format (primary path)
      final cryptoResult = await _tryParseCryptoFormat(
        qrContent,
        eventPublicKey,
        trustedDevicePublicKeys: trustedDevicePublicKeys,
        revokedDeviceUids: revokedDeviceUids,
      );
      if (cryptoResult != null) {
        return cryptoResult;
      }

      // 2. Try URL format - extract reference_no
      final urlResult = _tryParseUrlFormat(qrContent);
      if (urlResult != null) {
        return QrVerificationResult.nonCrypto(
          ticketId: urlResult['reference'],
          format: 'url',
          message: 'URL format detected - requires online verification',
        );
      }

      // 3. Treat as plain reference (TUID or reference_no)
      return QrVerificationResult.nonCrypto(
        ticketId: qrContent,
        format: 'plain',
        message: 'Plain reference detected - requires online verification',
      );
    } catch (e) {
      return QrVerificationResult.invalid('Verification error: $e');
    }
  }

  /// Try to parse as crypto JSON format.
  Future<QrVerificationResult?> _tryParseCryptoFormat(
    String qrContent,
    String eventPublicKey,
    {
    Map<String, String>? trustedDevicePublicKeys,
    Set<String>? revokedDeviceUids,
  }
  ) async {
    try {
      Map<String, dynamic> qrData;
      try {
        qrData = jsonDecode(qrContent) as Map<String, dynamic>;
      } catch (e) {
        return null; // Not JSON format
      }

      final payload = qrData['payload'] as String?;
      final signature = qrData['signature'] as String?;

      if (payload == null || signature == null) {
        return null; // Missing required fields
      }

      // Parse payload to get ticket data
      Map<String, dynamic> ticketData;
      try {
        ticketData = jsonDecode(payload) as Map<String, dynamic>;
      } catch (e) {
        return QrVerificationResult.invalid('Invalid payload format');
      }

      bool isPendingSync = false;
      String verificationPublicKey = eventPublicKey;

      final issuerType = ticketData['issuer_type'] as String?;
      final issuerDeviceUid = ticketData['issuer_device_uid'] as String?;

      if (issuerType == 'device' && issuerDeviceUid != null) {
        if (revokedDeviceUids != null && revokedDeviceUids.contains(issuerDeviceUid)) {
          return QrVerificationResult.invalid('Issuer device revoked');
        }

        final deviceKey = trustedDevicePublicKeys?[issuerDeviceUid];
        if (deviceKey == null || deviceKey.isEmpty) {
          return QrVerificationResult.invalid('Unknown issuer device');
        }
        verificationPublicKey = deviceKey;
      }

      final isValid = await verifySignature(
        payload: payload,
        signatureBase64: signature,
        publicKeyBase64: verificationPublicKey,
      );

      if (!isValid) {
        return QrVerificationResult.invalid('Invalid signature');
      }

      return QrVerificationResult.valid(
        ticketData,
        payload,
        signature,
        isPendingSync: isPendingSync,
      );
    } catch (e) {
      return null;
    }
  }

  /// Try to parse as URL format and extract reference.
  Map<String, dynamic>? _tryParseUrlFormat(String qrContent) {
    // Match common URL patterns for ticket validation
    // Examples:
    // - https://domain.com/ticket/validate/uuid
    // - http://domain.com/ticket/validate/uuid
    // - /ticket/validate/uuid

    final patterns = [
      // Full URL with ticket/validate path
      RegExp(r'/ticket/validate/([a-f0-9\-]{36})', caseSensitive: false),
      // Route-style reference
      RegExp(r'/validate/([a-f0-9\-]{36})', caseSensitive: false),
      // Just UUID in URL context
      RegExp(r'[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(qrContent);
      if (match != null) {
        return {'reference': match.group(1) ?? match.group(0)};
      }
    }

    return null;
  }

  /// Create a canonical payload string from ticket data.
  /// The order of keys must match the server's createCanonicalPayload method.
  String createCanonicalPayload(Map<String, dynamic> ticketData) {
    final payload = <String, dynamic>{};

    // Match server's key ordering
    if (ticketData.containsKey('tuid')) payload['tuid'] = ticketData['tuid'];
    if (ticketData.containsKey('matche_id')) {
      payload['matche_id'] = ticketData['matche_id'];
    }
    if (ticketData.containsKey('ticket_types_id')) {
      payload['ticket_types_id'] = ticketData['ticket_types_id'];
    }
    if (ticketData.containsKey('customer_name') &&
        ticketData['customer_name'] != null) {
      payload['customer_name'] = ticketData['customer_name'];
    }
    if (ticketData.containsKey('amount')) {
      payload['amount'] = ticketData['amount'];
    }
    if (ticketData.containsKey('issued_at')) {
      payload['issued_at'] = ticketData['issued_at'];
    }
    if (ticketData.containsKey('issuer_type')) {
      payload['issuer_type'] = ticketData['issuer_type'];
    }

    return jsonEncode(payload);
  }

  /// Validate that a public key has correct Ed25519 format.
  bool isValidPublicKey(String publicKeyBase64) {
    try {
      final bytes = base64Decode(publicKeyBase64);
      // Ed25519 public keys are 32 bytes
      return bytes.length == 32;
    } catch (e) {
      return false;
    }
  }
}

/// Result of QR code verification
class QrVerificationResult {
  final bool isValid;
  final bool isPendingSync; // True if signed with public key marker
  final String? errorMessage;
  final Map<String, dynamic>? ticketData;
  final String? payload;
  final String? signature;

  QrVerificationResult._({
    required this.isValid,
    this.isPendingSync = false,
    this.errorMessage,
    this.ticketData,
    this.payload,
    this.signature,
  });

  factory QrVerificationResult.valid(
    Map<String, dynamic> ticketData,
    String payload,
    String signature, {
    bool isPendingSync = false,
  }) {
    return QrVerificationResult._(
      isValid: true,
      isPendingSync: isPendingSync,
      ticketData: ticketData,
      payload: payload,
      signature: signature,
    );
  }

  factory QrVerificationResult.invalid(String error) {
    return QrVerificationResult._(isValid: false, errorMessage: error);
  }

  factory QrVerificationResult.nonCrypto({
    required String ticketId,
    required String format,
    required String message,
  }) {
    return QrVerificationResult._(
      isValid: false,
      errorMessage: message,
      ticketData: {'tuid': ticketId, 'format': format},
    );
  }

  /// Get ticket ID (tuid) from verified data
  String? get ticketId => ticketData?['tuid'] as String?;

  /// Get match ID from verified data
  int? get matcheId => ticketData?['matche_id'] as int?;

  /// Get ticket type ID from verified data
  int? get ticketTypesId => ticketData?['ticket_types_id'] as int?;

  /// Get customer name from verified data
  String? get customerName => ticketData?['customer_name'] as String?;
}
