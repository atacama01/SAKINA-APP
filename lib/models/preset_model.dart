class PresetModel {
  final String name;
  final int minutes;
  final String icon;

  const PresetModel({
    required this.name,
    required this.minutes,
    required this.icon,
  });

  static const List<PresetModel> defaults = [
    PresetModel(name: 'Meeting', minutes: 45, icon: '💼'),
    PresetModel(name: 'Exam', minutes: 90, icon: '📝'),
    PresetModel(name: 'Mosque', minutes: 20, icon: '🕌'),
    PresetModel(name: 'Sleep', minutes: 480, icon: '🌙'),
  ];
}