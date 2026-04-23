class QurbaniCategory {
  final String id;
  final String title;
  final String subtitle;
  final double amount;
  final int hissahPerToken; // How many names fit in one token (e.g. Large Animal=7, Goat=1)

  QurbaniCategory({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.amount,
    this.hissahPerToken = 7,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'amount': amount,
        'hissah_per_token': hissahPerToken,
      };

  factory QurbaniCategory.fromJson(Map<String, dynamic> json) => QurbaniCategory(
        id: json['id'].toString(),
        title: json['title'],
        subtitle: json['subtitle'],
        amount: (json['amount'] as num).toDouble(),
        hissahPerToken: json['hissah_per_token'] ?? 7,
      );
}
