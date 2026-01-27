import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceCryptoService {
  static const _kDevicePrivateKey = 'device_private_key_base64';
  static const _kDevicePublicKey = 'device_public_key_base64';
  static const _kDeviceKeyVersion = 'device_key_version';

  final Ed25519 _algo = Ed25519();

  Future<DeviceKeyMaterial> ensureKeyPair() async {
    final prefs = await SharedPreferences.getInstance();

    final existingPriv = prefs.getString(_kDevicePrivateKey);
    final existingPub = prefs.getString(_kDevicePublicKey);
    final existingVer = prefs.getInt(_kDeviceKeyVersion);

    if (existingPriv != null && existingPub != null) {
      return DeviceKeyMaterial(
        publicKeyBase64: existingPub,
        privateKeyBase64: existingPriv,
        keyVersion: existingVer ?? 1,
      );
    }

    final keyPair = await _algo.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKey = await keyPair.extractPrivateKeyBytes();

    final publicKeyBase64 = base64Encode(publicKey.bytes);
    final privateKeyBase64 = base64Encode(privateKey);

    await prefs.setString(_kDevicePublicKey, publicKeyBase64);
    await prefs.setString(_kDevicePrivateKey, privateKeyBase64);
    await prefs.setInt(_kDeviceKeyVersion, 1);

    return DeviceKeyMaterial(
      publicKeyBase64: publicKeyBase64,
      privateKeyBase64: privateKeyBase64,
      keyVersion: 1,
    );
  }

  Future<String> signPayload({
    required String payload,
    required String privateKeyBase64,
    required String publicKeyBase64,
  }) async {
    final privateKeyBytes = base64Decode(privateKeyBase64);
    final publicKeyBytes = base64Decode(publicKeyBase64);

    final keyPair = SimpleKeyPairData(
      privateKeyBytes,
      publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );

    final sig = await _algo.sign(
      utf8.encode(payload),
      keyPair: keyPair,
    );

    return base64Encode(sig.bytes);
  }
}

class DeviceKeyMaterial {
  final String publicKeyBase64;
  final String privateKeyBase64;
  final int keyVersion;

  DeviceKeyMaterial({
    required this.publicKeyBase64,
    required this.privateKeyBase64,
    required this.keyVersion,
  });
}
