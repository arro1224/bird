class ProjectCreateRequest {
  const ProjectCreateRequest({
    required this.name,
    required this.cardId,
    this.idempotencyKey,
  });

  final String name;
  final String cardId;
  final String? idempotencyKey;

  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'card_id': cardId.trim(),
  };
}
