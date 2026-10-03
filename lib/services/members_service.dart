import 'package:supabase_flutter/supabase_flutter.dart';

class Member {
  const Member(this.email, this.role, this.joined);
  final String email;
  final String role; // owner | member
  final bool joined;
}

class MembersService {
  MembersService(this._client, this._libraryId, this._myEmail);
  final SupabaseClient _client;
  final String _libraryId;
  final String? _myEmail;

  Future<List<Member>> list() async {
    final rows = await _client
        .from('library_members')
        .select()
        .eq('library_id', _libraryId)
        .order('email');
    return rows
        .map((r) => Member(r['email'] as String, r['role'] as String, r['user_id'] != null))
        .toList();
  }

  bool isOwnerIn(List<Member> members) =>
      members.any((m) => m.role == 'owner' && m.email == _myEmail?.toLowerCase());

  Future<void> add(String normalizedEmail) => _client.from('library_members').insert({
        'library_id': _libraryId,
        'email': normalizedEmail,
        'role': 'member',
      });

  Future<void> remove(String email) => _client
      .from('library_members')
      .delete()
      .eq('library_id', _libraryId)
      .eq('email', email);
}
