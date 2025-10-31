class Ticket {
  final int id;
  final int matchId;
  final int ticketTypeId;
  final int userId;
  final String referenceNo;
  final String status;
  final String? customerName;
  final double amount;
  final String createdAt;
  final String updatedAt;

  Ticket({
    required this.id,
    required this.matchId,
    required this.ticketTypeId,
    required this.userId,
    required this.referenceNo,
    required this.status,
    this.customerName,
    required this.amount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Ticket.fromJson(Map<String, dynamic> json) {
    return Ticket(
      id: json['id'],
      matchId: json['matche_id'],
      ticketTypeId: json['ticket_types_id'],
      userId: json['user_id'],
      referenceNo: json['reference_no'],
      status: json['status'],
      customerName: json['customer_name'],
      amount: json['amount'].toDouble(),
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'matche_id': matchId,
      'ticket_types_id': ticketTypeId,
      'user_id': userId,
      'reference_no': referenceNo,
      'status': status,
      'customer_name': customerName,
      'amount': amount,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}