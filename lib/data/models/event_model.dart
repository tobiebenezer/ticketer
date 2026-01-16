class Event {
  final int id;
  final int userId;
  final String season;
  final String homeTeam;
  final String awayTeam;
  final String venue;
  final int stadiumCapacity;
  final String matchDate;
  final String competition;
  final String matchWeek;
  final String status;
  final String createdAt;
  final String updatedAt;

  Event({
    required this.id,
    required this.userId,
    required this.season,
    required this.homeTeam,
    required this.awayTeam,
    required this.venue,
    required this.stadiumCapacity,
    required this.matchDate,
    required this.competition,
    required this.matchWeek,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Get event name (home vs away)
  String get name => '$homeTeam vs $awayTeam';

  /// Parse match date as DateTime
  DateTime get matchDateParsed {
    try {
      return DateTime.parse(matchDate);
    } catch (e) {
      return DateTime.now();
    }
  }

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: json['id'],
      userId: json['user_id'],
      season: json['season'],
      homeTeam: json['home_team'],
      awayTeam: json['away_team'],
      venue: json['venue'],
      stadiumCapacity: json['stadium_capacity'],
      matchDate: json['match_date'],
      competition: json['competition'],
      matchWeek: json['match_week'],
      status: json['status'],
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'season': season,
      'home_team': homeTeam,
      'away_team': awayTeam,
      'venue': venue,
      'stadium_capacity': stadiumCapacity,
      'match_date': matchDate,
      'competition': competition,
      'match_week': matchWeek,
      'status': status,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}
