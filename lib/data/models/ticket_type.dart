class TicketType {
  final int id;
  final String name;
  final double price;
  final String? description;

  TicketType({
    required this.id,
    required this.name,
    required this.price,
    this.description,
  });

  factory TicketType.fromJson(Map<String, dynamic> json) {
    // Handle both API format ('amount', 'desc') and potential legacy format ('price', 'description')
    final amountVal = json['amount'] ?? json['price'] ?? '0.0';
    final descVal = json['desc'] ?? json['description'];

    return TicketType(
      id: json['id'],
      name: json['name'] ?? '',
      price: double.tryParse(amountVal.toString()) ?? 0.0,
      description: descVal,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'amount': price.toString(), // API expects 'amount' as string
      'desc': description,
    };
  }
}
