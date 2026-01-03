class NotificationHistoryItem {
  final String type;
  final String title;
  final String body;
  final DateTime receivedAt;

  NotificationHistoryItem({
    required this.type,
    required this.title,
    required this.body,
    required this.receivedAt,
  });
}
