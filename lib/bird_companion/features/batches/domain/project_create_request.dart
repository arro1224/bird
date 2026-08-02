class ProjectCreateRequest {
  const ProjectCreateRequest({
    required this.name,
    required this.cardId,
  });

  final String name;
  final String cardId;

  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'card_id': cardId.trim(),
  };
}
