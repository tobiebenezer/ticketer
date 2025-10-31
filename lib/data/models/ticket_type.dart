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
    return TicketType(
      id: json['id'],
      name: json['name'],
      price: double.parse(json['amount']),
      description: json['desc'],
    );
  }
}
