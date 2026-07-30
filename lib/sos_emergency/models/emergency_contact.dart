class EmergencyContact {
  const EmergencyContact({
    required this.id,
    required this.name,
    required this.phoneNumber,
    this.isPrimary = false,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final String phoneNumber;
  final bool isPrimary;
  final bool isDefault;

  EmergencyContact copyWith({
    String? name,
    String? phoneNumber,
    bool? isPrimary,
  }) => EmergencyContact(
    id: id,
    name: name ?? this.name,
    phoneNumber: phoneNumber ?? this.phoneNumber,
    isPrimary: isPrimary ?? this.isPrimary,
    isDefault: isDefault,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phoneNumber': phoneNumber,
    'isPrimary': isPrimary,
    'isDefault': isDefault,
  };

  factory EmergencyContact.fromJson(Map<String, dynamic> json) =>
      EmergencyContact(
        id: json['id'] as String,
        name: json['name'] as String,
        phoneNumber: json['phoneNumber'] as String,
        isPrimary: json['isPrimary'] as bool? ?? false,
        isDefault: json['isDefault'] as bool? ?? false,
      );
}
