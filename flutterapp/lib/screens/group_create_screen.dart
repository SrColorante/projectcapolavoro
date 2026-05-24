import 'package:flutter/material.dart';
import '../api/chat_api.dart';
import '../models/user_profile.dart';
import '../services/api_exception_handler.dart';

class GroupCreateScreen extends StatefulWidget {
  const GroupCreateScreen({super.key, required this.currentUserId});
  final String currentUserId;

  @override
  State<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends State<GroupCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _customIdController = TextEditingController();
  
  final _chatApi = ChatApi();
  bool _isLoading = false;

  // Preset list of contacts
  final List<Map<String, String>> _contacts = [
    {'id': '1234567890', 'name': 'Mario Rossi'},
    {'id': '1234567891', 'name': 'Luca Bianchi'},
    {'id': '1234567892', 'name': 'Giulia Verdi'},
  ];

  final Set<String> _selectedMemberIds = {};

  @override
  void initState() {
    super.initState();
    // Exclude current user from selectable contacts
    _contacts.removeWhere((c) => c['id'] == widget.currentUserId);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _customIdController.dispose();
    super.dispose();
  }

  void _toggleMember(String id) {
    setState(() {
      if (_selectedMemberIds.contains(id)) {
        _selectedMemberIds.remove(id);
      } else {
        _selectedMemberIds.add(id);
      }
    });
  }

  void _addCustomId() {
    final customId = _customIdController.text.trim();
    if (!UserProfile.isValidTenDigitId(customId)) {
      ApiExceptionHandler.showSnackBarError(context, 'L\'ID deve essere numerico e di 10 cifre.');
      return;
    }
    if (customId == widget.currentUserId) {
      ApiExceptionHandler.showSnackBarError(context, 'Non puoi aggiungere te stesso manualmente.');
      return;
    }
    if (_selectedMemberIds.contains(customId)) {
      ApiExceptionHandler.showSnackBarError(context, 'Membro già selezionato.');
      return;
    }

    setState(() {
      _selectedMemberIds.add(customId);
      if (!_contacts.any((c) => c['id'] == customId)) {
        _contacts.add({'id': customId, 'name': 'Utente $customId'});
      }
      _customIdController.clear();
    });
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedMemberIds.isEmpty) {
      ApiExceptionHandler.showSnackBarError(context, 'Seleziona almeno un partecipante.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final groupId = await _chatApi.createGroup(
        userId: widget.currentUserId,
        name: _nameController.text.trim(),
        memberIds: _selectedMemberIds.toList(),
      );
      if (mounted) {
        Navigator.of(context).pop(groupId);
      }
    } catch (error) {
      if (mounted) {
        ApiExceptionHandler.handleError(context, error);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crea Nuovo Gruppo'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nome del Gruppo',
                          prefixIcon: Icon(Icons.group_add_rounded),
                          border: OutlineInputBorder(),
                        ),
                        validator: (val) => val == null || val.trim().isEmpty ? 'Inserisci il nome del gruppo' : null,
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Seleziona Partecipanti:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _contacts.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final contact = _contacts[index];
                            final contactId = contact['id']!;
                            final isSelected = _selectedMemberIds.contains(contactId);
                            return CheckboxListTile(
                              title: Text(contact['name']!),
                              subtitle: Text('ID: $contactId'),
                              value: isSelected,
                              onChanged: (_) => _toggleMember(contactId),
                              activeColor: const Color(0xFFDC143C),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _customIdController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Aggiungi ID manuale (10 cifre)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            style: IconButton.styleFrom(backgroundColor: const Color(0xFFDC143C)),
                            icon: const Icon(Icons.add, color: Colors.white),
                            onPressed: _addCustomId,
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _createGroup,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC143C),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                )
                              : const Text('CREA GRUPPO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
