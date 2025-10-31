class TicketValidationResult {
  final String message;
  final String type;
  final String status;
  final String id; // ticket reference no

  TicketValidationResult({
    required this.message,
    required this.type,
    required this.status,
    required this.id,
  });

  factory TicketValidationResult.fromJson(Map<String, dynamic> json) {
    return TicketValidationResult(
      message: json['message'] ?? '',
      type: json['type'] ?? '',
      status: json['status'] ?? '',
      id: json['id'] ?? '',
    );
  }
}
