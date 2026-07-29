/// Represents a single emergency contact that can be alerted
/// when the user triggers an SOS event.
class SosContact {
  final String id;
  final String name;
  final String phoneNumber;
  final String relation;
  final bool isPrimary;
  final bool isDefault;

  const SosContact({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.relation,
    this.isPrimary = false,
    this.isDefault = false,
  });

  factory SosContact.fromJson(Map<String, dynamic> json) {
    return SosContact(
      id: json['id'] as String,
      name: json['name'] as String,
      phoneNumber: json['phoneNumber'] as String,
      relation: json['relation'] as String,
      isPrimary: json['isPrimary'] as bool? ?? false,
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phoneNumber': phoneNumber,
      'relation': relation,
      'isPrimary': isPrimary,
      'isDefault': isDefault,
    };
  }

  SosContact copyWith({
    String? id,
    String? name,
    String? phoneNumber,
    String? relation,
    bool? isPrimary,
    bool? isDefault,
  }) {
    return SosContact(
      id: id ?? this.id,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      relation: relation ?? this.relation,
      isPrimary: isPrimary ?? this.isPrimary,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SosContact && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'SosContact(id: $id, name: $name, phone: $phoneNumber, relation: $relation, primary: $isPrimary)';
}
