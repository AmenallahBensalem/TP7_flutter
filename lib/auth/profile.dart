enum AccountRole { admin, user }

enum AccountStatus { pending, approved, rejected }

class Profile {
  Profile.fromRow(Map<String, dynamic> row)
    : id = row['id'] as String,
      fullName = row['full_name'] as String,
      email = row['email'] as String,
      phone = row['phone'] as String,
      _role = row['role'] as String,
      _status = row['status'] as String;

  final String id;
  final String fullName;
  final String email;
  final String phone;
  final String _role;
  final String _status;

  AccountRole get role => AccountRole.values.byName(_role);
  AccountStatus get status => AccountStatus.values.byName(_status);
  bool get isAdmin =>
      role == AccountRole.admin && status == AccountStatus.approved;
}
