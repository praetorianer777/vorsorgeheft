import 'dart:convert';

/// An appointment this device had recorded, replaced by what another device
/// recorded for the same appointment.
///
/// Last-write-wins is silent by design, and for a renamed child that is the
/// right thing. For a recorded appointment it is not: the parent who wrote
/// "3 March" and now sees "4 March" should learn that the other phone did
/// that, rather than doubt their own memory. The notice is device-local, like
/// everything else that is about this phone rather than about the family.
class OverwriteNotice {
  const OverwriteNotice({
    required this.personId,
    required this.ruleId,
    required this.doseId,
    required this.previousDate,
    required this.previousSkipped,
    required this.currentDate,
    required this.currentSkipped,
    required this.fromNodeId,
  });

  factory OverwriteNotice.fromJson(Map<String, Object?> json) =>
      OverwriteNotice(
        personId: json['personId']! as String,
        ruleId: json['ruleId']! as String,
        doseId: json['doseId'] as String?,
        previousDate: DateTime.parse(json['previousDate']! as String),
        previousSkipped: json['previousSkipped'] == true,
        currentDate: json['currentDate'] == null
            ? null
            : DateTime.parse(json['currentDate']! as String),
        currentSkipped: json['currentSkipped'] == true,
        fromNodeId: json['fromNodeId']! as String,
      );

  final String personId;
  final String ruleId;
  final String? doseId;
  final DateTime previousDate;
  final bool previousSkipped;

  /// Null when the other device removed the record altogether.
  final DateTime? currentDate;
  final bool currentSkipped;

  /// The device whose entry won: a paired peer, or the writer of an imported
  /// file, which may be a phone this one has never been paired with.
  final String fromNodeId;

  bool get removed => currentDate == null;

  Map<String, Object?> toJson() => {
    'personId': personId,
    'ruleId': ruleId,
    'doseId': doseId,
    'previousDate': previousDate.toIso8601String(),
    'previousSkipped': previousSkipped,
    'currentDate': currentDate?.toIso8601String(),
    'currentSkipped': currentSkipped,
    'fromNodeId': fromNodeId,
  };

  static String encodeList(Iterable<OverwriteNotice> notices) =>
      jsonEncode([for (final n in notices) n.toJson()]);

  static List<OverwriteNotice> decodeList(String? encoded) {
    if (encoded == null || encoded.isEmpty) return const [];
    final decoded = jsonDecode(encoded);
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        if (item is Map) OverwriteNotice.fromJson(item.cast()),
    ];
  }
}
